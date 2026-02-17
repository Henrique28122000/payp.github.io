#!/bin/bash
set -e

# ─────────────────────────────────────────
# CORES PARA OUTPUT
# ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ─────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────
APP_NAME="nexyra-link"
APP_DIR="/opt/nexyra-link"
JS_FILE="monitor.js"
CONFIG_FILE="$APP_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
MENU_CMD="/usr/local/bin/nexyra"
BACKUP_DIR="$APP_DIR/backups"
LOG_FILE="$APP_DIR/install.log"

# ─────────────────────────────────────────
# CRIA DIRETÓRIOS
# ─────────────────────────────────────────
echo -e "${BLUE}📂 Criando diretórios...${NC}"
mkdir -p "$APP_DIR"
mkdir -p "$BACKUP_DIR"
mkdir -p "$APP_DIR/logs"

# ─────────────────────────────────────────
# FUNÇÕES DE LOG
# ─────────────────────────────────────────
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERRO]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1" | tee -a "$LOG_FILE"
}

# ─────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────
clear
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║   ███╗   ██╗███████╗██╗  ██╗██╗   ██╗██████╗  █████╗   ║"
echo "║   ████╗  ██║██╔════╝╚██╗██╔╝╚██╗ ██╔╝██╔══██╗██╔══██╗  ║"
echo "║   ██╔██╗ ██║█████╗   ╚███╔╝  ╚████╔╝ ██████╔╝███████║  ║"
echo "║   ██║╚██╗██║██╔══╝   ██╔██╗   ╚██╔╝  ██╔══██╗██╔══██║  ║"
echo "║   ██║ ╚████║███████╗██╔╝ ██╗   ██║   ██║  ██║██║  ██║  ║"
echo "║   ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝  ║"
echo "║                                                          ║"
echo "║              🔗 NEXYRA LINK - MONITOR                   ║"
echo "║         Multi-Empresa | Tempo Real | Notificações       ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

log "🚀 Iniciando instalação do Nexyra Link Monitor"
sleep 2

# ─────────────────────────────────────────
# CHECK ROOT
# ─────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    error "❌ Execute como root (use: sudo su)"
fi

# ─────────────────────────────────────────
# VERIFICA SISTEMA
# ─────────────────────────────────────────
log "📋 Verificando sistema..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
    log "✅ Sistema: $OS $VER"
else
    warning "⚠️ Não foi possível identificar o sistema"
fi

# ─────────────────────────────────────────
# VERIFICA INTERNET
# ─────────────────────────────────────────
log "🌐 Verificando conexão com internet..."
if ping -c 1 google.com &> /dev/null; then
    log "✅ Internet OK"
else
    warning "⚠️ Sem internet, continuando mesmo assim..."
fi

# ─────────────────────────────────────────
# UPDATE SYSTEM
# ─────────────────────────────────────────
log "📦 Atualizando sistema..."
apt update -y >> "$LOG_FILE" 2>&1 || warning "⚠️ Falha no apt update, continuando..."

# ─────────────────────────────────────────
# INSTALA DEPENDÊNCIAS
# ─────────────────────────────────────────
log "📦 Instalando dependências..."
apt install -y curl wget git jq sudo net-tools unzip htop nload >> "$LOG_FILE" 2>&1

# ─────────────────────────────────────────
# VERIFICA NODE.JS
# ─────────────────────────────────────────
if ! command -v node >/dev/null 2>&1; then
    log "📦 Instalando Node.js 18 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >> "$LOG_FILE" 2>&1
    apt install -y nodejs >> "$LOG_FILE" 2>&1
else
    NODE_VER=$(node -v)
    log "✅ Node.js já instalado: $NODE_VER"
fi

# ─────────────────────────────────────────
# VERIFICA NPM
# ─────────────────────────────────────────
if ! command -v npm >/dev/null 2>&1; then
    log "📦 Instalando npm..."
    apt install -y npm >> "$LOG_FILE" 2>&1
fi

# ─────────────────────────────────────────
# ENTRA NO DIRETÓRIO
# ─────────────────────────────────────────
cd "$APP_DIR"

# ─────────────────────────────────────────
# CRIA MONITOR.JS (VERSÃO COMPLETA SEM FETCH)
# ─────────────────────────────────────────
log "📝 Criando monitor.js (versão completa sem fetch)..."

cat > "$JS_FILE" <<'EOF'
const { exec } = require("child_process");
const net = require("net");
const dns = require("dns");
const fs = require("fs");
const http = require("http");
const https = require("https");
const url = require("url");
const os = require("os");

// ============================
// PROTEÇÃO ANTI-FECHAMENTO
// ============================
process.on("uncaughtException", err => {
  console.error("❌ Erro fatal:", err);
});
process.on("unhandledRejection", err => {
  console.error("❌ Promise rejeitada:", err);
});

