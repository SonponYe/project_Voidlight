#!/usr/bin/env bash
# One-time setup of the Akira game server on an Ubuntu machine (Oracle Cloud).
#
#   1. copy this file, akira-server.service and the server build to the machine
#   2. bash setup_server.sh                 (opens 9040 and the room ports 9100-9105)
#      bash setup_server.sh 9040 9100:9105 443 80   (your own list, e.g. for TLS)
#
# It is safe to run again. It makes an unprivileged "akira" user, installs the
# server as a service that starts at boot and restarts if it crashes, and opens
# the machine's own firewall (Oracle's Ubuntu images block everything but SSH by
# default, on top of the cloud network rules you set in Oracle's web console).
set -euo pipefail

cd "$(dirname "$0")"
if [ $# -gt 0 ]; then PORTS=("$@"); else PORTS=(9040 9100:9105); fi

# The server build: akira_server.arm64 (Oracle's free ARM machines) or .x86_64.
case "$(uname -m)" in
  aarch64) BUILD=akira_server.arm64 ;;
  x86_64) BUILD=akira_server.x86_64 ;;
  *) echo "Unknown CPU type $(uname -m)"; exit 1 ;;
esac
if [ ! -f "$BUILD" ]; then
  echo "Missing $BUILD next to this script. Copy the server build for this CPU here first."
  exit 1
fi

id akira >/dev/null 2>&1 || sudo useradd --system --home-dir /opt/akira --shell /usr/sbin/nologin akira
sudo mkdir -p /opt/akira /etc/akira
sudo chown akira:akira /opt/akira
sudo install -m 755 "$BUILD" /opt/akira/akira_server
if [ ! -f /etc/akira/server.env ]; then
  # Every room is its own copy of the game (~100 MB): fewer on a small machine.
  MAX_ROOMS=6
  if [ "$(free -m | awk '/^Mem:/{print $2}')" -lt 2000 ]; then MAX_ROOMS=3; fi
  echo "AKIRA_ARGS=\"--port=9040 --room-port-base=9100 --max-rooms=$MAX_ROOMS\"" | sudo tee /etc/akira/server.env >/dev/null
fi
sudo install -m 644 akira-server.service /etc/systemd/system/akira-server.service

for port in "${PORTS[@]}"; do
  if ! sudo iptables -C INPUT -m state --state NEW -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
    sudo iptables -I INPUT 1 -m state --state NEW -p tcp --dport "$port" -j ACCEPT
  fi
done
if command -v netfilter-persistent >/dev/null 2>&1; then
  sudo netfilter-persistent save
else
  echo "Note: install iptables-persistent (sudo apt install iptables-persistent) or the firewall rule is lost on reboot."
fi

sudo systemctl daemon-reload
sudo systemctl enable akira-server
sudo systemctl restart akira-server
sleep 2
systemctl --no-pager --lines=8 status akira-server || true
echo
echo "Done. Watch it live with:  journalctl -u akira-server -f"
