#!/bin/bash

set -e

APP_DIR="/opt/netpulse"
JS_FILE="Completo.js"
JS_URL="https://raw.githubusercontent.com/Henrique28122000/payp.github.io/refs/heads/main/Completo.js"

echo "🚀 Instalando Nexyra Link / NetPulse Monitor"

# ─────────────────────────────
# Atualiza sistema
# ─────────────────────────────
apt update -y

# ─────────────────────────────
# Instala dependências básicas
# ─────────────────────────────
apt install -y curl wget git sudo

# ─────────────────────────────
# Instala Node.js
# ─────────────────────────────
if ! command -v node &> /dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
fi

# ─────────────────────────────
# Cria diretório
# ─────────────────────────────
mkdir -p $APP_DIR
cd $APP_DIR

# ─────────────────────────────
# Baixa script principal
# ─────────────────────────────
wget -O $JS_FILE $JS_URL

# ─────────────────────────────
# Scripts auxiliares
# ─────────────────────────────

cat > start.sh <<'EOF'
#!/bin/bash
clear
echo "✅ Nexyra Link iniciado"
nohup node Completo.js > monitor.log 2>&1 &
echo $! > netpulse.pid
EOF

cat > stop.sh <<'EOF'
#!/bin/bash
if [ -f netpulse.pid ]; then
  kill $(cat netpulse.pid)
  rm netpulse.pid
  echo "⏹️ Nexyra Link parado"
else
  echo "⚠️ Não está rodando"
fi
EOF

cat > menu.sh <<'EOF'
#!/bin/bash

while true; do
  clear
  echo "🖥️ Nexyra Link / NetPulse Monitor"
  echo "────────────────────────────────"
  echo "1) ▶️ Iniciar monitor"
  echo "2) ⏹️ Parar monitor"
  echo "3) 📄 Ver logs"
  echo "4) 🚀 Ativar auto start (boot)"
  echo "5) ❌ Desativar auto start"
  echo "0) 🔚 Sair"
  echo
  read -p "Escolha: " opt

  case $opt in
    1) ./start.sh; sleep 2 ;;
    2) ./stop.sh; sleep 2 ;;
    3) tail -f monitor.log ;;
    4) systemctl enable netpulse && systemctl start netpulse; sleep 2 ;;
    5) systemctl stop netpulse && systemctl disable netpulse; sleep 2 ;;
    0) exit ;;
  esac
done
EOF

chmod +x *.sh

# ─────────────────────────────
# Service systemd
# ─────────────────────────────
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

# ─────────────────────────────
# Abrir menu ao entrar via SSH
# ─────────────────────────────
if ! grep -q "menu.sh" ~/.bashrc; then
  echo "cd $APP_DIR && ./menu.sh" >> ~/.bashrc
fi

echo "✅ Instalação concluída!"
echo "🔁 Reconecte via SSH para abrir o menu automaticamente"
