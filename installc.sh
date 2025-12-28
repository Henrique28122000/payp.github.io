
#!/bin/bash
set -e

APP_DIR="/opt/netpulse"
APP_NAME="netpulse"
JS_FILE="Completo.js"
JS_URL="https://raw.githubusercontent.com/Henrique28122000/payp.github.io/refs/heads/main/Completo.js"
CONFIG_FILE="$APP_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

echo "🚀 Instalando Nexyra Link / NetPulse Monitor"
sleep 1

# ─────────────────────────────────────────
# Atualiza sistema
# ─────────────────────────────────────────
apt update -y

# ─────────────────────────────────────────
# Dependências
# ─────────────────────────────────────────
apt install -y curl wget sudo git jq

# ─────────────────────────────────────────
# Node.js 20
# ─────────────────────────────────────────
if ! command -v node >/dev/null 2>&1; then
  echo "📦 Instalando Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
fi

# ─────────────────────────────────────────
# Diretório da aplicação
# ─────────────────────────────────────────
mkdir -p "$APP_DIR"
cd "$APP_DIR"

# ─────────────────────────────────────────
# Baixa o monitor
# ─────────────────────────────────────────
echo "⬇️ Baixando monitor..."
wget -q -O "$JS_FILE" "$JS_URL"

# ─────────────────────────────────────────
# Cria config.json
# ─────────────────────────────────────────
cat > "$CONFIG_FILE" <<EOF
{
  "apis": {
    "get": "https://paulohenriquedev.site/netpulse/get_nodes_1.php",
    "update": "https://paulohenriquedev.site/netpulse/update_node_1.php"
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
# Script START
# ─────────────────────────────────────────
cat > start.sh <<'EOF'
#!/bin/bash
systemctl start netpulse
systemctl status netpulse --no-pager
EOF

# ─────────────────────────────────────────
# Script STOP
# ─────────────────────────────────────────
cat > stop.sh <<'EOF'
#!/bin/bash
systemctl stop netpulse
echo "⏹️ Nexyra Link parado"
EOF

# ─────────────────────────────────────────
# Script LOGS
# ─────────────────────────────────────────
cat > logs.sh <<'EOF'
#!/bin/bash
journalctl -u netpulse -f
EOF

# ─────────────────────────────────────────
# MENU
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
  echo "✅ Intervalo atualizado para ${min} minuto(s)"
  sleep 1
}

while true; do
  clear
  echo "🖥️ Nexyra Link / Monitor"
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
# SYSTEMD SERVICE (CORRETO)
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

systemctl daemon-reload

# ─────────────────────────────────────────
# Menu automático no SSH
# ─────────────────────────────────────────
if ! grep -q "menu.sh" ~/.bashrc; then
  echo "cd $APP_DIR && ./menu.sh" >> ~/.bashrc
fi

echo
echo "✅ Instalação concluída com SUCESSO!"
echo "📂 Diretório: $APP_DIR"
echo "⚙️ Serviço: netpulse"
echo "🔁 Reinicie ou reconecte via SSH para abrir o menu"
