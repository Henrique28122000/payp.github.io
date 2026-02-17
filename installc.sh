#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────
# CORES
# ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────
# CONFIGURAÇÕES
# ─────────────────────────────────────────────────────────────
APP_NAME="nexyra-link"
APP_DIR="/opt/nexyra-link"
JS_FILE="monitor.js"
CONFIG_FILE="$APP_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
MENU_CMD="/usr/local/bin/nexyra"
BACKUP_DIR="$APP_DIR/backups"
LOG_DIR="$APP_DIR/logs"
LOG_FILE="$LOG_DIR/install.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ─────────────────────────────────────────────────────────────
# FUNÇÃO DE LOG (CORRIGIDA)
# ─────────────────────────────────────────────────────────────
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# ─────────────────────────────────────────────────────────────
error() {
    echo -e "${RED}[ERRO]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

# ─────────────────────────────────────────────────────────────
# FUNÇÃO DE LIMPEZA
# ─────────────────────────────────────────────────────────────
clean_installation() {
    echo -e "${YELLOW}🧹 Limpando instalação anterior...${NC}"
    
    if systemctl is-active --quiet nexyra-link 2>/dev/null; then
        systemctl stop nexyra-link
    fi
    
    if systemctl is-enabled --quiet nexyra-link 2>/dev/null; then
        systemctl disable nexyra-link
    fi
    
    rm -f "$SERVICE_FILE"
    
    if [ -d "$APP_DIR" ]; then
        echo -e "${BLUE}📦 Fazendo backup...${NC}"
        mkdir -p "$BACKUP_DIR"
        cp -r "$APP_DIR" "${BACKUP_DIR}/backup_${TIMESTAMP}" 2>/dev/null || true
    fi
    
    rm -rf "$APP_DIR"
    rm -f "$MENU_CMD"
    systemctl daemon-reload 2>/dev/null || true
    
    echo -e "${GREEN}✅ Limpeza concluída${NC}"
    sleep 2
}

# ─────────────────────────────────────────────────────────────
# FUNÇÃO DE DESINSTALAÇÃO
# ─────────────────────────────────────────────────────────────
uninstall() {
    clear
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║      DESINSTALAR NEXYRA LINK          ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Isso irá:${NC}"
    echo -e "  ${RED}•${NC} Parar o serviço"
    echo -e "  ${RED}•${NC} Remover todos os arquivos"
    echo -e "  ${RED}•${NC} Remover o comando 'nexyra'"
    echo ""
    read -p "❓ Tem certeza? (s/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${YELLOW}🗑️  Desinstalando...${NC}"
        
        if systemctl is-active --quiet nexyra-link 2>/dev/null; then
            systemctl stop nexyra-link
        fi
        
        if systemctl is-enabled --quiet nexyra-link 2>/dev/null; then
            systemctl disable nexyra-link
        fi
        
        rm -f "$SERVICE_FILE"
        rm -rf "$APP_DIR"
        rm -f "$MENU_CMD"
        
        systemctl daemon-reload
        
        sed -i '/# Nexyra Link/d' /root/.bashrc 2>/dev/null || true
        sed -i '/nexyra/d' /root/.bashrc 2>/dev/null || true
        
        echo -e "${GREEN}✅ Nexyra Link desinstalado com sucesso!${NC}"
        exit 0
    else
        echo -e "${BLUE}Desinstalação cancelada${NC}"
        sleep 2
        return
    fi
}

# ─────────────────────────────────────────────────────────────
# CRIAR ARQUIVO JS (SIMPLIFICADO)
# ─────────────────────────────────────────────────────────────
create_js_file() {
    cat > "$APP_DIR/$JS_FILE" <<'EOF'
const { exec } = require("child_process");
const fs = require("fs");
const http = require("http");
const https = require("https");
const url = require("url");

const config = JSON.parse(fs.readFileSync("./config.json", "utf8"));

const GET_NODES_API = config.apis.get_nodes;
const UPDATE_NODE_API = config.apis.update_node;
const GET_USERS_API = config.apis.get_users;
const UPDATE_SERVER_API = config.apis.update_server;
const CHECK_INTERVAL = config.check_interval_ms || 30000;

console.log("=".repeat(50));
console.log("🚀 Nexyra Link Monitor iniciado");
console.log(`⏱️  Intervalo: ${CHECK_INTERVAL/1000}s`);
console.log("=".repeat(50));

function request(url, postData = null) {
    return new Promise((resolve, reject) => {
        const parsedUrl = new URL(url);
        const client = parsedUrl.protocol === 'https:' ? https : http;
        
        const options = {
            hostname: parsedUrl.hostname,
            port: parsedUrl.port || (parsedUrl.protocol === 'https:' ? 443 : 80),
            path: parsedUrl.pathname + parsedUrl.search,
            method: postData ? 'POST' : 'GET',
            headers: { 'Content-Type': 'application/json' },
            timeout: 10000
        };

        const req = client.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try { resolve(JSON.parse(data)); } 
                    catch { resolve(data); }
                } else {
                    reject(new Error(`HTTP ${res.statusCode}`));
                }
            });
        });

        req.on('error', reject);
        req.on('timeout', () => req.destroy());
        
        if (postData) req.write(JSON.stringify(postData));
        req.end();
    });
}

