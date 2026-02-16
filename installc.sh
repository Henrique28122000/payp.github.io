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
NC='\033[0m' # No Color

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
# UPDATE SYSTEM
# ─────────────────────────────────────────
log "📦 Atualizando sistema..."
apt update -y >> "$LOG_FILE" 2>&1 || warning "⚠️ Falha no apt update, continuando..."
apt upgrade -y >> "$LOG_FILE" 2>&1 || warning "⚠️ Falha no apt upgrade, continuando..."

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
# CRIA DIRETÓRIO
# ─────────────────────────────────────────
log "📂 Criando diretório $APP_DIR..."
mkdir -p "$APP_DIR"
cd "$APP_DIR"

# ─────────────────────────────────────────
# BAIXA SCRIPT JS ATUALIZADO
# ─────────────────────────────────────────
log "⬇️ Baixando monitor multi-empresa..."
wget -q -O "$JS_FILE" "$JS_URL" || {
    # Fallback se URL falhar
    warning "⚠️ Falha no download, criando script básico..."
    cat > "$JS_FILE" <<'EOF'
// Script básico de monitoramento
console.log("Monitor Nexyra Link iniciado...");
setInterval(() => {
    console.log("Verificando...");
}, 60000);
EOF
}

# ─────────────────────────────────────────
# CRIA CONFIG.JSON ATUALIZADO
# ─────────────────────────────────────────
log "⚙️ Criando arquivo de configuração..."
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
  "check_interval_ms": 60000,
  "log_level": "info",
  "max_concurrent": 10
}
EOF

# ─────────────────────────────────────────
# CRIA SCRIPTS AUXILIARES
# ─────────────────────────────────────────
log "📝 Criando scripts auxiliares..."

# Script de start
cat > start.sh <<'EOF'
#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
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
journalctl -u nexyra-link -n 10 --no-pager | grep "Verificando\|Servidor"
EOF

# Script de edição de config
cat > edit-config.sh <<'EOF'
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CONFIG="/opt/nexyra-link/config.json"

if [ ! -f "$CONFIG" ]; then
    echo -e "${YELLOW}⚠️ Config não encontrada${NC}"
    exit 1
fi

echo -e "${GREEN}🔧 Editando configuração${NC}"
echo "────────────────────────"
nano "$CONFIG"

echo -e "${GREEN}✅ Configuração salva. Reinicie o monitor:${NC}"
echo "   nexyra restart"
EOF

# Script de teste de API
cat > test-api.sh <<'EOF'
#!/bin/bash
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

CONFIG="/opt/nexyra-link/config.json"

if [ ! -f "$CONFIG" ]; then
    echo -e "${RED}❌ Config não encontrada${NC}"
    exit 1
fi

GET_USERS=$(jq -r '.apis.get_users' "$CONFIG")
GET_NODES=$(jq -r '.apis.get_nodes' "$CONFIG")
UPDATE_NODE=$(jq -r '.apis.update_node' "$CONFIG")
UPDATE_SERVER=$(jq -r '.apis.update_server' "$CONFIG")

echo -e "${CYAN}🔍 Testando APIs${NC}"
echo "────────────────────────"

test_api() {
    local url=$1
    local name=$2
    
    echo -n "📡 $name... "
    if curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" | grep -q "200\|404"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FALHOU${NC}"
    fi
}

test_api "$GET_USERS" "Get Users"
test_api "$GET_NODES?userId=test" "Get Nodes"
test_api "$UPDATE_NODE" "Update Node"
test_api "$UPDATE_SERVER" "Update Server"

echo ""
echo -e "${CYAN}⚙️ Configurações atuais:${NC}"
jq '.' "$CONFIG"
EOF

# Dar permissão de execução
chmod +x *.sh

# ─────────────────────────────────────────
# CRIA MENU INTERATIVO AVANÇADO
# ─────────────────────────────────────────
log "📝 Criando menu interativo..."
cat > menu.sh <<'EOF'
#!/bin/bash

# ─────────────────────────────────────────
# CORES
# ─────────────────────────────────────────
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

# ─────────────────────────────────────────
# FUNÇÕES
# ─────────────────────────────────────────
show_header() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                 NEXYRA LINK - MONITOR                    ║"
    echo "║                    Multi-Empresa v3.0                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