// ============================
// LOAD CONFIG
// ============================
const config = JSON.parse(fs.readFileSync("./config.json", "utf8"));

const GET_NODES_API = config.apis.get_nodes;
const UPDATE_NODE_API = config.apis.update_node;
const GET_USERS_API = config.apis.get_users;
const UPDATE_SERVER_API = config.apis.update_server;

const TCP_PORTS = config.tcp_ports;
const TIMEOUT_PING = config.timeouts.ping;
const TIMEOUT_TCP = config.timeouts.tcp;
const RETRIES = config.retries;
const CHECK_INTERVAL = config.check_interval_ms;

const isWindows = process.platform === "win32";

// Cache
let serverStatusCache = new Map();
let stats = {
  totalChecks: 0,
  totalChanges: 0,
  startTime: new Date()
};

// ============================
// FUNÇÃO PARA REQUISIÇÕES HTTP
// ============================
function request(options, postData = null) {
  return new Promise((resolve, reject) => {
    const parsedUrl = url.parse(options.url || options);
    const isHttps = parsedUrl.protocol === 'https:';
    const client = isHttps ? https : http;
    
    const requestOptions = {
      hostname: parsedUrl.hostname,
      port: parsedUrl.port || (isHttps ? 443 : 80),
      path: parsedUrl.path,
      method: options.method || 'GET',
      headers: options.headers || { 'Content-Type': 'application/json' },
      timeout: options.timeout || 10000
    };

    const req = client.request(requestOptions, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk;
      });
      
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            const jsonData = JSON.parse(data);
            resolve(jsonData);
          } catch (e) {
            resolve(data);
          }
        } else {
          reject(new Error(`HTTP ${res.statusCode}`));
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });

    if (postData) {
      req.write(JSON.stringify(postData));
    }
    
    req.end();
  });
}

// ============================
// BUSCAR USUÁRIOS
// ============================
async function fetchUsersWithServers() {
  try {
    const users = await request({
      url: GET_USERS_API,
      method: 'GET',
      headers: { 'User-Agent': 'NexyraLink/3.0' },
      timeout: 10000
    });
    
    return Array.isArray(users) ? users : [];
  } catch (err) {
    console.error("❌ Erro ao buscar usuários:", err.message);
    return [];
  }
}

// ============================
// BUSCAR NODES
// ============================
async function fetchUserNodes(userId) {
  try {
    const apiUrl = `${GET_NODES_API}?userId=${userId}`;
    const nodes = await request({
      url: apiUrl,
      method: 'GET',
      headers: { 'User-Agent': 'NexyraLink/3.0' },
      timeout: 10000
    });
    
    return Array.isArray(nodes) ? nodes : [];
  } catch (err) {
    console.error(`❌ Erro ao buscar nodes:`, err.message);
    return [];
  }
}

// ============================
// ATUALIZAR STATUS DO SERVIDOR
// ============================
async function updateServerStatus(uid, isOnline, pingMs, reason) {
  try {
    const now = new Date();
    const lastUpdate = now.getFullYear() + '-' + 
                      String(now.getMonth() + 1).padStart(2, '0') + '-' +
                      String(now.getDate()).padStart(2, '0') + ' ' +
                      String(now.getHours()).padStart(2, '0') + ':' +
                      String(now.getMinutes()).padStart(2, '0') + ':' +
                      String(now.getSeconds()).padStart(2, '0');

    const postData = {
      uid: uid,
      is_online: isOnline,
      last_update: lastUpdate,
      ping_ms: pingMs,
      reason: reason
    };

    await request({
      url: UPDATE_SERVER_API,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      timeout: 5000
    }, postData);
    
    return true;
  } catch (err) {
    console.error(`❌ Erro ao atualizar servidor:`, err.message);
    return false;
  }
}

// ============================
// ATUALIZAR STATUS DO NODE
// ============================
async function updateNodeStatus(data) {
  try {
    await request({
      url: UPDATE_NODE_API,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      timeout: 5000
    }, data);
    return true;
  } catch (err) {
    console.error(`❌ Erro ao atualizar node:`, err.message);
    return false;
  }
}

// ============================
// DNS CHECK
// ============================
function checkDNS(host) {
  return new Promise(resolve => {
    dns.lookup(host, err => resolve(!err));
  });
}

// ============================
// ICMP PING
// ============================
function pingICMP(host, timeout = TIMEOUT_PING) {
  return new Promise(resolve => {
    const start = Date.now();
    const cmd = `ping -c 1 -W ${Math.ceil(timeout/1000)} ${host}`;

    exec(cmd, (err, stdout) => {
      if (err) {
        return resolve({ online: false });
      }

      const match = stdout.match(/(time|tempo)[=<]\s*(\d+)/i);
      const ms = match ? parseInt(match[2], 10) : null;
      
      resolve({ 
        online: true, 
        ms: ms || (Date.now() - start)
      });
    });
  });
}

