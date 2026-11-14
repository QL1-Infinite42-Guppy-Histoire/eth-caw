#!/usr/bin/env bash
# CAW node — ONE-TOUCH installer (mainnet, community deployment).
#
# What this does, in one run, on a fresh Ubuntu 24.04 VPS:
#   1. Installs Node.js 22, PostgreSQL, Redis, cloudflared, a firewall.
#   2. Creates the node database with a generated password.
#   3. Downloads the open-source CAW node code and configures it for THIS
#      deployment (contract addresses are in the code's mainnet preset).
#   4. Starts the node as a system service and opens a public HTTPS URL
#      through a Cloudflare quick tunnel.
#   5. Writes your public node URL to /opt/caw/node-url.txt
#
# How to run it (either way works):
#   A) Paste this whole script into your VPS provider's "startup script"
#      field when you create the server (e.g. ConoHa). Nothing else to do.
#   B) On an existing server, as root:
#        curl -fsSL https://ql1-infinite42-guppy-histoire.github.io/eth-caw/node-kit/install-node.sh | bash
#
# The node starts READ-ONLY (timeline serving). No wallet key is involved.
# Becoming a validator (submitting posts) is an optional later step that
# uses YOUR OWN key, placed by you on YOUR server only. See GUIDE.md.
#
# Run as root. Re-running is safe for kit-managed files (they are
# refreshed); any OTHER local change in the source checkout stops the
# installer for operator review instead of being overwritten.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# BEGIN reviewed-source selection (also exercised by the offline regression)
# Adapted from PR #2 (Xubu-Trad) with two kit-specific changes, both
# documented in GUIDE.md: (1) when CAW_SOURCE_COMMIT is entirely unset,
# the kit's reviewed default pin below is used, so the one-touch flow
# still works — set the variable (even empty) to override/stop;
# (2) the dirty-checkout refusal is scoped: the two deployment address
# files this kit itself overwrites on every run, plus the kit-generated
# client/config.json, are allowed to differ; anything else still stops.
CAW_KIT_DEFAULT_SOURCE_COMMIT=97cd13f3a1423f702d411472fdd2b2a2e7bfbd59
caw_require_source_selection() {
  CAW_SOURCE_COMMIT=${CAW_SOURCE_COMMIT-$CAW_KIT_DEFAULT_SOURCE_COMMIT}
  if [[ ! $CAW_SOURCE_COMMIT =~ ^[0-9a-f]{40}$ ]]; then
    echo "STOP: set CAW_SOURCE_COMMIT to the full lowercase 40-character commit you reviewed." >&2
    return 1
  fi
  CAW_SOURCE_REPO=${CAW_SOURCE_REPO:-https://github.com/GilgameshCaw/Caw}
}

caw_select_source() {
  local target=$1 actual status unexpected
  caw_require_source_selection || return 1
  if [[ -e "$target" ]]; then
    [[ -d "$target/.git" ]] || { echo "STOP: source directory is not a checkout" >&2; return 1; }
    status=$(git -C "$target" status --porcelain --untracked-files=all) || return 1
    # Kit-managed paths may differ: the deployment address overlay (the
    # installer rewrites both files from the published kit copies below)
    # and the generated client/config.json. Anything else is operator
    # work the installer must not overwrite.
    unexpected=$(printf '%s\n' "$status" | grep -v '^$' \
      | grep -v ' client/src/abi/addresses.ts$' \
      | grep -v ' client/src/abi/deployments.ts$' \
      | grep -v ' client/config.json$' || true)
    [[ -z "$unexpected" ]] || {
      echo "STOP: existing source has local files or changes outside the kit-managed overlay:" >&2
      printf '%s\n' "$unexpected" >&2
      echo "Preserve them and use a reviewed clean checkout." >&2
      return 1
    }
  else
    git init "$target" || return 1
  fi
  # Fetch exactly the selected object. Never fall back to a branch or stale HEAD.
  git -C "$target" fetch --no-tags --depth 1 "$CAW_SOURCE_REPO" "$CAW_SOURCE_COMMIT" || return 1
  actual=$(git -C "$target" rev-parse 'FETCH_HEAD^{commit}') || return 1
  [[ "$actual" == "$CAW_SOURCE_COMMIT" ]] || { echo "STOP: fetched commit mismatch" >&2; return 1; }
  git -C "$target" checkout --detach "$CAW_SOURCE_COMMIT" || return 1
  [[ $(git -C "$target" rev-parse HEAD) == "$CAW_SOURCE_COMMIT" ]] || return 1
  [[ -f "$target/client/package.json" ]] || { echo "STOP: selected source has no client/package.json" >&2; return 1; }
}
# END reviewed-source selection

# Fail before installing packages or changing system configuration.
caw_require_source_selection

echo "=== CAW node one-touch installer ==="

# ---------- 1. Packages ----------
apt-get update -y
apt-get install -y curl git ufw postgresql redis-server build-essential python3 openssl

if ! command -v node >/dev/null || [ "$(node -v | cut -d. -f1)" != "v22" ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

if ! command -v cloudflared >/dev/null; then
  case "$(uname -m)" in
    aarch64|arm64) CF_ARCH=arm64 ;;
    *) CF_ARCH=amd64 ;;
  esac
  curl -fsSL -o /usr/local/bin/cloudflared \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CF_ARCH"
  chmod +x /usr/local/bin/cloudflared