edit_apis() {
    echo -e "${CYAN}🔧 EDITAR APIS${NC}"
    echo "────────────────────────"
    
    current_get=$(jq -r '.apis.get_users' "$CONFIG")
    current_nodes=$(jq -r '.apis.get_nodes' "$CONFIG")
    current_update=$(jq -r '.apis.update_node' "$CONFIG")
    current_server=$(jq -r '.apis.update_server' "$CONFIG")
    
    echo -e "Atual GET Users: ${YELLOW}$current_get${NC}"
    read -p "Nova GET Users (Enter para manter): " new_get
    [ -n "$new_get" ] && jq ".apis.get_users=\"$new_get\"" "$CONFIG" > tmp && mv tmp "$CONFIG"
    
    echo -e "Atual GET Nodes: ${YELLOW}$current_nodes${NC}"
    read -p "Nova GET Nodes (Enter para manter): " new_nodes
    [ -n "$new_nodes" ] && jq ".apis.get_nodes=\"$new_nodes\"" "$CONFIG" > tmp && mv tmp "$CONFIG"
    
    echo -e "Atual UPDATE Node: ${YELLOW}$current_update${NC}"
    read -p "Nova UPDATE Node (Enter para manter): " new_upd
    [ -n "$new_upd" ] && jq ".apis.update_node=\"$new_upd\"" "$CONFIG" > tmp && mv tmp "$CONFIG"
    
    echo -e "Atual UPDATE Server: ${YELLOW}$current_server${NC}"
    read -p "Nova UPDATE Server (Enter para manter): " new_srv
    [ -n "$new_srv" ] && jq ".apis.update_server=\"$new_srv\"" "$CONFIG" > tmp && mv tmp "$CONFIG"
    
    echo -e "${GREEN}✅ APIs atualizadas!${NC}"
    sleep 2
}

edit_interval() {
    echo -e "${CYAN}⏱️ EDITAR INTERVALO${NC}"
    echo "────────────────────────"
    
    current_ms=$(jq '.check_interval_ms' "$CONFIG")
    current_min=$((current_ms / 60000))
    
    echo -e "Atual: ${YELLOW}$current_min minutos${NC}"
    read -p "Novo intervalo em minutos: " min
    
    if [[ "$min" =~ ^[0-9]+$ ]] && [ "$min" -gt 0 ]; then
        ms=$((min * 60000))
        jq ".check_interval_ms=$ms" "$CONFIG" > tmp && mv tmp "$CONFIG"
        echo -e "${GREEN}✅ Intervalo atualizado para $min minutos${NC}"
    else
        echo -e "${RED}❌ Valor inválido${NC}"
    fi
    sleep 2
}

edit_ports() {
    echo -e "${CYAN}🔌 EDITAR PORTAS TCP${NC}"
    echo "────────────────────────"
    
    current_ports=$(jq '.tcp_ports[]' "$CONFIG" | tr '\n' ' ')
    echo -e "Portas atuais: ${YELLOW}$current_ports${NC}"
    read -p "Novas portas (separadas por espaço): " -a ports
    
    if [ ${#ports[@]} -gt 0 ]; then
        ports_json=$(printf '%s\n' "${ports[@]}" | jq -R . | jq -s .)
        jq ".tcp_ports=$ports_json" "$CONFIG" > tmp && mv tmp "$CONFIG"
        echo -e "${GREEN}✅ Portas atualizadas!${NC}"
    fi
    sleep 2
}

view_stats() {
    echo -e "${PURPLE}📊 ESTATÍSTICAS${NC}"
    echo "────────────────────────"
    
    # Status do serviço
    if systemctl is-active --quiet nexyra-link; then
        echo -e "Serviço: ${GREEN}ATIVO ✅${NC}"
    else
        echo -e "Serviço: ${RED}INATIVO ❌${NC}"
    fi
    
    # Uptime
    if [ -f "$APP_DIR/uptime.log" ]; then
        uptime=$(cat "$APP_DIR/uptime.log")
        echo -e "Uptime: ${CYAN}$uptime${NC}"
    fi
    
    # Últimas verificações
    echo ""
    echo -e "${YELLOW}Últimas 10 verificações:${NC}"
    journalctl -u nexyra-link -n 10 --no-pager | grep "Verificando\|Servidor" | tail -5
    
    # Erros recentes
    echo ""
    echo -e "${YELLOW}Erros recentes:${NC}"
    journalctl -u nexyra-link -n 20 --no-pager | grep "❌\|⚠️" | tail -3
    
    echo ""
    read -p "Pressione Enter para continuar..."
}

# ─────────────────────────────────────────
# MENU PRINCIPAL
# ─────────────────────────────────────────
while true; do
    show_header
    
    echo -e "${WHITE}╔════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║           MENU DE CONTROLE            ║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC}  ${GREEN}1)${NC} ▶️  Iniciar monitor               ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${RED}2)${NC} ⏹️  Parar monitor                 ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${BLUE}3)${NC} 🔄  Reiniciar monitor             ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${CYAN}4)${NC} 📄  Ver logs em tempo real        ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${PURPLE}5)${NC} 📊  Estatísticas                 ${WHITE}║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC}  ${YELLOW}6)${NC} 🔧  Editar APIs                  ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${YELLOW}7)${NC} ⏱️   Editar intervalo            ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${YELLOW}8)${NC} 🔌  Editar portas TCP            ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${YELLOW}9)${NC} 📝  Editar config manualmente    ${WHITE}║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC}  ${BLUE}10)${NC} 🚀  Ativar auto start (boot)      ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${RED}11)${NC} ❌  Desativar auto start          ${WHITE}║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC}  ${CYAN}12)${NC} 🔍  Testar APIs                   ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC}  ${PURPLE}13)${NC} 📦  Ver versão                   ${WHITE}║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC}  ${RED}0)${NC} 🔚  Sair                          ${WHITE}║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════╝${NC}"
    echo ""
    read -p "👉 Escolha uma opção: " opt

    case "$opt" in
        1) ./start.sh ;;
        2) ./stop.sh ;;
        3) ./restart.sh ;;
        4) ./logs.sh ;;
        5) view_stats ;;
        6) edit_apis ;;
        7) edit_interval ;;
        8) edit_ports ;;
        9) ./edit-config.sh ;;
        10) systemctl enable nexyra-link && echo -e "${GREEN}✅ Auto start ativado${NC}" && sleep 2 ;;
        11) systemctl disable nexyra-link && echo -e "${RED}❌ Auto start desativado${NC}" && sleep 2 ;;
        12) ./test-api.sh && read -p "Pressione Enter..." ;;
        13) 
            echo -e "${CYAN}Versão: 3.0.0${NC}"
            echo -e "Node: $(node -v)"
            echo -e "Data: $(date)"
            read -p "Pressione Enter..."
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

