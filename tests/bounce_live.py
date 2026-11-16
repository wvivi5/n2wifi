#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Live check of bounce_radio() on a real box: power-cycle the radio, then
watch whether the backend re-picks a saved network on its own.

Run it detached (systemd-run), never over the ssh session that depends on
the very radio being turned off:

    systemd-run --unit=n2wifi-bounce-test --collect \
        /usr/bin/python3 /tmp/bounce_live.py /tmp/n2wifi-dev

Result goes to /tmp/n2wifi-bounce-live.log (stdout is lost with the link).
"""
import importlib.machinery
import importlib.util
import sys
import time

SRC = sys.argv[1] if len(sys.argv) > 1 else "/usr/local/bin/n2wifi"
OUT = "/tmp/n2wifi-bounce-live.log"

ldr = importlib.machinery.SourceFileLoader("n2wifi", SRC)
spec = importlib.util.spec_from_loader("n2wifi", ldr)
m = importlib.util.module_from_spec(spec)
ldr.exec_module(m)


def log(msg):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write("[%s] %s\n" % (time.strftime("%H:%M:%S"), msg))


def main():
    open(OUT, "w", encoding="utf-8").close()
    before = m.link_state("ip")
    log("before: ssid=%s ip=%s" % (before["ssid"], before["ip"]))

    t0 = time.time()
    detail = m.bounce_radio("nm")
    log("bounce_radio -> %r (took %.1fs)" % (detail, time.time() - t0))
    if not detail:
        log("RESULT: backend offered no power-cycle")
        return 2

    t1 = time.time()
    while time.time() - t1 < 90:
        time.sleep(3)
        s = m.link_state("ip")
        if s["ok"]:
            log("back after %.0fs: ssid=%s ip=%s"
                % (time.time() - t1, s["ssid"], s["ip"]))
            log("RESULT: recovered" if s["ssid"] == before["ssid"]
                else "RESULT: recovered on a different network")
            return 0
        log("  still down (%.0fs)" % (time.time() - t1))
    log("RESULT: still offline after 90s -- this is the case the snapshot "
        "rollback exists for")
    return 1


if __name__ == "__main__":
    sys.exit(main())
