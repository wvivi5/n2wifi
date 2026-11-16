# n2wifi

**不开屏，从命令行管理 WiFi —— 扫描、添加、切换、回滚，全程不用碰屏幕。**
同一个文件，同时支持 **Android**、**NetworkManager** 发行版和纯 **wpa_supplicant** 系统。

[English](README.md)

```
$ n2wifi scan
扫到 2 个 AP（2 个不同 SSID）：
  信号      频段  信道  加密        SSID
  -55 dBm   5G    36    WPA/WPA2    SiteA-5G   [当前,associated]
  -58 dBm   2.4G  6     WPA/WPA2    SiteA      [已保存]
```

同一条命令，在一台没装 `iw` 的 NetworkManager 机器上（信号改按百分比显示）：

```
$ n2wifi scan
扫到 31 个 AP（28 个不同 SSID）：
  信号      频段  信道  加密        SSID
  100%      2.4G  6     WPA1 WPA2   HomeNet
  87%       5G    36    WPA1 WPA2   HomeNet_5G   [当前]
```

---

## 为什么需要它

无头 Android 设备（广告机、测试机、机顶盒、跑 Linux chroot + ssh 的手机）经常要改 WiFi，
但没有屏幕可点。

常规做法是 `wpa_cli`，可部分厂商 ROM（尤其是 MIUI）的 `wpa_supplicant` 控制口
**对第三方客户端完全不回包**：`PING`、`STATUS`、`SCAN` 全部超时，`wpa_cli` 直接废掉。

`n2wifi` 走另一条路：直接改系统自己的 WiFi 配置存储 `WifiConfigStore.xml`，
再让 Android 框架重新加载它。不需要屏幕、不碰 `wpa_supplicant` 控制口、不用 Xposed、不装 APK。

在普通 Linux 上，同一套命令驱动系统里真正干活的组件：NetworkManager 管着网卡就用 `nmcli`，
否则就退到 `wpa_cli` / `wpa_supplicant.conf`。你不用再记三套工具链，
`scan` / `list` / `add` / `join` / `del` / `revert` 一套到底。

## 三种后端

| 标识 | 平台 | 配置存储 | `apply` 代价 |
|---|---|---|---|
| `android` | Android 7+ | `/data/misc/wifi/WifiConfigStore.xml`，11+ 在 `/data/misc/apexdata/com.android.wifi/…` | 重启 `system_server`，链路抖 30~60 秒 |
| `nm` | NetworkManager（Debian/Ubuntu/Fedora/Arch 的桌面与服务器、postmarketOS） | `nmcli connection` 档案，位于 `/etc/NetworkManager/system-connections/` | 重新激活连接，1~3 秒 |
| `wpa` | wpa_supplicant（Raspbian Lite、pmOS、嵌入式、Android ≤6） | `wpa_supplicant.conf`，或活的控制口 | `wpa_cli reconfigure`，通常不到 1 秒 |

按上表顺序检测，命中即止；`n2wifi backend` 会打出选了哪个、依据是什么。
可以用 `N2WIFI_BACKEND=android|nm|wpa` 强制指定。

## 功能

- `scan` —— 扫周边 AP：信号 / 频段 / 信道 / 加密，并标出 `[当前]` / `[已保存]`
- `list` / `status` / `ip` —— 存了哪些、现在连哪个、给脚本用的纯 IP 输出
- `add` / `join` / `del` —— 只写入 / 写入并立即切换 / 删除
- `backend` —— 显示检测到哪个后端、用哪个配置文件、哪块网卡
- **安全写入** —— 原子替换 + 提交前自检 + 每次写入都自动备份 + `revert` 回滚
- **切坏了不会失联** —— `join` 前先放一个脱离会话的守卫，切完没网就按三级阶梯自救：
  后端自己回连 → 重启射频让系统自己挑 → 才回滚配置（`--strict` / `--check` / `--timeout` / `--bounce-wait` 可调）
- **不手写格式（Android）** —— 新条目从系统自己写的 `<Network>` 块克隆，Android 版本间的字段差异不会把你的网络悄悄丢掉
- **Android 上全程不碰 `wpa_supplicant`** —— 改配置时链路一直在跑
- **没有隐藏依赖** —— 有 `iw` 就用 `iw`，没有就自动改用 `nmcli`
- 单文件、只用标准库、中英文输出（`--lang en|zh`）

## 可用的系统

