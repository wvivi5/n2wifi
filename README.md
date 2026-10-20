# n2wifi

**Manage a headless Android phone's Wi-Fi from a terminal — scan, add, switch and roll back
networks without ever touching the screen.**

[中文说明](README.zh-CN.md)

```
$ n2wifi scan
2 APs, 2 distinct SSIDs:
  signal    band  chan  security    SSID
  -55 dBm   5G    36    WPA/WPA2    SiteA-5G   [connected,associated]
  -58 dBm   2.4G  6     WPA/WPA2    SiteA      [saved]
```

---

## Why this exists

Headless Android devices — kiosk phones, test farms, TV boxes, anything running a Linux chroot
over ssh — constantly need their Wi-Fi changed, and there is no screen to tap.

The usual tool for this is `wpa_cli`, but on several vendor ROMs (MIUI in particular) the
`wpa_supplicant` control socket **never answers third-party clients**: `PING`, `STATUS` and
`SCAN` all time out, so `wpa_cli` is useless there.

`n2wifi` takes the other road: it edits the platform's own Wi-Fi config store
(`WifiConfigStore.xml`) and then asks the framework to reload it. No screen, no
`wpa_supplicant` control socket, no Xposed, no extra APK.

## Features

- `scan` — nearby APs with signal, band, channel and security, `[connected]` / `[saved]` tags
- `list` / `status` / `ip` — what is saved, what is connected, and a script-friendly IP
- `add` / `join` / `del` — add a network, add and switch to it now, or remove one
- **Safe writes** — atomic replace, XML self-check before commit, automatic timestamped
  backup for every single write, and `revert`
- **Format-proof** — new entries are cloned from a block the system wrote itself, so field
  changes between Android versions do not silently drop your network
- **Never touches `wpa_supplicant`** — the link keeps running while the config is rewritten
- Single file, standard library only, bilingual CLI (`--lang en|zh`)

## Supported systems

| | |
|---|---|
| **Tested on** | Xiaomi Mi Note 2 (`scorpio`), Android 8.0 / MIUI 9, config store `/data/misc/wifi/WifiConfigStore.xml` |
| **Expected to work** | Android 7.0 – 10 (same store format and location) |
| **Android 11+** | Auto-detects `/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml`. The store format is still the same `WifiConfigStoreData` XML, so it should work — **not tested yet** |
| **Not supported** | Android ≤ 6 (those use `wpa_supplicant.conf`, not this store), non-root shells, ROMs that keep Wi-Fi config somewhere else |

Requirements:

- **root** (uid 0) — `n2wifi` must be able to read/write `/data/misc/wifi` and to kill `system_server`
- **Python 3.7+** in the shell you run it from (a Linux chroot, Termux, or any root shell)
- **`iw`** — the chroot's `iw`, or Android's `/system/bin/iw` (auto-detected)
- `/proc` mounted (always true on Android)

No Wi-Fi hardware? `scan` and `status` need `wlan0`; `add` / `del` work without it.

## Install

`n2wifi` is one file. Copy it to `/usr/local/bin/n2wifi` (or anywhere in `PATH`) and make it
executable.

### A. Over ssh (the phone already has Wi-Fi)

```sh
./install.sh root@192.168.1.50 8022
```

or by hand:

```sh
scp -P 8022 n2wifi root@192.168.1.50:/usr/local/bin/n2wifi
ssh -p 8022 root@192.168.1.50 'chmod 755 /usr/local/bin/n2wifi && n2wifi --version'
```

### B. No Wi-Fi yet — USB bootstrap (the chicken-and-egg case)

Plug USB, forward the phone's ssh port over adb, then push it:

```sh
adb forward tcp:8022 tcp:8022
scp -P 8022 n2wifi root@127.0.0.1:/usr/local/bin/n2wifi
ssh -p 8022 root@127.0.0.1 'chmod 755 /usr/local/bin/n2wifi && n2wifi scan'
```

On Windows:

```powershell
.\deploy.ps1 -Serial 4bbc97a9
```

### C. Windows, over the LAN (one phone or a whole range)

```powershell
.\deploy.ps1 -IPs 192.168.1.50
.\deploy.ps1 -Range 192.168.1.50-59
```

`deploy.ps1` uses `scp` + `ssh` (OpenSSH client, built into Windows 10+). Exit code is the
number of failures.

## Quick start

```sh
n2wifi scan                      # what is around?
n2wifi add "SiteB-5G" "password" # save it (does not disturb the current link)
n2wifi apply                     # make Android use it
```

Switching right now, in one step:

```sh
n2wifi join "SiteB-5G" "password"
```

After a reboot the phone reconnects on its own — the config is the platform's own store,
nothing is injected at boot.

## Commands

