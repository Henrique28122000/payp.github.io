#!/bin/bash
set -e

# -─────────────────────────────────────────────────────────────
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
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# URLs fixas dos endpoints
GET_USERS_ENDPOINT="get_users_with_servers.php"
GET_NODES_ENDPOINT="get_nodes_1.php"
UPDATE_NODE_ENDPOINT="update_node_1.php"
UPDATE_SERVER_ENDPOINT="update_server_status.php"

# ─────────────────────────────────────────────────────────────
# FUNÇÃO DE LOG
# ─────────────────────────────────────────────────────────────
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERRO]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

# ─────────────────────────────────────────────────────────────
# FUNÇÃO PARA INSTALAR DEPENDÊNCIAS BÁSICAS
# ─────────────────────────────────────────────────────────────
install_basic_deps() {
    echo -e "${BLUE}📦 Instalando dependências básicas...${NC}"
    apt update -y > /dev/null 2>&1 || true
    apt install -y curl wget jq > /dev/null 2>&1
    
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  jq não pôde ser instalado via apt, tentando instalar manualmente...${NC}"
        curl -L -o /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 2>/dev/null
        chmod +x /usr/bin/jq
    fi
    
    if command -v jq >/dev/null 2>&1; then
        echo -e "${GREEN}✅ jq instalado com sucesso${NC}"
    else
        echo -e "${RED}❌ Falha ao instalar jq${NC}"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────
# FUNÇÃO PARA VALIDAR CHAVE DE INSTALAÇÃO (SEM USAR JQ)
# ─────────────────────────────────────────────────────────────
validate_installation_key() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      VALIDAÇÃO DE INSTALAÇÃO          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Digite a chave de instalação:${NC}"
    read -p "🔑 Chave: " INSTALL_KEY
    
    if [ -z "$INSTALL_KEY" ]; then
        error "Chave não pode estar vazia"
    fi
    
    echo ""
    echo -e "${CYAN}📡 Validando chave...${NC}"
    
    # URL base para validação (altere para sua URL real)
    BASE_URL="https://nexyra.myftp.biz/netpulse"
    
    # Valida a chave e obtém o link base
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"key\":\"$INSTALL_KEY\"}" \
        --max-time 10 \
        "$BASE_URL/validate_key.php")
    
    # Verifica se a consulta foi bem sucedida
    if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
        error "Falha ao conectar com o servidor"
    fi
    
    # Extrai o status e o link base usando grep/sed (fallback case)
    if command -v jq >/dev/null 2>&1; then
        # Usa jq se disponível
        STATUS=$(echo "$RESPONSE" | jq -r '.status // "error"')
        
        if [ "$STATUS" != "success" ]; then
            MESSAGE=$(echo "$RESPONSE" | jq -r '.message // "Chave inválida"')
            echo -e "${RED}❌ $MESSAGE${NC}"
            error "Validação falhou"
        fi
        
        BASE_LINK=$(echo "$RESPONSE" | jq -r '.base_link // empty')
        
    else
        # Fallback: usa grep e sed para extrair os valores
        if echo "$RESPONSE" | grep -q '"status"[[:space:]]*:[[:space:]]*"success"'; then
            STATUS="success"
            # Extrai o base_link
            BASE_LINK=$(echo "$RESPONSE" | grep -o '"base_link"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"base_link"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
            
            if [ -z "$BASE_LINK" ]; then
                error "Link base não encontrado na resposta"
            fi
        else
            # Tenta extrair mensagem de erro
            ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"message"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
            ERROR_MSG=${ERROR_MSG:-"Chave inválida"}
            echo -e "${RED}❌ $ERROR_MSG${NC}"
            error "Validação falhou"
        fi
    fi
    
    if [ -z "$BASE_LINK" ]; then
        error "Link base não encontrado na resposta"
    fi
    
    # Remove barra no final se existir
    BASE_LINK=$(echo "$BASE_LINK" | sed 's:/*$::')
    
    echo -e "${GREEN}✅ Chave validada com sucesso!${NC}"
    echo ""
    echo -e "${CYAN}📋 Link base: $BASE_LINK${NC}"
    echo ""
    
    # Monta as URLs completas
    GET_USERS_API="$BASE_LINK/$GET_USERS_ENDPOINT"
    GET_NODES_API="$BASE_LINK/$GET_NODES_ENDPOINT"
    UPDATE_NODE_API="$BASE_LINK/$UPDATE_NODE_ENDPOINT"
    UPDATE_SERVER_API="$BASE_LINK/$UPDATE_SERVER_ENDPOINT"
    
    echo -e "${CYAN}📋 URLs configuradas:${NC}"
    echo "  • GET Users: $GET_USERS_API"
    echo "  • GET Nodes: $GET_NODES_API"
    echo "  • UPDATE Node: $UPDATE_NODE_API"
    echo "  • UPDATE Server: $UPDATE_SERVER_API"
    echo ""
    
    # Testa rapidamente as URLs
    echo -e "${YELLOW}🔍 Testando conexão com as APIs...${NC}"
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$GET_USERS_API" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "401" ]; then
        echo -e "  ✅ GET Users: $HTTP_CODE"
    else
        echo -e "  ⚠️  GET Users: $HTTP_CODE (possível erro)"
    fi
    
    sleep 2
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
# CRIAR ARQUIVO JS
# ─────────────────────────────────────────────────────────────
create_js_file() {
    cat > "$APP_DIR/$JS_FILE" <<'EOF'
const { exec } = require("child_process");
const fs = require("fs");
const http = require("http");
const https = require("https");
const os = require("os");

const config = JSON.parse(fs.readFileSync("./config.json", "utf8"));

const GET_NODES_API = config.apis.get_nodes;
const UPDATE_NODE_API = config.apis.update_node;
const GET_USERS_API = config.apis.get_users;
const UPDATE_SERVER_API = config.apis.update_server;
const CHECK_INTERVAL = config.check_interval_ms || 30000;

// Função para obter o IP do servidor atual
function getCurrentServerIP() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            // Pula interfaces internas e IPv6
            if (iface.internal) continue;
            if (iface.family !== 'IPv4') continue;
            return iface.address;
        }
    }
    return null;
}