fi

systemctl enable --now postgresql redis-server

# Firewall: SSH only. The API stays on localhost, exposed via the tunnel.
ufw allow 22/tcp
ufw --force enable

# ---------- 2. Database ----------
if [ ! -f /root/.caw-db-pass ]; then
  openssl rand -hex 16 > /root/.caw-db-pass
  chmod 600 /root/.caw-db-pass
fi
DBPASS=$(cat /root/.caw-db-pass)
su postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='caw'\"" | grep -q 1 || \
  su postgres -c "psql -c \"CREATE USER caw WITH PASSWORD '$DBPASS'\""
su postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='caw_mainnet'\"" | grep -q 1 || \
  su postgres -c "createdb -O caw caw_mainnet"

# ---------- 3. Node code + config ----------
mkdir -p /opt/caw
caw_select_source /opt/caw/Caw

# Point the node at THIS deployment: the upstream repository carries its own
# testnet addresses, so overwrite the two generated address files with the
# ones resolved for this community deployment (published in the node kit).
KIT=https://ql1-infinite42-guppy-histoire.github.io/eth-caw/node-kit
curl -fsSL "$KIT/abi/addresses.ts"   -o /opt/caw/Caw/client/src/abi/addresses.ts
curl -fsSL "$KIT/abi/deployments.ts" -o /opt/caw/Caw/client/src/abi/deployments.ts

cd /opt/caw/Caw/client
if [ ! -f .env ]; then
  cat > .env <<EOF
DATABASE_URL=postgresql://caw:$DBPASS@127.0.0.1:5432/caw_mainnet
L1_RPC_URL=wss://ethereum-rpc.publicnode.com
L1_RPC_URL_HTTP=https://ethereum-rpc.publicnode.com
L2_RPC_URL=wss://mainnet.base.org
L2_RPC_URL_HTTP=https://mainnet.base.org
ETH_MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com
VALIDATOR_PRIVATE_KEY=
SPONSOR_ENABLED=0
ZK_PROVER_ENABLED=0
L1_CHAIN_ID=1
L2_CHAIN_ID=8453
COOKIE_SECURE=false
PRISMA_QUERY_ENGINE_TYPE=binary
MEDIA_STORAGE_BACKEND=local
NETWORK_ID=1
INSTANCE_API_URL=http://127.0.0.1:4000
ALLOWED_ORIGINS=https://ql1-infinite42-guppy-histoire.github.io
EOF
fi
chmod 600 .env
grep -q '^JWT_SECRET=' .env || echo "JWT_SECRET=$(openssl rand -hex 32)" >> .env
# Browser frontends (the community web viewer and other Pages-hosted
# frontends) are rejected by the node's CORS allow-list unless their
# origin is listed. Add the community Pages origin on re-runs too.
grep -q '^ALLOWED_ORIGINS=' .env || echo "ALLOWED_ORIGINS=https://ql1-infinite42-guppy-histoire.github.io" >> .env