| Command | What it does |
|---|---|
| `n2wifi list` | List saved networks, marking the connected one |
| `n2wifi status` | Current SSID, signal, band, IP, and the saved list |
| `n2wifi ip` | Print just the IPv4 address (exit 2 if not connected) — handy in scripts |
| `n2wifi scan` | Scan nearby APs: signal / band / channel / security; merges same-SSID BSSes, keeps the strongest |
| `n2wifi scan --all` | Same, but every BSSID (see how many APs / roaming points a SSID has) |
| `n2wifi add <SSID> <pass>` | Write the network to the store (takes effect on the next reload/reboot) |
| `n2wifi add <SSID> --open` | Add an open network |
| `n2wifi join <SSID> <pass>` | `add` + `apply` |
| `n2wifi del <SSID>` | Remove a saved network (needs `apply` to take effect) |
| `n2wifi apply` | Make the framework reload the store — restarts `system_server` |
| `n2wifi backups` | List the automatic backups |
| `n2wifi revert [file]` | Restore a backup (default: newest), then `apply` |
| `--lang en\|zh` | Output language (default: from `LANG`, otherwise English) |

Exit codes: `0` ok, `1` error, `2` not connected (`ip`).

## How it works

1. **Find the store.** `/data/misc/wifi/WifiConfigStore.xml` (Android 7–10) or
   `/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml` (Android 11+). Override with
   `N2WIFI_XML=...`. Inside a chroot the path is reached through `/proc/1/root/...`.
2. **Clone, never invent.** A new `<Network>` block is cloned from the last saved network and
   only the fields that matter are rewritten (`SSID`, `ConfigKey`, `PreSharedKey`, key-mgmt
   bytes, status flags). Android's parser silently drops blocks with missing fields — a
   hand-written block without `CreationTime`, for example, vanishes on the next framework
   restart. Cloning keeps the format exactly as the system writes it, on every Android version.
3. **Write atomically.** New content goes to `WifiConfigStore.xml.n2tmp`, is re-parsed as XML
   and checked for `WifiConfigStoreData` + `NetworkList`, then `rename()`d over the original
   with owner `1000:1000` and mode `0600`. If the self-check fails, the original is untouched.
4. **Back up first.** Every write first copies the store to
   `WifiConfigStore.xml.n2bak-<YYYYmmdd-HHMMSS>` (a `-2`, `-3`… suffix is added when two writes
   land in the same second, so a backup is never clobbered).
5. **`apply` = restart `system_server`.** The framework only reads the store at startup, so
   `n2wifi` kills `system_server`; zygote exits, init starts a fresh one, and the new
   `system_server` re-reads the store. `netd` and `wpa_supplicant` are not restarted, so the
   link (and your ssh session) normally survives.

## What `apply` / `join` really does to your phone

- **AOSP-like ROMs:** the framework restarts in ~20–40 s, the Wi-Fi link blips, ssh usually
  stays up. This is the happy path.
- **Some vendor ROMs (e.g. MIUI 9 on the test device):** the death of `system_server` is treated
  as a system crash and the **phone reboots**. Your ssh session drops. The phone comes back in
  1–2 minutes with the new config active, which is still the right end state — just be ready
  for it, and do not run `join` on a phone you cannot power-cycle.

If you would rather avoid the surprise, use `n2wifi add` (write only) and let the config take
effect at the next reboot you were going to do anyway.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `error: must run as root (uid 0)` | not root | run inside the chroot / `su -c` |
| `error: cannot find the Wi-Fi config store` | Android ≤ 6, or an unusual ROM | `N2WIFI_XML=/data/.../WifiConfigStore.xml n2wifi list` |
| `error: iw not found` | no `iw` anywhere | `apt-get install -y iw` in the chroot, or use Android's `/system/bin/iw` |
| `scan failed: ... wlan0` | Wi-Fi is off / `wlan0` is down | `svc wifi enable`, wait ~10 s, scan again |
| `no AP found` | Wi-Fi off, or `wlan0` has no scan results yet | `svc wifi enable`, then `n2wifi scan` |
| ssh dies during `join` / `apply` | framework restart (or full reboot on some ROMs) | wait 1–2 min and reconnect; the config was already written |
| Phone unreachable after `join` | wrong SSID / password, or the AP is out of range | plug USB (`adb forward tcp:8022 tcp:8022`), or use a USB Ethernet adapter |
| Old network still connected after `add` | `add` only writes the file | `n2wifi apply` |
| Network disappears after a reboot | store format mismatch on that Android version | `n2wifi revert`, then send the `<Network>` block of your `WifiConfigStore.xml` in an issue |
| `WPA2 passphrase must be 8-63 characters` | invalid password length | — |

## FAQ

**Does it need the screen?** No. Everything is done over adb or ssh.

**Does it survive reboots / power loss?** Yes — it edits the config the platform itself uses.

**Does it work without root?** No. It writes `/data/misc/wifi` and restarts `system_server`.

**Can I script it?** `n2wifi ip` prints the address; exit codes are `0` / `1` / `2`.

**Does it support WEP / enterprise (802.1X)?** WEP no. WPA2-PSK and open networks, yes.
Enterprise networks are not handled by this tool.

**Is the Wi-Fi password stored in clear text?** It goes into `WifiConfigStore.xml` as
`PreSharedKey`, exactly like when you type it into the settings UI — same file, same format.

## License

MIT — see [LICENSE](LICENSE).
