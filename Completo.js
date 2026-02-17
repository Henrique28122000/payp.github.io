const { exec } = require("child_process");
const net = require("net");
const dns = require("dns");
const fs = require("fs");
const http = require("http");
const https = require("https");
const url = require("url");

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
// LOAD CONFIG JSON
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

// ============================
// UTIL
// ============================
const sleep = ms => new Promise(r => setTimeout(r, ms));
const isIP = host => /^(\d{1,3}\.){3}\d{1,3}$/.test(host);

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
// BUSCAR USUÁRIOS (GET_USERS_API)
// ============================
async function fetchUsersWithServers() {
  try {
    console.log("📡 Buscando usuários com servidores...");
    const users = await request({
      url: GET_USERS_API,
      method: 'GET',
      headers: { 'User-Agent': 'NetPulse/2.0' },
      timeout: 10000
    });
    
    console.log(`✅ Encontrados ${users.length} usuários`);
    return Array.isArray(users) ? users : [];
    
  } catch (err) {
    console.error("❌ Erro ao buscar usuários:", err.message);
    return [];
  }
}

// ============================
// BUSCAR NODES (GET_NODES_API)
// ============================
async function fetchUserNodes(userId) {
  try {
    const apiUrl = `${GET_NODES_API}?userId=${userId}`;
    const nodes = await request({
      url: apiUrl,
      method: 'GET',
      headers: { 'User-Agent': 'NetPulse/2.0' },
      timeout: 10000
    });
    
    return Array.isArray(nodes) ? nodes : [];
    
  } catch (err) {
    console.error(`❌ Erro ao buscar nodes:`, err.message);
    return [];
  }
}

// ============================
// ATUALIZAR STATUS DO SERVIDOR (SEM monitoring_status)
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

    // NOTA: Não estamos enviando monitoring_status porque não existe na tabela
    const postData = {
      uid: uid,
      is_online: isOnline,
      last_update: lastUpdate,
      ping_ms: pingMs,
      reason: reason
    };

    console.log(`📤 Enviando atualização:`, postData);
    
    const response = await request({
      url: UPDATE_SERVER_API,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      timeout: 5000
    }, postData);
    
    console.log(`✅ Resposta:`, response);
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

  console.log(`   🔍 Testando ${host}...`);

  if (!isIP(host)) {
    const dnsOk = await checkDNS(host);
    if (!dnsOk) return { online: false, reason: "DNS falhou" };
  }

  for (let i = 0; i <= RETRIES; i++) {
    const ping = await pingICMP(host);
    if (ping.online) {
      console.log(`   ✅ ICMP OK - ${ping.ms}ms`);
      return { 
        online: true, 
        ms: ping.ms, 
        method: "icmp"
      };
    }

    const tcp = await checkTCP(host);
    if (tcp.online) {
      console.log(`   ✅ TCP porta ${tcp.port} OK - ${tcp.ms}ms`);
      return { 
        online: true, 
        ms: tcp.ms,
        method: `tcp:${tcp.port}`
      };
    }

    if (i < RETRIES) {
      console.log(`   ⚠️ Tentativa ${i + 1} falhou, tentando novamente...`);
      await sleep(1000);
    }
  }

  console.log(`   ❌ Todas as tentativas falharam`);
  return { 
    online: false, 
    reason: "timeout após múltiplas tentativas"
  };
}

