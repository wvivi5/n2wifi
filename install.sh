#!/bin/sh
# install.sh -- install n2wifi locally, or push it to a remote host over ssh.
#
# Local install (the common case):
#   ./install.sh                   # as root; adds python3 if it is missing
#   ./install.sh --no-deps         # never touch the package manager
#
# Remote push (Android phone, embedded board, any Linux box):
#   ./install.sh root@192.168.1.50
#   ./install.sh root@192.168.1.50 8022
#   ./install.sh root@127.0.0.1 8022 /data/local/tmp/n2wifi   # after: adb forward tcp:8022 tcp:8022
#
# Requirements: python3 (3.6+) on the target.  Nothing else -- n2wifi drives
# whatever the platform already has (nmcli / wpa_cli / iw / ip).  If python3
# is missing this script installs it with whatever package manager the box
# has (apk / apt / dnf / yum / pacman / zypper / xbps / opkg).
set -e

# Alpine and postmarketOS put apk in /sbin, and a root shell started in an
# unusual way (su, a serial getty, a container) often has no /sbin in PATH.
# Without this, `command -v apk` fails on a box that clearly has apk.
PATH="$PATH:/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin"
export PATH

NO_DEPS=0
case "${N2WIFI_NO_DEPS:-0}" in 1|yes|true) NO_DEPS=1 ;; esac

ARGS=""
for a in "$@"; do
    case "$a" in
        --no-deps|-n) NO_DEPS=1 ;;
        *) ARGS="$ARGS $a" ;;
    esac
done
# shellcheck disable=SC2086
set -- $ARGS

SRC=$(dirname "$0")/n2wifi
[ -f "$SRC" ] || { echo "error: $SRC not found"; exit 1; }

have_python() { command -v python3 >/dev/null 2>&1; }

# Every candidate is tried by absolute name through PATH, so this works on
# busybox-based images that ship a stripped-down shell.
install_python3() {
    log=/tmp/n2wifi-deps.log
    try() {
        pm=$1
        shift
        echo "-> python3 is missing, installing it with $pm"
        if "$@" >>"$log" 2>&1; then
            return 0
        fi
        echo "   $pm failed (see $log), trying the next one" >&2
        return 1
    }

    if command -v apk >/dev/null 2>&1; then
        try apk apk add --no-cache python3 && return 0
    fi
    if command -v apt-get >/dev/null 2>&1; then
        # Try without an index update first: it is much faster and usually works.
        try apt-get apt-get install -y --no-install-recommends python3 && return 0
        try apt-get apt-get update && try apt-get apt-get install -y --no-install-recommends python3 && return 0
    fi
    if command -v dnf >/dev/null 2>&1; then
        try dnf dnf install -y python3 && return 0
    fi
    if command -v yum >/dev/null 2>&1; then
        try yum yum install -y python3 && return 0
    fi
    if command -v pacman >/dev/null 2>&1; then
        try pacman pacman -Sy --noconfirm --needed python && return 0
    fi
    if command -v zypper >/dev/null 2>&1; then
        try zypper zypper --non-interactive install python3 && return 0
    fi
    if command -v xbps-install >/dev/null 2>&1; then
        try xbps xbps-install -Sy python3 && return 0
    fi
    if command -v opkg >/dev/null 2>&1; then
        try opkg opkg update && try opkg opkg install python3-light python3 && return 0
        try opkg opkg install python3 && return 0
    fi
    return 1
}

need_python() {
    # $1 = "here" or "there"
    where=$1
    have_python && return 0

    if [ "$NO_DEPS" = 1 ]; then
        echo "error: python3 not found, and --no-deps was given" >&2
        echo "       install python3 yourself, then re-run:" >&2
        echo "         apk add python3        # Alpine / postmarketOS" >&2
        echo "         apt-get install -y python3   # Debian / Ubuntu" >&2
        echo "         pacman -S python       # Arch" >&2
        exit 1
    fi

    if [ "$(id -u)" -ne 0 ]; then
        echo "error: python3 is missing and this is not root, so it cannot be installed" >&2
        echo "       re-run as root (sudo, or 'su -'), or install python3 yourself" >&2
        exit 1
    fi

    if install_python3 && have_python; then
        echo "-> python3 $(python3 -V 2>&1 | sed 's/^Python //') installed"
        return 0
    fi

    echo "error: python3 is missing and could not be installed automatically" >&2
    echo "       (no usable package manager, or no network / no package index)" >&2
    echo "       install it by hand, then re-run this script:" >&2
    echo "         apk add python3 / apt-get install -y python3 / pacman -S python" >&2
    echo "       last attempt log: /tmp/n2wifi-deps.log" >&2
    exit 1
}

# ---- local install ---------------------------------------------------------
if [ -z "${1:-}" ]; then
    DEST=${DEST:-/usr/local/bin/n2wifi}

    if [ "$(id -u)" -ne 0 ]; then
        echo "error: run as root -- either 'sudo ./install.sh', or log in as root" >&2
        echo "       (on a box where sudo itself is broken, 'su -' then re-run)" >&2
        exit 1
    fi

    need_python here

    install -m 755 "$SRC" "$DEST"
    echo "-> installed $DEST"
    "$DEST" --version
    echo "-> backend on this host:"
    "$DEST" backend || true
    echo ""
    echo "ok: try 'n2wifi status' / 'n2wifi scan' / 'n2wifi list'"
    exit 0
fi

# ---- remote push -----------------------------------------------------------
HOST=$1
PORT=${2:-8022}
DEST=${3:-/usr/local/bin/n2wifi}

echo "-> scp n2wifi to $HOST:$DEST (port $PORT)"
scp -P "$PORT" "$SRC" "$HOST:$DEST"

# The target has its own PATH (and possibly no python3), so the same treatment
# runs over there.  The snippet goes in on stdin -- quoting it inline would mean
# fighting two layers of shell quoting for $DEST, which is how these scripts
# usually break.
echo "-> check the interpreter on the target"
if ssh -p "$PORT" "$HOST" "DEST='$DEST' sh -s" <<'TARGET'
set -e
PATH="$PATH:/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin"
export PATH

if ! command -v python3 >/dev/null 2>&1; then
    echo "!! python3 is missing on the target, trying to install it"
    if command -v apk >/dev/null 2>&1; then
        apk add --no-cache python3
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get install -y --no-install-recommends python3
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y python3
    elif command -v yum >/dev/null 2>&1; then
        yum install -y python3
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm --needed python
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install python3
    elif command -v xbps-install >/dev/null 2>&1; then
        xbps-install -Sy python3
    elif command -v opkg >/dev/null 2>&1; then
        opkg install python3
    else
        echo "!! no package manager found on the target" >&2
        exit 1
    fi
fi

chmod 755 "$DEST"
"$DEST" --version
"$DEST" backend
TARGET
then
    :
else
    echo "pushed, but the self test failed -- check root / python3 on the target" >&2
    exit 1
fi

echo "ok: run 'n2wifi --help' on the target"
