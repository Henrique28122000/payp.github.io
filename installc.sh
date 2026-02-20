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
const net = require("net");
const dns = require("dns");
const os = require("os");
const { promisify } = require("util");

const execAsync = promisify(exec);
const dnsLookup = promisify(dns.lookup);

const config = JSON.parse(fs.readFileSync("./config.json", "utf8"));

const GET_NODES_API = config.apis.get_nodes;
const UPDATE_NODE_API = config.apis.update_node;
const GET_USERS_API = config.apis.get_users;
const UPDATE_SERVER_API = config.apis.update_server;
const CHECK_INTERVAL = config.check_interval_ms || 30000;

const TIMEOUT = 5000;
const RETRIES = 2;
const BATCH_SIZE = 1;

/* ============================= */
/* ESTADO EM MEMÓRIA */
/* ============================= */
const nodeState = {
    all: new Map(),
    online: new Set(),
    offline: new Set(),
    unknown: new Set(),
    lastCheck: new Map(),
    failCount: new Map(),
    processing: new Set()
};

const serverState = {
    all: new Map(),
    online: new Set(),
    offline: new Set(),
    processing: new Set()
};

/* ============================= */
/* PEGAR IP DO SERVIDOR */
/* ============================= */
function getCurrentServerIP() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (!iface.internal && iface.family === "IPv4") {
                return iface.address;
            }
        }
    }
    return null;
}

const SERVER_IP = getCurrentServerIP();

console.log("==================================================");
console.log("🚀 NEXYRA LINK MONITOR - COM ATUALIZAÇÃO DE IP");
console.log("🌐 IP do Servidor:", SERVER_IP);
console.log("⏱ Intervalo completo:", CHECK_INTERVAL / 1000, "segundos");
console.log("🔄 Atualiza lista de nodes a cada ciclo");
console.log("==================================================");

/* ============================= */
/* REQUISIÇÃO API */
/* ============================= */
async function request(url, postData = null) {
    return new Promise((resolve, reject) => {
        const parsed = new URL(url);
        const client = parsed.protocol === "https:" ? https : http;

        const options = {
            hostname: parsed.hostname,
            port: parsed.port || (parsed.protocol === "https:" ? 443 : 80),
            path: parsed.pathname + parsed.search,
            method: postData ? "POST" : "GET",
            headers: { "Content-Type": "application/json" },
            timeout: 10000
        };

        const req = client.request(options, res => {
            let data = "";
            res.on("data", chunk => data += chunk);
            res.on("end", () => {
                try {
                    resolve(JSON.parse(data));
                } catch {
                    resolve(data);
                }
            });
        });

        req.on("error", reject);
        req.on("timeout", () => {
            req.destroy();
            reject(new Error("Timeout API"));
        });

        if (postData) req.write(JSON.stringify(postData));
        req.end();
    });
}

/* ============================= */
/* TESTES DE CONECTIVIDADE */
/* ============================= */

// Ping
async function pingTest(host) {
    if (!host) return false;
    try {
        const isWin = process.platform === "win32";
        const cmd = isWin
            ? `ping -n 1 -w 2000 ${host}`
            : `ping -c 1 -W 2 ${host}`;
        await execAsync(cmd, { timeout: 2000 });
        return true;
    } catch {
        return false;
    }
}

// TCP Connect
async function tcpTest(host, port = 80) {
    return new Promise(resolve => {
        const socket = new net.Socket();
        socket.setTimeout(2000);

        socket.on("connect", () => {
            socket.destroy();
            resolve(true);
        });

        socket.on("timeout", () => {
            socket.destroy();
            resolve(false);
        });

        socket.on("error", () => resolve(false));

        socket.connect(port, host);
    });
}

// HTTP
async function httpTest(url) {
    return new Promise(resolve => {
        const client = url.startsWith("https") ? https : http;
        
        const req = client.get(url, { 
            timeout: 2000,
            rejectUnauthorized: false
        }, res => {
            resolve(res.statusCode >= 200 && res.statusCode < 500);
            req.destroy();
        });

        req.on("error", () => resolve(false));
        req.on("timeout", () => {
            req.destroy();
            resolve(false);
        });
    });
}