# The node app refuses to start without config.json (programs/start.ts exits
# with "config.json not found; copy from template"). Build it from the
# upstream template with THIS deployment's mainnet values: the template
# itself carries testnet chain ids (84532 / 11155111) and ${ENV} placeholders
# that are NOT expanded at load time, so literal values are required.
if [ ! -f config.json ]; then
  python3 - <<'PYEOF'
import json
cfg = json.load(open('config.template.json'))
L1 = "https://ethereum-rpc.publicnode.com"
L2 = "https://mainnet.base.org"
for e in cfg:
    s, c = e["service"], e["config"]
    if s == "Api":
        # The Api service copies config.allowedOrigins into
        # process.env.ALLOWED_ORIGINS at startup (overwriting any env
        # value), and the API's CORS allow-list is built from that.
        # The template ships only http://localhost:5274, which makes
        # every browser frontend unreadable. Add the community Pages
        # origin so the read-only web viewer works out of the box.
        origins = c.get("allowedOrigins", [])
        if "https://ql1-infinite42-guppy-histoire.github.io" not in origins:
            origins.append("https://ql1-infinite42-guppy-histoire.github.io")
        c["allowedOrigins"] = origins
    if s == "Validator": c["l2RpcUrl"] = L2
    if s == "RawEventsGatherer": c.update(chainId=8453, rpcUrl=L2)
    if s == "ChainSyncService": c.update(l1RpcUrl=L1, ethMainnetRpcUrl=L1)
    if s in ("NftTransferWatcher", "DepositWatcher"): c.update(l1RpcUrl=L1, chainId=1)
json.dump(cfg, open('config.json', 'w'), indent=2)
print("config.json written (mainnet)")
PYEOF
fi

npm install --no-audit --no-fund
set -a; . ./.env; set +a
npx prisma db push --skip-generate
node ../cli/scripts/ensure-manual-sql-cli.js || true

# ---------- 3b. Client patches for THIS deployment (disclosed) ----------
# The contracts are untouched. The upstream NODE CLIENT, however, is
# testnet-hardcoded in its validator submit path and cannot submit a
# single mainnet transaction unmodified (the Base RPC rejects its
# transactions with "invalid chain ID"). The patches below are the
# minimum client-side fixes, applied loudly and fail-closed: if the
# pinned source does not contain the exact expected patterns, the
# installer STOPS for manual review rather than guessing. Both patches
# are also documented in GUIDE.md.
VS=src/services/ValidatorService/index.ts
[ -f "$VS" ] || { echo "STOP: $VS not found in the selected source." >&2; exit 1; }
[ -f /opt/caw/ValidatorService.index.ts.orig ] || cp "$VS" /opt/caw/ValidatorService.index.ts.orig

count() { grep -o -F "$1" "$VS" | wc -l; }

# Patch 1 (always): validator chain id 84532 (Base Sepolia) -> 8453 (Base).
# Sites patched: 2x fallback provider, 1x websocket provider, 1x cached
# chain id, 1x replication provider, 2x standalone chainId properties.
# The BASE_SEPOLIA_CHAIN_ID constant and the 'base-sepolia' metadata-map
# entry (an inline "{ chainId: 84532, env: 'testnet', ... }" row that
# DESCRIBES Sepolia) are deliberately NOT touched — hence the anchored
# pattern, which matches only lines consisting of the property alone.
count_prop() { grep -c -E '^[[:space:]]*chainId: 84532,$' "$VS"; }
count_prop_new() { grep -c -E '^[[:space:]]*chainId: 8453,$' "$VS"; }
if [ "$(count 'makeFallbackJsonRpcProvider(l2HttpRpcUrls, 8453)')" = 2 ] && [ "$(count_prop_new)" = 2 ]; then
  echo "client patch 1 (validator chain id) already applied — skipping"
