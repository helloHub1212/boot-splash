# boot-splash V1.0

**[English](README.md) | 中文**

把 Linux 的开机动画换成**内核日志**（原版 Arch / Debian 那种观感），并且可一键切回去。

**把几层装饰逐个摘掉，并把 console 落到图形控制台（fbcon）**。

---

## 一、功能介绍

### 效果

| | 开启前 | 开启后 |
|---|---|---|
| 屏幕内容 | 厂商 logo / 主题动画 | 内核 printk 日志 + systemd `[ OK ]` 行 |
| 观感 | 图形开机动画 | 原版 Arch、Debian 那样 |

### 它改了什么

往内核命令行追加以下参数：

| 参数 | 作用 |
|---|---|
| `console=tty0` | 确保日志落到本地图形控制台（只配了 `console=ttyS0` 时不加就看不到） |
| `loglevel=7` | 恢复 `pr_info` 级别输出（`quiet` 会把 loglevel 压到 4） |
| `fbcon=nodefer` | 让 fbcon 立即接管 console，既从最早开始滚日志，又刷掉固件/引导器残留画面 |
| `logo.nologo` | 不画内核小企鹅 |
| `vt.global_cursor_default=0` | 隐藏闪烁光标 |
| `plymouth.enable=0` | 兜底：即使 plymouth 被别的单元拉起也不显示主题 |

并从命令行里剥离各发行版的图形启动标志：

| 标志 | 来源 |
|---|---|
| `quiet`、`splash` | 通用 |
| `rhgb` | Fedora / RHEL |
| `splash=silent`、`splash=verbose` | openSUSE（按前缀匹配） |

如果系统用 mkinitcpio，还会从 `/etc/mkinitcpio.conf` 的 `HOOKS` 中移除 `plymouth`。

> **关键点**：`quiet` 会**同时**压掉内核日志和 systemd 的 `[ OK ]` 行。本工具走的是「完全不加 `quiet`」，所以你得到的是原版 Arch 那种滚动输出。若只想保留 systemd 状态行而不要内核日志，那是另一回事——反过来加 `systemd.show_status=0` 即可。

### 跨发行版支持

后端自动探测，改哪个文件、怎么重新生成都是自动决定的：

| 场景 | 命令行写在哪 | initramfs | 引导器刷新 |
|---|---|---|---|
| Limine + `limine-entry-tool` | `/etc/default/limine` 的 `KERNEL_CMDLINE[default]`（保留原有 `=`/`+=` 写法）；否则 `/etc/kernel/cmdline` | `mkinitcpio -P` | `limine-update` |
| BLS 条目（Fedora / RHEL / systemd-boot + kernel-install） | 直接改 `/boot/loader/entries/*.conf` 的 `options` 行，同时写 `/etc/kernel/cmdline` 供以后装新内核用 | `mkinitcpio -P` / `dracut -f --regenerate-all` | 不需要（条目已直接更新） |
| mkinitcpio（Arch 系） | `/etc/kernel/cmdline` | `mkinitcpio -P` | 按探测 |
| systemd-boot / UKI | `/etc/kernel/cmdline` | `mkinitcpio -P` | `bootctl update` |
| Debian / Ubuntu | `/etc/kernel/cmdline` | `update-initramfs -u -k all` | `update-grub` / `grub-mkconfig` |
| openSUSE / 通用 GRUB | `/etc/default/grub` 的 `GRUB_CMDLINE_LINUX_DEFAULT` | 按探测 | `grub-mkconfig` |

后端优先级：**Limine → BLS 条目 → GRUB → 通用 `/etc/kernel/cmdline`**。

`HOOKS` 的两种写法（`HOOKS=(...)` 数组形式、`HOOKS="..."` 字符串形式）都支持，`plymouth` 位于首位 / 末位 / 中间都能正确处理。

**未被覆盖**：syslinux、rEFInd、ZFSBootMenu、U-Boot（嵌入式）、Android/ABL、Alpine 的 `extlinux.conf`，这些需要手工改各自的配置。