// ============================
// TCP CHECK
// ============================
function checkTCP(host, ports = TCP_PORTS, timeout = TIMEOUT_TCP) {
  return new Promise(resolve => {
    let finished = false;
    let checked = 0;

    ports.forEach(port => {
      const socket = new net.Socket();
      socket.setTimeout(timeout);

      const start = Date.now();

      socket.connect(port, host, () => {
        if (!finished) {
          const ms = Date.now() - start;
          finished = true;
          socket.destroy();
          resolve({ online: true, port, ms });
        }
      });

      socket.on("error", () => {
        socket.destroy();
        checked++;
        if (!finished && checked === ports.length) {
          finished = true;
          resolve({ online: false });
        }
      });

      socket.on("timeout", () => {
        socket.destroy();
        checked++;
        if (!finished && checked === ports.length) {
          finished = true;
          resolve({ online: false });
        }
      });
    });
  });
}

// ============================
// CHECK COMPLETO DE HOST
// ============================
async function checkHost(host) {
  if (!host || host.trim() === '') {
    return { online: false, reason: "IP não configurado" };
  }

  if (!isIP(host)) {
    const dnsOk = await checkDNS(host);
    if (!dnsOk) return { online: false, reason: "DNS falhou" };
  }

  for (let i = 0; i <= RETRIES; i++) {
    const ping = await pingICMP(host);
    if (ping.online) {
      return { 
        online: true, 
        ms: ping.ms, 
        method: "icmp"
      };
    }

    const tcp = await checkTCP(host);
    if (tcp.online) {
      return { 
        online: true, 
        ms: tcp.ms,
        method: `tcp:${tcp.port}`
      };
    }

    if (i < RETRIES) await sleep(1000);
  }

  return { 
    online: false, 
    reason: "timeout"
  };
}

// ============================
// VERIFICA SERVIDOR DE UM USUÁRIO
// ============================
async function checkUserServer(user) {
  if (!user.monitoring_ip) return null;
  if (user.monitoring_enabled === 0) return null;

  const result = await checkHost(user.monitoring_ip);
  const isOnline = result.online ? 1 : 0;

  await updateServerStatus(
    user.uid,
    isOnline,
    result.ms || null,
    result.reason || null
  );

  return { is_online: isOnline, ip: user.monitoring_ip, result };
}

// ============================
// VERIFICA TODOS OS SERVIDORES
// ============================
async function checkAllServers() {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`📡 VERIFICANDO SERVIDORES - ${new Date().toLocaleString()}`);
  console.log(`${'='.repeat(60)}`);
  
  const users = await fetchUsersWithServers();
  
  if (users.length === 0) {
    console.log("⚠️ Nenhum servidor configurado");
    return;
  }

  let online = 0;
  let offline = 0;

  for (const user of users) {
    if (user.monitoring_ip) {
      const status = await checkUserServer(user);
      if (status) {
        if (status.is_online) online++;
        else offline++;
        console.log(`   ${status.is_online ? '✅' : '❌'} ${user.email} - ${user.monitoring_ip} ${status.result.ms ? `[${status.result.ms}ms]` : ''}`);
      }
    }
    await sleep(500);
  }

  console.log(`\n📊 RESUMO: ${online} online, ${offline} offline`);
  stats.totalChecks++;
}

// ============================
// VERIFICA NODES DE UM USUÁRIO
// ============================
async function checkUserNodes(user) {
  if (!user.monitoring_ip) return;

  const nodes = await fetchUserNodes(user.uid);
  
  if (nodes.length === 0) return;

  console.log(`\n🔍 VERIFICANDO NODES DE: ${user.email} (${nodes.length})`);

  let alterados = 0;

  for (const node of nodes) {
    if (!node?.ip) continue;

    const result = await checkHost(node.ip);
    const newStatus = result.online ? "online" : "offline";

    if (newStatus !== node.status) {
      console.log(`   ⚡ ${node.ip} mudou: ${node.status} → ${newStatus} ${result.ms ? `[${result.ms}ms]` : ''}`);
      
      await updateNodeStatus({
        id: node.id,
        status: newStatus,
        last_ping: result.ms || null
      });

      alterados++;
      stats.totalChanges++;
    }

    await sleep(300);
  }

  if (alterados > 0) {
    console.log(`   ✅ ${alterados} alterações em ${user.email}`);
  }
}

// ============================
// VERIFICA TODOS OS NODES
// ============================
async function checkAllNodes() {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`🔄 VERIFICANDO NODES - ${new Date().toLocaleString()}`);
  console.log(`${'='.repeat(60)}`);
  
  const users = await fetchUsersWithServers();
  
  for (const user of users) {
    if (user.monitoring_ip) {
      await checkUserNodes(user);
    }
  }
}

