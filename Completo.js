const { exec } = require("child_process");
const net = require("net");
const dns = require("dns");

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
// CONFIG
// ============================
const GET_API = "https://paulohenriquedev.site/netpulse/get_nodes.php";
const UPDATE_API = "https://paulohenriquedev.site/netpulse/update_node.php";

const TCP_PORTS = [80, 443, 22, 8080];
const TIMEOUT_PING = 1200;
const TIMEOUT_TCP = 1500;
const RETRIES = 2;

const CHECK_INTERVAL = 30_000;
const isWindows = process.platform === "win32";

// ============================
// UTIL
// ============================
const sleep = ms => new Promise(r => setTimeout(r, ms));
const isIP = host => /^(\d{1,3}\.){3}\d{1,3}$/.test(host);

// ============================
// LIMPA TERMINAL (PORTÁVEL)
// ============================
function clearConsole() {
  if (isWindows) {
    exec("cls");
  } else {
    process.stdout.write("\x1Bc");
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
// CICLO
// ============================
async function checkAllNodes() {
  clearConsole();

  console.log("🖥️ Nexyra Link / NetPulse Monitor");
  console.log(`⏱️ Verificação: ${new Date().toLocaleString()}`);
  console.log("──────────────────────────────────");

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
      }

      console.log(
        `${node.ip.padEnd(18)} → ${newStatus}` +
        (result.method ? ` [${result.method}]` : "")
      );

    } catch (err) {
      console.error(`⚠️ Erro no IP ${node.ip}:`, err);
    }
  }
}

// ============================

// LOOP Quero fazer um .exe 32 bits pelo termux da certo 
// ============================
(async () => {
  console.log("✅ Nexyra Link iniciado");
  while (true) {
    await checkAllNodes();
    await sleep(CHECK_INTERVAL);
  }
})();
