# n2wifi

**Manage Wi-Fi from a terminal — scan, add, switch and roll back networks
without ever touching the screen.** Works on **Android**, on **NetworkManager**
distros and on plain **wpa_supplicant** systems, from one single file.

[中文说明](README.zh-CN.md)

```
$ n2wifi scan
2 APs, 2 distinct SSIDs:
  signal    band  chan  security    SSID
  -55 dBm   5G    36    WPA/WPA2    SiteA-5G   [connected,associated]
  -58 dBm   2.4G  6     WPA/WPA2    SiteA      [saved]
```

The same command against a NetworkManager host (no `iw` installed):

```
$ n2wifi scan
31 APs, 28 distinct SSIDs:
  signal    band  chan  security    SSID
  100%      2.4G  6     WPA1 WPA2   HomeNet
  87%       5G    36    WPA1 WPA2   HomeNet_5G   [connected]
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

On a normal Linux box the same commands drive whatever is actually in charge —
`nmcli` when NetworkManager owns the radio, `wpa_cli`/`wpa_supplicant.conf` when it does not.
You get one set of commands (`scan` / `list` / `add` / `join` / `del` / `revert`) instead of
remembering three different toolchains.

## Backends

| id | platform | config store | `apply` cost |
|---|---|---|---|
| `android` | Android 7+ | `/data/misc/wifi/WifiConfigStore.xml`, or `/data/misc/apexdata/com.android.wifi/…` on 11+ | restarts `system_server`, link blips 30–60 s |
| `nm` | NetworkManager (Debian/Ubuntu/Fedora/Arch desktop & server, postmarketOS) | `nmcli connection` profiles under `/etc/NetworkManager/system-connections/` | re-activates the profile, 1–3 s |
| `wpa` | wpa_supplicant (Raspbian Lite, pmOS, embedded, Android ≤6) | `wpa_supplicant.conf`, or the live control socket | `wpa_cli reconfigure`, usually <1 s |

Detection runs in that order and stops at the first match; `n2wifi backend` prints
what was picked and why. Override with `N2WIFI_BACKEND=android|nm|wpa`.

## Features

- `scan` — nearby APs with signal, band, channel and security, `[connected]` / `[saved]` tags
- `list` / `status` / `ip` — what is saved, what is connected, and a script-friendly IP
- `add` / `join` / `del` — add a network, add and switch to it now, or remove one
- `backend` — which backend was detected, which config file it uses, which interface
- **Safe writes** — atomic replace, self-check before commit, automatic timestamped
  backup for every write, and `revert`
- **A bad switch cannot strand you** — `join` arms a detached guard first and climbs a
  three-step ladder: backend autoconnect → radio power-cycle → rollback
  (`--strict` / `--check` / `--timeout` / `--bounce-wait` tune the decision)
- **Format-proof (Android)** — new entries are cloned from a block the system wrote itself,
  so field changes between Android versions do not silently drop your network
- **Never touches `wpa_supplicant` on Android** — the link keeps running while the config is rewritten
- **No hidden dependencies** — `iw` is used when present, `nmcli` takes over when it is not
- Single file, standard library only, bilingual CLI (`--lang en|zh`)

## Supported systems

| | |
|---|---|
| **Tested on (Android)** | Xiaomi Mi Note 2 (`scorpio`), Android 8.0 / MIUI 9, store `/data/misc/wifi/WifiConfigStore.xml` |
| **Tested on (NM)** | postmarketOS on Redmi Note 4X (musl, NM 1.4x): `backend`, `list`, `status`, `ip`, `scan` (nmcli fallback), `add`, `del`, `backups`, `revert` |
| **Tested on (wpa)** | Debian host with a synthetic `wpa_supplicant.conf`: `list`, `add`, `del`, `backups`, `revert` |
| **Expected to work** | Android 7.0–10 (same store format); any distro with NetworkManager ≥1.10 or wpa_supplicant ≥2.6 |
| **Android 11+** | Auto-detects `/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml`. Same `WifiConfigStoreData` XML, so it should work — **not tested yet** |
| **Not supported** | Android ≤ 6 (use `N2WIFI_BACKEND=wpa`), non-root shells, ROMs that keep Wi-Fi config somewhere else |

Requirements:

- **root** (uid 0) — writes to system config, and on Android also `kill system_server`
- **Python 3.6+** (standard library only)
- One of: `nmcli` + running NetworkManager, `wpa_cli`/`wpa_supplicant.conf`, or `iw`
  (`iw` is optional on the `nm` backend — scanning falls back to `nmcli`)
- `/proc` mounted

No Wi-Fi hardware? `scan` and `status` need a wireless interface; `add` / `del` work without it.
Set `N2WIFI_IFACE=wlp3s0` if auto-detection picks the wrong one.

## Install

One command (as root; **python3 gets installed if it is missing**):

```sh
curl -fsSL https://codeload.github.com/wvivi5/n2wifi/tar.gz/refs/heads/main \
  | tar xz -C /tmp && sh /tmp/n2wifi-main/install.sh