// ============================
// MOSTRA ESTATÍSTICAS
// ============================
function showStats() {
  const uptime = Math.floor((Date.now() - stats.startTime) / 1000);
  const hours = Math.floor(uptime / 3600);
  const minutes = Math.floor((uptime % 3600) / 60);
  const seconds = uptime % 60;

  console.log(`\n📊 ESTATÍSTICAS:`);
  console.log(`   ⏱️  Uptime: ${hours}h ${minutes}m ${seconds}s`);
  console.log(`   🔄 Verificações: ${stats.totalChecks}`);
  console.log(`   ⚡ Total de alterações: ${stats.totalChanges}`);
  console.log(`   🖥️  Hostname: ${os.hostname()}`);
  console.log(`   💾 Memória livre: ${Math.round(os.freemem() / 1024 / 1024)}MB`);
}

// ============================
// LOOP PRINCIPAL
// ============================
(async () => {
  console.log("\n" + "=".repeat(70));
  console.log("🚀 Nexyra Link v3.0 - Monitoramento Multi-Empresa");
  console.log("=".repeat(70));
  console.log(`⏱️  Intervalo: ${CHECK_INTERVAL/1000}s`);
  console.log(`📡 GET Users: ${GET_USERS_API}`);
  console.log(`📡 GET Nodes: ${GET_NODES_API}`);
  console.log("=".repeat(70) + "\n");

  // Primeira verificação
  await checkAllServers();
  await checkAllNodes();
  showStats();

  while (true) {
    const startTime = Date.now();
    
    try {
      await checkAllServers();
      await checkAllNodes();
      showStats();
    } catch (err) {
      console.error("❌ Erro no loop principal:", err);
    }

    const elapsed = Date.now() - startTime;
    const waitTime = Math.max(5000, CHECK_INTERVAL - elapsed);
    
    console.log(`\n⏳ Aguardando ${Math.round(waitTime/1000)}s...\n`);
    await sleep(waitTime);
  }
})();
EOF

log "✅ monitor.js criado com sucesso"

# ─────────────────────────────────────────
# CRIA CONFIG.JSON COMPLETO
# ─────────────────────────────────────────
log "⚙️ Criando config.json..."

cat > "$CONFIG_FILE" <<EOF
{
  "apis": {
    "get_users": "https://nexyra.myftp.biz/netpulse/get_users_with_servers.php",
    "get_nodes": "https://nexyra.myftp.biz/netpulse/get_nodes_1.php",
    "update_node": "https://nexyra.myftp.biz/netpulse/update_node_1.php",
    "update_server": "https://nexyra.myftp.biz/netpulse/update_server_status.php"
  },
  "tcp_ports": [80, 443, 22, 21, 8080, 3306, 5432],
  "timeouts": {
    "ping": 3000,
    "tcp": 2000
  },
  "retries": 2,
  "check_interval_ms": 30000,
  "log_level": "info"
}
EOF

log "✅ config.json criado"

# ─────────────────────────────────────────
# CRIA SCRIPTS AUXILIARES COMPLETOS
# ─────────────────────────────────────────
log "📝 Criando scripts auxiliares..."

# Script: start.sh
cat > start.sh <<'EOF'
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}▶️ Iniciando Nexyra Link...${NC}"
systemctl start nexyra-link
sleep 2
echo -e "${GREEN}✅ Serviço iniciado${NC}"
echo ""
systemctl status nexyra-link --no-pager
EOF

# Script: stop.sh
cat > stop.sh <<'EOF'
#!/bin/bash
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}⏹️ Parando Nexyra Link...${NC}"
systemctl stop nexyra-link
echo -e "${GREEN}✅ Serviço parado${NC}"
EOF

# Script: restart.sh
cat > restart.sh <<'EOF'
#!/bin/bash
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔄 Reiniciando Nexyra Link...${NC}"
systemctl restart nexyra-link
sleep 2
echo -e "${GREEN}✅ Serviço reiniciado${NC}"
echo ""
systemctl status nexyra-link --no-pager
EOF

# Script: logs.sh
cat > logs.sh <<'EOF'
#!/bin/bash
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}📄 LOGS EM TEMPO REAL${NC}"
echo -e "${YELLOW}Pressione Ctrl+C para sair${NC}"
echo ""
journalctl -u nexyra-link -f -o cat
EOF

# Script: status.sh
cat > status.sh <<'EOF'
#!/bin/bash
PURPLE='\033[0;35m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${PURPLE}📊 STATUS DO MONITOR${NC}"
echo "═══════════════════════════════"

# Status do serviço
if systemctl is-active --quiet nexyra-link; then
    echo -e "Serviço: ${GREEN}● ATIVO${NC}"
else
    echo -e "Serviço: ${RED}○ INATIVO${NC}"
fi

