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
// LOAD CONFIG JSON
// ============================
const config = JSON.parse(fs.readFileSync("./config.json", "utf8"));

const GET_API = config.apis.get;
const UPDATE_API = config.apis.update;

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
    const cmd = isWindows
      ? `ping -n 1 -w ${timeout} ${host}`
      : `ping -c 1 -W 1 ${host}`;

    exec(cmd, (err, stdout) => {
      if (err) return resolve({ online: false });

      const match = stdout.match(/(tempo|time)[=<]\s*(\d+)/i);
      const ms = match ? parseInt(match[2], 10) : null;

      resolve({ online: true, ms });
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

      socket.connect(port, host, () => {
        if (!finished) {
          finished = true;
          socket.destroy();
          resolve({ online: true, port });
        }
      });

      socket.on("error", done);
      socket.on("timeout", done);

      function done() {
        socket.destroy();
        checked++;
        if (!finished && checked === ports.length) {
          finished = true;
          resolve({ online: false });
        }
      }
    });
  });
}

// ============================
// CHECK COMPLETO
// ============================
async function isOnline(host) {
  if (!isIP(host)) {
    const dnsOk = await checkDNS(host);
    if (!dnsOk) return { online: false, reason: "dns" };
  }

  for (let i = 0; i <= RETRIES; i++) {
    const ping = await pingICMP(host);
    if (ping.online) {
      return { online: true, ms: ping.ms, method: "icmp" };
    }

    const tcp = await checkTCP(host);
    if (tcp.online) {
      return { online: true, method: `tcp:${tcp.port}` };
    }
  }

  return { online: false, reason: "timeout" };
}

// ============================
// CICLO PRINCIPAL
// ============================
async function checkAllNodes() {
  console.log(`\n🔄 Verificação - ${new Date().toLocaleTimeString()}`);

  let nodes = [];
  try {
    const res = await fetch(GET_API);
    nodes = await res.json();
  } catch (err) {
    console.error("❌ Erro ao buscar nós:", err);
    return;
  }

  for (const node of nodes) {
    if (!node?.ip) continue;

    try {
      const result = await isOnline(node.ip);
      const newStatus = result.online ? "online" : "offline";

      if (newStatus !== node.status) {
        await fetch(UPDATE_API, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            id: node.id,
            status: newStatus,
            last_ping: result.ms ?? null
          })
        });

        console.log(
          `${node.ip} → ${newStatus}` +
          (result.method ? ` [${result.method}]` : "")
        );
      }
    } catch (err) {
      console.error(`⚠️ Erro no IP ${node.ip}:`, err);
    }
  }
}

// ============================
// LOOP INFINITO
// ============================
(async () => {
  console.log("✅ NetPulse iniciado");
  while (true) {
    await checkAllNodes();
    await sleep(CHECK_INTERVAL);
  }
})();