else
  [ "$(count 'makeFallbackJsonRpcProvider(l2HttpRpcUrls, 84532)')" = 2 ] && \
  [ "$(count 'makeWebSocketProvider(l2RpcUrl, 84532')" = 1 ] && \
  [ "$(count '_cachedChainId = 84532')" = 1 ] && \
  [ "$(count 'makeJsonRpcProvider(replicationHttpRpcUrl, 84532)')" = 1 ] && \
  [ "$(count_prop)" = 2 ] || {
    echo "STOP: validator source does not match the expected testnet patterns;" >&2
    echo "the upstream client changed — review src/services/ValidatorService/index.ts manually." >&2
    exit 1
  }
  sed -i \
    -e 's/makeFallbackJsonRpcProvider(l2HttpRpcUrls, 84532)/makeFallbackJsonRpcProvider(l2HttpRpcUrls, 8453)/g' \
    -e 's/makeWebSocketProvider(l2RpcUrl, 84532/makeWebSocketProvider(l2RpcUrl, 8453/g' \
    -e 's/_cachedChainId = 84532/_cachedChainId = 8453/' \
    -e 's/makeJsonRpcProvider(replicationHttpRpcUrl, 84532)/makeJsonRpcProvider(replicationHttpRpcUrl, 8453)/' \
    -e 's/^\([[:space:]]*\)chainId: 84532,/\1chainId: 8453,/' \
    "$VS"
  [ "$(count 'makeFallbackJsonRpcProvider(l2HttpRpcUrls, 8453)')" = 2 ] && [ "$(count_prop_new)" = 2 ] || {
    echo "STOP: chain-id patch did not land as expected; review $VS manually." >&2
    exit 1
  }
  echo "client patch 1 applied: validator chain id 84532 -> 8453 (mainnet fix)"
fi

# Patch 2 (OPT-IN, default OFF): subsidy mode. The protocol's default
# tip (1,000 CAW per action, paid by the poster) is worth about
# 0.001 JPY at the CAW price observed on 2026-11-12, while one delivery
# costs about 0.36 JPY in Base gas + LayerZero fees — the break-even
# tip is roughly 170,000 CAW. With the upstream tip check left ON
# (default), this node's validator will decline almost every real
# submission, exactly as designed upstream. Setting CAW_NODE_SUBSIDY=1
# disables that one check on THIS node only: the node then delivers
# posts at the operator's small expense. Posters still pay the full
# protocol amounts (action cost + tip), enforced by the contracts.
# Other nodes are unaffected and remain free to decline.
if [ "${CAW_NODE_SUBSIDY:-0}" = "1" ]; then
  if grep -q 'if (false) {' "$VS"; then
    echo "client patch 2 (subsidy mode) already applied — skipping"
  else
    [ "$(count 'if (tipInWei < effectiveGasCost) {')" = 1 ] || {
      echo "STOP: tip-check pattern not found exactly once; review the validator source manually." >&2
      exit 1
    }
    sed -i 's/if (tipInWei < effectiveGasCost) {/if (false) {/' "$VS"
    echo "client patch 2 applied: SUBSIDY MODE — this node delivers posts even when the tip"
    echo "is below delivery cost (about 0.36 JPY per post at 2026-11-12 prices)."
  fi
  printf 'subsidy-mode enabled %s\n' "$(date -u +%FT%TZ)" > /opt/caw/SUBSIDY_MODE
else
  rm -f /opt/caw/SUBSIDY_MODE
  echo "subsidy mode OFF (default): the validator keeps the upstream tip check."
  echo "At current prices the default 1,000 CAW tip is below delivery cost, so this"
  echo "node will mostly serve reads. See GUIDE.md (subsidy mode) to change that."
