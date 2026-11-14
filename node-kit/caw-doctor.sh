#!/usr/bin/env bash
# caw-doctor — operations assistant for a CAW node (community deployment).
#
# Run it ON YOUR OWN server, as root. It talks only to your own node
# (localhost API + your own database) and to a public Base RPC for
# read-only chain checks. There is no central server and nothing is
# sent anywhere.
#
# Subcommands:
#   caw-doctor status           Read-only overview: node liveness, queue
#                               state, validator balance, on-chain cawonce.
#   caw-doctor check            Cron-friendly health check. Exit 0 = healthy.
#                               Exit 1 = warning (e.g. balance getting low).
#                               Exit 2 = a problem that needs attention.
#   caw-doctor unblock [--yes]  Release FAILED queue rows that block a
#                               poster's cawonce — only after an on-chain
#                               check proves each row is safe to remove.
#   caw-doctor restart [--yes]  Restart the node service and wait until
#                               the API answers again. (The documented
#                               first move when a post stops moving.)
#
# Safety rules:
#   - status / check never change anything.
#   - unblock deletes ONLY rows with status='failed', and only when the
#     on-chain nextCawonce for that sender proves the row can never be
#     delivered (see below). Pending / processing rows are never touched.
#   - unblock / restart ask for confirmation unless --yes is given.
#   - The validator private key is never printed, logged or transmitted.
#     If the wallet address is derived from it, that happens inside a
#     local node process that outputs only the public address (the same
#     pattern make-validator-wallet.sh uses).
#
# Configuration (environment variables, all optional):
#   CAW_CLIENT_DIR        default /opt/caw/Caw/client
#   CAW_API_URL           default http://127.0.0.1:4000
#   CAW_BASE_RPC          default: L2_RPC_URL_HTTP from the node .env,
#                         else https://mainnet.base.org
#   CAW_ACTIONS_ADDRESS   default 0xf4dFCf0EF472E8aaD3783479051f61EC574C6A8E
#                         (CawActions for THIS deployment, on Base)
#   CAW_VALIDATOR_ADDRESS the validator wallet address. Default: derived
#                         locally from the key in the node .env (address
#                         only). Set this to skip derivation.
#   CAW_DB_PASS_FILE      default /root/.caw-db-pass
#   CAW_STALL_MINUTES     a 'processing' row untouched for longer than
#                         this counts as stalled. Default 15.
#   CAW_WARN_WEI          balance warning threshold.  Default 500000000000000 (0.0005 ETH)
#   CAW_CRIT_WEI          balance critical threshold. Default 100000000000000 (0.0001 ETH)
#
# Context for the thresholds: one delivery batch cost about 1.2e-6 ETH
# in Base gas + LayerZero fees when measured in November 2026, so
# 0.0005 ETH still covers roughly 400 deliveries.
set -uo pipefail

CLIENT_DIR="${CAW_CLIENT_DIR:-/opt/caw/Caw/client}"
ENV_FILE="$CLIENT_DIR/.env"
CONFIG_FILE="$CLIENT_DIR/config.json"
API_URL="${CAW_API_URL:-http://127.0.0.1:4000}"
ACTIONS_ADDRESS="${CAW_ACTIONS_ADDRESS:-0xf4dFCf0EF472E8aaD3783479051f61EC574C6A8E}"
DB_PASS_FILE="${CAW_DB_PASS_FILE:-/root/.caw-db-pass}"
DB_NAME="${CAW_DB_NAME:-caw_mainnet}"
DB_USER="${CAW_DB_USER:-caw}"
DB_HOST="${CAW_DB_HOST:-127.0.0.1}"
STALL_MINUTES="${CAW_STALL_MINUTES:-15}"
WARN_WEI="${CAW_WARN_WEI:-500000000000000}"
CRIT_WEI="${CAW_CRIT_WEI:-100000000000000}"
ASSUME_YES=0

# ---------- small helpers ----------

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

