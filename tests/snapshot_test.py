#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Real file I/O test for snapshot_config()/restore_snapshot().

No network, no system files: N2WIFI_CONF / N2WIFI_XML point at temp copies,
so the rollback restore path (android + wpa) is exercised for real.
"""
import importlib.machinery
import importlib.util
import os
import stat
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "/usr/local/bin/n2wifi-dev"
TMP = "/tmp/n2wifi-snaptest"
os.makedirs(TMP, exist_ok=True)

fails = []


def check(name, cond, detail=""):
    print(("  PASS  " if cond else "  FAIL  ") + name + ("  " + detail if detail else ""))
    if not cond:
        fails.append(name)


def load(backend, env):
    for k in ("N2WIFI_BACKEND", "N2WIFI_CONF", "N2WIFI_XML"):
        os.environ.pop(k, None)
    os.environ["N2WIFI_BACKEND"] = backend
    os.environ.update(env)
    ldr = importlib.machinery.SourceFileLoader("n2wifi_" + backend, SRC)
    spec = importlib.util.spec_from_loader("n2wifi_" + backend, ldr)
    mod = importlib.util.module_from_spec(spec)
    ldr.exec_module(mod)
    return mod


def write(path, body):
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)
    os.chmod(path, 0o644)


# ---- wpa -------------------------------------------------------------------
conf = os.path.join(TMP, "wpa_supplicant.conf")
ORIG = 'ctrl_interface=/run/wpa_supplicant\nnetwork={\n  ssid="OldNet"\n  psk="oldpass1"\n}\n'
write(conf, ORIG)
m = load("wpa", {"N2WIFI_CONF": conf})
m.IFACE = "wlan0"

print("wpa backend (%s)" % conf)
snap = m.snapshot_config("prejoin")
check("snapshot created", snap and os.path.exists(snap), str(snap))
check("snapshot is a sibling .n2snap-<tag>",
      bool(snap) and snap == conf + ".n2snap-prejoin", str(snap))
check("snapshot mode 600", bool(snap) and stat.S_IMODE(os.stat(snap).st_mode) == 0o600,
      oct(stat.S_IMODE(os.stat(snap).st_mode)) if snap else "-")

# simulate the bad switch: a new network block gets appended
write(conf, ORIG + 'network={\n  ssid="NewNet"\n  psk="deadbeef"\n}\n')
check("live conf really changed", "NewNet" in open(conf).read())
ok = m.restore_snapshot(snap)
check("restore_snapshot returns True", ok)
check("conf is byte-identical to the snapshot",
      open(conf).read() == ORIG, repr(open(conf).read()[:40]))
check("restored file mode 600", stat.S_IMODE(os.stat(conf).st_mode) == 0o600,
      oct(stat.S_IMODE(os.stat(conf).st_mode)))

# a truncated/garbage snapshot must be refused, not written
bad = conf + ".n2snap-bad"
write(bad, "   \n")
check("empty snapshot refused", m.restore_snapshot(bad) is False)
check("missing snapshot refused", m.restore_snapshot("/tmp/does-not-exist.n2snap-x") is False)

# ---- android ---------------------------------------------------------------
xml = os.path.join(TMP, "WifiConfigStore.xml")
XORIG = ('<?xml version="1.0" encoding="utf-8"?>\n<WifiConfigStoreData>\n'
         '<NetworkList>\n<Network>\n<string name="SSID">&quot;OldNet&quot;</string>\n'
         '</Network>\n</NetworkList>\n</WifiConfigStoreData>\n')
write(xml, XORIG)
a = load("android", {"N2WIFI_XML": xml})
a.IFACE = "wlan0"
a.UID = os.getuid()
a.GID = os.getgid()

print("")
print("android backend (%s)" % xml)
asnap = a.snapshot_config("prejoin")
check("android snapshot created", asnap and os.path.exists(asnap), str(asnap))
write(xml, XORIG.replace("OldNet", "NewNet"))
check("android restore ok", a.restore_snapshot(asnap) is True)
check("android xml contains the old SSID again", "OldNet" in open(xml).read())
check("android xml mode 600", stat.S_IMODE(os.stat(xml).st_mode) == 0o600,
      oct(stat.S_IMODE(os.stat(xml).st_mode)))

badxml = xml + ".n2snap-bad"
write(badxml, "<not-a-config/>")
check("non-WifiConfigStore snapshot refused", a.restore_snapshot(badxml) is False)

# nm has nothing to snapshot -- the guard deletes the profile instead
nm = load("nm", {})
check("nm has no snapshot target", nm.active_config_file() is None)

print("")
print("%d failure(s)" % len(fails))
sys.exit(1 if fails else 0)