### 适用范围与前提

1. **内核必须编了 `CONFIG_FRAMEBUFFER_CONSOLE`**，日志才能上屏。极精简的嵌入式内核常把它关掉，此时 `fbcon=` 参数无效。
2. **UEFI 固件的 BGRT logo 关不干净**：`CONFIG_ACPI_BGRT` 是编译期选项，发行版预编译内核改不了，`fbcon=nodefer` 只能尽早覆盖它。要彻底关掉需自编译内核。
3. **非 mkinitcpio 系统没有等价的 plymouth hook 可删**：dracut 会在装了 plymouth 时自动把它塞进 initramfs，Debian 的 initramfs-tools 靠命令行里的 `splash` 触发。此时本工具靠 `plymouth.enable=0` 兜底，**要绝对干净需卸载 plymouth 包**。
4. 若 Limine 启用了 `ENABLE_ENROLL_LIMINE_CONFIG`，改完配置必须再执行 `limine-enroll-config`，否则校验失败会无法启动。工具会检测并警告，但不代为执行。
5. UKI 模式下命令行被烧进 `.efi`，需要重新生成 UKI 才能生效。
6. 显示管理器（SDDM / GDM）自己的登录界面背景与开机动画无关，仍会显示。
7. **需要 bash 4.0+**（脚本内部使用关联数组存放双语文案）。主流发行版自带的都是 bash 5.x。

### 使用方法

**TUI 交互界面（推荐）**

```bash
git clone https://github.com/helloHub1212/boot-splash.git
cd boot-splash
chmod +x install.sh boot-splash
./install.sh
```

启动时先选语言（会记住上次的选择，直接回车即用默认值）：

```
╔══════════════════════════════════════════════════════════════════════════════╗
│ 选择语言 / Select language                                                   │
╠══════════════════════════════════════════════════════════════════════════════╣
│  1) English                                                                  │
│  2) 中文                                                                     │
╚══════════════════════════════════════════════════════════════════════════════╝

  请选择 [1-2] (默认: 中文): 
```

选中文后进入主菜单（菜单里的 8 可随时切换语言）：

```
╔══════════════════════════════════════════════════════════════════════════════╗
│ boot-splash  ·  开机画面管理  ·  V1.0                                        │
╠══════════════════════════════════════════════════════════════════════════════╣
│ 当前模式       : 开机动画（未启用）                                          │
│ 引导后端       : limine                                                      │
│ 命令行         : /etc/default/limine                                         │
│ 工具状态       : 已安装  /usr/local/bin/boot-splash                          │
│ 运行身份       : 普通用户（需要时提示 sudo 密码）                            │
╠══════════════════════════════════════════════════════════════════════════════╣
│  1) 安装并启用 —— 关闭开机动画，改用内核日志                                 │
│  2) 恢复       —— 还原图形开机动画                                           │
│  3) 预览改动   —— dry-run，不落盘                                            │
│  4) 回滚       —— 还原最近一次备份                                           │
│  5) 仅安装工具 —— 只复制文件，不改系统配置                                   │
│  6) 卸载工具                                                                 │
│  7) 查看详细状态                                                             │
│  8) 切换语言                                                                 │
│  0) 退出                                                                     │
╚══════════════════════════════════════════════════════════════════════════════╝
```

选项 1 和 2 都是「先展示完整 diff → 再确认一次 → 才落盘」，回答 `n` 则完全零改动。

**语言**：界面支持中文与英文。语言选择会记住到 `/var/lib/boot-splash/lang`；用 `--lang=zh|en` 或 `BOOT_SPLASH_LANG=zh|en` 可直接跳过选择界面。TUI 会把语言透传给 `boot-splash`，因此界面内展示的命令输出也是同一种语言。