/* ============================= */
/* TESTE COMPLETO - 4 TESTES */
/* ============================= */
async function preciseCheck(node) {
    console.log(`   🔍 Testando node ${node.ip}:${node.port || 80}...`);
    
    const host = node.ip;
    const port = node.port || 80;
    const startTime = Date.now();
    
    // TESTES EM SEQUÊNCIA
    console.log(`      ├─ Teste 1/4: Ping...`);
    if (await pingTest(host)) {
        console.log(`      ✅ ONLINE via Ping (${Date.now() - startTime}ms)`);
        return true;
    }
    
    console.log(`      ├─ Teste 2/4: TCP...`);
    if (await tcpTest(host, port)) {
        console.log(`      ✅ ONLINE via TCP (${Date.now() - startTime}ms)`);
        return true;
    }
    
    console.log(`      ├─ Teste 3/4: HTTP...`);
    if (await httpTest(`http://${host}:${port}`)) {
        console.log(`      ✅ ONLINE via HTTP (${Date.now() - startTime}ms)`);
        return true;
    }
    
    console.log(`      ├─ Teste 4/4: HTTPS...`);
    if (await httpTest(`https://${host}:${port}`)) {
        console.log(`      ✅ ONLINE via HTTPS (${Date.now() - startTime}ms)`);
        return true;
    }
    
    console.log(`      ❌ OFFLINE - Todos os testes falharam (${Date.now() - startTime}ms)`);
    return false;
}

/* ============================= */
/* TESTE RÁPIDO */
/* ============================= */
async function quickCheck(node) {
    const host = node.ip;
    const port = node.port || 80;
    
    const [pingResult, tcpResult] = await Promise.all([
        pingTest(host),
        tcpTest(host, port)
    ]);
    
    return pingResult || tcpResult;
}

/* ============================= */
/* ATUALIZA STATUS SERVIDOR */
/* ============================= */
async function updateServerStatus(uid, online) {
    if (serverState.processing.has(uid)) return;
    serverState.processing.add(uid);
    
    try {
        const now = new Date();
        const brasiliaTime = new Date(
            now.toLocaleString("en-US", { timeZone: "America/Sao_Paulo" })
        );
        const lastUpdate = brasiliaTime
            .toISOString()
            .slice(0, 19)
            .replace("T", " ");

        const server = serverState.all.get(uid);
        if (server) {
            const oldStatus = server.online;
            server.online = online;
            server.lastUpdate = lastUpdate;
            
            if (online) {
                serverState.online.add(uid);
                serverState.offline.delete(uid);
            } else {
                serverState.offline.add(uid);
                serverState.online.delete(uid);
            }
            
            if (oldStatus !== online) {
                console.log(`\n${online ? '🟢' : '🔴'} SERVIDOR ${uid} ${online ? 'ONLINE' : 'OFFLINE'}`);
            }
        }

        await request(UPDATE_SERVER_API, {
            uid: uid,
            is_online: online ? 1 : 0,
            last_update: lastUpdate
        });
    } finally {
        serverState.processing.delete(uid);
    }
}

/* ============================= */
/* ATUALIZA STATUS NODE */
/* ============================= */
async function updateNodeStatus(node, online, isQuickCheck = false) {
    if (nodeState.processing.has(node.id)) return;
    nodeState.processing.add(node.id);
    
    try {
        const newStatus = online ? "online" : "offline";
        const oldStatus = node.status;
        
        node.status = newStatus;
        node.lastCheck = new Date().toISOString();
        if (online) node.lastOnline = node.lastCheck;
        
        nodeState.lastCheck.set(node.id, Date.now());
        
        if (online) {
            nodeState.online.add(node.id);
            nodeState.offline.delete(node.id);
            nodeState.unknown.delete(node.id);
            nodeState.failCount.set(node.id, 0);
        } else {
            nodeState.offline.add(node.id);
            nodeState.online.delete(node.id);
            nodeState.unknown.delete(node.id);
            const failCount = (nodeState.failCount.get(node.id) || 0) + 1;
            nodeState.failCount.set(node.id, failCount);
        }
        
        if (newStatus !== oldStatus) {
            await request(UPDATE_NODE_API, {
                id: node.id,
                status: newStatus,
                last_check: node.lastCheck,
                last_online: node.lastOnline,
                fail_count: nodeState.failCount.get(node.id) || 0
            });
            
            if (!isQuickCheck) {
                console.log(`\n⚡ ${online ? '🟢' : '🔴'} NODE ${node.ip} → ${newStatus}`);
                if (!online && oldStatus === 'online') {
                    console.log(`   ⚠️ Caiu às ${new Date().toLocaleTimeString()}`);
                } else if (online && oldStatus === 'offline') {
                    const offlineTime = Math.round((Date.now() - (nodeState.lastCheck.get(node.id) || Date.now())) / 1000);
                    console.log(`   ✅ Voltou após ${offlineTime}s`);
                }
            }
        }
    } finally {
        nodeState.processing.delete(node.id);
    }
}

