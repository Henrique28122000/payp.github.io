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