```

`n2wifi` itself is one file, but it needs python3. When the target does not have
it, `install.sh` installs it through whatever package manager the box has
(`apk` / `apt` / `dnf` / `yum` / `pacman` / `zypper` / `xbps` / `opkg` are all
recognised) and then carries on -- you will not be dropped into a "go fix your
dependencies" dead end. Use `--no-deps` (or `N2WIFI_NO_DEPS=1`) to keep it away
from the package manager; it will then tell you exactly which command to run.

### 0. Straight from GitHub (no local copy of the repo)

`n2wifi` is a single file, but **avoid** the `raw.githubusercontent.com`
one-liner -- that host is frequently reset (or resolves to IPv6 only) on
mainland networks, which shows up as `curl: (35) Recv failure: Connection
reset by peer`. Use one of these instead:

**0a. Grab the release tarball (no `git`, no `raw.` host)**

The [releases](https://github.com/wvivi5/n2wifi/releases/latest) carry a full package and the
single-file tool separately. The package is the easiest path:

```sh
curl -fL https://github.com/wvivi5/n2wifi/releases/latest/download/n2wifi-2.1.2.tar.gz | tar xz
cd n2wifi-2.1.2 && ./install.sh
```

If you only want the tool itself and would rather not run `install.sh` at all, download the
standalone `n2wifi` asset and drop it into your `PATH`.

**A. With `git` (recommended -- `git pull` upgrades later)**

```sh
git clone --depth 1 https://github.com/wvivi5/n2wifi.git
cd n2wifi && ./install.sh          # already root? skip sudo
```

The clone itself sometimes dies on HTTP/2 (`RPC failed; curl 16 Error in the
HTTP2 framing layer` / `fatal: expected flush after ref listing`). That is the
network, not your typing. Force HTTP/1.1 -- the repo is tiny, the slowdown does
not matter:

```sh
git -c http.version=HTTP/1.1 clone --depth 1 https://github.com/wvivi5/n2wifi.git
```

Still failing? Use B below (the tarball is 47 KB).

> If `sudo` itself is broken (`/etc/sudo.conf is owned by uid ...`, which happens
> on a rootfs that was unpacked as a non-root user), do not fix sudo -- log in as
> root and run `./install.sh` directly.

**B. Without `git`** -- grab the tarball from `codeload` (GitHub's archive
host, usually reachable):

```sh
curl -fsSL -o /tmp/n2wifi.tgz \
  https://codeload.github.com/wvivi5/n2wifi/tar.gz/refs/heads/main