# Últimas 20 linhas de log
echo ""
echo -e "${YELLOW}Últimas 20 linhas de log:${NC}"
echo "───────────────────────────────"
journalctl -u nexyra-link -n 20 --no-pager -o cat | tail -20

echo ""
echo -e "${YELLOW}Para ver logs em tempo real:${NC} nexyra logs"
EOF

# Script: test.sh
cat > test.sh <<'EOF'
#!/bin/bash
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

CONFIG="/opt/nexyra-link/config.json"

echo -e "${CYAN}🔍 TESTANDO APIs${NC}"
echo "═══════════════════════════════"

# Carrega URLs
GET_USERS=$(jq -r '.apis.get_users' "$CONFIG")
GET_NODES=$(jq -r '.apis.get_nodes' "$CONFIG")
UPDATE_NODE=$(jq -r '.apis.update_node' "$CONFIG")
UPDATE_SERVER=$(jq -r '.apis.update_server' "$CONFIG")

test_api() {
    local url=$1
    local name=$2
    
    echo -n "📡 $name... "
    if curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" | grep -q "200"; then
        echo -e "${GREEN}OK${NC}"
    elif curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" | grep -q "404"; then
        echo -e "${YELLOW}OK (404 - Rota existe)${NC}"
    else
        echo -e "${RED}FALHOU${NC}"
    fi
}

test_api "$GET_USERS" "GET Users"
test_api "$GET_NODES?userId=test" "GET Nodes"
test_api "$UPDATE_NODE" "UPDATE Node"
test_api "$UPDATE_SERVER" "UPDATE Server"

echo ""
echo -e "${CYAN}⚙️ Configurações atuais:${NC}"
jq '.' "$CONFIG"
EOF

# Script: edit.sh
cat > edit.sh <<'EOF'
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CONFIG="/opt/nexyra-link/config.json"

echo -e "${GREEN}🔧 EDITAR CONFIGURAÇÃO${NC}"
echo "═══════════════════════════════"
echo -e "${YELLOW}Opções disponíveis:${NC}"
echo "1) Editar APIs"
echo "2) Editar intervalo"
echo "3) Editar portas TCP"
echo "4) Editar timeouts"
echo "5) Abrir editor completo (nano)"
echo "0) Voltar"
echo ""
read -p "Escolha: " opt

case $opt in
    1)
        current=$(jq -r '.apis.get_users' "$CONFIG")
        echo "GET Users atual: $current"
        read -p "Nova URL: " new
        [ -n "$new" ] && jq ".apis.get_users=\"$new\"" "$CONFIG" > tmp && mv tmp "$CONFIG"
        
        current=$(jq -r '.apis.get_nodes' "$CONFIG")
        echo "GET Nodes atual: $current"
        read -p "Nova URL: " new
        [ -n "$new" ] && jq ".apis.get_nodes=\"$new\"" "$CONFIG" > tmp && mv tmp "$CONFIG"
        
        echo -e "${GREEN}✅ APIs atualizadas${NC}"
        ;;
    2)
        current=$(jq '.check_interval_ms' "$CONFIG")
        current_min=$((current / 60000))
        echo "Intervalo atual: $current_min minutos"
        read -p "Novo intervalo em minutos: " min
        if [[ "$min" =~ ^[0-9]+$ ]] && [ "$min" -gt 0 ]; then
            ms=$((min * 60000))
            jq ".check_interval_ms=$ms" "$CONFIG" > tmp && mv tmp "$CONFIG"
            echo -e "${GREEN}✅ Intervalo alterado para $min minutos${NC}"
        fi
        ;;
    3)
        current=$(jq '.tcp_ports[]' "$CONFIG" | tr '\n' ' ')
        echo "Portas atuais: $current"
        read -p "Novas portas (separadas por espaço): " -a ports
        if [ ${#ports[@]} -gt 0 ]; then
            ports_json=$(printf '%s\n' "${ports[@]}" | jq -R . | jq -s .)
            jq ".tcp_ports=$ports_json" "$CONFIG" > tmp && mv tmp "$CONFIG"
            echo -e "${GREEN}✅ Portas atualizadas${NC}"
        fi
        ;;
    4)
        current=$(jq '.timeouts.ping' "$CONFIG")
        echo "Timeout ping atual: $current ms"
        read -p "Novo timeout ping (ms): " ping
        [[ "$ping" =~ ^[0-9]+$ ]] && jq ".timeouts.ping=$ping" "$CONFIG" > tmp && mv tmp "$CONFIG"
        
        current=$(jq '.timeouts.tcp' "$CONFIG")
        echo "Timeout TCP atual: $current ms"
        read -p "Novo timeout TCP (ms): " tcp
        [[ "$tcp" =~ ^[0-9]+$ ]] && jq ".timeouts.tcp=$tcp" "$CONFIG" > tmp && mv tmp "$CONFIG"
        
        echo -e "${GREEN}✅ Timeouts atualizados${NC}"
        ;;
    5)
        nano "$CONFIG"
        echo -e "${GREEN}✅ Configuração salva${NC}"
        ;;
    *) return ;;