| | |
|---|---|
| **实测通过（Android）** | 小米 Note 2（`scorpio`），Android 8.0 / MIUI 9，配置存储 `/data/misc/wifi/WifiConfigStore.xml` |
| **实测通过（NM）** | 红米 Note 4X 上的 postmarketOS（musl，NM 1.4x）：`backend`、`list`、`status`、`ip`、`scan`（无 iw，走 nmcli 兜底）、`add`、`del`、`backups`、`revert` |
| **实测通过（wpa）** | Debian 主机 + 造的 `wpa_supplicant.conf`：`list`、`add`、`del`、`backups`、`revert` |
| **预期可用** | Android 7.0 ~ 10（配置存储的位置和格式都一样）；任何带 NetworkManager ≥1.10 或 wpa_supplicant ≥2.6 的发行版 |
| **Android 11+** | 自动识别 `/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml`。格式仍是同一套 `WifiConfigStoreData` XML，应该能用，但**尚未实测** |
| **不支持** | Android ≤ 6（改用 `N2WIFI_BACKEND=wpa`）、非 root、把 WiFi 配置放在别处的 ROM |

运行环境要求：

- **root**（uid 0）—— 要写系统配置，Android 上还要能杀 `system_server`
- **Python 3.6+**（只用标准库）
- 三者之一：`nmcli` + 运行中的 NetworkManager、`wpa_cli`/`wpa_supplicant.conf`、或 `iw`
  （`nm` 后端上 `iw` 是可选的，扫描会退回 `nmcli`）
- `/proc` 已挂载

没有 WiFi 硬件也能用：`add` / `del` 不需要网卡，只有 `scan` / `status` 需要。
自动探测选错网卡时用 `N2WIFI_IFACE=wlp3s0` 指定。

## 安装

`n2wifi` 就是一个文件，复制到 `/usr/local/bin/n2wifi`（或任何在 `PATH` 里的地方）并给执行权限。

### 0. 直接从 GitHub 装（手上没有仓库副本）

`n2wifi` 只有一个文件，但**不建议**用 `raw.githubusercontent.com` 那行 curl ——
这个域名在国内经常被 RST（`curl: (35) Recv failure: Connection reset by peer`），
而且它只解析出 IPv6 的时候更会直接失败。用下面两条中的任意一条：

**A. 有 `git`（推荐，一次 clone 之后还能 `git pull` 升级）**

```sh
git clone --depth 1 https://github.com/wvivi5/n2wifi.git
cd n2wifi && ./install.sh          # 已经是 root 就直接跑，不用 sudo
```

clone 有时会失败在 HTTP/2 上（`RPC failed; curl 16 Error in the HTTP2 framing
layer` / `fatal: expected flush after ref listing`），这是网络层的问题，不是你
敲错了。退到 HTTP/1.1 再试，体积很小，慢一点无所谓：

```sh
git -c http.version=HTTP/1.1 clone --depth 1 https://github.com/wvivi5/n2wifi.git
```

还不行就直接走下面的 B（tarball 只有 47 KB）。

> `sudo` 本身坏掉的时候（`/etc/sudo.conf is owned by uid ...`，常见于用 tar 解压
> 覆盖过系统目录的机器）就别修 sudo 了 —— root 登录后直接 `./install.sh`。

**B. 没有 `git`** —— 从 `codeload`（GitHub 的打包下载域名，通常通）拿 tarball：

```sh
curl -fsSL -o /tmp/n2wifi.tgz \
  https://codeload.github.com/wvivi5/n2wifi/tar.gz/refs/heads/main
mkdir -p /tmp/n2wifi && tar xzf /tmp/n2wifi.tgz -C /tmp/n2wifi --strip-components=1
sudo /tmp/n2wifi/install.sh
```

装完确认：

```sh
n2wifi --version && n2wifi backend
```

升级就是重跑上面那条（`git pull` 或重新下 tarball）；配置文件、`.n2bak-*`
备份、`.n2snap-*` 快照都不会被动。

> 别只下 `install.sh`：它要读**同目录**下的 `n2wifi`，单独下会直接报
> `error: ./n2wifi not found`。
>
> 如果你那边 `raw.githubusercontent.com` 恰好能通，也可以直接拿单文件：
> `sudo curl -4 -fsSL -o /usr/local/bin/n2wifi https://raw.githubusercontent.com/wvivi5/n2wifi/main/n2wifi && sudo chmod 755 /usr/local/bin/n2wifi`

