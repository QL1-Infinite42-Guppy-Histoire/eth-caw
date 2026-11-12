#!/usr/bin/env bash
# CAW node — create the validator (delivery) wallet ON this server.
#
# A fresh node is read-only: it serves timelines, but it cannot submit
# ("deliver") signed posts to Base until it has its own validator
# wallet holding a little Base ETH for gas. This script:
#   1. Generates a brand-new wallet ON THIS SERVER. The private key is
#      written straight into the node's .env file. It is NEVER printed,
#      NEVER leaves this server, and must never be sent to anyone.
#   2. Points the validator at YOUR CAW name, so the delivery tips
#      (CAW) that posters pay are credited to your name's balance.
#   3. Prints ONLY the public address, so you know where to send gas.
#
# Usage (as root, after install-node.sh has completed):
#   bash make-validator-wallet.sh <your CAW name number>
# The name number is the token id of your name (e.g. @guppy is 3).
# If you omit it, the number already in config.json is kept.
#
# The wallet is gas-only. Keep the amount small: if this server is
# lost, whatever ETH remains in the wallet is lost with it.
set -euo pipefail

CLIENT=/opt/caw/Caw/client
ENV_FILE="$CLIENT/.env"
CONFIG="$CLIENT/config.json"

[ "$(id -u)" = 0 ] || { echo "Run as root." >&2; exit 1; }
[ -f "$ENV_FILE" ] || { echo "STOP: $ENV_FILE not found — run install-node.sh first." >&2; exit 1; }
[ -d "$CLIENT/node_modules/ethers" ] || { echo "STOP: node dependencies not installed — run install-node.sh first." >&2; exit 1; }

NAME_ID="${1:-}"
if [ -n "$NAME_ID" ] && ! [[ "$NAME_ID" =~ ^[0-9]+$ ]]; then
  echo "STOP: the name number must be a plain number (your name's token id)." >&2
  exit 1
fi

if grep -q '^VALIDATOR_PRIVATE_KEY=0x[0-9a-fA-F]\{64\}$' "$ENV_FILE"; then
  EXISTING_KEY=$(grep '^VALIDATOR_PRIVATE_KEY=' "$ENV_FILE" | cut -d= -f2)
  ADDR=$(cd "$CLIENT" && VALIDATOR_PRIVATE_KEY="$EXISTING_KEY" node -e '
    const { ethers } = require("ethers");
    console.log(new ethers.Wallet(process.env.VALIDATOR_PRIVATE_KEY).address);')
  echo "A validator wallet is already set on this server: $ADDR"
  echo "Nothing changed. Fund that address with a little Base ETH if it is empty."
  exit 0
fi

# Generate the wallet; write the key directly into .env. Only the
# public address is printed.
ADDR=$(cd "$CLIENT" && node -e '
  const fs = require("fs");
  const { ethers } = require("ethers");
  const w = ethers.Wallet.createRandom();
  const envPath = ".env";
  let env = fs.readFileSync(envPath, "utf8");
  if (/^VALIDATOR_PRIVATE_KEY=.*$/m.test(env)) {
    env = env.replace(/^VALIDATOR_PRIVATE_KEY=.*$/m, "VALIDATOR_PRIVATE_KEY=" + w.privateKey);
  } else {
    env += "\nVALIDATOR_PRIVATE_KEY=" + w.privateKey + "\n";
  }
  fs.writeFileSync(envPath, env, { mode: 0o600 });
  console.log(w.address);')
chmod 600 "$ENV_FILE"

# Point the validator at the operator's own name (tips credit there).
if [ -n "$NAME_ID" ] && [ -f "$CONFIG" ]; then
  python3 - "$CONFIG" "$NAME_ID" <<'PYEOF'
import json, sys
path, name_id = sys.argv[1], int(sys.argv[2])
cfg = json.load(open(path))
for e in cfg:
    if e.get("service") == "Validator":
        e["config"]["validatorId"] = name_id
json.dump(cfg, open(path, "w"), indent=2)
print(f"validator name number set to {name_id}")
PYEOF
fi

echo ""
echo "Validator wallet created ON THIS SERVER."
echo "Public address (safe to share): $ADDR"
echo ""
echo "Next steps:"
echo "  1. Send a small amount of ETH ON BASE to $ADDR"
echo "     (about 0.005 ETH — roughly 1,500 JPY — covers hundreds of posts;"
echo "      this wallet is gas-only, so never send more than you can lose)"
echo "  2. Restart the node:  systemctl restart caw-node"
echo "  3. From then on, this node can deliver signed posts to the chain."
echo ""
echo "The private key is only in $ENV_FILE on this server. It was never"
echo "printed. Do not open that file on camera or send it to anyone."
