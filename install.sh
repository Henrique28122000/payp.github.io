#!/bin/bash
set -e

echo "🚀 Instalando NetPulse Monitor..."

# ============================
# CONFIG
# ============================
APP_DIR="/opt/netpulse"
SCRIPT_NAME="index.js"
RAW_URL="https://raw.githubusercontent.com/Henrique28122000/payp.github.io/main/index.js"
LOG_FILE="$APP_DIR/netpulse.log"

# ============================
# ROOT CHECK
# ============================
if [ "$(id -u)" != "0" ]; then
  echo "❌ Rode como root ou sudo"
  exit 1
fi

# ============================
# DEPENDENCIAS BASICAS
# ============================
apt update -y
apt install -y curl ca-certificates

# ============================
# NODE.JS
# ============================
if ! command -v node >/dev/null 2>&1; then
  echo "📦 Instalando Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
else
  echo "✅ Node.js já instalado"
fi

NODE_BIN=$(command -v node)

# ============================
# CRIA APP DIR
# ============================
mkdir -p "$APP_DIR"
cd "$APP_DIR"

# ============================
# DOWNLOAD SCRIPT
# ============================
echo "⬇️ Baixando index.js..."
curl -fsSL "$RAW_URL" -o "$SCRIPT_NAME"

if [ ! -s "$SCRIPT_NAME" ]; then
  echo "❌ Falha ao baixar index.js"
  exit 1
fi

# ============================
# PACKAGE.JSON
# ============================
cat > package.json <<'EOF'
{
  "name": "netpulse",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "node-fetch": "^3.3.2"
  }
}
EOF

# ============================
# DEPENDENCIAS NODE
# ============================
npm install --silent

# ============================
# TESTE
# ============================
echo "🧪 Testando execução..."
$NODE_BIN "$SCRIPT_NAME" || true

# ============================
# CRONTAB (ANTI DUPLA EXECUÇÃO)
# ============================
CRON="* * * * * /usr/bin/flock -n /tmp/netpulse.lock $NODE_BIN $APP_DIR/$SCRIPT_NAME >> $LOG_FILE 2>&1"

(crontab -l 2>/dev/null | grep -v "$SCRIPT_NAME" || true; echo "$CRON") | crontab -

# ============================
# FINAL
# ============================
echo ""
echo "✅ NetPulse instalado com sucesso"
echo "⏱ Rodando a cada 1 minuto"
echo "📄 Logs: $LOG_FILE"