### A. 装在本机（已经有仓库副本：git clone 或解压 zip 之后）

```sh
sudo ./install.sh          # 装到 /usr/local/bin/n2wifi，并打印检测到的后端
```

或者手动：

```sh
sudo install -m 755 n2wifi /usr/local/bin/n2wifi
n2wifi backend             # 看看它识别成了什么
```

### B. 走 ssh（手机已经连着 WiFi）

```sh
./install.sh root@192.168.1.50 8022
```

或者手动：

```sh
scp -P 8022 n2wifi root@192.168.1.50:/usr/local/bin/n2wifi
ssh -p 8022 root@192.168.1.50 'chmod 755 /usr/local/bin/n2wifi && n2wifi --version'
```

### C. 还没配 WiFi —— 用 USB 先打通（先有鸡还是先有蛋）

插上 USB，把手机的 ssh 端口用 adb 转发出来，再推：

```sh
adb forward tcp:8022 tcp:8022
scp -P 8022 n2wifi root@127.0.0.1:/usr/local/bin/n2wifi
ssh -p 8022 root@127.0.0.1 'chmod 755 /usr/local/bin/n2wifi && n2wifi scan'
```

Windows 一条命令：

```powershell
.\deploy.ps1 -Serial 4bbc97a9
```

### D. Windows 走局域网（单台或整段）

```powershell
.\deploy.ps1 -IPs 192.168.1.50
.\deploy.ps1 -Range 192.168.1.50-59
.\deploy.ps1 -IPs 192.168.1.162 -Port 22      # 普通 Linux 主机
```

`deploy.ps1` 用 `scp` + `ssh`（Windows 10+ 自带 OpenSSH 客户端）。退出码 = 失败的台数。

## 快速上手

```sh
n2wifi backend                   # 先看检测到哪个后端 / 哪个配置文件 / 哪块网卡
n2wifi scan                      # 周边有什么
n2wifi add "SiteB-5G" "password" # 先存进去（不影响当前连接）
n2wifi apply                     # 让后端用它
```

想立刻切过去，一条命令：

```sh
n2wifi join "SiteB-5G" "password"
```

重启之后机器会自己连回来 —— 因为写的是系统自己的配置存储，开机不需要任何注入。

## 命令

| 命令 | 作用 |
|---|---|
| `n2wifi backend` | 显示检测到的后端、用的配置文件、网卡，以及判断依据 |
| `n2wifi list` | 列出已保存的网络，标出当前连的那个 |
| `n2wifi status` | 当前 SSID / 信号 / 频段 / IP + 已保存列表 |
| `n2wifi ip` | 只打印 IPv4 地址（未连接退出码 2），给脚本用 |
| `n2wifi scan` | 扫周边 AP：信号 / 频段 / 信道 / 加密；同名合并取最强 |
| `n2wifi scan --all` | 同上，但按 BSSID 全列（看一个 SSID 有几个 AP / 漫游点） |
| `n2wifi add <SSID> <密码>` | 写入配置（下次重载/重启生效），会做密码长度校验 |
| `n2wifi add <SSID> --open` | 加一个开放网络 |
| `n2wifi join <SSID> <密码>` | `add` + `apply`，切坏了自动自救（见下节） |
| `n2wifi del <SSID>` | 删除某个已保存网络（需要 `apply` 才生效） |
| `n2wifi apply` | 让后端重新加载配置（代价见上面的后端表） |
| `n2wifi guard` | 上一次 `join` 的守卫判了什么、为什么 |
| `n2wifi backups` | 列出自动备份 |
| `n2wifi revert [文件]` | 用备份恢复（默认最新），之后 `apply` |
| `--lang en\|zh` | 输出语言（默认看 `LANG`，都没有就用英文） |

退出码：`0` 成功，`1` 出错，`2` 未连接（`ip`）。

## 切坏了就失联？`join` 会自己回滚

无头机器的 WiFi 就是唯一的上联。所以一次失败的 `join` 不是"连错了网络"，
而是"机器没了" —— 没有 ssh、进不去，只能等人去断电重启。

`join` 因此默认带一个守卫（guard）：**在生效之前**先起一个脱离会话的进程，
它盯着链路，切坏了就按三级阶梯自救 —— 越靠前越便宜：

