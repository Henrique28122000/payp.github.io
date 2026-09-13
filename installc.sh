#!/bin/bash
set -e
VERSION="2.4.0"
APP_DIR="/opt/nexyra-link"
CONFIG="$APP_DIR/config.json"
SERVICE="/etc/systemd/system/nexyra-link.service"

need_root() {
  if [ "$(id -u)" != "0" ]; then echo "Execute como root"; exit 1; fi
}

install_deps() {
  apt update -y >/dev/null 2>&1 || true
  apt install -y curl jq iputils-ping openssh-client sshpass nodejs npm >/dev/null 2>&1 || true
}

read_config() {
  read -p "URL base da API [https://api.nexyratech.com.br/netpulse]: " BASE_URL
  BASE_URL=${BASE_URL:-https://api.nexyratech.com.br/netpulse}
  read -p "Chave de instalacao do cliente: " INSTALL_KEY
  [ -z "$INSTALL_KEY" ] && echo "Chave obrigatoria" && exit 1
  mkdir -p "$APP_DIR"
  cat > "$CONFIG" <<EOF
{
  "base_url": "$BASE_URL",
  "key": "$INSTALL_KEY",
  "version": "$VERSION",
  "interval_ms": 30000,
  "mikrotiks": []
}
EOF
}

create_monitor() {
cat > "$APP_DIR/monitor.js" <<'EOF'
const fs = require('fs');
const { execFile } = require('child_process');
const net = require('net');
const cfgPath = '/opt/nexyra-link/config.json';
const statePath = '/opt/nexyra-link/node-state.json';
const queuePath = '/opt/nexyra-link/history-queue.json';
const archivePath = '/opt/nexyra-link/node-history.jsonl';
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
console.log(`Nexyra Link Agent v${cfg.version || '2.4.0'}`);

function readLocal(path, fallback) {
  try { return JSON.parse(fs.readFileSync(path, 'utf8')); } catch { return fallback; }
}

function writeLocal(path, value) {
  const temporary = `${path}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(value));
  fs.renameSync(temporary, path);
}

let nodeState = readLocal(statePath, {});
let historyQueue = readLocal(queuePath, []);

function archiveEvent(event) {
  fs.appendFileSync(archivePath, `${JSON.stringify(event)}\n`);
  if (fs.statSync(archivePath).size > 25 * 1024 * 1024) {
    const lines = fs.readFileSync(archivePath, 'utf8').trim().split('\n').slice(-100000);
    fs.writeFileSync(`${archivePath}.tmp`, lines.join('\n') + '\n');
    fs.renameSync(`${archivePath}.tmp`, archivePath);
  }
}

function post(action, data) {
  const url = `${cfg.base_url.replace(/\/$/, '')}/api.php?action=${action}`;
  return fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) }).catch(() => null);
}

function getPayload() {
  const url = `${cfg.base_url.replace(/\/$/, '')}/api.php?action=get_monitor_payload&key=${encodeURIComponent(cfg.key)}`;
  return fetch(url).then(r => r.json()).catch(() => null);
}

async function flushHistory() {
  while (historyQueue.length) {
    const event = historyQueue[0];
    try {
      const response = await fetch(`${cfg.base_url.replace(/\/$/, '')}/update_node_1.php`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...event, key: cfg.key })
      });
      if (!response.ok) return;
      const result = await response.json();
      if (!result.success) return;
      historyQueue.shift();
      writeLocal(queuePath, historyQueue);
    } catch { return; }
  }
}

function ping(ip) {
  return new Promise(resolve => {
    execFile('ping', ['-c', '1', '-W', '2', ip], err => resolve(!err));
  });
}


function tcpPort(host, port) {
  return new Promise(resolve => {
    const socket = new net.Socket();
    let done = false;
    const finish = ok => {
      if (done) return;
      done = true;
      socket.destroy();
      resolve(ok);
    };
    socket.setTimeout(2500);
    socket.once('connect', () => finish(true));
    socket.once('timeout', () => finish(false));
    socket.once('error', () => finish(false));
    socket.connect(Number(port), host);
  });
}

const FALLBACK_PORTS = [80, 443, 8080, 8443, 8728, 8291, 22, 53];

async function tcpFallback(host) {
  for (const port of FALLBACK_PORTS) {
    if (await tcpPort(host, port)) return { online: true, port };
  }
  return { online: false, port: null };
}
function sshPppoe(mk) {
  return new Promise(resolve => {
    const args = ['-p', String(mk.ssh_port || 22), mk.password || '', 'ssh', '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=8', `${mk.username}@${mk.host}`, '/ppp active print detail without-paging'];
    execFile('sshpass', args, { timeout: 15000 }, (err, stdout) => {
      if (err) return resolve({ error: err.message, clients: [] });
      const clients = stdout.split(/\r?\n/).map(line => {
        const user = (line.match(/name="?([^"\s]+)"?/) || [])[1];
        if (!user) return null;
        return {
          username: user,
          address: (line.match(/address=([^\s]+)/) || [])[1] || null,
          uptime: (line.match(/uptime=([^\s]+)/) || [])[1] || null,
          caller_id: (line.match(/caller-id="?([^"\s]+)"?/) || [])[1] || null,
          service: (line.match(/service=([^\s]+)/) || [])[1] || null
        };
      }).filter(Boolean);
      resolve({ clients });
    });
  });
}

async function tick() {
  await flushHistory();
  const payload = await getPayload();
  if (!payload || !payload.success) return;
  await post('monitoring_heartbeat', { uid: payload.user.uid, server_ip: payload.user.monitoring_ip || 'monitor' });
  for (const node of payload.nodes || []) {
    let online = await ping(node.ip);
    let detected_port = null;
    if (!online) {
      const fallback = await tcpFallback(node.ip);
      online = fallback.online;
      detected_port = fallback.port;
    }
    const status = online ? 'online' : 'offline';
    if (nodeState[node.id] !== status) {
      const event = { id: node.id, uid: payload.user.uid, status, detected_port, checked_at: new Date().toISOString() };
      historyQueue.push(event);
      archiveEvent(event);
      nodeState[node.id] = status;
      writeLocal(statePath, nodeState);
      writeLocal(queuePath, historyQueue);
    } else {
      await fetch(`${cfg.base_url.replace(/\/$/, '')}/update_node_1.php`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: node.id, status, detected_port, checked_at: new Date().toISOString(), key: cfg.key })
      }).catch(() => null);
    }
  }
  await flushHistory();
  const mikrotiks = (payload.mikrotiks || []).filter(mk => mk.password);
  if ((payload.mikrotiks || []).length && !payload.credentials_allowed) console.log('Credenciais bloqueadas para este IP:', payload.request_ip);
  for (const mk of mikrotiks) {
    const result = await sshPppoe(mk);
    if (result.error) {
      await post('mikrotik_error', { key: cfg.key, mikrotik_id: mk.id, error: result.error });
    } else {
      await post('update_pppoe_clients', { key: cfg.key, mikrotik_id: mk.id, clients: result.clients });
    }
  }
}

tick();
setInterval(tick, cfg.interval_ms || 30000);
EOF
}

create_service() {
cat > "$SERVICE" <<EOF
[Unit]
Description=Nexyra Link Monitor
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node $APP_DIR/monitor.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable nexyra-link
systemctl restart nexyra-link
}

need_root
install_deps
read_config
create_monitor
create_service

echo "Nexyra Link Agent v$VERSION instalado."
echo "Use: systemctl status nexyra-link"
echo "As credenciais MikroTik agora vem do banco somente quando o IP deste servidor estiver liberado no app."




