# Clash Verge 配置迁移指南（macOS）

把一台 Mac 上已经调好的 Clash Verge 配置，完整搬到另一个系统账户（或另一台 Mac）上。
包括：订阅节点、策略组、分流规则、端口设置、界面偏好——搬完之后打开就能直接用，不用重新导入订阅、不用重新调设置。

本文记录了一次真实迁移的完整过程与原理。

---

## 目录

- [一、先搞清楚：Clash Verge 的配置存在哪](#一先搞清楚clash-verge-的配置存在哪)
- [二、迁移原理：两个系统之间是怎么打通的](#二迁移原理两个系统之间是怎么打通的)
- [三、动手之前：必须退出 Clash Verge](#三动手之前必须退出-clash-verge)
- [四、完整迁移步骤](#四完整迁移步骤)
- [五、哪些文件必须迁，哪些不要迁](#五哪些文件必须迁哪些不要迁)
- [六、迁移完成后的验证](#六迁移完成后的验证)
- [七、安全须知（重要）](#七安全须知重要)
- [八、常见问题](#八常见问题)

---

## 一、先搞清楚：Clash Verge 的配置存在哪

Clash Verge（含 Clash Verge Rev）在 macOS 上**不使用** `~/.config`，也不使用 `~/.clash`。
它的全部数据都放在下面这一个目录里：

```
~/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/
```

> 注意最后那段目录名，它是应用的 Bundle ID。Clash Verge Rev 的 ID 是
> `io.github.clash-verge-rev.clash-verge-rev`。
> 老版本的 Clash Verge 可能是 `io.github.clash-verge-rev.clash-verge` 或
> `clash-verge`，迁移前先确认自己用的是哪个。

目录里的内容分工如下：

| 文件 / 目录 | 作用 | 迁移时 |
|---|---|---|
| `profiles/` | **所有订阅文件本体**（下载回来的节点配置、规则、脚本） | **必须迁** |
| `profiles.yaml` | 订阅索引：哪个订阅是当前使用的、订阅的 URL、策略组选择记忆 | **必须迁** |
| `verge.yaml` | 应用偏好设置：端口、TUN、系统代理开关、界面、延迟测试项 | **必须迁** |
| `config.yaml` | 内核启动参数（端口、external-controller、TUN 等） | 建议迁 |
| `dns_config.yaml` | Clash Verge 的 DNS 覆写设置 | 建议迁 |
| `icons/` | 自定义策略组图标 | 可选 |
| `test/` | 延迟测试用的资源 | 可选 |
| `geoip.dat` `geosite.dat` `Country.mmdb` `ASN.mmdb` | GeoIP / GeoSite 数据库（各十几 MB） | **不用迁**，新版应用会自带或自动下载 |
| `cache.db` | 运行时缓存 | **不要迁** |
| `singleton-instance.json` / `.lock` | 单实例锁 | **不要迁** |
| `logs/` `service-logs/` | 日志 | **不要迁** |

**关键点**：真正承载你"配置成果"的其实只有三个——`profiles/`、`profiles.yaml`、`verge.yaml`。
其余要么是运行时产物，要么是能自动重新生成的。

---

## 二、迁移原理：两个系统之间是怎么打通的

### 场景说明

本文对应的场景是：**同一台 Mac 上存在两个系统账户**。

| 角色 | 账户名 | 家目录 |
|---|---|---|
| 旧系统（配置来源） | `yg` | `/Users/yg` |
| 新系统（配置目标） | `zz` | `/Users/zz` |

当前登录的是 `zz`，我们要从 `yg` 那里把配置拿过来。

### 为什么能直接读到另一个账户的文件

这是 macOS 的**卷结构**决定的，也是整个迁移能"零工具"完成的原因。

macOS 从 Catalina 开始把系统拆成两个卷：

```
Macintosh HD          →  系统卷，只读，挂载在 /
Macintosh HD - Data   →  数据卷，可写，挂载在 /System/Volumes/Data
```

而 `/Users` 实际是数据卷上的目录，通过 firmlink 映射过来。所以：

```
/Users/yg
```

和

```
/Volumes/Macintosh HD - Data/Users/yg
```

**指向的是同一份数据**。只要当前账户对 `/Users/yg` 有读权限，就能像访问自己文件一样直接读。

于是两个账户下的配置目录，路径一一对应：

| | 旧账户 yg | 新账户 zz |
|---|---|---|
| 配置目录 | `/Volumes/Macintosh HD - Data/Users/yg/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev` | `/Users/zz/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev` |

> 也可以直接写 `/Users/yg/Library/Application Support/...`，两种路径等价。
> 用 `/Volumes/Macintosh HD - Data/...` 这种写法更稳，因为它不依赖 firmlink。

### 如果不是同一台机器呢

原理不变，只是"源路径"换成挂载点：

- **外接硬盘 / Time Machine 备份**：源路径变成 `/Volumes/你的硬盘/Users/yg/Library/Application Support/...`
- **网络共享**：先 `mount_smbfs` 或 Finder 连接，然后同样按上面的相对路径找
- **迁移助理**：它会把整个家目录搬过来，配置目录自然也在里面

所以记住这条核心公式就够了：

```
<任意可访问的根>/Users/<旧账户名>/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev
                       ↓ 复制
/Users/<新账户名>/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev
```

---

## 三、动手之前：必须退出 Clash Verge

这一步是**最容易忽略、也最容易导致迁移失败**的地方。

Clash Verge 在运行时会：

1. 在内存里持有配置，退出时可能**把内存版本写回磁盘**——你刚复制过去的文件会被覆盖回去；
2. 持续写 `cache.db`、`logs/`、`singleton-instance.json`；
3. 内核 `verge-mihomo` 会重新生成 `clash-verge.yaml`。

所以顺序一定是：**退出 → 复制 → 启动**，不能反过来。

退出方式：

```bash
# 优雅退出
osascript -e 'quit app "Clash Verge"'

# 确认主程序与内核都已退出
pgrep -fl "Clash Verge|verge-mihomo"
```

如果还有残留进程，强制结束：

```bash
pkill -f "Clash Verge"
pkill -f "verge-mihomo"
```

两个进程都消失后，才可以开始复制。

> `verge-mihomo` 是 Clash Verge 内置的 Clash.Meta 内核进程，
> 它会以 `-d <配置目录> -f <配置目录>/clash-verge.yaml` 的参数运行，
> 从进程参数就能看出它正在用哪个目录——这也是判断"配置到底生效在哪个路径"的好办法。

---

## 四、完整迁移步骤

### 第 1 步：备份目标端现有配置

**永远先备份。** 目标端可能已经有一份自己生成的默认配置，虽然价值不高，但回滚时能救命。

```bash
cp -R "/Users/zz/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev" \
      "/Users/zz/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev.backup-$(date +%Y%m%d-%H%M%S)"
```

### 第 2 步：退出 Clash Verge

见上一节。

### 第 3 步：复制配置文件

设两个变量，后面好写：

```bash
SRC="/Volumes/Macintosh HD - Data/Users/yg/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
DST="/Users/zz/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
```

复制三个核心文件：

```bash
cp -f "$SRC/profiles.yaml" "$DST/profiles.yaml"
cp -f "$SRC/verge.yaml"    "$DST/verge.yaml"
cp -f "$SRC/dns_config.yaml" "$DST/dns_config.yaml"
cp -f "$SRC/config.yaml"   "$DST/config.yaml"
```

复制订阅目录（注意 `/.` 的写法，表示"把源目录**里面**的内容合进目标目录"，
这样不会因为目标目录已存在而失败，也不会删掉目标里已有的文件）：

```bash
cp -R "$SRC/profiles/." "$DST/profiles/"
```

可选：图标

```bash
cp -R "$SRC/icons/." "$DST/icons/" 2>/dev/null
```

### 第 4 步：校对

确认关键文件字节数一致：

```bash
diff "$SRC/profiles.yaml" "$DST/profiles.yaml" && echo "profiles.yaml 一致"
diff "$SRC/verge.yaml"    "$DST/verge.yaml"    && echo "verge.yaml 一致"
ls -l "$DST/profiles/"
```

`profiles/` 里应该能看到原来所有的订阅文件、规则模板、脚本文件。

### 第 5 步：启动并验证

```bash
open -a "Clash Verge"
```

然后看内核有没有正常起来：

```bash
pgrep -fl "Clash Verge|verge-mihomo"
```

### 第 6 步（可选）：直接跑脚本

仓库里附了一个把上面步骤串起来的脚本：

```bash
./scripts/migrate-clash-verge.sh --src-user yg --dst-user zz
```

脚本会做：检查进程并提示退出 → 备份目标端 → 复制三类核心文件与 `profiles/` → 打印校验结果。
详细用法见脚本头部注释。

---

## 五、哪些文件必须迁，哪些不要迁

### 必须迁

- **`profiles/`** —— 订阅本体。里面通常有两类东西：
  - 远程订阅下载后缓存的文件（体积大，几百 KB 到几 MB，内容包含 `proxies:` 节点列表）
  - 各种增强模板：`Merge.yaml`（合并覆写）、`Script.js`（脚本处理后置）、
    `rules.yaml`（规则增删）、`proxies.yaml`（节点增删）、`groups.yaml`（策略组增删）、
    以及你可能自己写的自定义脚本
- **`profiles.yaml`** —— 订阅索引。它记录了：
  - `current:` 当前使用的是哪个订阅（**不迁这个，打开后会是空的**）
  - `items:` 每个订阅的 `uid`、类型、文件名、订阅 URL、更新间隔、
    自动更新开关、关联的 merge/script/rules/proxies/groups 模板、
    以及 `selected:` 记录的策略组节点选择记忆
- **`verge.yaml`** —— 应用设置：端口、系统代理开关、TUN、语言、主题、
  托盘图标、延迟测试目标等

### 建议迁

- **`config.yaml`** —— 内核启动参数。注意里面常有
  `external-controller-unix: /var/folders/xx/..../verge-mihomo.sock` 这种
  **带临时目录的路径**，那个路径是旧机器/旧会话生成的，复制过来没有意义，
  应用启动时会按当前环境重新写一份，所以复制与否影响不大。
- **`dns_config.yaml`** —— 如果你在界面上配过 DNS 覆写，就一起迁。

### 不要迁

| 文件 | 原因 |
|---|---|
| `cache.db` | 运行时缓存，含旧环境状态，可能引起异常 |
| `singleton-instance.json` / `.lock` | 单实例锁，含旧进程的 PID 与 socket 路径 |
| `logs/` `service-logs/` | 日志，纯噪音 |
| `.window-state.json` `window_state.json` | 窗口位置，因屏幕分辨率而异 |
| `geoip.dat` `geosite.dat` `Country.mmdb` `ASN.mmdb` | 数十 MB 的数据库，会重新下载/自带；实在要迁再迁 |

---

## 六、迁移完成后的验证

启动 Clash Verge 后，按这三层确认：

**1. 看内核是否起来了**

```bash
pgrep -fl verge-mihomo
```

内核能起来，说明配置语法没被复制坏。

**2. 看订阅是否真的加载了**

```bash
# 运行时合成出来的配置，体积应该从几 KB 涨到几百 KB
ls -l ~/Library/Application\ Support/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml

# 里面的策略组应该出现在日志里
tail -20 ~/Library/Application\ Support/io.github.clash-verge-rev.clash-verge-rev/logs/sidecar/sidecar_latest.log
```

日志里看到类似下面的行，就说明节点和策略组都加载成功了：

```
Mixed(http+socks) proxy listening at: 127.0.0.1:7897
Start initial compatible provider 🔰 节点选择
```

**3. 看界面**

打开 Clash Verge → 「订阅」页应该能看到原来所有的订阅卡片，
「代理」页能看到策略组和节点列表，策略组里之前选中的节点也还在。

---

## 七、安全须知（重要）

**`profiles.yaml` 和 `profiles/` 里含真实凭据，属于敏感数据。**

具体来说，这些文件里可能有：

- 订阅链接，且 URL 里常常**直接带 token**，形如
  `https://example.com/config?token=<一长串十六进制>`
  —— 拿到这个 URL 等于拿到你的机场账号
- 节点信息：`server:` 地址、`port:` 端口、`password:` 密码、`uuid:` 等
- 局域网订阅还可能暴露**内网 IP**，形如 `http://192.168.1.100:8080/share/config.yaml`

因此：

- **绝对不要把 `profiles.yaml` 和 `profiles/*.yaml` 原样提交到 Git 仓库**，
  哪怕是私有仓库也不建议
- 要分享或归档配置时，先把这些字段替换成占位符：
  - 订阅 URL → `https://example.com/subscribe?token=YOUR_TOKEN_HERE`
  - `server:` → `example.com` 或 `127.0.0.1`
  - `password:` / `uuid:` → `REDACTED`
  - 内网 IP → `192.168.1.100`
- 本仓库 `examples/` 下的所有文件都是**脱敏后的示例**，节点为虚构数据，
  仅用于演示格式，不能直接使用
- 用 `scripts/sanitize-check.sh` 可以在提交前自查，它会扫描出可疑字段

---

## 八、常见问题

**Q：迁移后打开 Clash Verge，订阅列表是空的？**
`profiles.yaml` 没迁过去，或者被应用覆盖了。确认复制时应用处于关闭状态。

**Q：订阅卡片在，但点进去没有节点？**
`profiles/` 目录没迁完整，或文件名与 `profiles.yaml` 里记录的 `file:` 字段对不上。
检查 `profiles.yaml` 中每项的 `file:` 值，确认 `profiles/` 下有同名文件。

**Q：提示配置错误、内核起不来？**
大概率是复制过程中文件被截断，或者两个版本的应用配置格式不同。
先看 `logs/sidecar/sidecar_latest.log` 里的报错行。
另一个排查方向：`verge.yaml` 里如果有跨版本不兼容的字段，删掉对应行重启试试。

**Q：系统代理开着但上不了网？**
检查 `verge.yaml` 里的 `verge_mixed_port` 与内核实际监听端口是否一致，
以及旧配置里的节点在当前网络环境下是否可用（订阅可能已过期或换了地址）。

**Q：两个账户之间复制，提示 Operation not permitted？**
说明当前账户对旧账户的家目录没有读权限。macOS 对家目录默认是 `drwxr-x---+`，
只有本人和管理员组可读。解决：用管理员账户执行，或在系统设置里给磁盘完全访问权限。

**Q：能用 `~/Library/Application Support` 的路径直接复制吗？**
能。`~` 只会展开成当前用户的家目录，所以跨账户时必须写绝对路径。

---

## 附：本次迁移的实际环境

| 项目 | 值 |
|---|---|
| 系统 | macOS（Sequoia 14 系列卷结构） |
| 应用 | Clash Verge Rev |
| 配置目录名 | `io.github.clash-verge-rev.clash-verge-rev` |
| 旧账户 | `yg` |
| 新账户 | `zz` |
| 迁移方式 | 同一台机器，通过 Data 卷绝对路径直读 |
| 迁移文件 | `profiles/`（14 个文件）、`profiles.yaml`、`verge.yaml`、`config.yaml`、`dns_config.yaml`、`icons/` |
| 迁移结果 | 内核正常启动，混合端口 127.0.0.1:7897 监听成功，策略组全部加载 |

---

## License

MIT