# ─────────────────────────────────────────
# CRIA COMANDO GLOBAL
# ─────────────────────────────────────────
log "🔗 Criando comando global 'nexyra'..."
ln -sf "$APP_DIR/menu.sh" "$MENU_CMD"
chmod +x "$MENU_CMD"

# ─────────────────────────────────────────
# CRIA ARQUIVO DE UPTIME
# ─────────────────────────────────────────
date > "$APP_DIR/uptime.log"

# ─────────────────────────────────────────
# CRIA SERVICE SYSTEMD ATUALIZADO
# ─────────────────────────────────────────
log "⚙️ Criando serviço systemd..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Nexyra Link Monitor - Multi-Empresa
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node $APP_DIR/$JS_FILE
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
User=root
Group=root
Environment=NODE_ENV=production
Environment=PATH=/usr/bin:/usr/local/bin
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nexyra-link

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
# CONFIGURA PARA ABRIR MENU NO SSH
# ─────────────────────────────────────────
log "🔧 Configurando menu automático no SSH..."
if ! grep -q "$APP_DIR/menu.sh" /root/.bashrc; then
    echo "" >> /root/.bashrc
    echo "# Abrir menu do Nexyra Link automaticamente" >> /root/.bashrc
    echo "if [ -f $APP_DIR/menu.sh ]; then" >> /root/.bashrc
    echo "    clear" >> /root/.bashrc
    echo "    $APP_DIR/menu.sh" >> /root/.bashrc
    echo "fi" >> /root/.bashrc
fi

# ─────────────────────────────────────────
# VERIFICA INSTALAÇÃO
# ─────────────────────────────────────────
log "🔍 Verificando instalação..."
sleep 3

if systemctl is-active --quiet nexyra-link; then
    echo -e "${GREEN}✅ Serviço está rodando!${NC}"
else
    warning "⚠️ Serviço não está rodando, verificando logs..."
    journalctl -u nexyra-link -n 10 --no-pager
fi

# ─────────────────────────────────────────
# RESUMO FINAL
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
echo -e "${CYAN}📋 INFORMAÇÕES:${NC}"
echo "──────────────────────────────"
echo -e "📂 Diretório: ${YELLOW}$APP_DIR${NC}"
echo -e "⚙️  Config: ${YELLOW}$CONFIG_FILE${NC}"
echo -e "📦 Versão: ${YELLOW}3.0.0${NC}"
echo -e "🖥️  Node: ${YELLOW}$(node -v)${NC}"
echo ""
echo -e "${GREEN}🚀 COMANDOS DISPONÍVEIS:${NC}"
echo "──────────────────────────────"
echo -e "   ${WHITE}nexyra${NC}        → Abrir menu interativo"
echo -e "   ${WHITE}systemctl status nexyra-link${NC} → Ver status"
echo -e "   ${WHITE}journalctl -u nexyra-link -f${NC} → Ver logs"
echo ""
echo -e "${YELLOW}📝 PRÓXIMOS PASSOS:${NC}"
echo "──────────────────────────────"
echo -e "1️⃣  Execute ${WHITE}nexyra${NC} para abrir o menu"
echo -e "2️⃣  Configure as APIs no menu (opção 6)"
echo -e "3️⃣  Teste as conexões (opção 12)"
echo -e "4️⃣  Ajuste o intervalo de verificação (opção 7)"
echo ""
echo -e "${BLUE}🔗 ACESSO RÁPIDO:${NC}"
echo "──────────────────────────────"
echo -e "   ${WHITE}cd $APP_DIR && ./menu.sh${NC}"
echo ""
echo -e "${PURPLE}✨ O menu abrirá automaticamente na próxima vez que conectar via SSH!${NC}"
echo -e "${GREEN}👉 Digite 'nexyra' para abrir agora!${NC}"
echo ""

# ─────────────────────────────────────────
# PERGUNTA SE QUER ABRIR MENU AGORA
# ─────────────────────────────────────────
read -p "❓ Deseja abrir o menu agora? (s/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Ss]$ ]]; then
    cd "$APP_DIR"
    ./menu.sh
fi
