#!/usr/bin/env bash
set -Eeuo pipefail
VERSION="2.5.1"
APP_DIR="/opt/nexyra-link"
CONFIG="$APP_DIR/config.json"
API_DEFAULT="https://api.nexyratech.com.br/netpulse"
die(){ echo "[ERRO] $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "Execute como root."

install_deps(){
  echo "[Nexyra] Instalando dependencias..."
  if command -v apt-get >/dev/null; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl jq iputils-ping nodejs npm ca-certificates
  elif command -v dnf >/dev/null; then
    dnf install -y curl jq iputils nodejs npm ca-certificates
  else
    die "Instale curl, jq, ping, npm e Node.js 18+."
  fi
  [ "$(node -p 'Number(process.versions.node.split(".")[0])')" -ge 18 ] || die "Node.js 18+ obrigatorio."
}

configure(){
  local old_url="" old_key=""
  [ -f "$CONFIG" ] && old_url="$(jq -r '.base_url // empty' "$CONFIG" 2>/dev/null || true)" && old_key="$(jq -r '.key // empty' "$CONFIG" 2>/dev/null || true)"
  read -r -p "URL da API [${old_url:-$API_DEFAULT}]: " BASE_URL
  BASE_URL="${BASE_URL:-${old_url:-$API_DEFAULT}}"; BASE_URL="${BASE_URL%/}"
  read -r -p "Chave [Enter mantem a atual]: " INSTALL_KEY; INSTALL_KEY="${INSTALL_KEY:-$old_key}"
  [ -n "$INSTALL_KEY" ] || die "Chave obrigatoria."
  local response
  response="$(curl -fsS --max-time 20 -H 'Content-Type: application/json' -d "$(jq -nc --arg key "$INSTALL_KEY" '{key:$key}')" "$BASE_URL/validate_key.php")" || die "API indisponivel."
  [ "$(printf %s "$response"|jq -r '.success // false')" = true ] || die "$(printf %s "$response"|jq -r '.message // "Chave recusada"')"
  mkdir -p "$APP_DIR"
  jq -n --arg u "$BASE_URL" --arg k "$INSTALL_KEY" --arg v "$VERSION" '{base_url:$u,key:$k,version:$v,interval_ms:30000,offline_threshold_ms:60000}' > "$CONFIG"
  chmod 600 "$CONFIG"
}

write_monitor(){
cat > "$APP_DIR/monitor.js" <<'NODE'
'use strict';
const fs=require('fs'),net=require('net'),{execFile}=require('child_process');
const {RouterOSAPI}=require('node-routeros');
const dir='/opt/nexyra-link/',cfg=JSON.parse(fs.readFileSync(dir+'config.json','utf8')),base=cfg.base_url.replace(/\/$/,'');
const sf=dir+'node-state.json',qf=dir+'history-queue.json',hf=dir+'node-history.jsonl';
const read=(p,d)=>{try{return JSON.parse(fs.readFileSync(p,'utf8'))}catch{return d}};
const write=(p,v)=>{fs.writeFileSync(p+'.tmp',JSON.stringify(v));fs.renameSync(p+'.tmp',p)};
let states=read(sf,{}),queue=read(qf,[]),running=false;
async function req(url,opt={}){const c=new AbortController(),t=setTimeout(()=>c.abort(),15000);try{const r=await fetch(url,{...opt,signal:c.signal}),s=(await r.text()).replace(/^\uFEFF+/,'').trim(),j=s?JSON.parse(s):{};if(!r.ok||j.success===false)throw Error(j.message||('HTTP '+r.status));return j}finally{clearTimeout(t)}}
const post=(a,d)=>req(base+'/api.php?action='+a,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)});
const update=d=>req(base+'/update_node_1.php',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...d,key:cfg.key})});
const payload=()=>req(base+'/api.php?action=get_monitor_payload&key='+encodeURIComponent(cfg.key));
const ping=h=>new Promise(ok=>execFile('ping',['-c','1','-W','2',h],{timeout:4000},e=>ok(!e)));
const tcp=(h,p)=>new Promise(ok=>{const s=new net.Socket();let done=false,end=v=>{if(!done){done=true;s.destroy();ok(v)}};s.setTimeout(2200);s.once('connect',()=>end(true));s.once('timeout',()=>end(false));s.once('error',()=>end(false));s.connect(p,h)});
async function detect(h){if(await ping(h))return{online:true,port:null};for(const p of [80,443,22,8291,8728,8080,8443,53])if(await tcp(h,p))return{online:true,port:p};return{online:false,port:null}}
function archive(e){fs.appendFileSync(hf,JSON.stringify(e)+'\n');if(fs.statSync(hf).size>25*1024*1024){const x=fs.readFileSync(hf,'utf8').trim().split('\n').slice(-100000);fs.writeFileSync(hf+'.tmp',x.join('\n')+'\n');fs.renameSync(hf+'.tmp',hf)}}
async function flush(){while(queue.length)try{await update(queue[0]);queue.shift();write(qf,queue)}catch(e){console.error('Fila:',e.message);return}}
async function check(n,uid){const now=Date.now(),r=await detect(n.ip),old=states[n.id]||{status:n.status||'unknown',failed:null};let status='online',failed=null;if(!r.online){failed=old.failed||now;status=now-failed>=(cfg.offline_threshold_ms||60000)?'offline':old.status}const e={id:Number(n.id),uid,status,detected_port:r.port,checked_at:new Date().toISOString()};if(status!==old.status){queue.push(e);archive({...e,old_status:old.status});write(qf,queue)}else try{await update(e)}catch(x){console.error('Node '+n.id+':',x.message)}states[n.id]={status,failed};write(sf,states)}
async function pppoe(m){const conn=new RouterOSAPI({host:m.host,port:Number(m.port||8728),user:m.username,password:String(m.password),tls:Boolean(Number(m.use_ssl)),timeout:10,keepalive:false});try{await conn.connect();const rows=await conn.write('/ppp/active/print');return rows.map(x=>({username:x.name,address:x.address||null,uptime:x.uptime||null,caller_id:x['caller-id']||null,service:x.service||null}))}finally{try{conn.close()}catch{}}}
async function tick(){if(running)return;running=true;try{await flush();const d=await payload();await post('monitoring_heartbeat',{uid:d.user.uid,server_ip:d.request_ip});for(const n of d.nodes||[])await check(n,d.user.uid);await flush();if(!d.credentials_allowed&&(d.mikrotiks||[]).length)console.error('Credenciais bloqueadas para '+d.request_ip);for(const m of d.mikrotiks||[])if(m.password)try{await post('update_pppoe_clients',{key:cfg.key,mikrotik_id:m.id,clients:await pppoe(m)})}catch(e){console.error('MikroTik '+m.name+':',e.message);try{await post('mikrotik_error',{key:cfg.key,mikrotik_id:m.id,error:e.message})}catch{}}}catch(e){console.error(new Date().toISOString(),e.message)}finally{running=false}}
console.log('Nexyra Link Agent v'+cfg.version);tick();setInterval(tick,cfg.interval_ms||30000);
NODE
node --check "$APP_DIR/monitor.js" >/dev/null
cd "$APP_DIR"
[ -f package.json ] || npm init -y >/dev/null 2>&1
npm install --omit=dev --save-exact node-routeros@1.6.9
}