/* ============================= */
/* SINCRONIZA NODES COM API */
/* ============================= */
async function syncNodesWithAPI(apiNodes, userId) {
    const apiNodeIds = new Set();
    let changes = 0;
    
    // Mapeia nodes da API
    for (const apiNode of apiNodes) {
        if (!apiNode.ip) continue;
        
        apiNodeIds.add(apiNode.id);
        apiNode.userId = userId;
        
        const existingNode = nodeState.all.get(apiNode.id);
        
        if (!existingNode) {
            // Node novo
            nodeState.all.set(apiNode.id, apiNode);
            nodeState.unknown.add(apiNode.id);
            changes++;
            console.log(`   📦 Novo node detectado: ${apiNode.ip} (ID: ${apiNode.id})`);
        } else if (
            existingNode.ip !== apiNode.ip || 
            existingNode.port !== apiNode.port
        ) {
            // Node foi modificado - ATUALIZA!
            console.log(`   ✏️ Node ${apiNode.id} modificado:`);
            console.log(`      IP: ${existingNode.ip} → ${apiNode.ip}`);
            if (existingNode.port !== apiNode.port) {
                console.log(`      Porta: ${existingNode.port || 80} → ${apiNode.port || 80}`);
            }
            
            // Mantém o status atual, mas atualiza IP/porta
            const currentStatus = existingNode.status;
            Object.assign(existingNode, apiNode);
            existingNode.status = currentStatus; // Preserva status
            nodeState.all.set(apiNode.id, existingNode);
            changes++;
        }
    }
    
    // Remove nodes que não existem mais na API
    for (const [nodeId, node] of nodeState.all) {
        if (node.userId === userId && !apiNodeIds.has(nodeId)) {
            console.log(`   🗑️ Node removido: ${node.ip} (ID: ${nodeId})`);
            nodeState.all.delete(nodeId);
            nodeState.online.delete(nodeId);
            nodeState.offline.delete(nodeId);
            nodeState.unknown.delete(nodeId);
            nodeState.lastCheck.delete(nodeId);
            nodeState.failCount.delete(nodeId);
            changes++;
        }
    }
    
    if (changes > 0) {
        console.log(`   ✅ Sincronização concluída: ${changes} alterações`);
    }
    
    return changes;
}

/* ============================= */
/* VERIFICA SERVIDORES */
/* ============================= */
async function checkServers() {
    const users = await request(GET_USERS_API);
    if (!Array.isArray(users)) return;

    for (const user of users) {
        if (user.monitoring_ip !== SERVER_IP) continue;

        const existingServer = serverState.all.get(user.uid);
        
        if (!existingServer) {
            serverState.all.set(user.uid, {
                uid: user.uid,
                ip: user.monitoring_ip,
                online: user.is_online === 1
            });
            
            if (user.is_online === 1) {
                serverState.online.add(user.uid);
            } else {
                serverState.offline.add(user.uid);
            }
            console.log(`📦 Novo servidor: ${user.uid}`);
        } else if (existingServer.ip !== user.monitoring_ip) {
            console.log(`✏️ Servidor ${user.uid} mudou IP: ${existingServer.ip} → ${user.monitoring_ip}`);
            existingServer.ip = user.monitoring_ip;
        }

        console.log(`\n📡 Verificando servidor ${user.uid} (${user.monitoring_ip})...`);
        const online = await pingTest(user.monitoring_ip);
        await updateServerStatus(user.uid, online);
        
        await new Promise(r => setTimeout(r, 500));
    }
}

