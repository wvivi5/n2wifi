#!/bin/sh
# install.sh -- push n2wifi to an Android phone over ssh.
#
# usage:
#   ./install.sh [user@host] [port] [dest]
#
# examples:
#   ./install.sh root@192.168.1.50
#   ./install.sh root@192.168.1.50 8022
#   ./install.sh root@127.0.0.1 8022 /data/local/tmp/n2wifi   # after: adb forward tcp:8022 tcp:8022
set -e

HOST=${1:-root@192.168.1.50}
PORT=${2:-8022}
DEST=${3:-/usr/local/bin/n2wifi}
SRC=$(dirname "$0")/n2wifi

[ -f "$SRC" ] || { echo "error: $SRC not found"; exit 1; }

echo "-> scp n2wifi to $HOST:$DEST (port $PORT)"
scp -P "$PORT" "$SRC" "$HOST:$DEST"

echo "-> chmod + self test"
ssh -p "$PORT" "$HOST" "chmod 755 '$DEST' && '$DEST' --version && '$DEST' list" || {
    echo "pushed, but the self test failed -- check python3 / root on the phone"
    exit 1
}

echo "ok: run 'n2wifi --help' on the phone"