| 级 | 动作 | 代价 | 什么时候用得上 |
|---|---|---|---|
| 0 | 什么都不做，让后端自己的 `autoconnect` 把旧网络接回来 | 1~3 秒 | 大多数情况，`nm` 会自己搞定 |
| 1 | 把新档案的 `autoconnect` 关掉 → **重启射频**（`nmcli radio wifi off/on`；android 用 `svc wifi disable/enable`；wpa 重启 supplicant）→ 等 `--bounce-wait` 秒 | 3~30 秒 | 后端卡在坏档案上、不肯自己挑别的时候 |
| 2 | 把切换前的配置原样放回去（android/wpa）／删掉新档案并激活旧档案（nm） | 秒级~分钟级 | 前两级都没救回来 |

守卫自己一个 session（`setsid`），生效过程中 ssh 被掐断也不会把它带走。

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

如果第 1 级也没救回来，第 2 级才会动手，那时输出是回滚：

```
[!] switch failed -> rolled back: re-activated SiteA; back on SiteA (192.168.1.9/24)
     the new network was removed from the config; run join again to retry
```

事后随时可以看它当时的判断：

```sh
n2wifi guard          # 最后一条记录：phase / target / old / msg
cat /run/n2wifi-guard.log
```

### 什么算"失败"——默认只在真的会失联时才回滚

| 切完的状态 | 默认行为 | `--strict` |
|---|---|---|
| 连上了目标网络 | 成功 | 成功 |
| 还连着旧网络（或别的网络），有 IP | **不动它**，只把新档案的 `autoconnect` 关掉 | 回滚 |
| 关联上了但 DHCP 拿不到 IP | 回滚 | 回滚 |
| 彻底没有 SSID / 没有 IP | 先重启射频，还不行就回滚 | 跳过第 1 级，直接回滚 |
| 机器本来就没连过任何网络 | 不回滚（没得回），只在日志里说明 | 同左 |

判断"还有没有上联"的严格程度由 `--check` 控制：

| `--check` | 算连上的条件 |
|---|---|
| `link` | 有 SSID（或网卡 carrier up），不看 IP |
| `ip`（默认） | 拿到 IPv4 地址 |
| `ping` | 有 IPv4，且默认网关 ping 得通（能抓"连上了但网是死的"） |

`--timeout N` 是"生效之后最多等多久"（默认 android 120 / nm 60 / wpa 45 秒）。
`--bounce-wait N` 是"重启射频之后给它多久自己连回来"（默认 30 秒）。
`--no-bounce` 跳过第 1 级，直接回滚。
`--no-guard` 关掉安全网，回到 2.0 的老行为。

### 回滚具体做了什么

| 后端 | 回滚动作 |
|---|---|
| `android` | 把 `WifiConfigStore.xml` 覆盖回切换前的快照 → 重启 `system_server` → 旧网络重新连上 |
| `wpa` | 把 `wpa_supplicant.conf` 覆盖回快照 → `wpa_cli reconfigure`（或重启服务） |
| `nm` | `nmcli connection delete <新档案>` → `connection reload` → `connection up <旧档案>` |

快照是配置文件旁边的 `<文件>.n2snap-prejoin`（权限 `0600`），
和 `.n2bak-<时间戳>` 那套自动备份分开，**不会**被 `backups` / `revert` 混进来。
因为回滚是把配置恢复到切换前，**新加的条目在回滚后就没了** —— 要重试就再跑一次 `join`。

### 它救不了什么

- **配置本身写坏了**（SSID/密码对，但格式坏了导致后端起不来）：回滚用的是同一套写入路径，
  同样可能坏。这种用 `n2wifi revert` 退到 `.n2bak-*` 备份。
- **你亲手把旧网络删了**（`n2wifi del` 之后才发现新的连不上）：没有"旧的"可回，守卫只会在日志里说清楚。
- **整机重启 / 内核卡死**：那不是 WiFi 的问题。
- **射频被彻底关掉**（`rfkill` hard block、驱动崩了、Wi-Fi 芯片没上电）：第 1 级的
  `radio off/on` 也开不回来，只能回滚配置干等 —— 这种要看 `dmesg`，不是配置能修的。
- 守卫只能保证"网络回来"，**不保证 IP 不变** —— 换 AP 之后 DHCP 给的新地址可能不一样，
  ssh 要用新 IP 连（这也是为什么建议在路由器上给这些机器做 DHCP 保留）。

### 同一条命令，三个后端分别做了什么

