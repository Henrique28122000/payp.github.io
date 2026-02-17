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
NC='\033[0m'

# ─────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────
APP_NAME="nexyra-link"
APP_DIR="/opt/nexyra-link"
JS_FILE="monitor.js"
JS_URL="https://raw.githubusercontent.com/Henrique28122000/payp.github.io/refs/heads/main/nexyra-monitor.js"
CONFIG_FILE="$APP_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
MENU_CMD="/usr/local/bin/nexyra"

# ─────────────────────────────────────────
# CRIA DIRETÓRIO PRIMEIRO
# ─────────────────────────────────────────
echo -e "${BLUE}📂 Criando diretório $APP_DIR...${NC}"
mkdir -p "$APP_DIR"

LOG_FILE="$APP_DIR/install.log"

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
echo "║                    Versão Simplificada                  ║"
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
# UPDATE SYSTEM
# ─────────────────────────────────────────
log "📦 Atualizando sistema..."
apt update -y >> "$LOG_FILE" 2>&1 || warning "⚠️ Falha no apt update, continuando..."

# ─────────────────────────────────────────
# INSTALA DEPENDÊNCIAS
# ─────────────────────────────────────────
log "📦 Instalando dependências..."
apt install -y curl wget git jq sudo net-tools unzip >> "$LOG_FILE" 2>&1

# ─────────────────────────────────────────
# VERIFICA NODE.JS
# ─────────────────────────────────────────
if ! command -v node >/dev/null 2>&1; then
    log "📦 Instalando Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> "$LOG_FILE" 2>&1
    apt install -y nodejs >> "$LOG_FILE" 2>&1
else
    NODE_VER=$(node -v)
    log "✅ Node.js já instalado: $NODE_VER"
fi

# ─────────────────────────────────────────
# ENTRA NO DIRETÓRIO
# ─────────────────────────────────────────
cd "$APP_DIR"

# ─────────────────────────────────────────
# BAIXA SCRIPT JS SIMPLIFICADO
# ─────────────────────────────────────────
log "⬇️ Baixando monitor simplificado..."

# Criar script monitor.js diretamente com seus links
cat > "$JS_FILE" <<'EOF'
const { exec } = require("child_process");
const net = require("net");
const dns = require("dns");
const fs = require("fs");

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

const GET_API = config.apis.get_nodes;
const UPDATE_API = config.apis.update_node;

const TCP_PORTS = config.tcp_ports;
const TIMEOUT_PING = config.timeouts.ping;
const TIMEOUT_TCP = config.timeouts.tcp;
const RETRIES = config.retries;
const CHECK_INTERVAL = config.check_interval_ms;

const isWindows = process.platform === "win32";

