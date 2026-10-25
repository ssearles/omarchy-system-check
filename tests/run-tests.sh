#!/usr/bin/env bash
# Test suite for the system-check scripts.
#
# No sudo, no real pacman: every external command is a stub in a throwaway
# sandbox HOME, and the health check's system paths are pointed at fixtures via
# OMARCHY_PACMAN_DB / OMARCHY_PACMAN_LOG / OMARCHY_ETC_DIR / OMARCHY_UPDATE_LOG.
#
#   tests/run-tests.sh          run everything
#   tests/run-tests.sh -v       also show each command's output
set -uo pipefail

repo=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
bin=$repo/bin
verbose=0
[[ ${1:-} == -v ]] && verbose=1

pass=0
fail=0
failed=()

ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() {
  fail=$((fail + 1))
  failed+=("$1")
  printf '  FAIL %s\n' "$1"
  [[ -n ${2:-} ]] && printf '       %s\n' "$2"
}
eq() { if [[ $2 == "$3" ]]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) no "$1" "[$2] not found in: $3" ;; esac; }
hasnt() { case "$3" in *"$2"*) no "$1" "unexpected [$2] in: $3" ;; *) ok "$1" ;; esac; }
section() { printf '\n%s\n' "$1"; }

sandbox() {
  SB=$(mktemp -d "${TMPDIR:-/tmp}/system-check-test.XXXXXX")
  mkdir -p "$SB/bin" "$SB/home/.local/bin" "$SB/run" "$SB/etc" "$SB/pacman/local" "$SB/log"
  cp "$bin"/omarchy-* "$SB/bin/"
  : >"$SB/log/pacman.log"

  cat >"$SB/bin/pacman" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  -Qtdq) [[ -n ${STUB_ORPHANS:-} ]] && printf '%s\n' ${STUB_ORPHANS}; exit 0 ;;
  -Dk)   [[ ${STUB_DK_FAIL:-0} == 1 ]] && exit 1; exit 0 ;;
  *)     exit 0 ;;
esac
SH

  cat >"$SB/bin/pgrep" <<'SH'
#!/usr/bin/env bash
[[ ${STUB_BUSY:-0} == 1 ]] && exit 0
exit 1
SH

  cat >"$SB/bin/systemctl" <<'SH'
#!/usr/bin/env bash
[[ ${STUB_FAILED_UNITS:-0} == 1 ]] && echo "foo.service loaded failed failed Foo"
exit 0
SH

  cat >"$SB/bin/checkupdates" <<'SH'
#!/usr/bin/env bash
case "${STUB_CHECKUPDATES_RC:-2}" in
  0) printf 'linux 7.2.5-3 -> 7.2.6-1\nextra/foo 1.0-1 -> 1.0-2\n' ;;
  2) exit 2 ;;
  *) exit "${STUB_CHECKUPDATES_RC}" ;;