write_service(){
cat > /etc/systemd/system/nexyra-link.service <<EOF
[Unit]
Description=Nexyra Link Monitor v$VERSION
Wants=network-online.target
After=network-online.target
[Service]
WorkingDirectory=$APP_DIR
ExecStart=$(command -v node) $APP_DIR/monitor.js
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
cat > "$APP_DIR/menu.sh" <<'MENU'
#!/usr/bin/env bash
printf '1) Status 2) Iniciar 3) Parar 4) Reiniciar 5) Logs 6) Testar API 7) Historico\n'
read -r -p 'Opcao: ' o
case "$o" in
1) systemctl --no-pager status nexyra-link;;2) systemctl start nexyra-link;;3) systemctl stop nexyra-link;;4) systemctl restart nexyra-link;;5) journalctl -u nexyra-link -n 100 -f;;
6) c=/opt/nexyra-link/config.json;u=$(jq -r .base_url "$c");k=$(jq -r .key "$c");curl -fsS "$u/api.php?action=get_monitor_payload&key=$(printf %s "$k"|jq -sRr @uri)"|jq;;
7) wc -l /opt/nexyra-link/node-history.jsonl 2>/dev/null||echo 0;;esac
MENU
chmod 750 "$APP_DIR/menu.sh"; ln -sf "$APP_DIR/menu.sh" /usr/local/bin/nexyra
systemctl daemon-reload; systemctl enable --now nexyra-link
}

install_agent(){ install_deps; configure; [ -d "$APP_DIR" ] && cp -a "$APP_DIR" "/opt/nexyra-link-backup-$(date +%Y%m%d-%H%M%S)" || true; write_monitor; write_service; echo "Nexyra Link v$VERSION instalado. MikroTik via API RouterOS na porta cadastrada. Use: nexyra"; }
uninstall_agent(){ read -r -p "Remover? [s/N]: " x; [[ "$x" =~ ^[sS]$ ]]||exit; systemctl disable --now nexyra-link 2>/dev/null||true; rm -f /etc/systemd/system/nexyra-link.service /usr/local/bin/nexyra; rm -rf "$APP_DIR"; systemctl daemon-reload; }
case "${1:-}" in install) install_agent;;uninstall) uninstall_agent;;*) printf 'Nexyra Link v%s\n1) Instalar/atualizar\n2) Desinstalar\n0) Sair\n' "$VERSION";read -r -p "Opcao: " o;case "$o" in 1) install_agent;;2) uninstall_agent;;*) exit;;esac;;esac