fi

# ---------- 4. Services ----------
cat > /etc/systemd/system/caw-node.service <<'EOF'
[Unit]
Description=CAW node (mainnet)
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/caw/Caw/client
EnvironmentFile=/opt/caw/Caw/client/.env
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

# Helper that keeps the current public tunnel URL in /opt/caw/node-url.txt
cat > /usr/local/bin/caw-node-url <<'EOF'
#!/usr/bin/env bash
for i in $(seq 1 30); do
  URL=$(journalctl -u caw-tunnel -n 200 --no-pager 2>/dev/null | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1 || true)
  if [ -n "$URL" ]; then echo "$URL" > /opt/caw/node-url.txt; echo "$URL"; exit 0; fi
  sleep 2
done
echo "tunnel URL not found yet — check: journalctl -u caw-tunnel -n 100" >&2
exit 1
EOF
chmod +x /usr/local/bin/caw-node-url

# Registry announcer: publishes this node's URL to the public node
# directory, so the app can find and connect to it automatically.
cat > /usr/local/bin/caw-announce <<'EOF'
#!/usr/bin/env bash
URL=$(caw-node-url || true)
[ -n "$URL" ] || exit 1
curl -fsSL -X POST https://eth-caw-registry.nepicobsv.workers.dev/announce \
  -H 'content-type: application/json' \
  -d "{\"url\":\"$URL\",\"preset\":\"mainnet\"}" >/dev/null || true
EOF
chmod +x /usr/local/bin/caw-announce

# Operator doctor: a read-first diagnostic for this node (queue state,
# validator balance, on-chain cawonce) with a guarded fix for the two
# known delivery problems — a stuck 'processing' row and failed rows
# that block a poster's cawonce. It runs entirely on this server.
# Kit-managed file: refreshed on every installer run.
curl -fsSL "$KIT/caw-doctor.sh" -o /usr/local/bin/caw-doctor
chmod +x /usr/local/bin/caw-doctor

cat > /etc/systemd/system/caw-announce.service <<'EOF'
[Unit]
Description=Announce this CAW node to the public registry
After=network.target caw-tunnel.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/caw-announce
EOF

cat > /etc/systemd/system/caw-announce.timer <<'EOF'
[Unit]
Description=Re-announce the CAW node regularly

[Timer]
OnBootSec=3min
OnUnitActiveSec=6h

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now caw-node.service
sleep 5
systemctl enable --now caw-tunnel.service
sleep 8
caw-node-url || true
systemctl enable --now caw-announce.timer
caw-announce || true

echo ""
echo "=== Done. Your CAW node is starting. ==="
echo "Public node URL:  $(cat /opt/caw/node-url.txt 2>/dev/null || echo '(see below)')"
echo "  - Re-print it any time:  caw-node-url"
echo "  - Node logs:             journalctl -u caw-node -f"
echo "  - Node health check:     caw-doctor status   (problems: caw-doctor check)"
echo "Your node also announces itself to the public node directory, so the"
echo "CAW (Ethereum Edition) app can find it on its own. To pin the app to"
echo "YOUR node specifically, paste the URL under the Node tab in the app."
echo "Note: the first chain sync can take a while on public RPCs."
echo ""
echo "Your node starts READ-ONLY: it serves timelines but cannot DELIVER"
echo "posts until it has a validator wallet of its own. When you are ready:"
echo "  1. Download make-validator-wallet.sh from the node kit (same site"
echo "     as this installer) and run it ON THIS SERVER as root:"
echo "       bash make-validator-wallet.sh <your CAW name number>"
echo "     It generates the wallet on this server only (the key never"
echo "     leaves it, and is never printed) and shows the address to fund."
echo "  2. Send a small amount of ETH on Base (about 0.005 ETH is plenty)"
echo "     to that address, then:  systemctl restart caw-node"
