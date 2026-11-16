#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Offline exercise of n2wifi's join guard -- no network is touched.

Loads the real n2wifi source, then swaps link_state()/run()/time for fakes so
every branch of guard_run() -- including the real do_rollback() nmcli
sequence -- runs deterministically and instantly.

The fake link is a timeline: (t_until, state).  The loop polls until the
deadline; sleeping advances a fake clock, so nothing actually waits.
"""
import importlib.machinery
import importlib.util
import json
import os
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "/usr/local/bin/n2wifi"

ldr = importlib.machinery.SourceFileLoader("n2wifi", SRC)
spec = importlib.util.spec_from_loader("n2wifi", ldr)
m = importlib.util.module_from_spec(spec)
ldr.exec_module(m)

STATE = "/tmp/n2wifi-test-guard.json"
LOG = "/tmp/n2wifi-test-guard.log"

fails = []


def check(name, cond, detail=""):
    print(("  PASS  " if cond else "  FAIL  ") + name + ("  " + detail if detail else ""))
    if not cond:
        fails.append(name)


class Clock:
    """A fake clock: sleeping advances it, so the loops finish instantly."""
    def __init__(self):
        self.t = 1000.0

    def time(self):
        return self.t

    def sleep(self, s):
        self.t += max(float(s), 0.5)


class Fake:
    def __init__(self, timeline):
        self.timeline = timeline      # [(t_until, state), ...]
        self.calls = []
        self.rc_map = {}

    def link_state(self, check="ip"):
        now = CLOCK.t - T0
        for t_until, state in self.timeline:
            if now < t_until:
                return dict(state)
        return dict(self.timeline[-1][1])

    def run(self, args, timeout=30, check=False):
        self.calls.append(list(args))
        rc = 0
        joined = " ".join(args)
        for pat, code in self.rc_map.items():
            if pat in joined:
                rc = code
                break
        return rc, "", ("" if rc == 0 else "fake failure")


def st(ssid=None, ip=None, ok=None):
    if ok is None:
        ok = bool(ip)
    return {"ssid": ssid, "ip": ip, "ok": ok, "blind": ssid is None}


OFFLINE = st(None, None, False)
NMC_SEQ = ["nmcli connection delete NewNet",
           "nmcli connection reload",
           "nmcli connection up OldNet"]
T0 = 0.0
CLOCK = Clock()


def run_case(name, timeline, cfg_extra=None, expect_phase=None, expect_rc=None,
             expect_calls=None, rc_map=None, forbid_calls=False):
    global T0
    T0 = CLOCK.t
    fake = Fake(timeline)
    fake.rc_map = rc_map or {}
    m.link_state = fake.link_state
    m.run = fake.run

    cfg = {"backend": "nm", "target": "NewNet", "old": "OldNet", "snap": None,
           "timeout": 12, "check": "ip", "strict": False, "marker": None,
           "bounce": False, "anchor": None,
           "state": STATE, "log": LOG, "verify": 9}
    cfg.update(cfg_extra or {})
    for f in (STATE, LOG):
        try:
            os.unlink(f)
        except OSError:
            pass

    rc = m.guard_run(cfg)
    rec = m.gread(STATE) or {}
    nm = [" ".join(c) for c in fake.calls if c and c[0] == "nmcli"]
    print("%-26s phase=%-11s rc=%s  nmcli=%d" % (name, rec.get("phase"), rc, len(nm)))
    if expect_phase:
        check(name + ": phase", rec.get("phase") == expect_phase,
              "got %r want %r" % (rec.get("phase"), expect_phase))
    if expect_rc is not None:
        check(name + ": exit", rc == expect_rc, "got %s want %s" % (rc, expect_rc))
    if expect_calls is not None:
        check(name + ": nmcli sequence",
              nm == expect_calls, "got %s" % nm)
    if forbid_calls:
        check(name + ": nothing rolled back", nm == [], "got %s" % nm)
    return fake, rec


m.time.time = CLOCK.time
m.time.sleep = CLOCK.sleep

print("n2wifi guard -- offline branch tests (source: %s)" % SRC)
print("version:", m.VERSION)
print("")

# A. the switch worked
run_case("A target reached",
         [(999, st("NewNet", "10.0.0.9/24"))],
         expect_phase="ok", expect_rc=0, forbid_calls=True)

# B. never left the old network -> still online, leave it alone, but the new
#    profile must not keep autoconnect on (it would fight at the next boot)
run_case("B online, not the target",
         [(999, st("OldNet", "10.0.0.5/24"))],
         expect_phase="ok", expect_rc=0,
         expect_calls=["nmcli connection modify NewNet connection.autoconnect no"])

# C. dead link -> roll back with the real nmcli sequence
run_case("C offline -> rollback",
         [(15, OFFLINE), (999, st("OldNet", "10.0.0.5/24"))],
         expect_phase="rolledback", expect_rc=0,
         expect_calls=NMC_SEQ)

# D. --strict: being on the wrong network counts as failure
run_case("D strict, wrong network",
         [(999, st("OldNet", "10.0.0.5/24"))],
         cfg_extra={"strict": True},
         expect_phase="rolledback", expect_rc=0,
         expect_calls=NMC_SEQ)

# E. first setup: there is nothing to fall back to
run_case("E no previous network",
         [(999, OFFLINE)],
         cfg_extra={"old": None},
         expect_phase="failed", expect_rc=1, forbid_calls=True)

# F. the rollback command itself fails
run_case("F rollback fails",
         [(999, OFFLINE)],
         rc_map={"up OldNet": 1},
         expect_phase="failed", expect_rc=1)

# G. config restored but the old network never comes back
run_case("G old never returns",
         [(15, OFFLINE), (999, st("SomeoneElse", "10.0.0.7/24"))],
         expect_phase="failed", expect_rc=1)

# H. associated to the target but DHCP never completes -> dead uplink, roll back
run_case("H target, no DHCP",
         [(15, st("NewNet", None)), (999, st("OldNet", "10.0.0.5/24"))],
         cfg_extra={"check": "ip"},
         expect_phase="rolledback", expect_rc=0, expect_calls=NMC_SEQ)

# J. --check link explicitly accepts "associated" as good enough
run_case("J check=link, associated",
         [(999, st("NewNet", None, True))],
         cfg_extra={"check": "link"},
         expect_phase="ok", expect_rc=0, forbid_calls=True)

# K. level 1: the timeout expires with no uplink, the radio is power-cycled,
#    and the backend re-picks a saved network on its own -> recovered, no
#    rollback at all (this is the cheap path the user asked for)
kc, krec = run_case("K radio bounce recovers",
                    [(40, OFFLINE), (999, st("OldNet", "10.0.0.5/24"))],
                    cfg_extra={"bounce": True, "bounce_wait": 30},
                    expect_phase="recovered", expect_rc=0)
kc_nm = [" ".join(c) for c in kc.calls if c and c[0] == "nmcli"]
check("K: autoconnect off before bouncing",
      "nmcli connection modify NewNet connection.autoconnect no" in kc_nm,
      "got %s" % kc_nm)
check("K: radio was actually cycled",
      "nmcli radio wifi off" in kc_nm and "nmcli radio wifi on" in kc_nm,
      "got %s" % kc_nm)
check("K: no rollback", not any("delete" in c for c in kc_nm), "got %s" % kc_nm)

# L. the power-cycle does not help either -> fall through to the snapshot/rollback
lc, _ = run_case("L bounce, still dead",
                 [(21, OFFLINE), (999, st("OldNet", "10.0.0.5/24"))],
                 cfg_extra={"bounce": True, "bounce_wait": 6},
                 expect_phase="rolledback", expect_rc=0)
lc_nm = [" ".join(c) for c in lc.calls if c and c[0] == "nmcli"]
check("L: bounced first, rolled back after",
      "nmcli radio wifi off" in lc_nm and "nmcli connection delete NewNet" in lc_nm,
      "got %s" % lc_nm)

# M. anchor: joined the target, got an IP, but the landmark is unreachable
#    -> that is somebody else's network, treat it as a failure
run_case("M anchor unreachable",
         [(15, st("NewNet", "10.0.0.9/24")), (999, st("OldNet", "10.0.0.5/24"))],
         cfg_extra={"anchor": "192.168.68.1"},
         rc_map={"ping -c 2 -W 2 192.168.68.1": 1},
         expect_phase="rolledback", expect_rc=0, expect_calls=NMC_SEQ)

# N. anchor reachable -> an ordinary success, nothing touched
run_case("N anchor reachable",
         [(999, st("NewNet", "10.0.0.9/24"))],
         cfg_extra={"anchor": "192.168.68.1"},
         expect_phase="ok", expect_rc=0, forbid_calls=True)

# I. android/wpa path: snapshot restore instead of nmcli
snap = "/tmp/n2wifi-test.conf.n2snap-prejoin"
with open(snap, "w") as f:
    f.write("network={\n  ssid=\"OldNet\"\n}\n")
m.restore_snapshot = lambda path: path == snap
m.reload_quiet = lambda b: True
run_case("I snapshot rollback (wpa)",
         [(15, OFFLINE), (999, st("OldNet", "10.0.0.5/24"))],
         cfg_extra={"backend": "wpa", "snap": snap},
         expect_phase="rolledback", expect_rc=0, forbid_calls=True)

print("")
print("last record:", json.dumps(m.gread(STATE), ensure_ascii=False))
print("state dir :", m.state_dir())
print("")
print("%d failure(s)" % len(fails))
sys.exit(1 if fails else 0)
