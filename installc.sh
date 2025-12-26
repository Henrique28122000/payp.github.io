#!/bin/bash
set -e

APP_DIR="/opt/netpulse"
JS_FILE="Completo.js"
JS_URL="https://raw.githubusercontent.com/Henrique28122000/payp.github.io/refs/heads/main/Completo.js"
CONFIG_FILE="$APP_DIR/config.json"

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
  echo "📦 Instalando Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
fi

# ─────────────────────────────────────────
# Diretório
# ─────────────────────────────────────────
mkdir -p $APP_DIR
cd $APP_DIR

# ─────────────────────────────────────────
# Baixa JS
# ─────────────────────────────────────────
echo "⬇️ Baixando monitor..."
wget -O $JS_FILE $JS_URL

# ─────────────────────────────────────────
# Cria config.json
# ─────────────────────────────────────────
cat > $CONFIG_FILE <<EOF
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
# Start
# ─────────────────────────────────────────
cat > start.sh <<'EOF'
#!/bin/bash
clear
echo "▶️ Nexyra Link iniciado"
nohup node Completo.js > monitor.log 2>&1 &
echo $! > netpulse.pid
sleep 1
EOF

# ─────────────────────────────────────────
# Stop
# ─────────────────────────────────────────
cat > stop.sh <<'EOF'
#!/bin/bash
if [ -f netpulse.pid ]; then
  kill $(cat netpulse.pid) 2>/dev/null
  rm -f netpulse.pid
  echo "⏹️ Nexyra Link parado"
else
  echo "⚠️ Monitor não está rodando"
fi
sleep 1
EOF

# ─────────────────────────────────────────
# Menu
# ─────────────────────────────────────────
cat > menu.sh <<'EOF'
#!/bin/bash

CONFIG="config.json"

edit_api() {
  read -p "Nova GET API: " get
  read -p "Nova UPDATE API: " upd
  jq ".apis.get=\"$get\" | .apis.update=\"$upd\"" $CONFIG > tmp && mv tmp $CONFIG
  echo "✅ APIs atualizadas"
  sleep 1
}

edit_interval() {
  read -p "Tempo em minutos: " min
  ms=$((min * 60000))
  jq ".check_interval_ms=$ms" $CONFIG > tmp && mv tmp $CONFIG
  echo "✅ Intervalo atualizado para ${min} minuto(s)"
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
  echo "6) 🚀 Ativar auto start"
  echo "7) ❌ Desativar auto start"
  echo "0) 🔚 Sair"
  echo
  read -p "Escolha: " opt

  case "$opt" in
    1) ./start.sh ;;
    2) ./stop.sh ;;
    3) tail -f monitor.log ;;
    4) edit_api ;;
    5) edit_interval ;;
    6) systemctl enable netpulse && systemctl start netpulse ;;
    7) systemctl stop netpulse && systemctl disable netpulse ;;
    0) exit ;;
  esac
done
EOF

chmod +x *.sh

# ─────────────────────────────────────────
# Systemd
# ─────────────────────────────────────────
cat > /etc/systemd/system/netpulse.service <<EOF
[Unit]
Description=Nexyra Link NetPulse Monitor
After=network.target

[Service]
ExecStart=/usr/bin/node $APP_DIR/Completo.js
WorkingDirectory=$APP_DIR
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# ─────────────────────────────────────────
# Auto menu SSH
# ─────────────────────────────────────────
if ! grep -q "menu.sh" ~/.bashrc; then
  echo "cd $APP_DIR && ./menu.sh" >> ~/.bashrc
fi

echo
echo "✅ Instalação concluída!"
echo "📂 Diretório: $APP_DIR"
echo "🔁 Reconecte via SSH para abrir o menu"
