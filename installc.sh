
#!/bin/bash
set -e

# ─────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────
APP_NAME="netpulse"
APP_DIR="/opt/netpulse"
JS_FILE="Completo.js"
JS_URL="https://raw.githubusercontent.com/Henrique28122000/payp.github.io/refs/heads/main/Completo.js"
CONFIG_FILE="$APP_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
MENU_CMD="/usr/local/bin/menu"

echo "🚀 Instalando Nexyra Link / NetPulse Monitor"
sleep 1

# ─────────────────────────────────────────
# CHECK ROOT
# ─────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo "❌ Execute como root"
  exit 1
fi

# ─────────────────────────────────────────
# UPDATE
# ─────────────────────────────────────────
apt update -y

# ─────────────────────────────────────────
# DEPENDÊNCIAS
# ─────────────────────────────────────────
apt install -y curl wget git jq sudo

# ─────────────────────────────────────────
# NODE.JS 20
# ─────────────────────────────────────────
if ! command -v node >/dev/null 2>&1; then
  echo "📦 Instalando Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
fi

# ─────────────────────────────────────────
# DIRETÓRIO
# ─────────────────────────────────────────
mkdir -p "$APP_DIR"
cd "$APP_DIR"

# ─────────────────────────────────────────
# BAIXA SCRIPT JS
# ─────────────────────────────────────────
echo "⬇️ Baixando monitor..."
wget -q -O "$JS_FILE" "$JS_URL"

# ─────────────────────────────────────────
# CONFIG.JSON
# ─────────────────────────────────────────
cat > "$CONFIG_FILE" <<EOF
{
  "apis": {
    "get": "https://nexyra.myftp.biz/netpulse/get_nodes_1.php",
    "update": "https://nexyra.myftp.biz/netpulse/update_node_1.php"
  },
  "check_interval_ms": 60000,
  "tcp_ports": [80, 443, 22, 8080],
  "timeouts": {
    "ping": 1200,
    "tcp": 1500
  },
  "retries": 2
}
EOF

# ─────────────────────────────────────────
# SCRIPTS AUXILIARES
# ─────────────────────────────────────────
cat > start.sh <<'EOF'
#!/bin/bash
systemctl start netpulse
systemctl status netpulse --no-pager
EOF

cat > stop.sh <<'EOF'
#!/bin/bash
systemctl stop netpulse
echo "⏹️ NetPulse parado"
EOF

cat > logs.sh <<'EOF'
#!/bin/bash
journalctl -u netpulse -f
EOF

# ─────────────────────────────────────────
# MENU INTERATIVO
# ─────────────────────────────────────────
cat > menu.sh <<'EOF'
#!/bin/bash

CONFIG="config.json"

edit_api() {
  read -p "Nova GET API: " get
  read -p "Nova UPDATE API: " upd
  jq ".apis.get=\"$get\" | .apis.update=\"$upd\"" "$CONFIG" > tmp && mv tmp "$CONFIG"
  echo "✅ APIs atualizadas"
  sleep 1
}

edit_interval() {
  read -p "Tempo em minutos: " min
  ms=$((min * 60000))
  jq ".check_interval_ms=$ms" "$CONFIG" > tmp && mv tmp "$CONFIG"
  echo "✅ Intervalo atualizado"
  sleep 1
}

while true; do
  clear
  echo "🖥️ Nexyra Link / NetPulse"
  echo "────────────────────────────"
  echo "1) ▶️ Iniciar monitor"
  echo "2) ⏹️ Parar monitor"
  echo "3) 📄 Ver logs"
  echo "4) 🔧 Alterar APIs"
  echo "5) ⏱️ Alterar tempo de verificação"
  echo "6) 🚀 Ativar auto start (boot)"
  echo "7) ❌ Desativar auto start"
  echo "8) 🔄 Reiniciar monitor"
  echo "0) 🔚 Sair"
  echo
  read -p "Escolha: " opt

  case "$opt" in
    1) systemctl start netpulse ;;
    2) systemctl stop netpulse ;;
    3) journalctl -u netpulse -f ;;
    4) edit_api ;;
    5) edit_interval ;;
    6) systemctl enable netpulse && echo "✅ Auto start ativado" && sleep 1 ;;
    7) systemctl disable netpulse && echo "❌ Auto start desativado" && sleep 1 ;;
    8) systemctl restart netpulse ;;
    0) exit ;;
  esac
done
EOF

chmod +x *.sh

# ─────────────────────────────────────────
# COMANDO GLOBAL: menu
# ─────────────────────────────────────────
ln -sf "$APP_DIR/menu.sh" "$MENU_CMD"
chmod +x "$MENU_CMD"

# ─────────────────────────────────────────
# SYSTEMD SERVICE
# ─────────────────────────────────────────
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Nexyra Link NetPulse Monitor
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node $APP_DIR/$JS_FILE
Restart=always
RestartSec=3
User=root
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# ─────────────────────────────────────────
# ATIVA + INICIA AUTOMATICAMENTE
# ─────────────────────────────────────────
systemctl daemon-reload
systemctl enable netpulse
systemctl restart netpulse

# ─────────────────────────────────────────
# MENU AUTOMÁTICO AO ENTRAR NO SSH
# ─────────────────────────────────────────
if ! grep -q "$APP_DIR/menu.sh" ~/.bashrc; then
  echo "cd $APP_DIR && ./menu.sh" >> ~/.bashrc
fi

echo
echo "✅ INSTALAÇÃO 100% CONCLUÍDA"
echo "🚀 NetPulse já está RODANDO"
echo "♻️ Ativado automaticamente no boot"
echo "📂 Diretório: $APP_DIR"
echo
echo "👉 Para abrir o menu a qualquer momento, digite:"
echo "   🔹 menu"
echo
echo "🔁 Reabra o SSH para abrir o menu automaticamente"