mkdir -p /tmp/n2wifi && tar xzf /tmp/n2wifi.tgz -C /tmp/n2wifi --strip-components=1
sudo /tmp/n2wifi/install.sh
```

Then:

```sh
n2wifi --version && n2wifi backend
```

Upgrading is the same command again (`git pull`, or a fresh tarball); the
configuration, the `.n2bak-*` backups and the `.n2snap-*` snapshots are left
alone.

> Do not download `install.sh` on its own: it reads `n2wifi` from its **own
> directory** and fails with `error: ./n2wifi not found`.
>
> If `raw.githubusercontent.com` happens to work from your network, the
> single file is still the shortest route: `sudo curl -4 -fsSL -o
> /usr/local/bin/n2wifi https://raw.githubusercontent.com/wvivi5/n2wifi/main/n2wifi
> && sudo chmod 755 /usr/local/bin/n2wifi`

### A. On this machine (you already have a copy of the repo)

```sh
sudo ./install.sh                 # installs to /usr/local/bin/n2wifi and prints the backend
```

or by hand:

```sh
sudo install -m 755 n2wifi /usr/local/bin/n2wifi
n2wifi backend                    # what did it detect?
```

### B. Over ssh (the phone already has Wi-Fi)

```sh
./install.sh root@192.168.1.50 8022
```

or by hand:

```sh
scp -P 8022 n2wifi root@192.168.1.50:/usr/local/bin/n2wifi
ssh -p 8022 root@192.168.1.50 'chmod 755 /usr/local/bin/n2wifi && n2wifi --version'
```

### C. No Wi-Fi yet — USB bootstrap (the chicken-and-egg case)

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

### D. Windows, over the LAN (one host or a whole range)

```powershell
.\deploy.ps1 -IPs 192.168.1.50
.\deploy.ps1 -Range 192.168.1.50-59
.\deploy.ps1 -IPs 192.168.1.162 -Port 22      # a normal Linux host
```

`deploy.ps1` uses `scp` + `ssh` (OpenSSH client, built into Windows 10+). Exit code is the
number of failures.

## Quick start

```sh
n2wifi backend                   # which backend / config file / interface
n2wifi scan                      # what is around?
n2wifi add "SiteB-5G" "password" # save it (does not disturb the current link)
n2wifi apply                     # make the backend use it
```

Switching right now, in one step:

```sh
n2wifi join "SiteB-5G" "password"
```

After a reboot the machine reconnects on its own — the config is the platform's own store,
nothing is injected at boot.

## Commands

| Command | What it does |
|---|---|
| `n2wifi backend` | Which backend was detected, which config file it uses, which interface, and why |
| `n2wifi list` | List saved networks, marking the connected one |
| `n2wifi status` | Current SSID, signal, band, IP, and the saved list |
| `n2wifi ip` | Print just the IPv4 address (exit 2 if not connected) — handy in scripts |
| `n2wifi scan` | Scan nearby APs: signal / band / channel / security; merges same-SSID BSSes, keeps the strongest |
| `n2wifi scan --all` | Same, but every BSSID (see how many APs / roaming points a SSID has) |
| `n2wifi add <SSID> <pass>` | Write the network to the store (takes effect on the next reload/reboot) |
| `n2wifi add <SSID> --open` | Add an open network |
| `n2wifi join <SSID> <pass>` | `add` + `apply`, with automatic self-rescue (next section) |
| `n2wifi del <SSID>` | Remove a saved network (needs `apply` to take effect) |
| `n2wifi apply` | Make the backend reload its config (see the backend table for the cost) |
| `n2wifi guard` | What the last `join` guard decided, and why |
| `n2wifi backups` | List the automatic backups |
| `n2wifi revert [file]` | Restore a backup (default: newest), then `apply` |
| `--lang en\|zh` | Output language (default: from `LANG`, otherwise English) |

Exit codes: `0` ok, `1` error, `2` not connected (`ip`).

## Copy one box's Wi-Fi to the rest of them

`sync_wifi.sh` is not an n2wifi subcommand but a companion script: it reads every wireless profile
(SSID / password / priority) off one machine that is already on the network — usually the gateway —
and pushes them to the others.

```sh
sh sync_wifi.sh                 # default host list, offline machines are skipped
sh sync_wifi.sh max1 n04        # only these hosts (ssh aliases or IPs)
sh sync_wifi.sh --from max1     # use a different source box, default rn4x
```

- Idempotent: existing profiles get `nmcli connection modify` (password + priority), missing ones get `add`.
- **It never brings a profile up**, so the target's current ssh session is untouched. With `autoconnect=yes`
  the machine picks the best network by priority the next time it loses one.
- Priorities are copied as-is: 5G usually 100, 2.4G 10 — i.e. "5G preferred, 2.4G as the safety net".
- Targets need NetworkManager (`nmcli`). Android / wpa backends should use `n2wifi add` per network instead.

## A bad switch cannot strand the box: `join` rolls back

On a headless box Wi-Fi *is* the uplink. A failed `join` is therefore not "wrong network",
it is "the box is gone" — no ssh, no way in, until somebody power-cycles it.

So `join` carries a guard. **Before** the switch is applied it spawns a detached process
that watches the link and, if the switch fails, climbs a three-step ladder — cheapest first:

| Step | What happens | Cost | When it is enough |
|---|---|---|---|
| 0 | nothing: the backend's own `autoconnect` picks the old network back up | 1-3 s | most of the time, `nm` sorts itself out |
| 1 | turn the new profile's `autoconnect` off → **power-cycle the radio** (`nmcli radio wifi off/on`; `svc wifi disable/enable` on android; restart the supplicant on wpa) → wait `--bounce-wait` seconds | 3-30 s | the backend is stuck retrying the dead profile |
| 2 | put the pre-switch config back (android/wpa) / delete the new profile and activate the old one (nm) | seconds to minutes | the first two did not work |

The guard runs in its own session (`setsid`), so the ssh connection dying mid-switch
cannot kill the thing that is supposed to rescue you.

```
$ n2wifi join "SiteB" "password"
[ok] added: SiteB  (1 -> 2 networks)
[guard] safety net armed (pid 28411); was on: SiteA
        no uplink -> power-cycle the radio first, roll back only if that fails (timeout 60s, check=ip)
