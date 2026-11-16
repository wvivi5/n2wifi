#!/bin/sh
# Drive the dependency installer inside install.sh without touching the host.
#
# The "package managers" are shell stubs that only record what they were asked
# to do, so this proves two things that a real box cannot easily show:
#   - the right package manager is picked when several exist
#   - a failing one is skipped instead of aborting the install
#
#   sh tests/install_deps_test.sh [path/to/install.sh]

set -u
SRC=${1:-install.sh}
[ -f "$SRC" ] || { echo "no such file: $SRC"; exit 1; }

WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

# Extract install_python3() from the shipping script -- the same code, not a
# copy that quietly drifts away from it.
sed -n '/^install_python3() {/,/^}$/p' "$SRC" > "$WORK/fn.sh"
[ -s "$WORK/fn.sh" ] || { echo "FAIL: could not extract install_python3()"; exit 1; }

BIN=$WORK/bin
LOG=$WORK/calls.log
mkdir -p "$BIN"

# Resolved before PATH is narrowed: with PATH=$BIN some shells cannot even find
# `sh` again, which shows up as a useless rc=127.
SH_BIN=$(command -v sh) || exit 1

stub() {                     # stub <name> <exit-code>
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit %s\n' "$1" "$LOG" "$2" > "$BIN/$1"
    chmod 755 "$BIN/$1"
}

fail=0

case_run() {                 # case_run <name> <expect-rc> [<expect-substring>]
    name=$1
    want=$2
    want_calls=${3:-}
    : > "$LOG"
    # Only the stubs are visible: no real apk/apt/dnf can be reached, and the
    # function itself needs nothing but shell builtins.
    PATH="$BIN" "$SH_BIN" -c '. "$1"; install_python3' _ "$WORK/fn.sh" >/dev/null 2>&1
    rc=$?
    got=$(tr '\n' '|' < "$LOG")

    if [ "$rc" != "$want" ]; then
        echo "FAIL $name: rc=$rc want=$want  calls=[$got]"
        fail=1
        return
    fi
    if [ -n "$want_calls" ]; then
        case "$got" in
            *"$want_calls"*) ;;
            *) echo "FAIL $name: calls=[$got] lacks '$want_calls'"; fail=1; return ;;
        esac
    fi
    echo "ok   $name  rc=$rc  [$got]"
}

# 1. apk present and working -> use it, and do not touch anything else
stub apk 0
stub apt-get 0
case_run "apk wins, others untouched" 0 "apk add --no-cache python3"
if grep -q "apt-get" "$LOG"; then
    echo "FAIL: apt-get was called even though apk worked"
    fail=1
fi

# 2. apk is there but broken -> fall through to apt-get
rm -f "$BIN"/*
stub apk 1
stub apt-get 0
case_run "broken apk -> apt-get" 0 "apt-get install -y --no-install-recommends python3"

# 3. no package manager at all -> clean failure, no lies
rm -f "$BIN"/*
case_run "nothing available" 1

# 4. Arch-style box
stub pacman 0
case_run "pacman only" 0 "pacman -Sy --noconfirm --needed python"

# 5. Router / OpenWrt style box
rm -f "$BIN"/*
stub opkg 0
case_run "opkg only" 0 "opkg install python3-light python3"

# 6. dnf box where apk/apt do not exist
rm -f "$BIN"/*
stub dnf 0
case_run "dnf only" 0 "dnf install -y python3"

echo ""
if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES"
    exit 1
fi