**权限模型**：不需要提前 `sudo`。平时以普通用户运行，只有真正要写系统文件时才询问密码；验证通过后缓存 sudo 时间戳并后台保活，后续操作不再重复询问。已经以 root 运行、或系统配了 `NOPASSWD` 时，全程零询问。只读操作（预览、状态）永不询问。

**命令行**

```bash
bash ./install.sh --install           # 只装文件
bash ./install.sh --status            # 打印状态（不需要 root）
bash ./install.sh --uninstall         # 卸载文件（不动系统配置）

boot-splash status               # 看当前状态
boot-splash off --dry-run        # 预览（不需要 root）
boot-splash off                  # 关闭动画 -> 内核日志
boot-splash on                   # 恢复图形动画
boot-splash rollback             # 回滚到最近一次备份
```

别名：`boot-splash-off` = `boot-splash off`，`boot-splash-on` = `boot-splash on`。

| 选项 | 说明 |
|---|---|
| `-y, --yes` | 跳过确认 |
| `-n, --dry-run` | 只打印将要做的修改，不落盘、不需要 root |
| `--no-regen` | 不执行 initramfs / 引导器刷新 |
| `--force` | 允许写入不含 `root=` 的命令行（危险） |
| `--params "..."` | 覆盖「关闭动画」追加的参数 |
| `--splash "..."` | 覆盖「开启动画」恢复的参数 |
| `--strip-extra "..."` | 只剥离、不作为默认恢复值的额外标志（默认 `rhgb`） |
| `--strip-prefix "..."` | 按前缀剥离的标志（默认 `splash=`） |
| `--no-bls` | 不直接修改 BLS 条目 |
| `--lang=zh\|en` | 指定界面语言，跳过启动时的语言选择（`install.sh`） |
| `--porcelain` | `status` 输出语言无关的 ASCII `key=value`（`boot-splash`） |

改完需要**重启**生效。

---

## 二、实现方法介绍


### 开机画面的来源分层

只有按层拆，才能关干净：

| # | 层 | 谁画的 | 本工具的处置 |
|---|---|---|---|
| 1 | UEFI 固件 | BGRT 表里的厂商 logo，内核 `CONFIG_ACPI_BGRT` 保留到被覆盖 | `fbcon=nodefer` 尽早抢屏覆盖 |
| 2 | 引导器 | Limine 菜单背景、超时倒计时 | 不动（属引导器菜单，非开机动画） |
| 3 | 内核 | `CONFIG_LOGO` 小企鹅；`quiet` 压低 console loglevel | 去 `quiet`、加 `logo.nologo` |
| 4 | initramfs | mkinitcpio 的 `plymouth` hook 在这里就拉起 `plymouthd` | 从 `HOOKS` 移除 `plymouth` |
| 5 | 用户态 | `plymouth-start/quit` | `plymouth.enable=0` 兜底 |

### 后端探测

启动时按固定优先级探测，决定「命令行写在哪」：

```
Limine → BLS 条目 → GRUB → 通用 /etc/kernel/cmdline
```

BLS 排在 GRUB 之前是关键：Fedora / RHEL 同样有 `/etc/default/grub`，但它们的 `grub.cfg` 只是链到 `/boot/loader/entries/*.conf`，改 `GRUB_CMDLINE_LINUX_DEFAULT`（乃至跑 `grub-mkconfig`）**对已装内核毫无影响**。检测 BLS 时只认带字面量 `root=` 的 `options` 行，从而自动跳过 `options $kernelopts ...` 这类间接形式。

命令行文件的读写按「形态」抽象成三种：纯文本单行、Limine 的 `KERNEL_CMDLINE[]=`、GRUB 的 `GRUB_CMDLINE_LINUX_DEFAULT="..."`。改写 Limine 条目时**保留原有的 `=` / `+=` 写法**，只换值。

### 防砖保护

```bash
assert_root_token() {
  # 新命令行含 root=                    -> 放行
  # 源含 root= 而新命令行不含            -> 拒绝（真正危险的情况）
  # 两边都不含 + 后端是 GRUB             -> 放行（grub-mkconfig 自己拼 root=）
  # 其余两边都不含                       -> 拒绝
}
```

