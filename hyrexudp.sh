#!/usr/bin/env bash
set -euo pipefail
echo "Starting HYREX ZIV installation..."
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Must run as root." >&2
  exit 1
fi
apt-get update -y && apt-get install -y curl jq
INSTALL_DIR="/opt/hyrex-ziv"
mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"
HYSTERIA_URL=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest \
  | jq -r '.assets[]|select(.name|test("hysteria-linux-amd64"))|.browser_download_url')
curl -L "$HYSTERIA_URL" -o hysteria && chmod +x hysteria
echo "{}" > users.json
cat > config.json <<CONFIG
{
  "listen": ":443",
  "disableTLS": true,
  "auth": { "type": "userpass", "userpass": {"admin":"changeme"} }
}
CONFIG
cat > /etc/systemd/system/hyrex-ziv.service <<SERVICE
[Unit]
Description=HYREX ZIV Hysteria UDP VPN Server
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/hysteria -c $INSTALL_DIR/config.json server
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
systemctl enable --now hyrex-ziv
curl -fsSL https://raw.githubusercontent.com/Hyper-21-stack/hyrex-ziv-manager/main/hyrex-menu.sh \
  -o /usr/local/bin/hyrex-ziv
chmod +x /usr/local/bin/hyrex-ziv
echo "HYREX ZIV installed! Run 'sudo hyrex-ziv' to manage."