function ping(host) {
    return new Promise(resolve => {
        if (!host) return resolve(false);
        exec(`ping -c 1 -W 2 ${host} 2>/dev/null`, (error) => {
            resolve(!error);
        });
    });
}

async function checkServers() {
    try {
        const users = await request(GET_USERS_API);
        if (!Array.isArray(users)) return;
        
        for (const user of users) {
            if (!user.monitoring_ip) continue;
            
            const online = await ping(user.monitoring_ip);
            const now = new Date();
            const lastUpdate = now.toISOString().slice(0,19).replace('T',' ');

            await request(UPDATE_SERVER_API, {
                uid: user.uid,
                is_online: online ? 1 : 0,
                last_update: lastUpdate
            }).catch(() => {});
            
            console.log(`${online ? '✅' : '❌'} ${user.email} - ${user.monitoring_ip}`);
        }
    } catch (err) {
        console.log("❌ Erro em servidores:", err.message);
    }
}

async function checkNodes() {
    try {
        const users = await request(GET_USERS_API);
        if (!Array.isArray(users)) return;
        
        for (const user of users) {
            if (!user.monitoring_ip) continue;
            
            const nodes = await request(`${GET_NODES_API}?userId=${user.uid}`).catch(() => []);
            if (!Array.isArray(nodes)) continue;
            
            for (const node of nodes) {
                if (!node?.ip) continue;
                
                const online = await ping(node.ip);
                const newStatus = online ? "online" : "offline";
                
                if (newStatus !== node.status) {
                    await request(UPDATE_NODE_API, { id: node.id, status: newStatus }).catch(() => {});
                    console.log(`⚡ ${node.ip}: ${node.status} → ${newStatus}`);
                }
            }
        }
    } catch (err) {
        console.log("❌ Erro em nodes:", err.message);
    }
}

async function run() {
    console.log(`\n🔄 Verificando - ${new Date().toLocaleTimeString()}`);
    await checkServers();
    await checkNodes();
}

run();
setInterval(run, CHECK_INTERVAL);
EOF
}

# ─────────────────────────────────────────────────────────────
# CRIAR CONFIG.JSON
# ─────────────────────────────────────────────────────────────
create_config_file() {
    cat > "$CONFIG_FILE" <<EOF
{
  "apis": {
    "get_users": "https://nexyra.myftp.biz/netpulse/get_users_with_servers.php",
    "get_nodes": "https://nexyra.myftp.biz/netpulse/get_nodes_1.php",
    "update_node": "https://nexyra.myftp.biz/netpulse/update_node_1.php",
    "update_server": "https://nexyra.myftp.biz/netpulse/update_server_status.php"
  },
  "check_interval_ms": 30000
}
EOF
}

