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
# @tags: prod, web
# @group: production
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

Host Local-Test
  HostName 127.0.0.1
  Port 39999
EOF

cat > "$FAKE_SSH" <<'EOF'
#!/bin/sh
echo "$@" > "${FAKE_LOG:?}"
EOF
chmod +x "$FAKE_SSH"

export SERVER_SSH_CONFIG="$CONFIG"
export SERVER_SSH="$FAKE_SSH"
export FAKE_LOG="$LOG"
export SERVER_STATE_FILE="$WORK/state"

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

# assert_eq <name> <actual> <expected>
assert_eq() {
  local name="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name (got '$actual', want '$expected')"
    fail=$((fail + 1))
  fi
}

# ── connect ────────────────────────────────────────────────────────

run 'exact connect' 0 "$SERVER" Beta-Two
assert_eq 'ssh received exactly the host' "$(cat "$LOG")" 'Beta-Two'

run 'fuzzy single match' 0 "$SERVER" beta
assert_eq 'ssh received fuzzy host' "$(cat "$LOG")" 'Beta-Two'

run_in 'picker: multiple matches, choose 2nd' 0 '2' "$SERVER" alpha
assert_eq 'ssh received picked host' "$(cat "$LOG")" 'Alpha-Two'

# Regression: ALL interactive UI goes to stderr; stdout must stay empty
# for connect paths, and ssh must receive a clean single host.
printf '%s\n' '1' | "$SERVER" alpha > "$WORK/pick.out" 2> "$WORK/pick.err"
run 'picker stdout stays empty' 0 sh -c "test ! -s '$WORK/pick.out'"
run 'status line on stderr, exactly once' 0 sh -c "test \$(grep -cxF 'Connecting to Alpha-One ...' '$WORK/pick.err') -eq 1"
run 'menu shown on stderr' 0 grep -q '\[ 2\] Alpha-Two' "$WORK/pick.err"

"$SERVER" Beta-Two > "$WORK/direct.out" 2> /dev/null
run 'direct-connect stdout stays empty' 0 sh -c "test ! -s '$WORK/direct.out'"

run_in 'picker: abort with q' 1 'q' "$SERVER"
run_in 'picker: invalid choice' 1 '99' "$SERVER"

run 'no match exits 1' 1 "$SERVER" zzz-none

# ── recency (server -) ─────────────────────────────────────────────

"$SERVER" Beta-Two >/dev/null 2>&1
run 'reconnect via -' 0 "$SERVER" -
assert_eq 'reconnected to last host' "$(cat "$LOG")" 'Beta-Two'
run 'no state exits 1' 1 env SERVER_STATE_FILE="$WORK/nonexistent" "$SERVER" -

# ── list / info / version / help ───────────────────────────────────

"$SERVER" list > "$WORK/list.out" 2>&1
run 'list exit 0' 0 true
run 'list shows Beta-Two' 0 grep -q 'Beta-Two' "$WORK/list.out"
run 'list shows all 6 aliases' 0 sh -c "test \$(grep -c '^  ' '$WORK/list.out') -eq 6"
run 'list shows hostname' 0 grep -q '10.0.0.2' "$WORK/list.out"
run 'list shows user@host:port' 0 grep -q 'root@10.0.0.2:2222' "$WORK/list.out"

"$SERVER" info Beta-Two > "$WORK/info.out" 2>&1
run 'info exit 0' 0 true
run 'info shows hostname' 0 grep -q '10.0.0.2' "$WORK/info.out"
run 'info shows user' 0 grep -q 'root' "$WORK/info.out"
run 'info unknown exits 1' 1 "$SERVER" info nope

# ── search ─────────────────────────────────────────────────────────

"$SERVER" search 10.0.0 > "$WORK/search.out" 2>&1
run 'search exit 0' 0 true
run 'search matches hostname' 0 grep -q 'Alpha-One' "$WORK/search.out"
run 'search matches user' 0 grep -q 'Beta-Two' "$WORK/search.out"

"$SERVER" search root > "$WORK/search2.out" 2>&1
run 'search by user' 0 grep -q 'Beta-Two' "$WORK/search2.out"
run 'search by user excludes others' 1 grep -q 'Alpha-One' "$WORK/search2.out"

run 'search no match exits 1' 1 "$SERVER" search zzz-none
run 'search requires term' 2 "$SERVER" search

run 'version prints' 0 "$SERVER" version
run 'help prints' 0 "$SERVER" help

# ── edit ───────────────────────────────────────────────────────────

run 'edit execs editor with config path' 0 env EDITOR=/bin/echo "$SERVER" edit

