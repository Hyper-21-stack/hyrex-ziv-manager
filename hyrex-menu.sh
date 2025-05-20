#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/hyrex-ziv"
USERS_FILE="$INSTALL_DIR/users.json"
CONFIG_FILE="$INSTALL_DIR/config.json"
SERVICE_NAME="hyrex-ziv"

[ -f "$USERS_FILE" ] || echo "{}" > "$USERS_FILE"

update_config() {
  userpass_json=$(jq 'to_entries|map({key:.key,value:.value.password})|from_entries' "$USERS_FILE")
  cat > "$CONFIG_FILE" <<C
{
  "listen": ":443",
  "disableTLS": true,
  "auth": {
    "type": "userpass",
    "userpass": $userpass_json
  }
}
C
}

restart_service() {
  echo "Restarting $SERVICE_NAME..."
  systemctl restart "$SERVICE_NAME"
  echo "Done."
}

add_user() {
  read -p "Username: " u
  [ -n "$u" ] || { echo "Empty username."; return; }
  if jq -e --arg U "$u" 'has($U)' "$USERS_FILE" >/dev/null; then
    echo "User exists."; return
  fi
  read -p "Password (blank=generate): " p
  [ -n "$p" ] || p=$(head /dev/urandom|tr -dc A-Za-z0-9|head -c16)
  echo "Password: $p"
  read -p "Expires in days: " d
  [[ "$d" =~ ^[0-9]+$ ]] || { echo "Invalid."; return; }
  e=$(date -d "+$d days" +"%F")
  tmp=$(mktemp)
  jq --arg U "$u" --arg P "$p" --arg E "$e" \
    '. + {($U):{password:$P,expiry:$E}}' "$USERS_FILE" > "$tmp" && mv "$tmp" "$USERS_FILE"
  echo "Added $u, expires $e."
  update_config; restart_service
}

list_users() {
  echo "Users (expiry):"
  today=$(date +"%F")
  jq -r 'to_entries[]|"\(.key)\t\(.value.expiry)"' "$USERS_FILE" | \
    while IFS=$'\t' read -r U E; do
      [[ "$E" < "$today" ]] && echo "$U  $E  (EXPIRED)" || echo "$U  $E"
    done
}

purge_expired() {
  echo "Purging expired..."
  today=$(date +"%F")
  tmp=$(mktemp)
  jq --arg T "$today" 'to_entries|map(select(.value.expiry>$T))|from_entries' \
    "$USERS_FILE" > "$tmp" && mv "$tmp" "$USERS_FILE"
  update_config; restart_service
}

backup_users() {
  ts=$(date +"%Y%m%d%H%M%S")
  cp "$USERS_FILE" "${USERS_FILE%.json}-$ts.json"
  echo "Backup saved."
}

uninstall() {
  read -p "Uninstall HYREX ZIV? (yes/NO): " a
  [[ "$a" == "yes" ]] || { echo "Canceled."; return; }
  systemctl stop "$SERVICE_NAME"
  systemctl disable "$SERVICE_NAME"
  rm -rf "$INSTALL_DIR" "/etc/systemd/system/$SERVICE_NAME.service"
  rm -f /usr/local/bin/hyrex-ziv
  systemctl daemon-reload
  echo "Uninstalled."
  exit
}

while true; do
  echo; echo "HYREX ZIV Menu"
  echo "1) Add user"; echo "2) List users"; echo "3) Purge expired"
  echo "4) Backup users"; echo "5) Restart service"; echo "6) Uninstall"; echo "7) Exit"
  read -p "Choose [1-7]: " o
  case $o in
    1) add_user ;; 2) list_users ;; 3) purge_expired
    4) backup_users ;; 5) restart_service ;; 6) uninstall
    7) break ;; *) echo "Invalid." ;;
  esac
done