规则的边界贴着语义走：`GRUB_CMDLINE_LINUX_DEFAULT` 本来就不含 `root=`，若一律要求「必须含 `root=`」，GRUB 后端将永远无法工作。

### 按需提权

以普通用户运行，需要写系统文件时才在界面内询问密码：

- 密码**不回显**，经 stdin 传给 `sudo -S`，**不出现在命令行参数里**（`ps` 看不到）。
- 验证通过后写 sudo 时间戳，并由后台进程保活，避免长时间停留在菜单后失效。
- 空密码单独提示（不占用重试次数），密码处 Ctrl-D 即取消且零改动。
- 连续 3 次失败放弃。
- 系统无 `sudo` 时明确提示并给出 `su -c` 替代方案；`BOOT_SPLASH_NO_ELEVATE=1` 可彻底禁用自动提权。

### 路径可重定向

所有文件路径都经过一个可重定向的根前缀：

```bash
R="${BOOT_SPLASH_ROOT:-}"
STATE_DIR="${R}/var/lib/boot-splash"
```

因此可以在**完全不触碰真实系统**的前提下，对任意一套配置做完整的 off / on 往返预览。

### 可回滚

每次落盘前把原文件按 UTC 时间戳备份到 `/var/lib/boot-splash/backups/`（保留最近 5 份），`rollback` 一条命令还原；本工具新建的文件会被删除而不是留空。

状态记录在 `/var/lib/boot-splash/state`，是可直接阅读的 shell 变量格式，可手工编辑。

### 界面实现

TUI **纯 bash 实现，不依赖 `whiptail` / `dialog` / `newt`**——否则安装器自己就先不跨发行版了。画框时按**显示宽度**计算（中文是双宽字符），因此中英混排时框线不会错位。

### 国际化

文案集中在脚本顶部的两张关联数组表（`MSG_ZH` / `MSG_EN`）里，以 key 索引，由 `t()` 按当前语言取值：

```bash
[menu.1]="安装并启用 —— 关闭开机动画，改用内核日志"   # MSG_ZH
[menu.1]="Install and enable — turn the splash off, use kernel log"  # MSG_EN
```

调用处只写 key，因此新增一条文案不会漏掉另一种语言之外的地方：

```bash
box " ${C_GRN}1${C_OFF}) $(t menu.1)"
```

语言的确定顺序是：`--lang` / `BOOT_SPLASH_LANG` → 上次记住的选择 → 系统 locale → 英文。TUI 通过 `ELEV_ENV` 把语言透传给提权后的 `boot-splash`，所以界面内外语言始终一致。

**中文菜单里的标签对齐是按显示宽度算的**，不能直接用 `printf '%-16s'`——它按字符数补空格，中文会短一截。因此有一个 `padw()`：先用 `wc -L` 取显示宽度，再补空格，中英两种语言的冒号都能对整齐。

### 机器可读的状态输出

TUI 需要从 `boot-splash` 读取当前模式、后端和命令行文件。如果直接解析人类可读的 `status`，一旦界面语言切换成英文，中文标签的匹配就会失效。因此 `status` 另有一个语言无关的接口：

```
$ boot-splash status --porcelain
MODE=unknown
BACKEND=limine
CMDLINE_FILE=/etc/default/limine
CMDLINE=quiet splash rw root=UUID=...
MANAGED_PARAMS=console=tty0 loglevel=7 ...
PARAMS_REMOVED=
HOOK_PLYMOUTH=yes
```

TUI 只解析这个输出，人类可读的 `status` 则完全跟随语言设置，两者互不影响。

---

## 三、文件

```
boot-splash     主脚本（CLI，无外部文件依赖）
install.sh      TUI 安装 / 管理器（需与 boot-splash 同目录）
README.md       本文档
```