| | `android` | `nm` | `wpa` |
|---|---|---|---|
| `add` 写到哪 | XML 里克隆出的 `<Network>` 块 | 新档案，`autoconnect no` | 追加 `network={…}` 到 conf，或 `wpa_cli add_network` + `save_config` |
| `del` | 删掉那个块 | `nmcli connection delete` | 删块 / `remove_network` |
| `apply` | 重启 `system_server`（30~60 秒） | `connection up`，1~3 秒 | `wpa_cli reconfigure`，不到 1 秒 |
| `scan` 数据源 | `iw`（或 chroot 里的 `/system/bin/iw`） | 有 `iw` 用 `iw`，没有就 `nmcli device wifi list` | 同 `nm` |
| 备份目标 | `WifiConfigStore.xml.n2bak-*` | `*.nmconnection.n2bak-*` | `wpa_supplicant.conf.n2bak-*` |

三种后端上 `add` 都**不会**让链路切过去：NetworkManager 档案建的时候就带
`autoconnect no`，Android 和 wpa 只动文件。真正激活的是 `join` / `apply`。

## 原理

### 三个后端共用的部分

- **扫描**有 `iw` 就 `iw dev <网卡> scan`。没有 `iw`（比如原版 postmarketOS 有
  NetworkManager 却没装 `iw`）就退回 `nmcli -t -f BSSID,SSID,SIGNAL,FREQ,SECURITY
  device wifi list`——这种方式信号是百分比而不是 dBm，表格里就显示 `%`。
  `iw` 存在但内核拒绝扫描时，也会自动改用 `nmcli`。
- **网卡**取 `/sys/class/net/*/wireless` 里的第一个，没有就问 `nmcli device status`
  哪个是 `wifi`，再没有就 `wlan0`。可用 `N2WIFI_IFACE` 覆盖。
- **备份**是原文件旁边的一份副本 `<文件>.n2bak-<年月日-时分秒>`，同一秒内第二次写入
  会加 `-2`、`-3` 后缀。只保留最近 20 份，更旧的自动清理，脚本跑循环也塞不满磁盘。
- **`add` 一律不激活**，见上表。

### `android` 后端

1. **定位存储。** `/data/misc/wifi/WifiConfigStore.xml`（Android 7~10）或
   `/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml`（Android 11+）。
   可用环境变量 `N2WIFI_XML=...` 强制指定。在 chroot 里通过 `/proc/1/root/...` 访问。
2. **克隆，而不是手写。** 新的 `<Network>` 块从最后一个已保存网络克隆，只改关键字段
   （`SSID`、`ConfigKey`、`PreSharedKey`、key-mgmt 字节、状态标志）。Android 的解析器会
   静默丢掉缺字段的块 —— 比如缺 `CreationTime` 的块，框架下一次重启就没了。克隆能保证
   格式和系统自己写出来的**完全一致**，跨 Android 版本也稳。
3. **原子写入。** 新内容先写到 `WifiConfigStore.xml.n2tmp`，重新按 XML 解析并校验
   `WifiConfigStoreData` + `NetworkList`，再 `rename()` 覆盖原文件，属主 `1000:1000`、
   权限 `0600`。自检不过就放弃，原文件一个字节都不动。
4. **先备份。** 每次写入前都会复制成 `WifiConfigStore.xml.n2bak-<年月日-时分秒>`；
   同一秒内第二次写入会加 `-2`、`-3` 后缀，**备份永远不会互相覆盖**。
5. **`apply` = 重启 `system_server`。** 框架只在启动时读这个存储，所以 `n2wifi` 杀掉
   `system_server`；zygote 跟着退出，init 再拉起一个新的，新框架重新读配置。
   `netd` 和 `wpa_supplicant` 不重启，但框架重启时 `wlan0` 会抖一下 —— 走 WiFi 的 ssh
   通常会断 30~60 秒，然后自己连回来。

### `nm` 后端

`add` 执行 `nmcli connection add type wifi con-name <SSID> ssid <SSID>
connection.autoconnect no`，再加 `wifi-sec.key-mgmt wpa-psk wifi-sec.psk <密码>`
（`--open` 则是 `wifi-sec.key-mgmt none`）。档案名故意用 SSID，这样 `list` / `del`
的行为可预测。`del` 先快照 keyfile 再 `nmcli connection delete`。`apply` 把
`connection.autoconnect` 改回 `yes` 并 `connection up`。

