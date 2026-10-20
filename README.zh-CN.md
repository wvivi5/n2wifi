# n2wifi

**不开屏，从命令行管理 Android 手机的 WiFi —— 扫描、添加、切换、回滚，全程不用碰屏幕。**

[English](README.md)

```
$ n2wifi scan
扫到 2 个 AP（2 个不同 SSID）：
  信号      频段  信道  加密        SSID
  -55 dBm   5G    36    WPA/WPA2    SiteA-5G   [当前,associated]
  -58 dBm   2.4G  6     WPA/WPA2    SiteA      [已保存]
```

---

## 为什么需要它

无头 Android 设备（广告机、测试机、机顶盒、跑 Linux chroot + ssh 的手机）经常要改 WiFi，
但没有屏幕可点。

常规做法是 `wpa_cli`，可部分厂商 ROM（尤其是 MIUI）的 `wpa_supplicant` 控制口
**对第三方客户端完全不回包**：`PING`、`STATUS`、`SCAN` 全部超时，`wpa_cli` 直接废掉。

`n2wifi` 走另一条路：直接改系统自己的 WiFi 配置存储 `WifiConfigStore.xml`，
再让 Android 框架重新加载它。不需要屏幕、不碰 `wpa_supplicant` 控制口、不用 Xposed、不装 APK。

## 功能

- `scan` —— 扫周边 AP：信号 / 频段 / 信道 / 加密，并标出 `[当前]` / `[已保存]`
- `list` / `status` / `ip` —— 存了哪些、现在连哪个、给脚本用的纯 IP 输出
- `add` / `join` / `del` —— 只写入 / 写入并立即切换 / 删除
- **安全写入** —— 原子替换 + 提交前 XML 自检 + 每次写入都自动备份 + `revert` 回滚
- **不手写格式** —— 新条目从系统自己写的 `<Network>` 块克隆，Android 版本间的字段差异不会把你的网络悄悄丢掉
- **全程不碰 `wpa_supplicant`** —— 改配置时链路一直在跑
- 单文件、只用标准库、中英文输出（`--lang en|zh`）

## 可用的系统

| | |
|---|---|
| **实测通过** | 小米 Note 2（`scorpio`），Android 8.0 / MIUI 9，配置存储 `/data/misc/wifi/WifiConfigStore.xml` |
| **预期可用** | Android 7.0 ~ 10（配置存储的位置和格式都一样） |
| **Android 11+** | 自动识别 `/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml`。格式仍是同一套 `WifiConfigStoreData` XML，应该能用，但**尚未实测** |
| **不支持** | Android ≤ 6（那是 `wpa_supplicant.conf`，不是这个存储）、非 root、把 WiFi 配置放在别处的 ROM |

运行环境要求：

- **root**（uid 0）—— 要读写 `/data/misc/wifi`，还要能杀 `system_server`
- 你运行它的那个 shell 里要有 **Python 3.7+**（Linux chroot、Termux、或任意 root shell）
- **`iw`** —— chroot 里的 `iw`，或 Android 的 `/system/bin/iw`（自动识别）
- `/proc` 已挂载（Android 上总是满足）

没有 WiFi 硬件也能用：`add` / `del` 不需要 `wlan0`，只有 `scan` / `status` 需要。

## 安装

`n2wifi` 就是一个文件，复制到 `/usr/local/bin/n2wifi`（或任何在 `PATH` 里的地方）并给执行权限。

### A. 走 ssh（手机已经连着 WiFi）

```sh
./install.sh root@192.168.1.50 8022
```

或者手动：

```sh
scp -P 8022 n2wifi root@192.168.1.50:/usr/local/bin/n2wifi
ssh -p 8022 root@192.168.1.50 'chmod 755 /usr/local/bin/n2wifi && n2wifi --version'
```

### B. 还没配 WiFi —— 用 USB 先打通（先有鸡还是先有蛋）

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

### C. Windows 走局域网（单台或整段）

```powershell
.\deploy.ps1 -IPs 192.168.1.50
.\deploy.ps1 -Range 192.168.1.50-59
```

`deploy.ps1` 用 `scp` + `ssh`（Windows 10+ 自带 OpenSSH 客户端）。退出码 = 失败的台数。

## 快速上手

```sh
n2wifi scan                      # 周边有什么
n2wifi add "SiteB-5G" "password" # 先存进去（不影响当前连接）
n2wifi apply                     # 让 Android 用它
```

想立刻切过去，一条命令：

```sh
n2wifi join "SiteB-5G" "password"
```

重启之后手机会自己连回来 —— 因为写的是系统自己的配置存储，开机不需要任何注入。

## 命令

| 命令 | 作用 |
|---|---|
| `n2wifi list` | 列出已保存的网络，标出当前连的那个 |
| `n2wifi status` | 当前 SSID / 信号 / 频段 / IP + 已保存列表 |
| `n2wifi ip` | 只打印 IPv4 地址（未连接退出码 2），给脚本用 |
| `n2wifi scan` | 扫周边 AP：信号 / 频段 / 信道 / 加密；同名合并取最强 |
| `n2wifi scan --all` | 同上，但按 BSSID 全列（看一个 SSID 有几个 AP / 漫游点） |
| `n2wifi add <SSID> <密码>` | 写入配置存储（下次重载/重启生效），会做密码长度校验 |
| `n2wifi add <SSID> --open` | 加一个开放网络 |
| `n2wifi join <SSID> <密码>` | `add` + `apply` |
| `n2wifi del <SSID>` | 删除某个已保存网络（需要 `apply` 才生效） |
| `n2wifi apply` | 让框架重新加载配置 —— 重启 `system_server` |
| `n2wifi backups` | 列出自动备份 |
| `n2wifi revert [文件]` | 用备份恢复（默认最新），之后 `apply` |
| `--lang en\|zh` | 输出语言（默认看 `LANG`，都没有就用英文） |

退出码：`0` 成功，`1` 出错，`2` 未连接（`ip`）。

## 原理

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