// ============================
// UTIL
// ============================
const sleep = ms => new Promise(r => setTimeout(r, ms));
const isIP = host => /^(\d{1,3}\.){3}\d{1,3}$/.test(host);

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
    const cmd = isWindows
      ? `ping -n 1 -w ${timeout} ${host}`
      : `ping -c 1 -W ${Math.ceil(timeout/1000)} ${host}`;

    exec(cmd, (err, stdout) => {
      if (err) return resolve({ online: false });

      const match = stdout.match(/(tempo|time)[=<]\s*(\d+)/i);
      const ms = match ? parseInt(match[2], 10) : null;
      const timeSpent = Date.now() - start;

      resolve({ 
        online: true, 
        ms: ms || timeSpent 
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
// CHECK COMPLETO
// ============================
async function isOnline(host) {
  if (!isIP(host)) {
    const dnsOk = await checkDNS(host);
    if (!dnsOk) return { online: false, reason: "dns_failed" };
  }

  for (let i = 0; i <= RETRIES; i++) {
    const ping = await pingICMP(host);
    if (ping.online) {
      return { 
        online: true, 
        ms: ping.ms, 
        method: "icmp",
        attempts: i + 1 
      };
    }

    const tcp = await checkTCP(host);
    if (tcp.online) {
      return { 
        online: true, 
        ms: tcp.ms || null,
        method: `tcp:${tcp.port}`,
        attempts: i + 1 
      };
    }

    if (i < RETRIES) await sleep(1000);
  }

  return { 
    online: false, 
    reason: "timeout",
    attempts: RETRIES + 1 
  };
}

// ============================
// VERIFICA TODOS OS NÓS
// ============================
async function checkAllNodes() {
  console.log(`\n🔄 Verificação - ${new Date().toLocaleTimeString()}`);

  let nodes = [];
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);

    const res = await fetch(GET_API, {
      signal: controller.signal,
      headers: { "User-Agent": "NexyraLink/1.0" }
    });
    
    clearTimeout(timeoutId);
    
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    
    nodes = await res.json();
    
    if (!Array.isArray(nodes)) {
      throw new Error("Resposta não é array");
    }
    
  } catch (err) {
    console.error("❌ Erro ao buscar nós:", err.message);
    return;
  }

  console.log(`📊 Total de nós: ${nodes.length}`);

  let alterados = 0;

  for (const node of nodes) {
    if (!node?.ip) continue;

    try {
      console.log(`🔍 Verificando ${node.ip}...`);
      
      const result = await isOnline(node.ip);
      const newStatus = result.online ? "online" : "offline";

      if (newStatus !== node.status) {
        console.log(`⚡ ${node.ip} mudou: ${node.status} → ${newStatus} ${result.method ? `[${result.method}]` : ''}`);
        
        const updateData = {
          id: node.id,
          status: newStatus,
          last_ping: result.ms || null
        };

        const updateRes = await fetch(UPDATE_API, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(updateData)
        });

        if (updateRes.ok) {
          alterados++;
          console.log(`✅ Atualizado: ${node.ip} → ${newStatus}`);
        } else {
          console.error(`❌ Falha ao atualizar ${node.ip}: HTTP ${updateRes.status}`);
        }
      } else {
        console.log(`✅ ${node.ip} permanece ${newStatus}`);
      }

      await sleep(500);
      
    } catch (err) {
      console.error(`⚠️ Erro no IP ${node.ip}:`, err.message);
    }
  }

  console.log(`✅ Verificação concluída. ${alterados} alterações.`);
}

// ============================
// LOOP PRINCIPAL
// ============================
(async () => {
  console.log("=".repeat(50));
  console.log("🚀 Nexyra Link Monitor - Iniciado");
  console.log(`⏱️  Intervalo: ${CHECK_INTERVAL/1000}s`);
  console.log(`📡 API: ${GET_API}`);
  console.log("=".repeat(50));

  while (true) {
    const startTime = Date.now();
    
    try {
      await checkAllNodes();
    } catch (err) {
      console.error("❌ Erro no loop principal:", err);
    }

    const elapsed = Date.now() - startTime;
    const waitTime = Math.max(1000, CHECK_INTERVAL - elapsed);
    
    console.log(`⏳ Aguardando ${Math.round(waitTime/1000)}s...\n`);
    await sleep(waitTime);
  }
})();
EOF

log "✅ Script monitor.js criado"

# ─────────────────────────────────────────
# CRIA CONFIG.JSON COM SEUS LINKS
# ─────────────────────────────────────────
log "⚙️ Criando arquivo de configuração com seus links..."

cat > "$CONFIG_FILE" <<EOF
{
  "apis": {
    "get_nodes": "https://nexyra.myftp.biz/netpulse/get_nodes_1.php",
    "update_node": "https://nexyra.myftp.biz/netpulse/update_node_1.php"
  },
  "tcp_ports": [80, 443, 22, 21, 8080],
  "timeouts": {
    "ping": 3000,
    "tcp": 2000
  },
  "retries": 2,
  "check_interval_ms": 30000
}
EOF

log "✅ Configuração criada com seus links"

# ─────────────────────────────────────────
# CRIA SCRIPTS AUXILIARES SIMPLES
# ─────────────────────────────────────────
log "📝 Criando scripts auxiliares..."

# Script de start
cat > start.sh <<'EOF'
#!/bin/bash
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}▶️ Iniciando Nexyra Link...${NC}"
systemctl start nexyra-link
sleep 2
systemctl status nexyra-link --no-pager
EOF

# Script de stop
cat > stop.sh <<'EOF'
#!/bin/bash
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}⏹️ Parando Nexyra Link...${NC}"
systemctl stop nexyra-link
echo "✅ Monitor parado"
EOF

# Script de restart
cat > restart.sh <<'EOF'
#!/bin/bash
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔄 Reiniciando Nexyra Link...${NC}"
systemctl restart nexyra-link
sleep 2
systemctl status nexyra-link --no-pager
EOF

# Script de logs
cat > logs.sh <<'EOF'
#!/bin/bash
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}📄 Exibindo logs (Ctrl+C para sair)${NC}"
echo ""
journalctl -u nexyra-link -f -n 50
EOF

# Script de status
cat > status.sh <<'EOF'
#!/bin/bash
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}📊 Status do Monitor${NC}"
echo "────────────────────────"
systemctl status nexyra-link --no-pager
echo ""
echo "📡 Últimas 10 verificações:"
journalctl -u nexyra-link -n 10 --no-pager | grep -E "Verificação|✅|❌" || echo "Nenhuma verificação ainda"
EOF

# Dar permissão de execução
chmod +x *.sh

# ─────────────────────────────────────────
# CRIA MENU SIMPLES E FUNCIONAL
# ─────────────────────────────────────────
log "📝 Criando menu simples..."
cat > menu.sh <<'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

APP_DIR="/opt/nexyra-link"
CONFIG="$APP_DIR/config.json"