esac
SH

  # No network: getent succeeds immediately so update-check does not wait 30 s.
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SB/bin/getent"
  # No Omarchy chatter: no omarchy-package update, no bar refresh.
  printf '#!/usr/bin/env bash\nexit 1\n' >"$SB/bin/omarchy-update-available"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SB/bin/omarchy-update-status"
  chmod +x "$SB/bin"/*

  export HOME="$SB/home"
  export XDG_RUNTIME_DIR="$SB/run"
  export OMARCHY_PACMAN_DB="$SB/pacman"
  export OMARCHY_PACMAN_LOG="$SB/log/pacman.log"
  export OMARCHY_ETC_DIR="$SB/etc"
  export OMARCHY_UPDATE_LOG="$SB/log/update.log"
  export OMARCHY_CHECK_RETRY_DELAY=0
  unset STUB_ORPHANS STUB_DK_FAIL STUB_FAILED_UNITS STUB_BUSY STUB_CHECKUPDATES_RC
}

cleanup() { [[ -n ${SB:-} && -d ${SB:-} ]] && rm -rf "$SB"; }
trap cleanup EXIT

run() {
  local script=$1
  shift
  "$SB/bin/$script" "$@" 2>&1
}
rc_of() {
  local script=$1
  shift
  "$SB/bin/$script" "$@" >/dev/null 2>&1
  echo $?
}
j() { jq -r "$1" <<<"$2"; }

# --------------------------------------------------------------------------
section "omarchy-update-check"
# --------------------------------------------------------------------------
sandbox
out=$(run omarchy-update-check --report); eq "no updates -> rc 0" 0 "$(rc_of omarchy-update-check --report)"
eq "no updates -> message" "No pending updates." "$out"

sandbox
export STUB_CHECKUPDATES_RC=0
out=$(run omarchy-update-check --report)
eq "updates pending -> count line" "2 package(s) pending:" "$(printf '%s\n' "$out" | head -1)"

sandbox
export STUB_CHECKUPDATES_RC=1
err=$(run omarchy-update-check --report); rc=$?
eq "checkupdates error -> exit 3" 3 "$rc"
has "checkupdates error -> explains skip" "SKIP" "$err"

# --------------------------------------------------------------------------
section "omarchy-health-check"
# --------------------------------------------------------------------------
sandbox
out=$(run omarchy-health-check --report); rc=$?
eq "clean -> rc 0" 0 "$rc"
has "clean -> says so" "System looks clean." "$out"

sandbox
export STUB_ORPHANS="a b"
out=$(run omarchy-health-check --report); rc=$?
eq "orphans -> rc 1" 1 "$rc"
has "orphans -> counts them" "2 orphaned package(s)" "$out"
has "orphans -> offers -Rns" "pacman -Rns a b" "$out"

sandbox
touch "$SB/pacman/db.lck"
out=$(run omarchy-health-check --report); rc=$?
eq "stale db.lck -> rc 1" 1 "$rc"
has "stale db.lck -> named" "stale pacman lock" "$out"

sandbox
mkdir -p "$SB/pacman/local/broken"
out=$(run omarchy-health-check --report); rc=$?
eq "missing desc -> rc 1" 1 "$rc"
has "missing desc -> names package" "missing desc" "$out"
has "missing desc -> broken" "broken" "$out"

sandbox
printf '[2026-10-24T10:00:00] [PACMAN] Running transaction started\n' >"$SB/log/pacman.log"
out=$(run omarchy-health-check --report); rc=$?
eq "log imbalance -> rc 1" 1 "$rc"
has "log imbalance -> reported" "pacman.log imbalance" "$out"

sandbox
touch "$SB/etc/pacman.conf.pacnew"
out=$(run omarchy-health-check --report); rc=$?
eq "pacnew -> rc 1" 1 "$rc"
has "pacnew -> counted" "1 unmerged .pacnew" "$out"

sandbox
export STUB_DK_FAIL=1
out=$(run omarchy-health-check --report); rc=$?
eq "pacman -Dk failure -> rc 1" 1 "$rc"
has "pacman -Dk failure -> reported" "dependency problems" "$out"

sandbox
export STUB_FAILED_UNITS=1
out=$(run omarchy-health-check --report); rc=$?
eq "failed unit -> rc 1" 1 "$rc"
has "failed unit -> counted" "1 failed systemd unit" "$out"

sandbox
printf 'Updating linux initcpios...\n' >"$SB/log/update.log"
out=$(run omarchy-health-check --report); rc=$?
eq "initcpio failure -> rc 1" 1 "$rc"
has "initcpio failure -> reported" "initramfs" "$out"

sandbox
export STUB_BUSY=1
out=$(run omarchy-health-check --report); rc=$?
eq "pacman busy -> exit 3, not 0" 3 "$rc"
has "pacman busy -> says skipped" "SKIP" "$out"

# --------------------------------------------------------------------------
section "omarchy-system-check --json"
# --------------------------------------------------------------------------
sandbox
out=$(run omarchy-system-check --json)
eq "clean -> known true" true "$(j .known "$out")"
eq "clean -> no updates" 0 "$(j .updates "$out")"
eq "clean -> no health issues" 0 "$(j .health "$out")"
eq "clean -> empty summary" "" "$(j .summary "$out")"

sandbox
export STUB_CHECKUPDATES_RC=0
out=$(run omarchy-system-check --json)
eq "updates only -> updates 2" 2 "$(j .updates "$out")"
eq "updates only -> summary" "2 updates" "$(j .summary "$out")"

sandbox
export STUB_ORPHANS="a b"
out=$(run omarchy-system-check --json)
eq "health only -> health 1" 1 "$(j .health "$out")"
eq "health only -> summary" "2 orphaned package(s)" "$(j .summary "$out")"

sandbox
export STUB_CHECKUPDATES_RC=0 STUB_ORPHANS="a b"
out=$(run omarchy-system-check --json)
eq "both -> updates" 2 "$(j .updates "$out")"
eq "both -> health" 1 "$(j .health "$out")"
eq "both -> summary" "2 updates, 2 orphaned package(s)" "$(j .summary "$out")"

# The update half retries a transient failure the same way.
sandbox
printf '#!/usr/bin/env bash\nc=%s/ucount\nif [[ -f $c ]]; then echo "No pending updates."; exit 0; fi\necho 1 >$c\nexit 3\n' "$SB" >"$SB/bin/omarchy-update-check"
chmod +x "$SB/bin/omarchy-update-check"
out=$(run omarchy-system-check --json)
eq "transient update failure -> retry clears skip" true "$(j .known "$out")"
eq "transient update failure -> no stale detail" "" "$(j .detail "$out")"

# A persistent failure still reports unknown, never clean.
sandbox
export STUB_CHECKUPDATES_RC=1
out=$(run omarchy-system-check --json)
eq "persistent update failure -> known false" false "$(j .known "$out")"
has "persistent update failure -> reason" "mirrors" "$(j .detail "$out")"

# Busy on the first attempt, fine on the second: the skip must clear.
sandbox
printf '#!/usr/bin/env bash\nc=%s/count\nif [[ -f $c ]]; then exit 0; fi\necho 1 >$c\nexit 3\n' "$SB" >"$SB/bin/omarchy-health-check"
chmod +x "$SB/bin/omarchy-health-check"
out=$(run omarchy-system-check --json)
eq "transient busy -> retry clears skip" true "$(j .known "$out")"
eq "transient busy -> no stale detail" "" "$(j .detail "$out")"

sandbox
export STUB_BUSY=1
out=$(run omarchy-system-check --json)
eq "pacman busy -> known false" false "$(j .known "$out")"
has "pacman busy -> reason" "pacman was busy" "$(j .detail "$out")"

sandbox
export STUB_CHECKUPDATES_RC=1
out=$(run omarchy-system-check --json)
eq "mirror error -> known false" false "$(j .known "$out")"
has "mirror error -> reason" "mirrors" "$(j .detail "$out")"

# An unexpected exit from the health check must not pass for clean either.
sandbox
printf '#!/usr/bin/env bash\nexit 2\n' >"$SB/bin/omarchy-health-check"
chmod +x "$SB/bin/omarchy-health-check"
out=$(run omarchy-system-check --json)
eq "health exit 2 -> known false" false "$(j .known "$out")"
has "health exit 2 -> reason" "exit 2" "$(j .detail "$out")"

sandbox
printf '#!/usr/bin/env bash\nexit 1\n' >"$SB/bin/omarchy-health-check"
chmod +x "$SB/bin/omarchy-health-check"
out=$(run omarchy-system-check --json)
eq "health exit 1, no ISSUE -> known false" false "$(j .known "$out")"
has "health exit 1, no ISSUE -> reason" "reported an error" "$(j .detail "$out")"

sandbox
mkdir -p "$XDG_RUNTIME_DIR/omarchy-system-check"
: >"$XDG_RUNTIME_DIR/omarchy-system-check/deferred"
out=$(run omarchy-system-check --json)
eq "deferred -> flagged" true "$(j .deferred "$out")"
eq "deferred -> still known" true "$(j .known "$out")"
eq "deferred -> no counts" 0 "$(j .updates "$out")"

# Every path must emit the same keys, or the widget has to guess.
sandbox
for scenario in clean updates health; do
  case $scenario in
    clean) out=$(run omarchy-system-check --json) ;;
    updates) export STUB_CHECKUPDATES_RC=0
out=$(run omarchy-system-check --json) ;;
    health) export STUB_ORPHANS="a"
out=$(run omarchy-system-check --json) ;;
  esac
  keys=$(jq -r 'keys | sort | join(",")' <<<"$out")
  eq "json keys ($scenario)" "deferred,detail,health,known,summary,updates" "$keys"
done

# --------------------------------------------------------------------------
section "omarchy-cleanup-popup --print"
# --------------------------------------------------------------------------
sandbox
export STUB_ORPHANS="a b"
out=$(run omarchy-cleanup-popup --print)
has "health only -> Health section" "Health" "$out"
hasnt "health only -> no update command" "  omarchy update" "$out"
has "health only -> says update not needed" "no update is pending" "$out"

sandbox
export STUB_CHECKUPDATES_RC=0 STUB_ORPHANS="a"
out=$(run omarchy-cleanup-popup --print)
h=$(printf '%s\n' "$out" | grep -n '^Health' | cut -d: -f1)
u=$(printf '%s\n' "$out" | grep -n '^Updates' | cut -d: -f1)
if [[ -n $h && -n $u ]] && ((h < u)); then ok "both -> Health before Updates"; else no "both -> Health before Updates" "health line [$h], updates line [$u]"; fi
has "both -> update command present" "omarchy update" "$out"

sandbox
export STUB_CHECKUPDATES_RC=1 STUB_ORPHANS="a"
out=$(run omarchy-cleanup-popup --print)
has "mirror error -> could not check" "could not check" "$out"
hasnt "mirror error -> no blind update command" "  omarchy update" "$out"

sandbox
out=$(run omarchy-cleanup-popup --print)
has "clean -> nothing to fix" "Nothing to fix." "$out"

# --------------------------------------------------------------------------
section "run-in-terminal script"
# --------------------------------------------------------------------------
sandbox
export STUB_ORPHANS="a b"
run omarchy-cleanup-popup --write-run-script "$SB/run.sh" >/dev/null
if [[ -f $SB/run.sh ]]; then ok "run script written"; else no "run script written"; fi
script=$(cat "$SB/run.sh" 2>/dev/null)
has "run script -> asks for repairs" "Run these repairs now? [y/N]" "$script"
hasnt "health only -> no update prompt" "Run omarchy update now?" "$script"
has "run script -> strict mode" "set -euo pipefail" "$script"
has "run script -> has the repair" "pacman -Rns a b" "$script"
if [[ -x $SB/run.sh ]]; then ok "run script executable"; else no "run script executable"; fi

sandbox
export STUB_ORPHANS="a b"
run omarchy-cleanup-popup --write-run-script "$SB/run.sh" >/dev/null
out=$(echo n | bash "$SB/run.sh" 2>&1); rc=$?
eq "answer n -> exit 0" 0 "$rc"
has "answer n -> says skipped" "Skipped the repairs." "$out"

sandbox
export STUB_ORPHANS="a b" STUB_CHECKUPDATES_RC=0
run omarchy-cleanup-popup --write-run-script "$SB/run.sh" >/dev/null
script=$(cat "$SB/run.sh")
has "both -> asks for repairs" "Run these repairs now?" "$script"
has "both -> asks for the update separately" "Run omarchy update now?" "$script"
rline=$(grep -n "Run these repairs now?" <<<"$script" | cut -d: -f1)
uline=$(grep -n "Run omarchy update now?" <<<"$script" | cut -d: -f1)
if [[ -n $rline && -n $uline ]] && ((rline < uline)); then
  ok "both -> repairs asked before the update"
else
  no "both -> repairs asked before the update" "repairs [$rline], update [$uline]"
fi

# Saying no to both must run neither job.
out=$(printf 'n\nn\n' | bash "$SB/run.sh" 2>&1); rc=$?
eq "both, n then n -> exit 0" 0 "$rc"
has "both, n then n -> repairs skipped" "Skipped the repairs." "$out"
has "both, n then n -> update skipped" "Skipped the update." "$out"

# --------------------------------------------------------------------------
# The state-colour maths lives in lib/contrast.js so it can be tested here as
# well as used from QML. Skipped, loudly, when node is not installed.
section "state colour (lib/contrast.js)"
if command -v node >/dev/null 2>&1; then
  if out=$(node "$repo/tests/contrast.test.js" 2>&1); then
    n=$(grep -c '^  ok ' <<<"$out")
    pass=$((pass + n))
    printf '  ok   contrast guard -> %s assertions\n' "$n"
  else
    no "contrast guard" "$(tail -5 <<<"$out")"
  fi
else
  printf '  skip contrast guard (node not installed)\n'
fi

# --------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
if ((fail)); then
  printf 'failed:\n'
  printf '  - %s\n' "${failed[@]}"
  exit 1
fi
exit 0
