#!/bin/sh
# Certbot runs this after it gets or renews a certificate. It hands the new
# certificate to the Akira server (which can't read /etc/letsencrypt itself) and
# restarts the server so it starts using it. A restart drops any match in
# progress, which happens about every two months, so it's best to renew when
# the room is empty (certbot renews roughly 30 days before expiry, at any hour).
#
# Install:  sudo install -m 755 renew-hook.sh /etc/letsencrypt/renewal-hooks/deploy/akira.sh
set -e
LINEAGE="${RENEWED_LINEAGE:?run by certbot, or set RENEWED_LINEAGE=/etc/letsencrypt/live/<your domain>}"
install -d -o akira -g akira -m 750 /etc/akira/certs
install -o akira -g akira -m 640 "$LINEAGE/fullchain.pem" /etc/akira/certs/fullchain.pem
install -o akira -g akira -m 640 "$LINEAGE/privkey.pem" /etc/akira/certs/privkey.pem
systemctl restart akira-server