show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       NEXYRA LINK - MONITOR            ║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}  ${GREEN}1)${NC} ▶️  Iniciar monitor              ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${RED}2)${NC} ⏹️  Parar monitor                ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${BLUE}3)${NC} 🔄  Reiniciar monitor            ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}4)${NC} 📄  Ver logs                     ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}5)${NC} 📊  Status                      ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}6)${NC} 🔧  Editar intervalo (min)      ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${RED}0)${NC} 🚪  Sair                         ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    read -p "👉 Escolha: " opt
}

edit_interval() {
    current_ms=$(jq '.check_interval_ms' "$CONFIG")
    current_min=$((current_ms / 60000))
    
    echo -e "${YELLOW}Intervalo atual: $current_min minutos${NC}"
    read -p "Novo intervalo em minutos: " min
    
    if [[ "$min" =~ ^[0-9]+$ ]] && [ "$min" -gt 0 ]; then
        ms=$((min * 60000))
        jq ".check_interval_ms=$ms" "$CONFIG" > tmp && mv tmp "$CONFIG"
        echo -e "${GREEN}✅ Intervalo alterado para $min minutos${NC}"
        echo -e "${CYAN}Reinicie o monitor para aplicar: opção 3${NC}"
    else
        echo -e "${RED}❌ Valor inválido${NC}"
    fi
    sleep 3
}

while true; do
    show_menu
    
    case "$opt" in
        1) ./start.sh ;;
        2) ./stop.sh ;;
        3) ./restart.sh ;;
        4) ./logs.sh ;;
        5) ./status.sh && read -p "Pressione Enter..." ;;
        6) edit_interval ;;
        0) 
            echo -e "${GREEN}Até logo!${NC}"
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
log "✅ Menu simples criado"

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
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Nexyra Link Monitor
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node $APP_DIR/$JS_FILE
Restart=always
RestartSec=5
User=root
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# ─────────────────────────────────────────
# ATIVA E INICIA SERVIÇO
# ─────────────────────────────────────────
log "🚀 Ativando e iniciando serviço..."
systemctl daemon-reload
systemctl enable nexyra-link >> "$LOG_FILE" 2>&1
systemctl restart nexyra-link >> "$LOG_FILE" 2>&1

# ─────────────────────────────────────────
# CONFIGURA MENU NO SSH (OPCIONAL)
# ─────────────────────────────────────────
if ! grep -q "nexyra" /root/.bashrc; then
    echo "" >> /root/.bashrc
    echo "# Comando nexyra disponível" >> /root/.bashrc
    echo "echo '💡 Digite ${GREEN}nexyra${NC} para abrir o menu'" >> /root/.bashrc
fi

# ─────────────────────────────────────────
# VERIFICA INSTALAÇÃO
# ─────────────────────────────────────────
sleep 3
if systemctl is-active --quiet nexyra-link; then
    echo -e "${GREEN}✅ Serviço está rodando!${NC}"
else
    warning "⚠️ Serviço não está rodando, verificando logs..."
    journalctl -u nexyra-link -n 5 --no-pager
fi

# ─────────────────────────────────────────
# RESUMO FINAL
# ─────────────────────────────────────────
clear
echo -e "${GREEN}"
echo "╔════════════════════════════════════════╗"
echo "║    INSTALAÇÃO CONCLUÍDA COM SUCESSO   ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${CYAN}📋 INFORMAÇÕES:${NC}"
echo "────────────────────────"
echo -e "📂 Diretório: ${YELLOW}$APP_DIR${NC}"
echo -e "🔗 GET API: ${YELLOW}https://nexyra.myftp.biz/netpulse/get_nodes_1.php${NC}"
echo -e "🔗 UPDATE API: ${YELLOW}https://nexyra.myftp.biz/netpulse/update_node_1.php${NC}"
echo -e "⏱️  Intervalo: ${YELLOW}30 segundos${NC}"
echo ""
echo -e "${GREEN}🚀 COMANDOS:${NC}"
echo "────────────────────────"
echo -e "   ${WHITE}nexyra${NC}        → Menu interativo"
echo -e "   ${WHITE}systemctl status nexyra-link${NC} → Status do serviço"
echo -e "   ${WHITE}journalctl -u nexyra-link -f${NC} → Logs em tempo real"
echo ""
echo -e "${YELLOW}📝 Para alterar o intervalo:${NC}"
echo "   1. Execute: nexyra"
echo "   2. Escolha opção 6"
echo "   3. Digite os minutos"
echo "   4. Reinicie com opção 3"
echo ""
echo -e "${GREEN}👉 Digite 'nexyra' para começar!${NC}"
echo ""

# Pergunta se quer abrir o menu
read -p "❓ Abrir menu agora? (s/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Ss]$ ]]; then
    cd "$APP_DIR"
    ./menu.sh
fi