# wei (decimal integer string) -> ETH with 6 decimal places, integer math.
wei_to_eth() {
  python3 - "$1" <<'PYEOF'
import sys
wei = int(sys.argv[1])
whole, frac = divmod(wei, 10**18)
print(f"{whole}.{frac:018d}"[:len(str(whole)) + 7])
PYEOF
}

# wei_lt A B -> true if A < B. Done in python3 because wei values can
# exceed bash's signed 64-bit integer range.
wei_lt() {
  python3 -c 'import sys; sys.exit(0 if int(sys.argv[1]) < int(sys.argv[2]) else 1)' "$1" "$2"
}

# Base RPC URL: explicit env, else the node's own .env, else public default.
base_rpc() {
  if [ -n "${CAW_BASE_RPC:-}" ]; then printf '%s' "$CAW_BASE_RPC"; return; fi
  if [ -f "$ENV_FILE" ]; then
    local u
    u=$(grep '^L2_RPC_URL_HTTP=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)
    if [ -n "$u" ]; then printf '%s' "$u"; return; fi
  fi
  printf '%s' "https://mainnet.base.org"
}

# One JSON-RPC call. $1 = method, $2 = params JSON array.
# Prints the "result" field, or nothing on failure (and sets RPC_ERR).
RPC_ERR=""
rpc_result() {
  local method="$1" params="$2" out
  out=$(curl -s --max-time 20 -X POST "$(base_rpc)" \
        -H 'content-type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}" 2>/dev/null) || {
    RPC_ERR="RPC unreachable"; return 1; }
  if printf '%s' "$out" | jq -e '.error' >/dev/null 2>&1; then
    RPC_ERR=$(printf '%s' "$out" | jq -r '.error.message // "RPC error"')
    return 1
  fi
  printf '%s' "$out" | jq -r '.result // empty'
}

# On-chain nextCawonce for a sender (name token id). Prints a decimal.
chain_next_cawonce() {
  local sender="$1" data res
  is_uint "$sender" || return 1
  data=$(printf '0x492046f6%064x' "$sender")
  res=$(rpc_result eth_call "[{\"to\":\"$ACTIONS_ADDRESS\",\"data\":\"$data\"},\"latest\"]") || return 1
  [ -n "$res" ] || return 1
  python3 -c 'import sys; print(int(sys.argv[1], 16))' "$res"
}

# Validator wallet balance in wei (decimal). Prints nothing on failure.
chain_balance_wei() {
  local addr="$1" res
  res=$(rpc_result eth_getBalance "[\"$addr\",\"latest\"]") || return 1
  [ -n "$res" ] || return 1
  python3 -c 'import sys; print(int(sys.argv[1], 16))' "$res"
}

validator_id() {
  [ -f "$CONFIG_FILE" ] || return 1
  jq -r '.[] | select(.service=="Validator") | .config.validatorId // empty' "$CONFIG_FILE" 2>/dev/null | head -1
}

# Validator wallet address. NEVER prints or logs the private key:
# derivation happens inside a local node process that outputs only the
# address (same pattern as make-validator-wallet.sh).
validator_address() {
  if [ -n "${CAW_VALIDATOR_ADDRESS:-}" ]; then printf '%s' "$CAW_VALIDATOR_ADDRESS"; return 0; fi
  [ -f "$ENV_FILE" ] || return 1
  local key
  key=$(grep '^VALIDATOR_PRIVATE_KEY=0x[0-9a-fA-F]\{64\}$' "$ENV_FILE" | tail -1 | cut -d= -f2 || true)
  [ -n "$key" ] || return 1
  [ -d "$CLIENT_DIR/node_modules/ethers" ] || return 1
  ( cd "$CLIENT_DIR" && VALIDATOR_PRIVATE_KEY="$key" node -e '
      const { ethers } = require("ethers");
      process.stdout.write(new ethers.Wallet(process.env.VALIDATOR_PRIVATE_KEY).address);' 2>/dev/null )
}

# psql against the node's own database. Prints nothing and fails if the
# password file is not readable (e.g. not running as root).
DB_OK=0
db_sql() {
  local pass
  [ -r "$DB_PASS_FILE" ] || return 1
  pass=$(cat "$DB_PASS_FILE")
  PGPASSWORD="$pass" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" \
    -v ON_ERROR_STOP=1 -tA -F '|' -c "$1" 2>/dev/null
}

confirm() {
  # $1 = prompt. Returns 0 if approved.
  [ "$ASSUME_YES" = 1 ] && return 0
  local reply=""
  printf '%s [y/N] ' "$1"
  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    read -r reply < /dev/tty || return 1
  else
    read -r reply || return 1
  fi
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

api_health_ok() {
  local out
  out=$(curl -s --max-time 10 "$API_URL/api/health" 2>/dev/null) || return 1
  printf '%s' "$out" | jq -e '.status == "ok"' >/dev/null 2>&1
}

# ---------- status ----------

cmd_status() {
  say "== CAW node status =="

  if command -v systemctl >/dev/null 2>&1; then
    local svc
    svc=$(systemctl is-active caw-node 2>/dev/null || true)
    say "service caw-node: ${svc:-unknown}"
  fi

  if api_health_ok; then
    say "API ($API_URL): ok"
  else
    say "API ($API_URL): NOT answering /api/health"
  fi

  local inst nid
  inst=$(curl -s --max-time 10 "$API_URL/api/instances" 2>/dev/null || true)
  nid=$(printf '%s' "$inst" | jq -r '.networkId // empty' 2>/dev/null || true)
  if [ -n "$nid" ]; then
    say "network id (from /api/instances): $nid"
  else
    say "network id: unavailable (/api/instances did not answer cleanly)"
  fi

  local vid
  vid=$(validator_id || true)
  if is_uint "${vid:-}"; then say "validator name number (config.json): $vid"; else vid=""; say "validator name number: not found in config.json"; fi

  say ""
  say "-- delivery queue (TxQueue) --"
  if db_sql 'SELECT 1' >/dev/null 2>&1; then
    DB_OK=1
    local rows
    rows=$(db_sql 'SELECT status, COUNT(*) FROM "TxQueue" GROUP BY status ORDER BY status')
    if [ -n "$rows" ]; then
      printf '%s\n' "$rows" | while IFS='|' read -r st cnt; do say "  $st: $cnt"; done
    else
      say "  (queue is empty)"
    fi
    local oldest
    oldest=$(db_sql 'SELECT COALESCE(ROUND(EXTRACT(EPOCH FROM (now() - MIN("createdAt"))) / 60)::int, -1) FROM "TxQueue" WHERE status = '"'"'processing'"'"'')
    if is_uint "${oldest:-}" && [ "$oldest" -ge 0 ]; then
      say "  oldest 'processing' row: ${oldest} min old"
    fi
    local failed_n
    failed_n=$(db_sql 'SELECT COUNT(*) FROM "TxQueue" WHERE status = '"'"'failed'"'"'')
    if is_uint "${failed_n:-}" && [ "$failed_n" -gt 0 ]; then
      say "  NOTE: $failed_n failed row(s) — each one blocks its cawonce for new posts."
      say "        Run 'caw-doctor unblock' to review them."
    fi
  else
    say "  (skipped: cannot read the database — run as root so $DB_PASS_FILE is readable)"
  fi

  say ""
  say "-- validator wallet (Base) --"
  local addr bal next
  addr=$(validator_address || true)
  if [ -n "$addr" ]; then
    say "address: $addr"
    bal=$(chain_balance_wei "$addr" || true)
    if is_uint "${bal:-}"; then
      say "balance: $(wei_to_eth "$bal") ETH"
    else
      say "balance: could not read (${RPC_ERR:-RPC error})"
    fi
  else
    say "address: not set (no validator key in .env, and CAW_VALIDATOR_ADDRESS not given)"
    say "         → this node can read and serve, but cannot deliver posts."
  fi
  if [ -n "$vid" ]; then
    next=$(chain_next_cawonce "$vid" || true)
    if is_uint "${next:-}"; then
      say "on-chain nextCawonce for name #$vid: $next"
    else
      say "on-chain nextCawonce: could not read (${RPC_ERR:-RPC error})"
    fi
  fi
}

# ---------- check ----------

cmd_check() {
  local problems=0 warnings=0
  is_uint "$STALL_MINUTES" || STALL_MINUTES=15
  is_uint "$WARN_WEI" || WARN_WEI=500000000000000
  is_uint "$CRIT_WEI" || CRIT_WEI=100000000000000

  if ! api_health_ok; then
    say "PROBLEM: node API is not answering /api/health ($API_URL)"
    problems=$((problems + 1))
  fi

  if db_sql 'SELECT 1' >/dev/null 2>&1; then
    local stuck
    stuck=$(db_sql "SELECT COUNT(*) FROM \"TxQueue\" WHERE status = 'processing' AND \"updatedAt\" < now() - interval '$STALL_MINUTES minutes'")
    if is_uint "${stuck:-}" && [ "$stuck" -gt 0 ]; then
      say "PROBLEM: $stuck queue row(s) stuck in 'processing' for over $STALL_MINUTES min — the known stall signature. First move: caw-doctor restart"
      problems=$((problems + 1))
    fi
    local failed_n
    failed_n=$(db_sql 'SELECT COUNT(*) FROM "TxQueue" WHERE status = '"'"'failed'"'"'')
    if is_uint "${failed_n:-}" && [ "$failed_n" -gt 0 ]; then
      say "PROBLEM: $failed_n failed queue row(s) — each blocks its cawonce at the node's submission check. Review with: caw-doctor unblock"
      problems=$((problems + 1))
    fi
    local pending_n
    pending_n=$(db_sql 'SELECT COUNT(*) FROM "TxQueue" WHERE status = '"'"'pending'"'"'')
    if is_uint "${pending_n:-}" && [ "$pending_n" -gt 0 ]; then
      say "note: $pending_n row(s) pending delivery"
    fi
  else
    say "WARN: cannot read the database (run as root) — queue checks skipped"
    warnings=$((warnings + 1))
  fi

  local addr bal
  addr=$(validator_address || true)
  if [ -n "$addr" ]; then
    bal=$(chain_balance_wei "$addr" || true)
    if is_uint "${bal:-}"; then
      if wei_lt "$bal" "$CRIT_WEI"; then
        say "PROBLEM: validator balance critically low: $(wei_to_eth "$bal") ETH — deliveries will fail. Fund $addr with a little Base ETH"
        problems=$((problems + 1))
      elif wei_lt "$bal" "$WARN_WEI"; then
        say "WARN: validator balance getting low: $(wei_to_eth "$bal") ETH (one delivery costs roughly 0.0000012 ETH)"
        warnings=$((warnings + 1))
      fi
    else
      say "WARN: could not read validator balance (${RPC_ERR:-RPC error})"
      warnings=$((warnings + 1))
    fi
  fi

  if [ "$problems" -gt 0 ]; then exit 2; fi
  if [ "$warnings" -gt 0 ]; then exit 1; fi
  say "OK: node healthy"
  exit 0
}

# ---------- unblock ----------

cmd_unblock() {
  db_sql 'SELECT 1' >/dev/null 2>&1 || {
    say "Cannot read the database — run as root so $DB_PASS_FILE is readable." >&2
    exit 1
  }

  local rows
  rows=$(db_sql 'SELECT id, "senderId", COALESCE(cawonce::text, '"'"''"'"'), COALESCE(reason, '"'"''"'"') FROM "TxQueue" WHERE status = '"'"'failed'"'"' ORDER BY id')
  if [ -z "$rows" ]; then
    say "No failed queue rows. Nothing is blocked."
    return 0
  fi

  say "Failed queue rows (each one blocks its cawonce for new posts):"
  local id sender cawonce reason next verdict deleted=0 skipped=0
  while IFS='|' read -r id sender cawonce reason; do
    [ -n "$id" ] || continue
    if ! is_uint "$id" || ! is_uint "$sender"; then
      say "  row $id: unexpected data — skipped (look at it manually)"
      skipped=$((skipped + 1)); continue
    fi
    if ! is_uint "${cawonce:-}"; then
      say "  row $id (sender $sender): no cawonce recorded — this row does not block submissions; leaving it alone"
      skipped=$((skipped + 1)); continue
    fi

    # The safety check: ask the CHAIN what cawonce it expects next for
    # this sender. Only two outcomes make deletion provably safe:
    #   next == row.cawonce : the action never landed; the chain still
    #                         expects exactly this cawonce, so removing
    #                         the failed row simply frees the poster to
    #                         re-sign at the same cawonce.
    #   next >  row.cawonce : the cawonce was already consumed on-chain
    #                         (a later action landed); this row is a
    #                         ghost and can never be delivered.
    # Anything else (next < cawonce, or the chain cannot be read) is
    # NOT provably safe, and the row is left untouched.
    next=$(chain_next_cawonce "$sender" || true)
    if ! is_uint "${next:-}"; then
      say "  row $id (sender $sender, cawonce $cawonce, reason: ${reason:-none}): cannot verify on-chain (${RPC_ERR:-RPC error}) — NOT touched"
      skipped=$((skipped + 1)); continue
    fi
    if [ "$next" -eq "$cawonce" ]; then
      verdict="never landed on-chain (chain nextCawonce = $next) — safe to release"
    elif [ "$next" -gt "$cawonce" ]; then
      verdict="cawonce already consumed on-chain (chain nextCawonce = $next) — ghost row, safe to remove"
    else
      say "  row $id (sender $sender, cawonce $cawonce, reason: ${reason:-none}): chain nextCawonce is $next, BELOW this row — not provably safe, NOT touched"
      skipped=$((skipped + 1)); continue
    fi

    say "  row $id (sender $sender, cawonce $cawonce, reason: ${reason:-none}): $verdict"
    if confirm "Delete failed row $id?"; then
      local out
      out=$(db_sql "DELETE FROM \"TxQueue\" WHERE id = $id AND status = 'failed'")
      if [ "$out" = "DELETE 1" ]; then
        say "    deleted row $id"
        deleted=$((deleted + 1))
      else
        say "    delete did not remove exactly one row (output: '${out:-none}') — check manually"
        skipped=$((skipped + 1))
      fi
    else
      say "    kept (not confirmed)"
      skipped=$((skipped + 1))
    fi
  done <<EOF
$rows
EOF

  say "Done. Deleted: $deleted, left alone: $skipped."
  say "Note: deleting a row only frees the cawonce on THIS node. The poster still has to submit again."
}

# ---------- restart ----------

cmd_restart() {
  command -v systemctl >/dev/null 2>&1 || { say "systemctl not found — this tool expects a kit-installed server." >&2; exit 1; }
  confirm "Restart the caw-node service now?" || { say "Not restarted."; return 0; }
  say "Restarting caw-node…"
  systemctl restart caw-node || { say "systemctl restart failed." >&2; exit 1; }
  local i
  for i in $(seq 1 60); do
    if api_health_ok; then
      say "Node is back: /api/health answers ok (after ~$((i * 2))s)."
      say "If a post was stuck in 'processing', watch it now — a restart normally resumes it."
      return 0
    fi
    sleep 2
  done
  say "Restarted, but /api/health is still not answering after 120s. Check: journalctl -u caw-node -n 80" >&2
  exit 1
}

# ---------- main ----------

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  --yes) ASSUME_YES=1; shift ;;
esac
case "${2:-}" in
  --yes) ASSUME_YES=1 ;;
esac

case "${1:-status}" in
  status)  cmd_status ;;
  check)   cmd_check ;;
  unblock) cmd_unblock ;;
  restart) cmd_restart ;;
  -h|--help|help) usage ;;
  *) say "unknown subcommand: ${1:-}" >&2; usage >&2; exit 64 ;;
esac