activating SiteB via NetworkManager ...
     [armed] armed: target=SiteB old=SiteA check=ip timeout=60s
     [bounce] no uplink after 60s (ssid=- ip=-); power-cycling the radio to let the backend re-pick a saved network
[ok] the switch failed but a radio power-cycle got the link back:
     radio power-cycle (nmcli radio wifi off/on) brought the link back on SiteA (192.168.1.9/24)

Connected : SiteA
...
```

If step 1 fails too, step 2 takes over and the output looks like this:

```
[!] switch failed -> rolled back: re-activated SiteA; back on SiteA (192.168.1.9/24)
     the new network was removed from the config; run join again to retry
```

Ask it later what it decided:

```sh
n2wifi guard          # last record: phase / target / old / msg
cat /run/n2wifi-guard.log
```

### What counts as a failure

| After the switch | Default | `--strict` |
|---|---|---|
| On the target network | success | success |
| Still on the old network (or another one) with an IP | **left alone**, only the new profile's `autoconnect` is turned back off | roll back |
| Associated to the target but DHCP never completes | roll back | roll back |
| No SSID / no IP at all | power-cycle the radio first, roll back if that fails | skip step 1, roll back |
| Nothing was connected before the switch | no rollback (nothing to go back to), only noted in the log | same |

How strictly "still has an uplink" is judged is `--check`:

| `--check` | Connected means |
|---|---|
| `link` | there is an SSID (or the interface carrier is up); IP is ignored |
| `ip` (default) | there is an IPv4 address |
| `ping` | IPv4 exists **and** the default gateway answers (catches "associated but dead") |

`--timeout N` is how long to give the new link *after* the switch was applied
(default 120 / 60 / 45 s for android / nm / wpa). `--bounce-wait N` is how long the
radio power-cycle gets to reconnect (default 30 s). `--no-bounce` skips step 1.
`--no-guard` turns the net off (the 2.0 behaviour).

### What the rollback actually does

| Backend | Rollback |
|---|---|
| `android` | copy `WifiConfigStore.xml` back from the pre-join snapshot → restart `system_server` → the old network reconnects |
| `wpa` | copy `wpa_supplicant.conf` back from the snapshot → `wpa_cli reconfigure` (or restart the service) |
| `nm` | `nmcli connection delete <new>` → `connection reload` → `connection up <old>` |

The snapshot is a sibling file `<config>.n2snap-prejoin` (mode `0600`), kept apart from the
`.n2bak-<timestamp>` backups so `backups` / `revert` never mix the two up.
Because the rollback restores the config as it was, **the newly added entry is gone after a
rollback** — just run `join` again to retry.

### What it cannot save you from

- **A broken config write** (right SSID/password, corrupt format): the rollback uses the same
  write path, so it can fail the same way. Use `n2wifi revert` to go back to a `.n2bak-*` backup.
- **You deleted the old network yourself** (`n2wifi del`, then found the new one does not work):
  there is no "old" left to return to; the guard says so in its log.
- **A reboot or a kernel hang** — that is not a Wi-Fi problem.
- **A radio that is really off** (`rfkill` hard block, driver crashed, chip not powered):
  the step-1 `radio off/on` cannot bring it back either, so you are left waiting for the
  rollback. Look at `dmesg`; no config change fixes that.
- The guard restores *connectivity*, not the *IP address* — DHCP may hand out a different
  address after changing AP, so reserve addresses on the router for these boxes.

### Same command, different backend

| | `android` | `nm` | `wpa` |
|---|---|---|---|
| `add` writes to | cloned `<Network>` block in the XML | a new profile with `autoconnect no` | `network={…}` appended to the conf, or `wpa_cli add_network` + `save_config` |
| `del` | removes the block | `nmcli connection delete` | removes the block / `remove_network` |
| `apply` | restart `system_server` (30–60 s) | `connection up`, 1–3 s | `wpa_cli reconfigure`, <1 s |
| `scan` source | `iw` (or `/system/bin/iw` via chroot) | `iw` if present, otherwise `nmcli device wifi list` | same as `nm` |
| backup target | `WifiConfigStore.xml.n2bak-*` | `*.nmconnection.n2bak-*` | `wpa_supplicant.conf.n2bak-*` |

`add` never switches the link on any backend: NetworkManager profiles are created with
`autoconnect no`, and the Android/wpa paths only touch the file. `join`/`apply` is what
actually activates.

## How it works

### Shared by every backend

- **Scan** uses `iw dev <iface> scan` when `iw` exists. If it does not (a stock
  postmarketOS has NetworkManager but no `iw`), `n2wifi` falls back to
  `nmcli -t -f BSSID,SSID,SIGNAL,FREQ,SECURITY device wifi list`, which reports signal as a
  percentage instead of dBm — the table shows `%` in that case. `iw` is also given up on if
  it is installed but the kernel refuses the scan.
- **Interface** is the first entry under `/sys/class/net/*/wireless`, else what
  `nmcli device status` calls a `wifi` device, else `wlan0`. Override with `N2WIFI_IFACE`.
- **Backups** are copies placed next to the original as `<file>.n2bak-<YYYYmmdd-HHMMSS>`;
  a `-2`, `-3`… suffix is added when two writes land in the same second. The newest 20 are
  kept and older ones are pruned, so a script in a loop cannot fill the disk.
- **`add` never activates anything** — see the per-backend table above.

### `android` backend

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
   `WifiConfigStore.xml.n2bak-<YYYYmmdd-HHMMSS>`.
5. **`apply` = restart `system_server`.** The framework only reads the store at startup, so
   `n2wifi` kills `system_server`; zygote exits, init starts a fresh one, and the new
   `system_server` re-reads the store. `netd` and `wpa_supplicant` are not restarted, but the
   framework restart does blip `wlan0` — an ssh session over Wi-Fi usually drops for ~30–60 s
   and then reconnects.

### `nm` backend

`add` runs `nmcli connection add type wifi con-name <SSID> ssid <SSID>
connection.autoconnect no` plus either `wifi-sec.key-mgmt wpa-psk wifi-sec.psk <pass>` or
`wifi-sec.key-mgmt none` for `--open`. The profile name is deliberately the SSID so that
`list` and `del` stay predictable. `del` snapshots the keyfile first, then
`nmcli connection delete`. `apply` flips `connection.autoconnect yes` and runs
`connection up`.

One gotcha this code handles: `nmcli -t` prints the raw settings name, so a Wi-Fi profile
appears as `802-11-wireless` rather than `wifi` — both spellings are accepted, otherwise
`list` looks empty on postmarketOS.

### `wpa` backend

If the control socket answers (`wpa_cli -i <iface> ping` → `PONG`), everything goes through
`wpa_cli`: `add_network`, `set_network … ssid/psk/key_mgmt`, `enable_network`, then
`save_config`. If `save_config` is refused (the socket is often read-only in containers),
it falls through to editing `wpa_supplicant.conf` directly. If there is no socket at all —
the normal case on a system where NetworkManager owns the radio — only the file is edited and
`apply` restarts the service.

The passphrase is written in plaintext inside quotes. That is valid for wpa_supplicant ≥2.0
and avoids a dependency on `wpa_passphrase`; the file is still `0600`.

## What `apply` / `join` really does to your phone

Measured on the test device (Mi Note 2, MIUI 9, Android 8.0):

- `system_server` is restarted and the new one is up in **~20–30 s**.
- The phone **does not reboot** — uptime keeps counting across `apply`.
- The Wi-Fi link blips while the framework comes back, so **your ssh session drops**
  and works again about 30–60 s later. The config is already on disk at that point;
  just reconnect.
- If you are connected through `adb forward` over USB: the USB gadget is owned by
  `system_server`, so adb disappears with it. Re-plug the cable or run
  `adb reconnect` (the phone keeps running).
- Some vendor ROMs do treat the death of `system_server` as a crash and reboot
  instead. It was not observed here, but it is out of this tool's control — if you
  cannot power-cycle the phone, use `n2wifi add` (write only) and let the config take
  effect at the next reboot you were going to do anyway.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `error: must run as root (uid 0)` | not root | run inside the chroot / `su -c` |
| `error: cannot find the Wi-Fi config store` | Android ≤ 6, or an unusual ROM | `N2WIFI_XML=/data/.../WifiConfigStore.xml n2wifi list` |
| `error: iw not found` | no `iw` anywhere | `apt-get install -y iw` in the chroot, or use Android's `/system/bin/iw` |
| `scan failed: ... wlan0` | Wi-Fi is off / `wlan0` is down | `svc wifi enable`, wait ~10 s, scan again |
| `no AP found` | Wi-Fi off, or `wlan0` has no scan results yet | `svc wifi enable`, then `n2wifi scan` |
| ssh dies during `join` / `apply` | the framework restart blips `wlan0` | wait ~1 min and reconnect; the config was already written, the phone never rebooted |
| adb disappears during `join` / `apply` (USB) | `system_server` owns the USB gadget and was restarted | re-plug the cable or `adb reconnect`; the phone keeps running |
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
