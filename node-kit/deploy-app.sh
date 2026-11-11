#!/usr/bin/env bash
# Deploy the CAW node app onto your provisioned server and run it as a
# systemd service, with a cloudflared quick tunnel for the public URL.
#
# Before running:
#   - Run setup.sh first (installs Node.js 22 / PostgreSQL / Redis).
#   - Place the node code (the Caw repository's client/) at /opt/caw/Caw
#   - Place env.template filled in as /opt/caw/Caw/client/.env
#     (DATABASE_URL password = the one in /root/.caw-db-pass)
#   - Validator only: your OWN wallet key file at
#     /opt/caw/secrets/validator.json  ({"privateKey": "0x..."})
#     Keep it on your server only. Never send it to anyone.
# Run as root on YOUR server.
set -euo pipefail

APP=/opt/caw/Caw/client
cd "$APP"

# If a validator key file exists, inject it into .env.
if [ -f /opt/caw/secrets/validator.json ]; then
  VALKEY=$(python3 -c "import json;print(json.load(open('/opt/caw/secrets/validator.json'))['privateKey'])")
  grep -q '^VALIDATOR_PRIVATE_KEY=' .env \
    && sed -i "s|^VALIDATOR_PRIVATE_KEY=.*|VALIDATOR_PRIVATE_KEY=$VALKEY|" .env \
    || echo "VALIDATOR_PRIVATE_KEY=$VALKEY" >> .env
fi
chmod 600 .env

npm install --no-audit --no-fund
set -a; . ./.env; set +a
npx prisma db push --skip-generate
node ../cli/scripts/ensure-manual-sql-cli.js || true

cat > /etc/systemd/system/caw-node.service <<'EOF'
[Unit]
Description=CAW node (mainnet)
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/caw/Caw/client
ExecStart=/usr/bin/node -r ./file-polyfill.js -r tsx/cjs programs/start.ts
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/caw-tunnel.service <<'EOF'
[Unit]
Description=Cloudflare quick tunnel for the CAW node API
After=network.target caw-node.service

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --url http://127.0.0.1:4000 --no-autoupdate
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now caw-node.service
sleep 5
systemctl enable --now caw-tunnel.service

echo "--- node status:"; systemctl --no-pager -n 3 status caw-node.service | head -5
echo "--- your public tunnel URL (wait a few seconds, then run):"
echo "journalctl -u caw-tunnel -n 50 --no-pager | grep -o 'https://[a-z0-9-]*\\.trycloudflare\\.com' | tail -1"