const SERVER_IP = getCurrentServerIP();
console.log("=".repeat(50));
console.log("🚀 Nexyra Link Monitor iniciado");
console.log(`🌐 IP do Servidor: ${SERVER_IP}`);
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
            // Só processa usuários cujo monitoring_ip é igual ao IP deste servidor
            if (!user.monitoring_ip || user.monitoring_ip !== SERVER_IP) {
                if (user.monitoring_ip) {
                    console.log(`⏭️  Ignorando usuário ${user.email || user.uid} - IP diferente (${user.monitoring_ip} != ${SERVER_IP})`);
                }
                continue;
            }
            
            // Se o IP do servidor de monitoramento for igual ao IP atual
            // Isso significa que este servidor é responsável por monitorar este usuário
            console.log(`📡 Monitorando servidor: ${user.email || user.uid} - IP: ${user.monitoring_ip}`);
            
            const online = await ping(user.monitoring_ip);
            const now = new Date();
            
            // Horário de Brasília (GMT-3)
            const brasiliaTime = new Date(now.toLocaleString('en-US', { timeZone: 'America/Sao_Paulo' }));
            const lastUpdate = brasiliaTime.toISOString().slice(0,19).replace('T',' ');

            await request(UPDATE_SERVER_API, {
                uid: user.uid,
                is_online: online ? 1 : 0,
                last_update: lastUpdate
            }).catch(() => {});
            
            console.log(`${online ? '✅' : '❌'} Servidor ${user.email || user.uid} - ${user.monitoring_ip}`);
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
            // Só processa usuários cujo monitoring_ip é igual ao IP deste servidor
            if (!user.monitoring_ip || user.monitoring_ip !== SERVER_IP) {
                continue;
            }
            
            console.log(`📡 Buscando nodes do usuário: ${user.email || user.uid}`);
            
            const nodes = await request(`${GET_NODES_API}?userId=${user.uid}`).catch(() => []);
            if (!Array.isArray(nodes)) continue;
            
            for (const node of nodes) {
                if (!node?.ip) continue;
                
                const online = await ping(node.ip);
                const newStatus = online ? "online" : "offline";
                
                if (newStatus !== node.status) {
                    await request(UPDATE_NODE_API, { 
                        id: node.id, 
                        status: newStatus 
                    }).catch(() => {});
                    console.log(`⚡ Node ${node.ip}: ${node.status || 'unknown'} → ${newStatus}`);
                } else {
                    console.log(`📊 Node ${node.ip}: permanece ${newStatus}`);
                }
            }
        }
    } catch (err) {
        console.log("❌ Erro em nodes:", err.message);
    }
}

