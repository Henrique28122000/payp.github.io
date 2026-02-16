const { exec } = require("child_process");
const net = require("net");
const dns = require("dns");
const fs = require("fs");
const os = require("os");
const https = require("https");

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

// Cache para status dos servidores
let serverStatusCache = new Map(); // ip -> { is_online, last_check }

// Cache para IPs de servidores por usuário
let userServersCache = new Map(); // uid -> { monitoring_ip, last_check }

// ============================
// UTIL
// ============================
const sleep = ms => new Promise(r => setTimeout(r, ms));
const isIP = host => /^(\d{1,3}\.){3}\d{1,3}$/.test(host);

// ============================
// BUSCAR USUÁRIOS COM SERVIDORES
// ============================
async function fetchUsersWithServers() {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);

    const res = await fetch(GET_USERS_API, {
      signal: controller.signal,
      headers: { "User-Agent": "NetPulse/2.0" }
    });
    
    clearTimeout(timeoutId);
    
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    
    const users = await res.json();
    return Array.isArray(users) ? users : [];
    
  } catch (err) {
    console.error("❌ Erro ao buscar usuários:", err.message);
    return [];
  }
}

// ============================
// BUSCAR NODES DE UM USUÁRIO
// ============================
async function fetchUserNodes(userId) {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);

    const res = await fetch(`${GET_NODES_API}?userId=${userId}`, {
      signal: controller.signal,
      headers: { "User-Agent": "NetPulse/2.0" }
    });
    
    clearTimeout(timeoutId);
    
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    
    const nodes = await res.json();
    return Array.isArray(nodes) ? nodes : [];
    
  } catch (err) {
    console.error(`❌ Erro ao buscar nodes do usuário ${userId}:`, err.message);
    return [];
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
// CHECK COMPLETO DE HOST
// ============================
async function checkHost(host) {
  if (!host || host.trim() === '') {
    return { online: false, reason: "no_ip" };
  }

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
// VERIFICA SERVIDOR DE UM USUÁRIO
// ============================
async function checkUserServer(user) {
  if (!user.monitoring_ip || user.monitoring_enabled === 0) {
    return null;
  }

  const cacheKey = user.monitoring_ip;
  const cached = serverStatusCache.get(cacheKey);
  
  // Usa cache se tiver menos de 5 minutos
  if (cached && (Date.now() - cached.timestamp < 300000)) {
    return cached.status;
  }

  console.log(`📡 Verificando servidor ${user.monitoring_ip} (${user.email})...`);
  
  const result = await checkHost(user.monitoring_ip);
  
  const status = {
    is_online: result.online,
    monitoring_ip: user.monitoring_ip,
    last_update: new Date().toISOString(),
    ping_ms: result.ms || null,
    method: result.method || null,
    reason: result.reason || null
  };

  // Atualiza cache
  serverStatusCache.set(cacheKey, {
    status,
    timestamp: Date.now()
  });

  // Atualiza no banco
  try {
    await fetch(UPDATE_SERVER_API, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        uid: user.uid,
        ...status
      })
    });
  } catch (err) {
    console.error(`❌ Erro ao atualizar status do servidor ${user.monitoring_ip}:`, err.message);
  }

  console.log(`✅ Servidor ${user.monitoring_ip}: ${result.online ? 'ONLINE' : 'OFFLINE'} ${result.ms ? `[${result.ms}ms]` : ''}`);
  
  return status;
}

// ============================
// VERIFICA TODOS OS SERVIDORES
// ============================
async function checkAllServers() {
  console.log(`\n📡 VERIFICANDO SERVIDORES - ${new Date().toLocaleTimeString()}`);
  
  const users = await fetchUsersWithServers();
  
  if (users.length === 0) {
    console.log("⚠️ Nenhum servidor configurado");
    return;
  }

  console.log(`👥 Total de usuários com servidor: ${users.length}`);

  let online = 0;
  let offline = 0;

  for (const user of users) {
    const status = await checkUserServer(user);
    if (status) {
      if (status.is_online) online++;
      else offline++;
    }
    await sleep(500); // Pausa entre verificações
  }

  console.log(`📊 Servidores: ${online} online, ${offline} offline`);
}

// ============================
// VERIFICA NODES DE UM USUÁRIO
// ============================
async function checkUserNodes(user) {
  // Só verifica nodes se o servidor do usuário estiver online
  const cacheKey = user.monitoring_ip;
  const cached = serverStatusCache.get(cacheKey);
  
  if (!cached || !cached.status.is_online) {
    console.log(`⏸️ Servidor de ${user.email} offline, pulando nodes`);
    return;
  }

  console.log(`\n🔍 VERIFICANDO NODES DE ${user.email} - ${user.monitoring_ip}`);
  
  const nodes = await fetchUserNodes(user.uid);
  
  if (nodes.length === 0) {
    console.log(`📭 Nenhum node para ${user.email}`);
    return;
  }

  console.log(`📊 Nodes: ${nodes.length}`);

  let alterados = 0;

  for (const node of nodes) {
    if (!node?.ip) continue;

    try {
      const result = await checkHost(node.ip);
      const newStatus = result.online ? "online" : "offline";

      if (newStatus !== node.status) {
        console.log(`⚡ ${node.ip} mudou: ${node.status} → ${newStatus} ${result.method ? `[${result.method}]` : ''}`);
        
        const updateData = {
          id: node.id,
          status: newStatus,
          last_ping: result.ms || null,
          method: result.method || null
        };

        const updateRes = await fetch(UPDATE_NODE_API, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(updateData)
        });

        if (updateRes.ok) {
          alterados++;
        }
      }

      await sleep(300); // Pausa entre nodes
      
    } catch (err) {
      console.error(`⚠️ Erro no node ${node.ip}:`, err.message);
    }
  }

  console.log(`✅ Nodes de ${user.email}: ${alterados} alterações`);
}

// ============================
// VERIFICA TODOS OS NODES
// ============================
async function checkAllNodes() {
  console.log(`\n🔄 VERIFICANDO TODOS OS NODES - ${new Date().toLocaleTimeString()}`);
  
  const users = await fetchUsersWithServers();
  
  for (const user of users) {
    await checkUserNodes(user);
  }
}

// ============================
// LOOP PRINCIPAL
// ============================
(async () => {
  console.log("=".repeat(70));
  console.log("🚀 NetPulse v3.0 - Monitoramento Multi-Empresa");
  console.log(`⏱️  Intervalo: ${CHECK_INTERVAL/1000}s`);
  console.log("=".repeat(70));

  // Primeira verificação imediata
  await checkAllServers();
  await checkAllNodes();

  // Loop infinito
  while (true) {
    const startTime = Date.now();
    
    try {
      // 1. Primeiro verifica todos os servidores
      await checkAllServers();
      
      // 2. Depois verifica os nodes
      await checkAllNodes();
      
    } catch (err) {
      console.error("❌ Erro no loop principal:", err);
    }

    const elapsed = Date.now() - startTime;
    const waitTime = Math.max(1000, CHECK_INTERVAL - elapsed);
    
    console.log(`\n⏳ Aguardando ${Math.round(waitTime/1000)}s...`);
    console.log("-".repeat(70));
    await sleep(waitTime);
  }
})();