这里有个必须处理的坑：`nmcli -t` 打印的是**原始设置名**，WiFi 档案显示成
`802-11-wireless` 而不是 `wifi`（`wifi` 只是非 `-t` 模式下的美化输出）。
两种写法都接受，否则在 postmarketOS 上 `list` 会是空的。

### `wpa` 后端

控制口能用（`wpa_cli -i <网卡> ping` 返回 `PONG`）时全走 `wpa_cli`：
`add_network`、`set_network … ssid/psk/key_mgmt`、`enable_network`，然后 `save_config`。
`save_config` 被拒（容器里控制口常常是只读的）就退回去直接改 `wpa_supplicant.conf`。
完全没有控制口时——也就是 NetworkManager 管着网卡的常见情况——只改文件，`apply` 重启服务。

密码以明文写在引号里。wpa_supplicant ≥2.0 都接受这种写法，也就不用依赖
`wpa_passphrase`；文件权限仍是 `0600`。

## `apply` / `join` 到底会把手机怎么样

在实测机（小米 Note 2，MIUI 9 / Android 8.0）上的实测结果：

- `system_server` 被重启，新的在 **约 20~30 秒**内起来。
- 手机**不会重启** —— 连续两次 `apply` 前后 `uptime` 一直连续。
- 框架回来时 WiFi 会抖一下，所以**你的 ssh 会断**，大约 30~60 秒后能重连。
  这时候配置早就写进磁盘了，重连就行。
- 如果是走 USB 的 `adb forward`：USB gadget 归 `system_server` 管，它会跟着消失。
  重新插拔线或 `adb reconnect`（手机一直在跑）。
- 个别厂商 ROM 确实会把 `system_server` 的死亡当成崩溃而整机重启。实测机没有出现，
  但这不归本工具控制 —— 如果你没法给手机断电重启，就用 `n2wifi add`（只写文件），
  等你下次本来就要重启的时候自然生效。

## 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `error: must run as root (uid 0)` | 不是 root | 进 chroot，或 `su -c` 运行 |
| `error: cannot find the Wi-Fi config store` | Android ≤ 6，或 ROM 放别处 | `N2WIFI_XML=/data/.../WifiConfigStore.xml n2wifi list` |
| `error: iw not found` | 哪都没有 `iw` | chroot 里 `apt-get install -y iw`，或用 Android 的 `/system/bin/iw` |
| `scan failed: ... wlan0` | WiFi 关着 / `wlan0` 没起来 | `svc wifi enable`，等 ~10 秒再扫 |
| `no AP found` | WiFi 关着，或还没有扫描结果 | `svc wifi enable` 后重新 `n2wifi scan` |
| `join` / `apply` 时 ssh 断了 | 框架重启时 `wlan0` 抖了一下 | 等 ~1 分钟重连，配置已经写进去了，手机没重启 |
| USB 下 `join` / `apply` 后 adb 不见了 | USB gadget 归 `system_server` 管，它被重启了 | 重新插拔线或 `adb reconnect`，手机一直在跑 |
| `join` 之后彻底联系不上 | SSID / 密码写错，或 AP 不在范围内 | 插 USB `adb forward tcp:8022 tcp:8022`，或用 USB 有线网卡 |
| `add` 之后还是连老的网络 | `add` 只写文件 | `n2wifi apply` |
| 重启后网络又没了 | 该 Android 版本的存储格式不同 | `n2wifi revert`，然后把 `WifiConfigStore.xml` 里的 `<Network>` 块发到 issue |
| `WPA2 passphrase must be 8-63 characters` | 密码长度不合法 | — |

## 常见问题

**需要屏幕吗？** 不需要，全部通过 adb 或 ssh 完成。

**重启 / 断电后还在吗？** 在。改的是系统自己用的配置存储。

**不用 root 能用吗？** 不能。要写 `/data/misc/wifi`，还要重启 `system_server`。

**能给脚本用吗？** `n2wifi ip` 只打印地址；退出码 `0` / `1` / `2`。

**支持 WEP / 企业级（802.1X）吗？** WEP 不支持；支持 WPA2-PSK 和开放网络。
企业级网络这个工具不处理。

**密码是明文存的吗？** 存在 `WifiConfigStore.xml` 的 `PreSharedKey` 里，和你在设置界面里
手动输入密码后的存法、位置、格式完全一样。

## 许可证

MIT，见 [LICENSE](LICENSE)。