# ─────────────────────────────────────────────────────────────
# CRIAR SCRIPTS AUXILIARES
# ─────────────────────────────────────────────────────────────
create_aux_scripts() {
    cat > "$APP_DIR/start.sh" <<'EOF'
#!/bin/bash
echo -e "\033[0;32m▶️ Iniciando Nexyra Link...\033[0m"
systemctl start nexyra-link
sleep 2
if systemctl is-active --quiet nexyra-link; then
    echo -e "\033[0;32m✅ Serviço iniciado\033[0m"
else
    echo -e "\033[0;31m❌ Falha ao iniciar\033[0m"
fi
EOF

    cat > "$APP_DIR/stop.sh" <<'EOF'
#!/bin/bash
echo -e "\033[1;33m⏹️ Parando Nexyra Link...\033[0m"
systemctl stop nexyra-link
echo -e "\033[0;32m✅ Serviço parado\033[0m"
EOF

    cat > "$APP_DIR/restart.sh" <<'EOF'
#!/bin/bash
echo -e "\033[0;34m🔄 Reiniciando Nexyra Link...\033[0m"
systemctl restart nexyra-link
sleep 2
echo -e "\033[0;32m✅ Serviço reiniciado\033[0m"
EOF

    cat > "$APP_DIR/logs.sh" <<'EOF'
#!/bin/bash
echo -e "\033[0;36m📄 LOGS (Ctrl+C para sair)\033[0m"
echo ""
journalctl -u nexyra-link -f -n 50
EOF

    cat > "$APP_DIR/status.sh" <<'EOF'
#!/bin/bash
clear
echo "════════════════════════════════════════"
echo "        STATUS DO MONITOR"
echo "════════════════════════════════════════"
echo ""
if systemctl is-active --quiet nexyra-link; then
    echo "📊 Serviço: ATIVO"
else
    echo "📊 Serviço: INATIVO"
fi
echo ""
echo "Últimas 10 linhas:"
journalctl -u nexyra-link -n 10 --no-pager | tail -10
echo ""
read -p "Pressione Enter para voltar..."
EOF

    chmod +x "$APP_DIR"/*.sh
}

# ─────────────────────────────────────────────────────────────
# CRIAR MENU PRINCIPAL
# ─────────────────────────────────────────────────────────────
create_menu() {
    cat > "$APP_DIR/menu.sh" <<'EOF'
#!/bin/bash
APP_DIR="/opt/nexyra-link"

while true; do
    clear
    echo "════════════════════════════════════════"
    echo "      NEXYRA LINK - MONITOR v3.0"
    echo "════════════════════════════════════════"
    echo ""
    echo "1) ▶️  INICIAR monitor"
    echo "2) ⏹️  PARAR monitor"
    echo "3) 🔄  REINICIAR monitor"
    echo "4) 📄  VER LOGS"
    echo "5) 📊  VER STATUS"
    echo "6) ⏱️  EDITAR INTERVALO"
    echo "7) 🔍  TESTAR APIs"
    echo "8) 🚀  ATIVAR AUTO START"
    echo "9) ❌  DESATIVAR AUTO START"
    echo "0) 🚪  SAIR"
    echo ""
    echo "Status: $(systemctl is-active nexyra-link)"
    echo ""
    read -p "👉 Escolha: " opt

    case $opt in
        1) cd "$APP_DIR" && ./start.sh ;;
        2) cd "$APP_DIR" && ./stop.sh ;;
        3) cd "$APP_DIR" && ./restart.sh ;;
        4) cd "$APP_DIR" && ./logs.sh ;;
        5) cd "$APP_DIR" && ./status.sh ;;
        6) 
            current=$(jq '.check_interval_ms' "$APP_DIR/config.json")
            current_min=$((current / 60000))
            echo "Atual: $current_min minutos"
            read -p "Novo intervalo (min): " min
            if [[ "$min" =~ ^[0-9]+$ ]] && [ "$min" -gt 0 ]; then
                ms=$((min * 60000))
                jq ".check_interval_ms=$ms" "$APP_DIR/config.json" > tmp && mv tmp "$APP_DIR/config.json"
                echo "✅ Alterado para $min minutos"
                echo "Reinicie o monitor (opção 3)"
            fi
            sleep 2
            ;;
        7) 
            GET_USERS=$(jq -r '.apis.get_users' "$APP_DIR/config.json")
            echo "Testando APIs..."
            curl -s -o /dev/null -w "GET Users: %{http_code}\n" --max-time 5 "$GET_USERS"
            read -p "Enter..."
            ;;
        8) systemctl enable nexyra-link && echo "✅ Auto start ativado" && sleep 2 ;;
        9) systemctl disable nexyra-link && echo "❌ Auto start desativado" && sleep 2 ;;
        0) echo "Até logo!" && exit 0 ;;
        *) echo "Opção inválida" && sleep 2 ;;
    esac
done
EOF
    chmod +x "$APP_DIR/menu.sh"
}

# ─────────────────────────────────────────────────────────────
# INSTALAÇÃO PRINCIPAL
# ─────────────────────────────────────────────────────────────
install() {
    clear
    echo -e "${BLUE}🚀 Iniciando instalação do Nexyra Link Monitor${NC}"
    
    clean_installation
    
    if [ "$EUID" -ne 0 ]; then
        error "❌ Execute como root"
    fi

    echo "📦 Atualizando sistema..."
    apt update -y > /dev/null 2>&1 || true
    
    echo "📦 Instalando dependências..."
    apt install -y curl wget jq sudo > /dev/null 2>&1

    if ! command -v node >/dev/null 2>&1; then
        echo "📦 Instalando Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash - > /dev/null 2>&1
        apt install -y nodejs > /dev/null 2>&1
    fi

    NODE_PATH=$(which node)
    [ -z "$NODE_PATH" ] && [ -f "/usr/bin/node" ] && NODE_PATH="/usr/bin/node"
    
    echo "✅ Node.js $($NODE_PATH -v) instalado"

    mkdir -p "$APP_DIR" "$BACKUP_DIR" "$LOG_DIR"
    
    create_js_file
    create_config_file
    create_aux_scripts
    create_menu

    ln -sf "$APP_DIR/menu.sh" "$MENU_CMD"
    chmod +x "$MENU_CMD"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Nexyra Link Monitor
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=$NODE_PATH $APP_DIR/$JS_FILE
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nexyra-link > /dev/null 2>&1
    systemctl start nexyra-link > /dev/null 2>&1

    sleep 2
    if systemctl is-active --quiet nexyra-link; then
        echo "✅ Serviço rodando!"
    fi

    if ! grep -q "nexyra" /root/.bashrc 2>/dev/null; then
        echo "" >> /root/.bashrc
        echo "# Nexyra Link" >> /root/.bashrc
        echo "echo '🔗 Digite nexyra para abrir o monitor'" >> /root/.bashrc
    fi

    clear
    echo "════════════════════════════════════════"
    echo "    INSTALAÇÃO CONCLUÍDA COM SUCESSO"
    echo "════════════════════════════════════════"
    echo ""
    echo "📂 Diretório: $APP_DIR"
    echo "🚀 Serviço: ATIVO"
    echo "⏱️  Intervalo: 30 segundos"
    echo ""
    echo "👉 Digite 'nexyra' para começar!"
    echo ""
    
    read -p "❓ Abrir menu agora? (s/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        cd "$APP_DIR" && ./menu.sh
    fi
}

# ─────────────────────────────────────────────────────────────
# MENU PRINCIPAL
# ─────────────────────────────────────────────────────────────
clear
echo "════════════════════════════════════════"
echo "     NEXYRA LINK - INSTALADOR v3.0"
echo "════════════════════════════════════════"
echo ""
echo "1) 🚀  Instalar Nexyra Link"
echo "2) 🗑️   Desinstalar"
echo "0) 🚪  Sair"
echo ""
read -p "👉 Escolha: " opt

case $opt in
    1) install ;;
    2) uninstall ;;
    0) echo "Até logo!" && exit 0 ;;
    *) echo "Opção inválida" && exit 1 ;;
esac