// ============================
// VERIFICA SERVIDOR DE UM USUÁRIO
// ============================
async function checkUserServer(user) {
  console.log(`\n📡 VERIFICANDO SERVIDOR DE: ${user.email}`);
  console.log(`   IP: ${user.monitoring_ip}`);
  console.log(`   Última atualização: ${user.monitoring_last_update || 'Nunca'}`);

  if (!user.monitoring_ip) {
    console.log(`   ⚠️ Sem IP configurado`);
    return null;
  }

  if (user.monitoring_enabled === 0) {
    console.log(`   ⚠️ Monitoramento desativado`);
    return null;
  }

  const cacheKey = user.monitoring_ip;
  const cached = serverStatusCache.get(cacheKey);
  
  // Cache de 2 minutos
  if (cached && (Date.now() - cached.timestamp < 120000)) {
    console.log(`   📦 Usando cache (menos de 2 minutos)`);
    return cached.status;
  }

  console.log(`   🔄 Testando conectividade...`);
  const result = await checkHost(user.monitoring_ip);
  
  const isOnline = result.online ? 1 : 0;
  const statusText = result.online ? 'ONLINE' : 'OFFLINE';
  
  console.log(`   📊 Resultado: ${statusText} ${result.ms ? `[${result.ms}ms]` : ''}`);

  // Atualiza cache
  serverStatusCache.set(cacheKey, {
    status: { is_online: isOnline },
    timestamp: Date.now()
  });

  // SEMPRE atualiza no banco
  console.log(`   📤 Atualizando banco de dados...`);
  const updated = await updateServerStatus(
    user.uid,
    isOnline,
    result.ms || null,
    result.reason || null
  );

  if (updated) {
    console.log(`   ✅ Servidor atualizado: ${statusText}`);
  } else {
    console.log(`   ❌ Falha ao atualizar servidor`);
  }
  
  return { is_online: isOnline };
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
    console.log("⚠️ Nenhum servidor configurado no banco de dados");
    return;
  }

  let online = 0;
  let offline = 0;

  for (const user of users) {
    if (user.monitoring_ip) {
      const result = await checkUserServer(user);
      if (result) {
        if (result.is_online) online++;
        else offline++;
      }
    }
    await sleep(500);
  }

  console.log(`\n📊 RESUMO: ${online} online, ${offline} offline`);
}

// ============================
// VERIFICA NODES DE UM USUÁRIO
// ============================
async function checkUserNodes(user) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`🔍 VERIFICANDO NODES DE: ${user.email}`);
  console.log(`   Servidor: ${user.monitoring_ip || 'Nenhum'}`);
  console.log(`${'='.repeat(60)}`);
  
  // Verifica se o servidor do usuário está online (usando cache)
  const cacheKey = user.monitoring_ip;
  const cached = serverStatusCache.get(cacheKey);
  
  if (!cached || !cached.status.is_online) {
    console.log(`   ⏸️ Servidor offline ou sem cache, pulando nodes`);
    return;
  }

  const nodes = await fetchUserNodes(user.uid);
  
  if (nodes.length === 0) {
    console.log(`   📭 Nenhum node configurado para este usuário`);
    return;
  }

  console.log(`   📊 Total de nodes: ${nodes.length}`);

  let alterados = 0;

  for (const node of nodes) {
    if (!node?.ip) continue;

    console.log(`\n   🔍 Node: ${node.name || node.ip}`);
    const result = await checkHost(node.ip);
    const newStatus = result.online ? "online" : "offline";

    if (newStatus !== node.status) {
      console.log(`   ⚡ Mudou: ${node.status} → ${newStatus}`);
      
      await updateNodeStatus({
        id: node.id,
        status: newStatus,
        last_ping: result.ms || null
      });

      alterados++;
    } else {
      console.log(`   ✅ OK: ${newStatus} ${result.ms ? `[${result.ms}ms]` : ''}`);
    }

    await sleep(300);
  }

  console.log(`\n   ✅ Nodes de ${user.email}: ${alterados} alterações`);
}

// ============================
// VERIFICA TODOS OS NODES
// ============================
async function checkAllNodes() {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`🔄 VERIFICANDO TODOS OS NODES - ${new Date().toLocaleString()}`);
  console.log(`${'='.repeat(60)}`);
  
  const users = await fetchUsersWithServers();
  
  for (const user of users) {
    if (user.monitoring_ip) {
      await checkUserNodes(user);
    }
  }
}

// ============================
// LOOP PRINCIPAL
// ============================
(async () => {
  console.log("\n" + "=".repeat(70));
  console.log("🚀 NetPulse v3.0 - Monitoramento Multi-Empresa");
  console.log("=".repeat(70));
  console.log(`⏱️  Intervalo: ${CHECK_INTERVAL/1000}s`);
  console.log(`📡 GET Users: ${GET_USERS_API}`);
  console.log(`📡 UPDATE Server: ${UPDATE_SERVER_API}`);
  console.log("=".repeat(70) + "\n");

  // Primeira verificação imediata
  await checkAllServers();
  await checkAllNodes();

  while (true) {
    const startTime = Date.now();
    
    try {
      await checkAllServers();
      await checkAllNodes();
      
    } catch (err) {
      console.error("❌ Erro no loop principal:", err);
    }

    const elapsed = Date.now() - startTime;
    const waitTime = Math.max(5000, CHECK_INTERVAL - elapsed);
    
    console.log(`\n⏳ Aguardando ${Math.round(waitTime/1000)}s até a próxima verificação...\n`);
    await sleep(waitTime);
  }
})();