# A fake editor named `vim` (line-capable) records its args, so we can
# assert the +N jump-to-line behavior.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/vim" <<EOF
#!/bin/sh
echo "\$@" > "$WORK/edit-args.log"
EOF
chmod +x "$WORK/bin/vim"

run 'edit <name> exit 0' 0 env PATH="$WORK/bin:$PATH" EDITOR=vim "$SERVER" edit Alpha-One
want="+$(grep -n '^Host Alpha-One$' "$CONFIG" | cut -d: -f1) $CONFIG"
assert_eq 'edit jumps to host line' "$(cat "$WORK/edit-args.log")" "$want"

run 'edit unknown exits 1' 1 env EDITOR=/bin/echo "$SERVER" edit nope

# Default editor is nano (no EDITOR/VISUAL set).
cat > "$WORK/bin/nano" <<EOF
#!/bin/sh
echo "\$@" > "$WORK/nano-args.log"
EOF
chmod +x "$WORK/bin/nano"

run 'edit defaults to nano' 0 env -u EDITOR -u VISUAL PATH="$WORK/bin:$PATH" "$SERVER" edit
assert_eq 'nano received config path' "$(cat "$WORK/nano-args.log")" "$CONFIG"

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

# ── add ─────────────────────────────────────────────────────────────

run_in 'add full block' 0 'Gamma-Three
10.0.0.9
deploy
2200
~/keys/gamma.pem
y' "$SERVER" add
run 'add wrote Host line' 0 grep -q '^Host Gamma-Three$' "$CONFIG"
run 'add wrote hostname' 0 grep -q '^  HostName 10.0.0.9$' "$CONFIG"
run 'add wrote user' 0 grep -q '^  User deploy$' "$CONFIG"
run 'add wrote port' 0 grep -q '^  Port 2200$' "$CONFIG"
run 'add expanded tilde in key' 0 grep -q "^  IdentityFile $HOME/keys/gamma.pem$" "$CONFIG"

run_in 'add minimal (only required)' 0 'Delta-Four
10.0.0.8



y' "$SERVER" add
run 'minimal add wrote hostname' 0 grep -q '^  HostName 10.0.0.8$' "$CONFIG"
run 'minimal add has no User line' 1 sed -n '/^Host Delta-Four$/,/^$/p' "$CONFIG" | grep -q 'User'

run_in 'add rejects duplicate alias then succeeds' 0 'Alpha-One
Fresh-Host
10.0.0.5



y' "$SERVER" add
run 'duplicate alias not re-added' 0 sh -c "test \$(grep -c '^Host Alpha-One$' '$CONFIG') -eq 1"
run 'fresh host added after retry' 0 grep -q '^Host Fresh-Host$' "$CONFIG"

run_in 'add rejects invalid alias then succeeds' 0 'has space
OK-Alias
10.0.0.6



y' "$SERVER" add
run 'invalid alias not written' 1 grep -q 'has space' "$CONFIG"
run 'valid alias written' 0 grep -q '^Host OK-Alias$' "$CONFIG"

run_in 'add rejects non-numeric port then succeeds' 0 'Fxp-Seven
10.0.0.77

abc
2200

y' "$SERVER" add
run 'port validated' 0 grep -q '^  Port 2200$' "$CONFIG"
run 'bad port not written' 1 grep -q 'abc' "$CONFIG"

run_in 'add abort at confirm' 1 'Zed-Nine
10.9.9.9



n' "$SERVER" add
run 'aborted add not written' 1 grep -q 'Zed-Nine' "$CONFIG"

# Regression: `add` on a brand-new (nonexistent) config — empty HOSTS
# array must not trip `set -u` on bash 3.2.
FRESH="$WORK/fresh-config"
run_in 'add creates fresh config' 0 'Brand-New
10.1.1.1
root


y' env SERVER_SSH_CONFIG="$FRESH" "$SERVER" add
run 'fresh config has Host line' 0 grep -q '^Host Brand-New$' "$FRESH"
run 'fresh config perms 600' 0 sh -c "test \$(stat -f '%Lp' '$FRESH') = 600"

# ── ping ────────────────────────────────────────────────────────────

run 'ping requires name' 2 "$SERVER" ping
run 'ping unknown exits 1' 1 "$SERVER" ping nope

# reachable: spin up a local listener on the Local-Test port
nc -l 39999 >/dev/null 2>&1 &
NC_PID=$!
sleep 0.5
run 'ping reachable host' 0 "$SERVER" ping Local-Test
kill "$NC_PID" 2>/dev/null

# ── tags & groups ───────────────────────────────────────────────────