async function checkServerStatus() {
    try {
        // Verifica se este servidor está registrado como monitoring_ip para algum usuário
        const users = await request(GET_USERS_API);
        if (!Array.isArray(users)) return;
        
        const myUsers = users.filter(u => u.monitoring_ip === SERVER_IP);
        
        if (myUsers.length === 0) {
            console.log(`⚠️  Nenhum usuário configurado com IP ${SERVER_IP}`);
            console.log(`📝 Usuários encontrados com outros IPs:`);
            users.filter(u => u.monitoring_ip).forEach(u => {
                console.log(`   • ${u.email || u.uid}: ${u.monitoring_ip}`);
            });
        } else {
            console.log(`✅ Monitorando ${myUsers.length} usuário(s) com IP ${SERVER_IP}`);
        }
    } catch (err) {
        console.log("❌ Erro ao verificar status:", err.message);
    }
}

async function run() {
    console.log(`\n🔄 Verificação - ${new Date().toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' })}`);
    console.log(`🌐 IP do servidor: ${SERVER_IP}`);
    
    // Primeiro verifica o status do servidor
    await checkServerStatus();
    
    // Depois monitora os servidores
    await checkServers();
    
    // E por fim os nodes
    await checkNodes();
}

// Executa uma verificação inicial
checkServerStatus().then(() => {
    run();
    setInterval(run, CHECK_INTERVAL);
});
EOF
}

# ─────────────────────────────────────────────────────────────
# CRIAR CONFIG.JSON
# ─────────────────────────────────────────────────────────────
create_config_file() {
    cat > "$CONFIG_FILE" <<EOF
{
  "apis": {
    "get_users": "$GET_USERS_API",
    "get_nodes": "$GET_NODES_API",
    "update_node": "$UPDATE_NODE_API",
    "update_server": "$UPDATE_SERVER_API"
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
    echo "8) 📋  VER CONFIGURAÇÃO"
    echo "9) 🚀  ATIVAR AUTO START"
    echo "10) ❌ DESATIVAR AUTO START"
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
            GET_NODES=$(jq -r '.apis.get_nodes' "$APP_DIR/config.json")
            echo "🔍 Testando APIs..."
            echo ""
            echo "GET Users: $(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$GET_USERS")"
            echo "GET Nodes: $(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$GET_NODES")"
            read -p "Enter..."
            ;;
        8)
            echo "📋 CONFIGURAÇÃO ATUAL:"
            echo ""
            jq '.' "$APP_DIR/config.json"
            echo ""
            read -p "Enter..."
            ;;
        9) systemctl enable nexyra-link && echo "✅ Auto start ativado" && sleep 2 ;;
        10) systemctl disable nexyra-link && echo "❌ Auto start desativado" && sleep 2 ;;
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
    
    # Primeiro instala as dependências básicas
    install_basic_deps
    
    # Valida a chave e obtém o link base
    validate_installation_key
    
    clean_installation
    
    if [ "$EUID" -ne 0 ]; then
        error "❌ Execute como root"
    fi

    echo "📦 Instalando dependências adicionais..."
    apt install -y sudo > /dev/null 2>&1

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
    echo "📋 APIs configuradas:"
    echo "  • GET Users: $GET_USERS_API"
    echo "  • GET Nodes: $GET_NODES_API"
    echo "  • UPDATE Node: $UPDATE_NODE_API"
    echo "  • UPDATE Server: $UPDATE_SERVER_API"
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
