#!/usr/bin/env bash
#
# tests/run.sh — smoke tests for the `server` CLI.
# Uses a throwaway ssh config + fake ssh binary; never touches the real
# ~/.ssh/config. Run from anywhere: bash tests/run.sh

set -u

readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SERVER="$PROJECT_DIR/server"
readonly WORK="$(mktemp -d /tmp/server-cli-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

readonly CONFIG="$WORK/ssh_config"
readonly FAKE_SSH="$WORK/fake-ssh"
readonly LOG="$WORK/ssh-args.log"

cat > "$CONFIG" <<'EOF'
# fake config for tests
Host Alpha-One
  HostName 10.0.0.1
  User ubuntu

Host Beta-Two
  HostName 10.0.0.2
  User root
  Port 2222

Host Alpha-Two
  HostName 10.0.0.3
  User ubuntu

Host Dual AliasFoo
  HostName 10.0.0.4
EOF

cat > "$FAKE_SSH" <<'EOF'
#!/bin/sh
echo "$@" > "${FAKE_LOG:?}"
EOF
chmod +x "$FAKE_SSH"

export SERVER_SSH_CONFIG="$CONFIG"
export SERVER_SSH="$FAKE_SSH"
export FAKE_LOG="$LOG"

pass=0
fail=0

# run <name> <expected-exit> <cmd...>
run() {
  local name="$1" want="$2"
  shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [[ "$got" -eq "$want" ]]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name (exit $got, want $want)"
    fail=$((fail + 1))
  fi
}

# run_in <name> <expected-exit> <stdin> <cmd...>
run_in() {
  local name="$1" want="$2" input="$3"
  shift 3
  printf '%s\n' "$input" | "$@" >/dev/null 2>&1
  local got=${PIPESTATUS[1]}
  if [[ "$got" -eq "$want" ]]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name (exit $got, want $want)"
    fail=$((fail + 1))
  fi
}

# ── connect ────────────────────────────────────────────────────────

run 'exact connect' 0 "$SERVER" Beta-Two
run 'ssh received exact host' 0 grep -qx 'Beta-Two' "$LOG"

run 'fuzzy single match' 0 "$SERVER" beta
run 'ssh received fuzzy host' 0 grep -qx 'Beta-Two' "$LOG"

run_in 'picker: multiple matches, choose 2nd' 0 '2' "$SERVER" alpha
run 'ssh received picked host' 0 grep -qx 'Alpha-Two' "$LOG"

run_in 'picker: abort with q' 1 'q' "$SERVER"
run_in 'picker: invalid choice' 1 '99' "$SERVER"

run 'no match exits 1' 1 "$SERVER" zzz-none

# ── list / info / version / help ───────────────────────────────────

"$SERVER" list > "$WORK/list.out" 2>&1
run 'list exit 0' 0 true
run 'list shows Beta-Two' 0 grep -q 'Beta-Two' "$WORK/list.out"
run 'list shows all 5 aliases' 0 sh -c "test \$(grep -c '^  ' '$WORK/list.out') -eq 5"

"$SERVER" info Beta-Two > "$WORK/info.out" 2>&1
run 'info exit 0' 0 true
run 'info shows hostname' 0 grep -q '10.0.0.2' "$WORK/info.out"
run 'info shows user' 0 grep -q 'root' "$WORK/info.out"
run 'info unknown exits 1' 1 "$SERVER" info nope

run 'version prints' 0 "$SERVER" version
run 'help prints' 0 "$SERVER" help

# ── edit ───────────────────────────────────────────────────────────

run 'edit execs editor with config path' 0 env EDITOR=/bin/echo "$SERVER" edit

# ── rm ─────────────────────────────────────────────────────────────

run_in 'rm confirm' 0 'y' "$SERVER" rm Beta-Two
run 'rm removed block' 1 grep -q 'Beta-Two' "$CONFIG"
run 'rm kept other blocks' 0 grep -q 'Alpha-One' "$CONFIG"
run 'rm created backup' 0 test -f "$CONFIG.server.bak"

run_in 'rm multi-alias rewrites Host line' 0 'y' "$SERVER" rm AliasFoo
run 'rm multi-alias kept remaining alias' 0 grep -q '^Host Dual$' "$CONFIG"

run_in 'rm abort keeps config' 1 'n' "$SERVER" rm Alpha-One
run 'aborted rm left block intact' 0 grep -q 'Alpha-One' "$CONFIG"

run 'rm unknown exits 1' 1 "$SERVER" rm nope

# ── summary ────────────────────────────────────────────────────────

echo
echo "passed: $pass  failed: $fail"
[[ "$fail" -eq 0 ]]
