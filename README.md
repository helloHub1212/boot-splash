# boot-splash V1.0

**English** | [中文](README.zh-CN.md)

Replace the Linux boot splash with **kernel log output** — the look of a vanilla Arch / Debian boot — and switch it back with a single command.

**It peels off the decorative layers one by one and lands the console on the graphical console (fbcon).**

---

## 1. Features

### Before / after

| | Before | After |
|---|---|---|
| On screen | Vendor logo / theme animation | Kernel printk log + systemd `[ OK ]` lines |
| Look | Graphical boot animation | A vanilla Arch / Debian boot |

### What it changes

It appends the following parameters to the kernel command line:

| Parameter | Purpose |
|---|---|
| `console=tty0` | Make sure the log lands on the local graphical console (if only `console=ttyS0` is configured, you won't see anything without this) |
| `loglevel=7` | Restore `pr_info`-level output (`quiet` clamps loglevel down to 4) |
| `fbcon=nodefer` | Let fbcon take over the console immediately — the log starts scrolling as early as possible, and any leftover firmware / bootloader image is wiped |
| `logo.nologo` | Don't draw the kernel penguin |
| `vt.global_cursor_default=0` | Hide the blinking cursor |
| `plymouth.enable=0` | Safety net: even if plymouth gets pulled in by some other unit, no theme is displayed |

It also strips the distro-specific graphical boot flags from the command line:

| Flag | Origin |
|---|---|
| `quiet`, `splash` | Common |
| `rhgb` | Fedora / RHEL |
| `splash=silent`, `splash=verbose` | openSUSE (matched by prefix) |

On systems using mkinitcpio it additionally removes `plymouth` from `HOOKS` in `/etc/mkinitcpio.conf`.

> **Key point:** `quiet` suppresses **both** the kernel log and systemd's `[ OK ]` lines. This tool takes the "no `quiet` at all" route, so you get the vanilla-Arch-style scrolling output. Wanting to keep only the systemd status lines and not the kernel log is a separate matter — the reverse, just add `systemd.show_status=0`.

### Cross-distribution support

Backends are auto-detected; which file to edit and how to regenerate are decided automatically:

| Scenario | Where the command line goes | initramfs | Bootloader refresh |
|---|---|---|---|
| Limine + `limine-entry-tool` | `KERNEL_CMDLINE[default]` in `/etc/default/limine` (keeping the existing `=` / `+=` form); otherwise `/etc/kernel/cmdline` | `mkinitcpio -P` | `limine-update` |
| BLS entries (Fedora / RHEL / systemd-boot + kernel-install) | Edit the `options` line of `/boot/loader/entries/*.conf` directly, and also write `/etc/kernel/cmdline` for future kernel installs | `mkinitcpio -P` / `dracut -f --regenerate-all` | Not needed (entries are updated directly) |
| mkinitcpio (Arch family) | `/etc/kernel/cmdline` | `mkinitcpio -P` | Auto-detected |
| systemd-boot / UKI | `/etc/kernel/cmdline` | `mkinitcpio -P` | `bootctl update` |
| Debian / Ubuntu | `/etc/kernel/cmdline` | `update-initramfs -u -k all` | `update-grub` / `grub-mkconfig` |
| openSUSE / generic GRUB | `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` | Auto-detected | `grub-mkconfig` |

Backend priority: **Limine → BLS entries → GRUB → generic `/etc/kernel/cmdline`**.

Both forms of `HOOKS` are supported (`HOOKS=(...)` array form and `HOOKS="..."` string form), and `plymouth` is handled correctly whether it sits first, last, or in the middle.

**Not covered:** syslinux, rEFInd, ZFSBootMenu, U-Boot (embedded), Android/ABL, and Alpine's `extlinux.conf` — these need to be configured by hand.

### Scope and prerequisites

1. **The kernel must be built with `CONFIG_FRAMEBUFFER_CONSOLE`** for the log to reach the screen. Very stripped-down embedded kernels often disable it, in which case the `fbcon=` parameter has no effect.
2. **The UEFI firmware's BGRT logo cannot be fully turned off:** `CONFIG_ACPI_BGRT` is a compile-time option, so it can't be changed on a distro's prebuilt kernel; `fbcon=nodefer` only overwrites it as early as possible. Removing it entirely requires building your own kernel.
3. **On non-mkinitcpio systems there is no equivalent plymouth hook to remove:** dracut pulls plymouth into the initramfs automatically whenever it is installed, and Debian's initramfs-tools is triggered by `splash` on the command line. In that case this tool falls back to `plymouth.enable=0`; **for a completely clean result, uninstall the plymouth package.**
4. If Limine has `ENABLE_ENROLL_LIMINE_CONFIG` enabled, you must run `limine-enroll-config` after changing the configuration, or the checksum check will fail and the machine will not boot. The tool detects and warns about this, but does not run it for you.
5. In UKI mode the command line is baked into the `.efi` file, so the UKI must be regenerated for changes to take effect.
6. The display manager's own login-screen background (SDDM / GDM) is unrelated to the boot splash and will still be shown.
7. **bash 4.0+ is required** (the scripts use associative arrays to hold the bilingual message tables). Every mainstream distribution ships bash 5.x.

### Usage

**Interactive TUI (recommended)**

```bash
bash ./install.sh          # No sudo needed; it asks for a password in the UI when privileges are required
```

It picks a language at startup (your last choice is remembered — press Enter to use the default):

```
╔══════════════════════════════════════════════════════════════════════════════╗
│ 选择语言 / Select language                                                   │
╠══════════════════════════════════════════════════════════════════════════════╣
│  1) English                                                                  │
│  2) 中文                                                                     │
╚══════════════════════════════════════════════════════════════════════════════╝

  请选择 [1-2] (默认: 中文): 
```

Choosing English brings you to the main menu (item 8 switches language at any time):

```
╔══════════════════════════════════════════════════════════════════════════════╗
│ boot-splash  ·  Boot splash manager  ·  V1.0                                 │
╠══════════════════════════════════════════════════════════════════════════════╣
│ Current mode   : boot splash (not enabled)                                   │
│ Bootloader     : limine                                                      │
│ Command line   : /etc/default/limine                                         │
│ Tool status    : installed  /usr/local/bin/boot-splash                       │
│ Running as     : user (will ask for sudo password)                           │
╠══════════════════════════════════════════════════════════════════════════════╣
│  1) Install and enable — turn the splash off, use kernel log                 │
│  2) Restore          — bring back the graphical splash                       │
│  3) Preview          — dry-run, writes nothing                               │
│  4) Rollback         — restore the most recent backup                        │
│  5) Install only     — copy files, leave system config alone                 │
│  6) Uninstall                                                                │
│  7) Show detailed status                                                     │
│  8) Switch language                                                          │
│  0) Quit                                                                     │
╚══════════════════════════════════════════════════════════════════════════════╝
```

Both option 1 and option 2 show the complete diff first, ask for confirmation, and only then write anything; answering `n` leaves the system completely untouched.

**Language:** the UI is available in Chinese and English. The choice is remembered in `/var/lib/boot-splash/lang`; `--lang=zh|en` or `BOOT_SPLASH_LANG=zh|en` skips the picker entirely. The TUI passes the language through to `boot-splash`, so the command output shown inside the UI is in the same language.

**Privilege model:** no need to `sudo` up front. It normally runs as an ordinary user and asks for a password only when it actually needs to write system files; once verified, the sudo timestamp is cached and kept alive by a background process, so later actions do not ask again. If you are already running as root, or the system is configured with `NOPASSWD`, nothing is ever asked. Read-only operations (preview, status) never prompt.

**Command line**

```bash
bash ./install.sh --install           # Install the files only
bash ./install.sh --status            # Print status (no root needed)
bash ./install.sh --uninstall         # Remove the files (leaves the system config alone)

boot-splash status               # Show the current state
boot-splash off --dry-run        # Preview (no root needed)
boot-splash off                  # Turn the splash off -> kernel log
boot-splash on                   # Restore the graphical splash
boot-splash rollback             # Roll back to the most recent backup
```

Aliases: `boot-splash-off` = `boot-splash off`, `boot-splash-on` = `boot-splash on`.

| Option | Description |
|---|---|
| `-y, --yes` | Skip confirmation |
| `-n, --dry-run` | Only print the changes that would be made; writes nothing, needs no root |
| `--no-regen` | Don't run the initramfs / bootloader refresh |
| `--force` | Allow writing a command line that contains no `root=` (dangerous) |
| `--params "..."` | Override the parameters appended when turning the splash off |
| `--splash "..."` | Override the parameters restored when turning the splash back on |
| `--strip-extra "..."` | Extra flags to strip but not restore by default (default `rhgb`) |
| `--strip-prefix "..."` | Flags to strip by prefix (default `splash=`) |
| `--no-bls` | Don't modify BLS entries directly |
| `--lang=zh\|en` | Set the UI language and skip the startup picker (`install.sh`) |
| `--porcelain` | Make `status` emit language-neutral ASCII `key=value` (`boot-splash`) |

A **reboot** is required for the changes to take effect.

---

## 2. Implementation

### The layers a boot splash comes from

Only by taking it apart layer by layer can it be turned off cleanly:

| # | Layer | Who draws it | What this tool does |
|---|---|---|---|
| 1 | UEFI firmware | The vendor logo in the BGRT table; the kernel keeps `CONFIG_ACPI_BGRT` alive until it is overwritten | `fbcon=nodefer` grabs the screen as early as possible |
| 2 | Bootloader | Limine menu background, timeout countdown | Left alone (that is the bootloader menu, not the boot splash) |
| 3 | Kernel | The `CONFIG_LOGO` penguin; `quiet` lowers the console loglevel | Drop `quiet`, add `logo.nologo` |
| 4 | initramfs | mkinitcpio's `plymouth` hook starts `plymouthd` right here | Remove `plymouth` from `HOOKS` |
| 5 | Userspace | `plymouth-start` / `plymouth-quit` | `plymouth.enable=0` as a safety net |

### Backend detection

At startup it probes in a fixed priority order to decide where the command line lives:

```
Limine → BLS entries → GRUB → generic /etc/kernel/cmdline
```

Putting BLS ahead of GRUB is the crucial part: Fedora / RHEL also have `/etc/default/grub`, but their `grub.cfg` merely chains to `/boot/loader/entries/*.conf`, so editing `GRUB_CMDLINE_LINUX_DEFAULT` (or even running `grub-mkconfig`) **has no effect whatsoever on already-installed kernels**. BLS detection accepts only `options` lines containing a literal `root=`, which automatically skips indirect forms such as `options $kernelopts ...`.

Reading and writing the command line is abstracted into three shapes: a plain single-line text file, Limine's `KERNEL_CMDLINE[]=`, and GRUB's `GRUB_CMDLINE_LINUX_DEFAULT="..."`. When rewriting a Limine entry the existing `=` / `+=` form is **preserved** and only the value is replaced.

### Brick protection

```bash
assert_root_token() {
  # new command line contains root=        -> allow
  # source has root= but new one doesn't   -> refuse (the genuinely dangerous case)
  # neither has root= and backend is GRUB  -> allow (grub-mkconfig assembles root= itself)
  # neither has root= otherwise            -> refuse
}
```

The rule follows the semantics rather than the intuition: `GRUB_CMDLINE_LINUX_DEFAULT` never contains `root=` to begin with, so a blanket requirement of "must contain `root=`" would make the GRUB backend permanently unusable.

### On-demand privilege escalation

It runs as an ordinary user and asks for a password inside the UI only when it needs to write system files:

- The password is **not echoed** and is passed to `sudo -S` via stdin, so it **never appears in the argument list** (invisible to `ps`).
- After successful verification the sudo timestamp is written and kept alive by a background process, so it does not expire while you sit in the menu.
- An empty password gets its own message (it does not consume a retry), and Ctrl-D at the password prompt cancels with zero changes.
- It gives up after 3 consecutive failures.
- If there is no `sudo` on the system it says so clearly and offers a `su -c` alternative; `BOOT_SPLASH_NO_ELEVATE=1` disables automatic elevation entirely.

### Redirectable paths

Every file path goes through a redirectable root prefix:

```bash
R="${BOOT_SPLASH_ROOT:-}"
STATE_DIR="${R}/var/lib/boot-splash"
```

So a complete off / on round trip can be previewed against any given configuration **without touching the real system at all**.

### Rollback

Before every write, the original files are backed up under a UTC timestamp to `/var/lib/boot-splash/backups/` (the most recent 5 are kept), and `rollback` restores them with a single command; files this tool created are deleted rather than left empty.

State is recorded in `/var/lib/boot-splash/state` in a directly readable shell-variable format that you can edit by hand.

### UI implementation

The TUI is **implemented in pure bash and depends on neither `whiptail`, `dialog`, nor `newt`** — otherwise the installer itself would be the first thing that isn't portable. Boxes are laid out by **display width** (CJK characters are double-width), so the borders stay aligned in mixed Chinese/English output.

### Internationalization

All messages live in two associative-array tables at the top of each script (`MSG_ZH` / `MSG_EN`), indexed by key and resolved by `t()` for the current language:

```bash
[menu.1]="安装并启用 —— 关闭开机动画，改用内核日志"                     # MSG_ZH
[menu.1]="Install and enable — turn the splash off, use kernel log"  # MSG_EN
```

Call sites only name the key, so adding a message cannot leave one language behind:

```bash
box " ${C_GRN}1${C_OFF}) $(t menu.1)"
```

The language is resolved in this order: `--lang` / `BOOT_SPLASH_LANG` → the remembered choice → the system locale → English. The TUI passes the language down through `ELEV_ENV`, so even the elevated `boot-splash` runs in the same language and the UI never mixes languages.

**Label alignment in the menus is computed from display width**, not from `printf '%-16s'` — the latter pads by character count, which under-pads CJK text. A small `padw()` takes the display width via `wc -L` and pads with spaces, so the colons line up in both languages.

### Machine-readable status output

The TUI needs to read the current mode, backend and command-line file out of `boot-splash`. Parsing the human-readable `status` directly would break the moment the UI switches to English, because the label matching would no longer find the Chinese labels. So `status` has a second, language-neutral interface:

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

The TUI parses only this; the human-readable `status` follows the language setting, and the two never interfere.

---

## 3. Files

```
boot-splash     Main script (CLI, no external file dependencies)
install.sh      TUI installer / manager (must sit in the same directory as boot-splash)
README.md       This document
```