"$SERVER" list > "$WORK/list2.out" 2>&1
run 'list shows tags' 0 grep -qF '[prod, web]' "$WORK/list2.out"
run 'list shows group' 0 grep -qF '(production)' "$WORK/list2.out"

"$SERVER" @prod > "$WORK/tag.out" 2>&1
run 'filter by tag' 0 grep -q 'Alpha-One' "$WORK/tag.out"
run 'filter by tag excludes others' 1 grep -q 'Beta-Two' "$WORK/tag.out"

"$SERVER" tag prod > "$WORK/tag2.out" 2>&1
run 'tag filter 1-arg form' 0 grep -q 'Alpha-One' "$WORK/tag2.out"

"$SERVER" @group:production > "$WORK/grp.out" 2>&1
run 'filter by group' 0 grep -q 'Alpha-One' "$WORK/grp.out"
run 'filter by group excludes others' 1 grep -q 'Beta-Two' "$WORK/grp.out"

"$SERVER" tags > "$WORK/tags.out" 2>&1
run 'tags list shows prod' 0 grep -q 'prod' "$WORK/tags.out"
run 'tags list shows web' 0 grep -q 'web' "$WORK/tags.out"

"$SERVER" groups > "$WORK/groups.out" 2>&1
run 'groups list shows production' 0 grep -q 'production' "$WORK/groups.out"

# mutation
run 'tag add' 0 "$SERVER" tag Gamma-Three staging
run 'tag add wrote comment' 0 grep -q '^# @tags: staging$' "$CONFIG"
run 'tag add idempotent' 0 "$SERVER" tag Gamma-Three staging
run 'tag not duplicated' 0 sh -c "test \$(grep -c 'staging' '$CONFIG') -eq 1"

run 'untag' 0 "$SERVER" untag Alpha-One web
run 'untag removed web' 1 grep -q 'web' "$CONFIG"
run 'untag kept prod' 0 grep -q 'prod' "$CONFIG"

run 'group set' 0 "$SERVER" group Delta-Four staging
run 'group set wrote comment' 0 grep -q '^# @group: staging$' "$CONFIG"

"$SERVER" @staging > "$WORK/staging.out" 2>&1
run 'filter by new tag' 0 grep -q 'Gamma-Three' "$WORK/staging.out"
"$SERVER" @group:staging > "$WORK/staging2.out" 2>&1
run 'filter by new group' 0 grep -q 'Delta-Four' "$WORK/staging2.out"

run 'ungroup' 0 "$SERVER" ungroup Delta-Four
run 'ungroup removed comment' 1 grep -q '^# @group: staging$' "$CONFIG"
run 'ungroup requires args' 2 "$SERVER" ungroup

run_in 'tag no args aborts on EOF' 1 '' "$SERVER" tag
run 'untag requires args' 2 "$SERVER" untag
run_in 'group no args aborts on EOF' 1 '' "$SERVER" group
run 'tag unknown host exits 1' 1 "$SERVER" tag nope foo

# ── interactive tag/group flows ─────────────────────────────────────

ICFG="$WORK/interactive-cfg"
cat > "$ICFG" <<'EOF'
Host One
  HostName 1.1.1.1
Host Two
  HostName 2.2.2.2
EOF

# no groups yet → "New name:" → type prod → pick host 2
run_in 'interactive group: create + assign' 0 $'prod\n2' env SERVER_SSH_CONFIG="$ICFG" "$SERVER" group
run 'interactive group wrote comment' 0 grep -q '^# @group: prod$' "$ICFG"
run 'interactive group assigned to host 2' 0 sh -c "grep -A1 '^# @group: prod$' '$ICFG' | grep -q 'Host Two'"

# groups exist now → pick existing (1) → pick host 1
run_in 'interactive group: pick existing' 0 $'1\n1' env SERVER_SSH_CONFIG="$ICFG" "$SERVER" group
run 'interactive group assigned to host 1' 0 sh -c "grep -A1 '^# @group: prod$' '$ICFG' | grep -q 'Host One'"

# interactive tag: no tags yet → type web → pick host 1
run_in 'interactive tag: create + assign' 0 $'web\n1' env SERVER_SSH_CONFIG="$ICFG" "$SERVER" tag
run 'interactive tag wrote comment' 0 grep -q '^# @tags: web$' "$ICFG"

# abort on empty input / invalid choice
run_in 'interactive group abort' 1 '' env SERVER_SSH_CONFIG="$ICFG" "$SERVER" group
run_in 'interactive invalid choice' 1 $'99' env SERVER_SSH_CONFIG="$ICFG" "$SERVER" group

# ── summary ────────────────────────────────────────────────────────

echo
echo "passed: $pass  failed: $fail"
[[ "$fail" -eq 0 ]]
