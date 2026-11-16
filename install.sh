#!/bin/sh
# install.sh -- install n2wifi locally, or push it to a remote host over ssh.
#
# Local install (the common case):
#   sudo ./install.sh
#
# Remote push (Android phone, embedded board, any Linux box):
#   ./install.sh root@192.168.1.50
#   ./install.sh root@192.168.1.50 8022
#   ./install.sh root@127.0.0.1 8022 /data/local/tmp/n2wifi   # after: adb forward tcp:8022 tcp:8022
#
# Requirements: python3 (3.6+) on the target.  Nothing else -- n2wifi drives
# whatever the platform already has (nmcli / wpa_cli / iw / ip).
set -e

SRC=$(dirname "$0")/n2wifi
[ -f "$SRC" ] || { echo "error: $SRC not found"; exit 1; }

# ---- local install ---------------------------------------------------------
if [ -z "${1:-}" ]; then
    DEST=${DEST:-/usr/local/bin/n2wifi}
    if ! command -v python3 >/dev/null 2>&1; then
        echo "error: python3 not found -- install it first (apt-get install -y python3)" >&2
        exit 1
    fi
    if [ "$(id -u)" -ne 0 ]; then
        echo "error: run with sudo (writing to $DEST)" >&2
        exit 1
    fi
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

echo "-> chmod + self test"
ssh -p "$PORT" "$HOST" "chmod 755 '$DEST' && '$DEST' --version && '$DEST' backend" || {
    echo "pushed, but the self test failed -- check python3 / root on the target"
    exit 1
}

echo "ok: run 'n2wifi --help' on the target"