esac

echo ""
echo -e "${YELLOW}Reinicie o serviço para aplicar:${NC} nexyra restart"
sleep 3
EOF

# Script: backup.sh
cat > backup.sh <<'EOF'
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BACKUP_DIR="/opt/nexyra-link/backups"
DATE=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="$BACKUP_DIR/backup_$DATE.tar.gz"

echo -e "${GREEN}📦 Criando backup...${NC}"
tar -czf "$BACKUP_FILE" /opt/nexyra-link/*.js /opt/nexyra-link/*.json /opt/nexyra-link/*.sh 2>/dev/null

if [ -f "$BACKUP_FILE" ]; then
    echo -e "${GREEN}✅ Backup criado: $BACKUP_FILE${NC}"
    echo ""
    echo -e "${YELLOW}Backups disponíveis:${NC}"
    ls -lh "$BACKUP_DIR" | tail -5
else
    echo -e "${YELLOW}⚠️ Nenhum arquivo para backup${NC}"
fi
EOF

# Script: restore.sh
cat > restore.sh <<'EOF'
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BACKUP_DIR="/opt/nexyra-link/backups"

echo -e "${GREEN}🔄 RESTAURAR BACKUP${NC}"
echo "═══════════════════════════════"

if [ ! "$(ls -A $BACKUP_DIR)" ]; then
    echo -e "${RED}❌ Nenhum backup encontrado${NC}"
    exit 1
fi

echo -e "${YELLOW}Backups disponíveis:${NC}"
ls -lh "$BACKUP_DIR" | tail -10

echo ""
read -p "Nome do arquivo de backup: " filename

if [ -f "$BACKUP_DIR/$filename" ]; then
    echo "Restaurando..."
    tar -xzf "$BACKUP_DIR/$filename" -C /
    echo -e "${GREEN}✅ Backup restaurado${NC}"
    echo -e "${YELLOW}Reinicie o serviço:${NC} nexyra restart"
else
    echo -e "${RED}❌ Arquivo não encontrado${NC}"
fi
EOF

# Script: monitor.sh
cat > monitor.sh <<'EOF'
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

while true; do
    clear
    echo -e "${CYAN}📊 MONITOR EM TEMPO REAL${NC}"
    echo "═══════════════════════════════"
    echo ""
    
    # Status do serviço
    if systemctl is-active --quiet nexyra-link; then
        echo -e "Serviço: ${GREEN}● ATIVO${NC}"
    else
        echo -e "Serviço: ${RED}○ INATIVO${NC}"
    fi
    
    # Últimas 5 linhas do log
    echo ""
    echo -e "${YELLOW}Últimas atualizações:${NC}"
    journalctl -u nexyra-link -n 5 --no-pager -o cat | tail -5
    
    # Uso de recursos
    echo ""
    echo -e "${CYAN}Uso de recursos:${NC}"
    ps aux | grep node | grep -v grep || echo "Node não está rodando"
    
    echo ""
    echo -e "${YELLOW}Atualizando a cada 5 segundos... (Ctrl+C para sair)${NC}"
    sleep 5
done
EOF

chmod +x *.sh
log "✅ Scripts auxiliares criados"

# ─────────────────────────────────────────
# CRIA MENU PRINCIPAL AVANÇADO
# ─────────────────────────────────────────
log "📝 Criando menu principal..."

cat > menu.sh <<'EOF'
#!/bin/bash

# ========================================
# NEXYRA LINK - MENU PRINCIPAL
# ========================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

APP_DIR="/opt/nexyra-link"
CONFIG="$APP_DIR/config.json"

# ========================================
# FUNÇÕES DO MENU
# ========================================

show_header() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║              NEXYRA LINK - MONITOR v3.0                  ║"
    echo "║              Multi-Empresa | Tempo Real                  ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

show_stats() {
    if systemctl is-active --quiet nexyra-link; then
        echo -e " ${GREEN}●${NC} Serviço: ${GREEN}ATIVO${NC}"
    else
        echo -e " ${RED}○${NC} Serviço: ${RED}INATIVO${NC}"
    fi
    
    if [ -f "$CONFIG" ]; then
        INTERVAL=$(jq '.check_interval_ms' "$CONFIG")
        MIN=$((INTERVAL / 60000))
        echo -e " ⏱️  Intervalo: ${YELLOW}${MIN} minutos${NC}"
        
        GET_USERS=$(jq -r '.apis.get_users' "$CONFIG" | cut -c1-50)
        echo -e " 📡 API: ${CYAN}${GET_USERS}...${NC}"
    fi
    echo ""
}

# Menu principal
while true; do
    show_header
    show_stats
    
    echo -e "${WHITE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    CONTROLE DO SERVIÇO                 ║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC}  ${GREEN}1)${NC} ▶️  INICIAR monitor              ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${RED}2)${NC} ⏹️  PARAR monitor                ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${BLUE}3)${NC} 🔄  REINICIAR monitor            ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${PURPLE}4)${NC} 📊  STATUS do serviço           ${WHITE}║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║                    VISUALIZAÇÃO                        ║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC}  ${CYAN}5)${NC} 📄  LOGS em tempo real           ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${CYAN}6)${NC} 📋  Últimas 50 linhas            ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${CYAN}7)${NC} 🔍  MONITOR em tempo real        ${WHITE}║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║                    CONFIGURAÇÕES                       ║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC}  ${YELLOW}8)${NC} 🔧  EDITAR configurações        ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${YELLOW}9)${NC} ⏱️   EDITAR intervalo           ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${YELLOW}10)${NC} 🔌 EDITAR portas TCP           ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${YELLOW}11)${NC} 🌐 EDITAR APIs                 ${WHITE}║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║                    FERRAMENTAS                         ║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC}  ${PURPLE}12)${NC} 🔍 TESTAR APIs                 ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${PURPLE}13)${NC} 📦 CRIAR backup                ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${PURPLE}14)${NC} 🔄 RESTAURAR backup            ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${PURPLE}15)${NC} 🚀 AUTO START (ativar)         ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${PURPLE}16)${NC} ❌ AUTO START (desativar)      ${WHITE}║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC}  ${RED}0)${NC} 🚪 SAIR                           ${WHITE}║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "👉 Escolha uma opção [0-16]: " opt

    case $opt in
        1) ./start.sh ;;
        2) ./stop.sh ;;
        3) ./restart.sh ;;
        4) ./status.sh && read -p "Pressione Enter..." ;;
        5) ./logs.sh ;;
        6) journalctl -u nexyra-link -n 50 --no-pager && read -p "Pressione Enter..." ;;
        7) ./monitor.sh ;;
        8) ./edit.sh ;;
        9) 
            current=$(jq '.check_interval_ms' "$CONFIG")
            current_min=$((current / 60000))
            echo -e "${YELLOW}Intervalo atual: $current_min minutos${NC}"
            read -p "Novo intervalo em minutos: " min
            if [[ "$min" =~ ^[0-9]+$ ]] && [ "$min" -gt 0 ]; then
                ms=$((min * 60000))
                jq ".check_interval_ms=$ms" "$CONFIG" > tmp && mv tmp "$CONFIG"
                echo -e "${GREEN}✅ Intervalo alterado para $min minutos${NC}"
                echo -e "${YELLOW}Reinicie o serviço: opção 3${NC}"
            fi
            sleep 2
            ;;
        10) ./edit.sh ;;
        11) ./edit.sh ;;
        12) ./test.sh && read -p "Pressione Enter..." ;;
        13) ./backup.sh && read -p "Pressione Enter..." ;;
        14) ./restore.sh && read -p "Pressione Enter..." ;;
        15) 
            systemctl enable nexyra-link
            echo -e "${GREEN}✅ Auto start ativado${NC}"
            sleep 2
            ;;
        16) 
            systemctl disable nexyra-link
            echo -e "${RED}❌ Auto start desativado${NC}"
            sleep 2
            ;;
        0) 
            echo -e "${GREEN}Até logo! 👋${NC}"
            exit 0
            ;;
        *) 
            echo -e "${RED}Opção inválida!${NC}"
            sleep 2
            ;;
    esac
done
EOF

chmod +x menu.sh
log "✅ Menu principal criado"

# ─────────────────────────────────────────
# CRIA COMANDO GLOBAL
# ─────────────────────────────────────────
log "🔗 Criando comando global 'nexyra'..."
ln -sf "$APP_DIR/menu.sh" "$MENU_CMD"
chmod +x "$MENU_CMD"

# ─────────────────────────────────────────
# CRIA SERVICE SYSTEMD
# ─────────────────────────────────────────
log "⚙️ Criando serviço systemd..."

NODE_PATH=$(which node)

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Nexyra Link Monitor - Multi-Empresa
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=$NODE_PATH $APP_DIR/$JS_FILE
Restart=always
RestartSec=5
User=root
Group=root
Environment=NODE_ENV=production
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nexyra-link

[Install]
WantedBy=multi-user.target
EOF

log "✅ Serviço systemd criado"

# ─────────────────────────────────────────
# ATIVA E INICIA SERVIÇO
# ─────────────────────────────────────────
log "🚀 Ativando e iniciando serviço..."
systemctl daemon-reload
systemctl enable nexyra-link >> "$LOG_FILE" 2>&1
systemctl restart nexyra-link >> "$LOG_FILE" 2>&1

# ─────────────────────────────────────────
# CONFIGURA MENU NO SSH
# ─────────────────────────────────────────
if ! grep -q "nexyra" /root/.bashrc; then
    echo "" >> /root/.bashrc
    echo "# Nexyra Link Monitor" >> /root/.bashrc
    echo "echo -e '${GREEN}🔗 Digite ${WHITE}nexyra${GREEN} para abrir o menu do Nexyra Link${NC}'" >> /root/.bashrc
fi

# ─────────────────────────────────────────
# VERIFICA INSTALAÇÃO
# ─────────────────────────────────────────
sleep 3
if systemctl is-active --quiet nexyra-link; then
    echo -e "${GREEN}✅ Serviço está rodando!${NC}"
else
    warning "⚠️ Serviço não está rodando, verificando logs..."
    journalctl -u nexyra-link -n 10 --no-pager
fi

# ─────────────────────────────────────────
# LIMPA TELA E MOSTRA RESUMO
# ─────────────────────────────────────────
clear
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║       ✅ INSTALAÇÃO 100% CONCLUÍDA COM SUCESSO          ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}📋 INFORMAÇÕES DO SISTEMA${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e " 📂 Diretório: ${YELLOW}$APP_DIR${NC}"
echo -e " ⚙️  Config: ${YELLOW}$CONFIG_FILE${NC}"
echo -e " 🖥️  Node: ${YELLOW}$(node -v)${NC}"
echo -e " 📝 Log: ${YELLOW}$LOG_FILE${NC}"
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}🔗 APIS CONFIGURADAS${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e " 📡 GET Users:  ${GREEN}https://nexyra.myftp.biz/netpulse/get_users_with_servers.php${NC}"
echo -e " 📡 GET Nodes:  ${GREEN}https://nexyra.myftp.biz/netpulse/get_nodes_1.php${NC}"
echo -e " 📡 UPDATE Node: ${GREEN}https://nexyra.myftp.biz/netpulse/update_node_1.php${NC}"
echo -e " 📡 UPDATE Server: ${GREEN}https://nexyra.myftp.biz/netpulse/update_server_status.php${NC}"
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}🚀 COMANDOS DISPONÍVEIS${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e " ${GREEN}▶️${NC} ${WHITE}nexyra${NC}        → Abrir menu interativo completo"
echo -e " ${GREEN}▶️${NC} ${WHITE}systemctl status nexyra-link${NC} → Status do serviço"
echo -e " ${GREEN}▶️${NC} ${WHITE}journalctl -u nexyra-link -f${NC} → Logs em tempo real"
echo -e " ${GREEN}▶️${NC} ${WHITE}cd $APP_DIR && ./menu.sh${NC} → Menu pelo diretório"
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}📌 EXPLICAÇÃO DAS OPÇÕES DO MENU${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e " ${GREEN}1) INICIAR${NC}     → Liga o serviço de monitoramento"
echo -e " ${RED}2) PARAR${NC}       → Desliga o serviço"
echo -e " ${BLUE}3) REINICIAR${NC}   → Reinicia o serviço (aplica alterações)"
echo -e " ${PURPLE}4) STATUS${NC}      → Mostra status detalhado do serviço"
echo -e " ${CYAN}5) LOGS${NC}        → Mostra logs em tempo real (Ctrl+C sai)"
echo -e " ${CYAN}6) ÚLTIMAS${NC}     → Mostra últimas 50 linhas de log"
echo -e " ${CYAN}7) MONITOR${NC}     → Monitor em tempo real com atualização automática"
echo -e " ${YELLOW}8) EDITAR${NC}      → Menu completo de edição de configurações"
echo -e " ${YELLOW}9) INTERVALO${NC}   → Altera rápido o intervalo de verificação"
echo -e " ${YELLOW}10) PORTAS${NC}     → Edita as portas TCP para verificação"
echo -e " ${YELLOW}11) APIs${NC}       → Edita as URLs das APIs"
echo -e " ${PURPLE}12) TESTAR${NC}     → Testa a conectividade com todas as APIs"
echo -e " ${PURPLE}13) BACKUP${NC}     → Cria um backup das configurações"
echo -e " ${PURPLE}14) RESTAURAR${NC}  → Restaura um backup anterior"
echo -e " ${PURPLE}15) AUTO START${NC} → Ativa inicialização automática no boot"
echo -e " ${PURPLE}16) AUTO START${NC} → Desativa inicialização automática"
echo -e " ${RED}0) SAIR${NC}        → Fecha o menu"
echo ""

echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}✨ O menu abrirá automaticamente na próxima vez que conectar via SSH!${NC}"
echo -e "${GREEN}👉 Digite 'nexyra' para abrir o menu AGORA!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Pergunta se quer abrir o menu
read -p "❓ Deseja abrir o menu agora? (s/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Ss]$ ]]; then
    cd "$APP_DIR"
    ./menu.sh
fi