/* ============================= */
/* VERIFICA NODES - COM SINCRONIZAÇÃO */
/* ============================= */
async function checkNodes() {
    const users = await request(GET_USERS_API);
    if (!Array.isArray(users)) return;

    for (const user of users) {
        if (user.monitoring_ip !== SERVER_IP) continue;

        console.log(`\n📋 Processando usuário ${user.uid}...`);
        
        const nodes = await request(`${GET_NODES_API}?userId=${user.uid}`);
        if (!Array.isArray(nodes)) continue;

        // SINCRONIZA com a API antes de verificar
        await syncNodesWithAPI(nodes, user.uid);

        // Filtra nodes válidos para verificação
        const validNodes = Array.from(nodeState.all.values())
            .filter(node => node.userId === user.uid && node.ip);
        
        if (validNodes.length === 0) {
            console.log(`   Nenhum node para verificar`);
            continue;
        }
        
        console.log(`\n🔍 Verificando ${validNodes.length} nodes do usuário ${user.uid}...`);
        
        for (let i = 0; i < validNodes.length; i++) {
            const node = validNodes[i];
            
            console.log(`\n   [${i + 1}/${validNodes.length}] Node ${node.ip}:${node.port || 80} (ID: ${node.id})`);
            
            const online = await preciseCheck(node);
            await updateNodeStatus(node, online, false);
            
            if (i < validNodes.length - 1) {
                console.log(`   ⏱ Aguardando 1s...`);
                await new Promise(r => setTimeout(r, 1000));
            }
        }
    }
    
    console.log(`\n📊 ESTATÍSTICAS:`);
    console.log(`   ├─ Total nodes: ${nodeState.all.size}`);
    console.log(`   ├─ Online: ${nodeState.online.size}`);
    console.log(`   ├─ Offline: ${nodeState.offline.size}`);
    console.log(`   └─ Novos: ${nodeState.unknown.size}`);
}

/* ============================= */
/* VERIFICAÇÃO RÁPIDA */
/* ============================= */
async function quickCheckOffline() {
    const toCheck = [
        ...Array.from(nodeState.offline),
        ...Array.from(nodeState.unknown)
    ].map(id => nodeState.all.get(id)).filter(node => node);
    
    if (toCheck.length === 0) return;
    
    console.log(`\n🔄 Verificação rápida: ${toCheck.length} nodes offline/novos...`);
    
    for (const node of toCheck) {
        if (nodeState.processing.has(node.id)) continue;
        
        console.log(`   🔍 Teste rápido ${node.ip}...`);
        const online = await quickCheck(node);
        
        if (online) {
            console.log(`   ✅ Node ${node.ip} respondeu, confirmando...`);
            const fullOnline = await preciseCheck(node);
            await updateNodeStatus(node, fullOnline, true);
        }
        
        await new Promise(r => setTimeout(r, 500));
    }
}

async function quickCheckServers() {
    const offlineServers = Array.from(serverState.offline)
        .map(id => serverState.all.get(id))
        .filter(server => server);
    
    if (offlineServers.length === 0) return;
    
    console.log(`\n🔄 Verificando ${offlineServers.length} servidores offline...`);
    
    for (const server of offlineServers) {
        if (serverState.processing.has(server.uid)) continue;
        
        const online = await pingTest(server.ip);
        if (online) {
            console.log(`   ✅ Servidor ${server.uid} respondeu`);
            await updateServerStatus(server.uid, true);
        }
        
        await new Promise(r => setTimeout(r, 500));
    }
}

/* ============================= */
/* LOOP PRINCIPAL */
/* ============================= */
async function run() {
    console.log("\n" + "=".repeat(60));
    console.log("🔄 VERIFICAÇÃO COMPLETA:", new Date().toLocaleString("pt-BR"));
    console.log("=".repeat(60));

    try {
        await checkServers();
        await checkNodes();
    } catch (err) {
        console.log("❌ ERRO GERAL:", err.message);
    }
}

/* ============================= */
/* INICIALIZAÇÃO */
/* ============================= */
async function initialize() {
    console.log("\n🚀 Inicializando monitor com sincronização automática...");
    console.log("📋 Qualquer alteração de IP será detectada no próximo ciclo!");
    
    await run();
    
    setInterval(run, CHECK_INTERVAL);
    
    setInterval(async () => {
        try {
            await quickCheckOffline();
            await quickCheckServers();
        } catch (err) {
            console.log("❌ Erro no quick check:", err.message);
        }
    }, 5000);
    
    console.log("✅ Monitor rodando!");
}

initialize().catch(console.error);

process.on('SIGINT', () => {
    console.log('\n\n📊 ESTATÍSTICAS FINAIS:');
    console.log(`   ├─ Servidores: ${serverState.all.size}`);
    console.log(`   ├─ Nodes totais: ${nodeState.all.size}`);
    console.log(`   ├─ Nodes online: ${nodeState.online.size}`);
    console.log(`   └─ Nodes offline: ${nodeState.offline.size}`);
    console.log('\n👋 Monitor encerrado');
    process.exit();
});
            
    
    
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
