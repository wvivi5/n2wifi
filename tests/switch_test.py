#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Offline exercise of `n2wifi switch` -- no network, no writes.

The point of `switch` is that it activates a profile that is already on disk,
so the three things worth proving are:
  1. an SSID that was never saved is refused (and nothing is activated),
  2. switching to the network we are already on is a no-op,
  3. the happy path activates the profile and never calls the write path.
"""
import importlib.machinery
import importlib.util
import os
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "/usr/local/bin/n2wifi"
if not os.path.exists(SRC):
    sys.exit("source not found: " + SRC)

ldr = importlib.machinery.SourceFileLoader("n2wifi", SRC)
spec = importlib.util.spec_from_loader("n2wifi", ldr)
m = importlib.util.module_from_spec(spec)
ldr.exec_module(m)

fails = []
calls = []


def check(name, got, want):
    ok = got == want
    print("  %s  %s  got %r want %r" % ("PASS" if ok else "FAIL", name, got, want))
    if not ok:
        fails.append(name)


def patch(cur_ssid):
    """Wire the module to a fake box that is currently on cur_ssid."""
    calls.clear()
    m.backend_name = lambda: "nm"
    m.saved_networks = lambda: ["Home-5G", "Home", "Cafe"]
    m.link_state = lambda check="ip": {"ssid": cur_ssid, "ip": "10.0.0.9/24",
                                       "ok": True, "blind": False}
    m.cmd_apply = lambda ssid=None: calls.append(("apply", ssid))
    m.cmd_status = lambda: calls.append(("status",))
    m.cmd_add = lambda *a, **k: calls.append(("add",) + a)
    m.snapshot_config = lambda tag="preswitch": None


print("1) unknown SSID is refused")
patch("Home-5G")
try:
    m.cmd_switch("Never-Saved")
    check("exit", "no exit", "SystemExit")
except SystemExit as e:
    check("exit code", e.code, 1)
check("nothing activated", calls, [])

print("2) already on the target -> no-op")
patch("Home-5G")
m.cmd_switch("Home-5G")
check("nothing activated", calls, [])

print("3) happy path: activate, never write")
patch("Home-5G")
m.cmd_switch("Cafe", guard=False)
check("applied the saved profile", calls, [("apply", "Cafe")])

print("4) the write path is not reachable from switch")
patch("Home-5G")
m.cmd_switch("Home", guard=False)
check("no add() call", [c for c in calls if c[0] == "add"], [])

print("")
print("%d failure(s)" % len(fails))
sys.exit(1 if fails else 0)
