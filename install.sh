#!/usr/bin/env bash
# =============================================================================
#  boot-splash TUI —— 开机画面管理界面 / boot splash manager
#
#  启动时先选语言，再进入主菜单。支持中文与英文。
#  Picks a language at startup, then enters the main menu. Chinese and English.
#
#    1) 安装并启用 / Install and enable   —— 关闭开机动画，改用内核日志
#    2) 恢复 / Restore                    —— 还原图形开机动画
#    3) 预览改动 / Preview                —— dry-run，不落盘
#    4) 回滚 / Rollback                   —— 还原最近一次备份
#    5) 仅安装工具 / Install only         —— 只复制文件，不修改系统配置
#    6) 卸载工具 / Uninstall
#    7) 查看详细状态 / Detailed status
#    8) 切换语言 / Switch language
#
#  权限模型：不需要提前 sudo。平时以普通用户运行，只有真正需要写系统文件时
#  才在界面里提示输入 sudo 密码；验证通过后缓存凭据并在会话内保活。
#
#  纯 bash 实现，不依赖 whiptail / dialog / newt。需要 bash 4.0+（关联数组）。
#
#  非交互用法 / Non-interactive:
#    ./install.sh --lang=en --install
#    ./install.sh --lang=zh --status
#    ./install.sh --tui
#
#  环境变量 / Environment:
#    BOOT_SPLASH_LANG   界面语言，zh | en（会透传给 boot-splash）
#    DESTDIR            安装根目录前缀（测试用）
#    BINDIR             安装到哪个 bin 目录（默认 /usr/local/bin）
#    BOOT_SPLASH_ROOT   影子根目录，透传给 boot-splash
#    BOOT_SPLASH_NO_ELEVATE=1   禁用自动提权
# =============================================================================
set -uo pipefail

VERSION="V1.0"
SELF="${0##*/}"

HERE="$(cd "$(dirname "$0")" && pwd)"
DESTDIR="${DESTDIR:-}"
BINDIR="${BINDIR:-/usr/local/bin}"
SUT="${HERE}/boot-splash"
INSTALL_PATH="${DESTDIR}${BINDIR}/boot-splash"

# 影子根（透传给 boot-splash）
R="${BOOT_SPLASH_ROOT:-}"
STATE_DIR="${R}/var/lib/boot-splash"
STATE_FILE="${STATE_DIR}/state"
LANG_FILE="${STATE_DIR}/lang"

# ---------- 颜色 / 画框 ------------------------------------------------------
if [ -t 1 ]; then
  C_RED=$'\033[1;31m'; C_GRN=$'\033[1;32m'; C_YEL=$'\033[1;33m'
  C_BLU=$'\033[1;34m'; C_CYA=$'\033[1;36m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_CYA=""; C_DIM=""; C_OFF=""
fi

W="$(tput cols 2>/dev/null || echo 72)"
case "$W" in ''|*[!0-9]*) W=72 ;; esac
[ "$W" -gt 88 ] && W=88
[ "$W" -lt 56 ] && W=56
RULE_W=$((W - 2))
UI_EOF=no

# =============================================================================
#  国际化 / Internationalization
# =============================================================================

LANG_CODE="${BOOT_SPLASH_LANG:-}"
LANG_PRESET=no            # 是否由命令行/环境变量指定（指定了就不弹语言选择）
LANG_DEFAULT=en

declare -A MSG_ZH=(
  # --- 语言选择 ---
  [lang.title]="选择语言 / Select language"
  [lang.prompt]="请选择"
  [lang.default]="默认"

  # --- 通用 ---
  [common.press]="按回车继续…"
  [common.invalid]="无效选择：%s"
  [common.cancel]="已取消。"
  [common.exit]="已退出。"

  # --- 标题栏 ---
  [hdr.title]="boot-splash  ·  开机画面管理  ·  %s"
  [hdr.mode]="当前模式"
  [hdr.backend]="引导后端"
  [hdr.cmdline]="命令行"
  [hdr.tool]="工具状态"
  [hdr.identity]="运行身份"
  [hdr.notdetected]="（未探测到）"

  # --- 身份 ---
  [id.root]="root"
  [id.sudo-ok]="普通用户（已获得 sudo 授权）"
  [id.sudo-maybe]="普通用户（需要时提示 sudo 密码）"
  [id.no-sudo]="普通用户（系统无 sudo，无法提权）"

  # --- 状态 ---
  [inst.yes]="已安装"
  [inst.no]="未安装"
  [mode.unset]="开机动画（未启用）"
  [mode.console]="内核日志模式"
  [mode.splash]="开机动画模式"
  [mode.unknown]="未知（状态文件无 MODE）"
  [backend.noscript]="(找不到 boot-splash)"
  [backend.unknown]="未知"

  # --- 主菜单 ---
  [menu.1]="安装并启用 —— 关闭开机动画，改用内核日志"
  [menu.2]="恢复       —— 还原图形开机动画"
  [menu.3]="预览改动   —— dry-run，不落盘"
  [menu.4]="回滚       —— 还原最近一次备份"
  [menu.5]="仅安装工具 —— 只复制文件，不改系统配置"
  [menu.6]="卸载工具"
  [menu.7]="查看详细状态"
  [menu.8]="切换语言"
  [menu.0]="退出"
  [menu.prompt]="选择 [0-8]"

  # --- 提权 ---
  [need.title]="该操作需要 root 权限"
  [need.reason.default]="该操作需要修改系统文件。"
  [need.reason.enable]="关闭开机动画会修改 mkinitcpio 配置和内核命令行。"
  [need.reason.restore]="恢复图形开机动画会修改内核命令行和 mkinitcpio 配置。"
  [need.reason.rollback]="回滚会覆盖 boot-splash 管理过的系统文件。"
  [need.reason.install]="安装 boot-splash 到 %s。"
  [need.reason.uninstall]="从 %s 卸载 boot-splash。"
  [need.disabled]="该操作需要 root 权限（已禁用自动提权，BOOT_SPLASH_NO_ELEVATE=%s）。"
  [need.nosudo]="该操作需要 root 权限，但系统里没有 sudo。"
  [need.nosudo.hint]="请安装 sudo，或以 root 身份重新运行：su -c \"%s --tui\""
  [pw.prompt]="请输入 sudo 密码（不回显）:"
  [pw.ok]="权限验证通过"
  [pw.empty]="密码为空，请重试。"
  [pw.wrong]="密码错误，请重试（已试 %s/3 次）"
  [pw.giveup]="连续 3 次验证失败，已放弃。"
  [pw.cancel]="已取消，未做任何修改。"

  # --- 动作 ---
  [act.step1]="第 1 步 / 2：安装文件"
  [act.step2]="第 2 步 / 2：关闭开机动画"
  [act.preview-hint]="下面先预览将要修改的内容，不会落盘。"
  [act.already]="已安装，跳过：%s"
  [act.installed]="已安装到 %s"
  [act.aliases]="已建立别名 boot-splash-off / boot-splash-on"
  [act.install-fail]="安装失败"
  [act.uninstall-fail]="卸载失败"
  [act.uninstalled]="已卸载"
  [act.no-syscfg]="系统配置未做任何修改。要启用内核日志，请选 1。"
  [act.restore-title]="恢复图形开机动画"
  [act.rollback-title]="回滚到最近一次备份"
  [act.rollback-hint]="会覆盖 boot-splash 管理过的文件（如 /etc/mkinitcpio.conf、命令行配置）。"
  [act.uninstall-warn]="卸载只删除程序文件，不会还原系统配置。"
  [act.uninstall-hint]="检测到本工具启用过；建议先选 %s2（恢复）%s 再卸载。"
  [act.status-title]="详细状态"
  [act.preview-title]="预览：关闭开机动画后的改动"
  [act.preview-on-title]="预览：恢复图形开机动画的改动"
  [act.applying]="正在应用"
  [act.restoring]="正在恢复"
  [act.rolling]="正在回滚"
  [act.confirm-apply]="确认执行以上修改？"
  [act.confirm-restore]="确认恢复？"
  [act.confirm-rollback]="确认回滚？"
  [act.confirm-uninstall]="确认卸载？"
  [act.cancelled-nosys]="已取消，系统配置未被修改。"
  [act.reboot]="重启后生效。"
  [act.done]="完成"
  [act.failed]="失败（退出码 %s）"

  # --- 错误 ---
  [err.noterm]="没有可用的终端。TUI 需要交互式终端，或使用 --install / --uninstall / --status。"
  [err.noscript]="找不到主脚本：%s"
  [err.unknownarg]="未知参数：%s"
  [err.needroot]="需要 root 权限。"
)

declare -A MSG_EN=(
  # --- language picker ---
  [lang.title]="Select language / 选择语言"
  [lang.prompt]="Choice"
  [lang.default]="default"

  # --- common ---
  [common.press]="Press Enter to continue…"
  [common.invalid]="Invalid choice: %s"
  [common.cancel]="Cancelled."
  [common.exit]="Exited."

  # --- header ---
  [hdr.title]="boot-splash  ·  Boot splash manager  ·  %s"
  [hdr.mode]="Current mode"
  [hdr.backend]="Bootloader"
  [hdr.cmdline]="Command line"
  [hdr.tool]="Tool status"
  [hdr.identity]="Running as"
  [hdr.notdetected]="(not detected)"

  # --- identity ---
  [id.root]="root"
  [id.sudo-ok]="user (sudo authorized)"
  [id.sudo-maybe]="user (will ask for sudo password)"
  [id.no-sudo]="user (no sudo, cannot elevate)"

  # --- state ---
  [inst.yes]="installed"
  [inst.no]="not installed"
  [mode.unset]="boot splash (not enabled)"
  [mode.console]="kernel log mode"
  [mode.splash]="boot splash mode"
  [mode.unknown]="unknown (no MODE in state file)"
  [backend.noscript]="(boot-splash not found)"
  [backend.unknown]="unknown"

  # --- main menu ---
  [menu.1]="Install and enable — turn the splash off, use kernel log"
  [menu.2]="Restore          — bring back the graphical splash"
  [menu.3]="Preview          — dry-run, writes nothing"
  [menu.4]="Rollback         — restore the most recent backup"
  [menu.5]="Install only     — copy files, leave system config alone"
  [menu.6]="Uninstall"
  [menu.7]="Show detailed status"
  [menu.8]="Switch language"
  [menu.0]="Quit"
  [menu.prompt]="Choice [0-8]"

  # --- privilege escalation ---
  [need.title]="This action requires root privileges"
  [need.reason.default]="This action needs to modify system files."
  [need.reason.enable]="Turning the splash off modifies the mkinitcpio config and the kernel command line."
  [need.reason.restore]="Restoring the graphical splash modifies the kernel command line and the mkinitcpio config."
  [need.reason.rollback]="Rolling back overwrites the system files boot-splash manages."
  [need.reason.install]="Install boot-splash to %s."
  [need.reason.uninstall]="Uninstall boot-splash from %s."
  [need.disabled]="This action requires root privileges (automatic elevation disabled, BOOT_SPLASH_NO_ELEVATE=%s)."
  [need.nosudo]="This action requires root privileges, but sudo is not installed."
  [need.nosudo.hint]="Install sudo, or re-run as root: su -c \"%s --tui\""
  [pw.prompt]="sudo password (not echoed):"
  [pw.ok]="Authentication OK"
  [pw.empty]="Empty password, please try again."
  [pw.wrong]="Wrong password, try again (attempt %s/3)"
  [pw.giveup]="3 failed attempts, giving up."
  [pw.cancel]="Cancelled; nothing was changed."

  # --- actions ---
  [act.step1]="Step 1 of 2: install files"
  [act.step2]="Step 2 of 2: turn off the boot splash"
  [act.preview-hint]="Below is a preview of the changes; nothing is written yet."
  [act.already]="Already installed, skipping: %s"
  [act.installed]="Installed to %s"
  [act.aliases]="Created aliases boot-splash-off / boot-splash-on"
  [act.install-fail]="Installation failed"
  [act.uninstall-fail]="Uninstall failed"
  [act.uninstalled]="Uninstalled"
  [act.no-syscfg]="No system configuration was touched. To enable kernel logging, choose 1."
  [act.restore-title]="Restore the graphical boot splash"
  [act.rollback-title]="Roll back to the most recent backup"
  [act.rollback-hint]="Overwrites the files boot-splash manages (e.g. /etc/mkinitcpio.conf, the command line config)."
  [act.uninstall-warn]="Uninstalling only removes the program files; it does not revert the system configuration."
  [act.uninstall-hint]="This tool has been used before; consider choosing %s2 (Restore)%s first."
  [act.status-title]="Detailed status"
  [act.preview-title]="Preview: changes for turning the splash off"
  [act.preview-on-title]="Preview: changes for restoring the graphical splash"
  [act.applying]="Applying"
  [act.restoring]="Restoring"
  [act.rolling]="Rolling back"
  [act.confirm-apply]="Apply the changes above?"
  [act.confirm-restore]="Restore?"
  [act.confirm-rollback]="Roll back?"
  [act.confirm-uninstall]="Uninstall?"
  [act.cancelled-nosys]="Cancelled; the system configuration was not modified."
  [act.reboot]="Takes effect after a reboot."
  [act.done]="Done"
  [act.failed]="Failed (exit code %s)"

  # --- errors ---
  [err.noterm]="No usable terminal. The TUI needs an interactive terminal; otherwise use --install / --uninstall / --status."
  [err.noscript]="Main script not found: %s"
  [err.unknownarg]="Unknown argument: %s"
  [err.needroot]="Root privileges required."
)

# t <key> [printf 参数...] —— 取当前语言的文案
t() {
  local key="$1"; shift
  local s
  if [ "$LANG_CODE" = zh ]; then s="${MSG_ZH[$key]-}"; else s="${MSG_EN[$key]-}"; fi
  [ -n "$s" ] || s="[$key]"
  if [ "$#" -eq 0 ]; then printf '%s' "$s"; else printf "$s" "$@"; fi
  return 0
}

detect_lang() {
  case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
    zh*|*_CN*|*_TW*|*_HK*) printf 'zh' ;;
    *)                     printf 'en' ;;
  esac
}

load_saved_lang() {
  [ -f "$LANG_FILE" ] || return 1
  local v
  v="$(head -n1 "$LANG_FILE" 2>/dev/null | tr -d '[:space:]')"
  case "$v" in zh|en) printf '%s' "$v"; return 0 ;; esac
  return 1
}

save_lang() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  [ -w "$STATE_DIR" ] || return 0
  printf '%s\n' "$LANG_CODE" > "$LANG_FILE" 2>/dev/null || true
  return 0
}

# ---------- 输出 -------------------------------------------------------------
log()  { printf '%s==>%s %s\n' "$C_BLU" "$C_OFF" "$*"; }
ok()   { printf '%s ✔ %s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }

# 重复字符 n 次
rep() { local c="$1" n="$2" i; for ((i = 0; i < n; i++)); do printf '%s' "$c"; done; }

# 显示宽度：先剥掉 ANSI 颜色码（wc -L 会把转义序列算成宽度），再用 wc -L 处理双宽字符
disp_width() {
  printf '%s' "$1" | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' | wc -L
}

# 按「显示宽度」右侧补空格
pad() {
  local s="$1" target="$2" cur
  cur="$(disp_width "$s")"
  case "$cur" in ''|*[!0-9]*) cur=0 ;; esac
  printf '%s' "$s"
  while [ "$cur" -lt "$target" ]; do printf ' '; cur=$((cur + 1)); done
}

# 按显示宽度右侧补空格（不带颜色码的纯文本用），让中英标签的冒号都能对齐
padw() {
  local s="$1" target="$2" cur
  cur="$(disp_width "$s")"
  printf '%s' "$s"
  while [ "$cur" -lt "$target" ]; do printf ' '; cur=$((cur + 1)); done
}

hline() { # $1=左 $2=横 $3=右
  printf '%s%s%s%s%s%s\n' "$C_BLU" "$1" "$(rep "$2" "$RULE_W")" "$3" "$C_OFF"
}
box() { # $1=内容；总显示宽度 = 1 + 1 + (W-4) + 1 + 1 = W，与 hline 一致
  printf '%s│%s %s %s│%s\n' "$C_BLU" "$C_OFF" "$(pad "$1" $((W - 4)))" "$C_BLU" "$C_OFF"
}
clear_screen() { [ -t 1 ] && printf '\033[2J\033[H'; return 0; }

pause() {
  printf '\n  %s%s%s' "$C_DIM" "$(t common.press)" "$C_OFF"
  IFS= read -r _ || { printf '\n'; UI_EOF=yes; }
  return 0
}

ask_yn() { # $1=问题；返回 0=是
  local ans
  printf '\n  %s%s%s [y/N] ' "$C_YEL" "$1" "$C_OFF"
  IFS= read -r ans || { printf '\n'; UI_EOF=yes; return 1; }
  case "$ans" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ---------- 环境探测 ---------------------------------------------------------

is_root() { [ "$(id -u)" -eq 0 ]; }
have_sudo() { command -v sudo >/dev/null 2>&1; }
is_installed() { [ -x "$INSTALL_PATH" ]; }

read_mode() {
  U_MODE="$(t mode.unset)"
  [ -f "$STATE_FILE" ] || return 0
  local m
  m="$(sed -nE 's/^MODE=(.*)$/\1/p' "$STATE_FILE" | tail -n1)"
  case "$m" in
    console) U_MODE="$(t mode.console)" ;;
    splash)  U_MODE="$(t mode.splash)" ;;
    "")      U_MODE="$(t mode.unknown)" ;;
    *)       U_MODE="$m" ;;
  esac
}

# 从 boot-splash 的 --porcelain 接口读取，标签是语言无关的 ASCII，
# 因此界面语言变化不会影响解析。
read_probe() {
  U_BACKEND=""
  U_CMDFILE=""
  [ -f "$SUT" ] || { U_BACKEND="$(t backend.noscript)"; return 0; }
  local out
  out="$(BOOT_SPLASH_LANG="$LANG_CODE" "$SUT" status --porcelain 2>/dev/null)"
  U_BACKEND="$(printf '%s\n' "$out" | sed -nE 's/^BACKEND=//p' | head -n1)"
  U_CMDFILE="$(printf '%s\n' "$out" | sed -nE 's/^CMDLINE_FILE=//p' | head -n1)"
  [ -n "$U_BACKEND" ] || U_BACKEND="$(t backend.unknown)"
}

# ---------- 按需提权 ---------------------------------------------------------

SUDO_ACQUIRED=no       # 本会话是否已通过验证
KEEPALIVE_PID=""
PENDING_REASON=""      # 当前操作的用途说明，显示在密码提示上方
ELEV_ENV=()            # 需要透传给 sudo 子进程的环境变量

build_elev_env() {
  ELEV_ENV=()
  [ -n "${BOOT_SPLASH_ROOT:-}" ] && ELEV_ENV+=("BOOT_SPLASH_ROOT=$BOOT_SPLASH_ROOT")
  [ -n "${DESTDIR:-}" ]          && ELEV_ENV+=("DESTDIR=$DESTDIR")
  [ -n "${BINDIR:-}" ]           && ELEV_ENV+=("BINDIR=$BINDIR")
  # 提权后 boot-splash 也必须是同一种语言，否则界面会中英混杂
  ELEV_ENV+=("BOOT_SPLASH_LANG=$LANG_CODE")
  return 0
}

sudo_cached() { have_sudo && sudo -n true 2>/dev/null; }

# 会话内保活 sudo 时间戳，避免长时间停留在菜单后突然失效
start_keepalive() {
  [ -n "$KEEPALIVE_PID" ] && return 0
  ( while sleep 50; do sudo -n true 2>/dev/null || exit 0; done ) >/dev/null 2>&1 &
  KEEPALIVE_PID=$!
  return 0
}
stop_keepalive() {
  [ -n "$KEEPALIVE_PID" ] || return 0
  kill "$KEEPALIVE_PID" 2>/dev/null || true
  KEEPALIVE_PID=""
  return 0
}

# 读取密码，不回显。输入源与菜单保持一致：
#   stdin 是终端或管道 -> 读 stdin（正常交互 / 管道驱动）
#   否则（stdin 被重定向到文件或 /dev/null）-> 退回 /dev/tty
read_secret() { # $1=接收变量名
  # 注意：内部临时变量不能叫 pw 之类的常见名。bash 是动态作用域，
  # printf -v "<name>" 会命中最近的那个同名局部变量；如果这里也声明了同名
  # local，就会写到自己身上，调用方拿不到值（且 set -u 下直接退出）。
  local __var="$1" _secret="" rc=1
  if [ -t 0 ] || [ -p /dev/stdin ]; then
    IFS= read -rs _secret; rc=$?
  elif [ -r /dev/tty ] && IFS= read -rs _secret < /dev/tty 2>/dev/null; then
    rc=0
  else
    IFS= read -rs _secret; rc=$?
  fi
  printf '\n'
  [ "$rc" -eq 0 ] || return 1
  printf -v "$__var" '%s' "$_secret"
  _secret=""
  return 0
}

# 取得 sudo 凭据（已有缓存则免密）。成功返回 0。
acquire_sudo() {
  if sudo_cached; then
    SUDO_ACQUIRED=yes; start_keepalive; return 0
  fi

  if ! have_sudo; then
    err "$(t need.nosudo)"
    printf '    %s%s%s\n' "$C_DIM" "$(t need.nosudo.hint "$SELF")" "$C_OFF"
    return 1
  fi

  printf '\n  %s%s%s\n' "$C_YEL" "$(t need.title)" "$C_OFF"
  [ -n "$PENDING_REASON" ] && printf '    %s%s%s\n' "$C_DIM" "$PENDING_REASON" "$C_OFF"

  local attempt pw
  for attempt in 1 2 3; do
    printf '    %s%s%s ' "$C_CYA" "$(t pw.prompt)" "$C_OFF"
    if ! read_secret pw; then
      printf '\n'
      warn "$(t pw.cancel)"
      return 1
    fi
    if [ -z "$pw" ]; then
      warn "$(t pw.empty)"
      continue
    fi
    # 密码只经 stdin 传给 sudo，不出现在命令行参数里（ps 看不到）
    if printf '%s\n' "$pw" | sudo -S -p '' -v 2>/dev/null; then
      unset pw
      SUDO_ACQUIRED=yes
      ok "$(t pw.ok)"
      start_keepalive
      return 0
    fi
    unset pw
    warn "$(t pw.wrong "$attempt")"
  done
  err "$(t pw.giveup)"
  return 1
}

# 确保具备 root 权限；$1=给用户看的理由
ensure_root() {
  PENDING_REASON="${1:-$(t need.reason.default)}"
  if is_root; then return 0; fi
  case "${BOOT_SPLASH_NO_ELEVATE:-no}" in
    yes|YES|1|true|TRUE)
      err "$(t need.disabled "$BOOT_SPLASH_NO_ELEVATE")"
      return 1 ;;
  esac
  if [ "$SUDO_ACQUIRED" = yes ] && sudo_cached; then return 0; fi
  SUDO_ACQUIRED=no
  acquire_sudo
}

# 以 root 身份执行：本来就是 root 就直接跑，否则走 sudo（透传必要环境变量）
run_as_root() {
  if is_root; then
    "$@"
  else
    sudo -n env "${ELEV_ENV[@]}" "$@"
  fi
}

# ---------- 界面 -------------------------------------------------------------

draw_lang_menu() { # $1=默认选项（en|zh）
  local def="$1" num
  case "$def" in zh) num=2 ;; *) num=1 ;; esac
  clear_screen
  printf '\n'
  hline ╔ ═ ╗
  box "$(t lang.title)"
  hline ╠ ═ ╣
  box " ${C_GRN}1${C_OFF}) English"
  box " ${C_GRN}2${C_OFF}) 中文"
  hline ╚ ═ ╝
  printf '\n  %s [1-2] (%s: %s): ' "$(t lang.prompt)" "$(t lang.default)" "$([ "$num" = 2 ] && printf '中文' || printf 'English')"
}

draw() {
  local id_tag
  if is_root; then
    id_tag="${C_GRN}$(t id.root)${C_OFF}"
  elif [ "$SUDO_ACQUIRED" = yes ]; then
    id_tag="${C_GRN}$(t id.sudo-ok)${C_OFF}"
  elif have_sudo; then
    id_tag="${C_YEL}$(t id.sudo-maybe)${C_OFF}"
  else
    id_tag="${C_RED}$(t id.no-sudo)${C_OFF}"
  fi

  read_mode; read_probe

  clear_screen
  printf '\n'
  hline ╔ ═ ╗
  box "${C_CYA}$(t hdr.title "$VERSION")${C_OFF}"
  hline ╠ ═ ╣
  box "$(padw "$(t hdr.mode)" 14) : ${C_CYA}${U_MODE}${C_OFF}"
  box "$(padw "$(t hdr.backend)" 14) : ${U_BACKEND}"
  box "$(padw "$(t hdr.cmdline)" 14) : ${U_CMDFILE:-$(t hdr.notdetected)}"
  if is_installed; then
    box "$(padw "$(t hdr.tool)" 14) : ${C_GRN}$(t inst.yes)${C_OFF}  ${C_DIM}${INSTALL_PATH}${C_OFF}"
  else
    box "$(padw "$(t hdr.tool)" 14) : ${C_YEL}$(t inst.no)${C_OFF}  ${C_DIM}${INSTALL_PATH}${C_OFF}"
  fi
  box "$(padw "$(t hdr.identity)" 14) : ${id_tag}"
  hline ╠ ═ ╣
  box " ${C_GRN}1${C_OFF}) $(t menu.1)"
  box " ${C_GRN}2${C_OFF}) $(t menu.2)"
  box " ${C_GRN}3${C_OFF}) $(t menu.3)"
  box " ${C_GRN}4${C_OFF}) $(t menu.4)"
  box " ${C_GRN}5${C_OFF}) $(t menu.5)"
  box " ${C_GRN}6${C_OFF}) $(t menu.6)"
  box " ${C_GRN}7${C_OFF}) $(t menu.7)"
  box " ${C_GRN}8${C_OFF}) $(t menu.8)"
  box " ${C_GRN}0${C_OFF}) $(t menu.0)"
  hline ╚ ═ ╝
}

show_run() { # $1=标题，其余=命令
  local title="$1"; shift
  printf '\n  %s%s%s\n  %s\n\n' "$C_CYA" "$title" "$C_OFF" "$(rep ─ $((W - 4)))"
  local rc=0
  BOOT_SPLASH_LANG="$LANG_CODE" "$@" || rc=$?
  printf '\n'
  if [ "$rc" -eq 0 ]; then ok "$(t act.done)"; else err "$(t act.failed "$rc")"; fi
  pause
  return 0
}

# ---------- 具体动作 ---------------------------------------------------------

do_install_files() {
  [ -f "$SUT" ] || { err "$(t err.noscript "$SUT")"; return 1; }
  run_as_root install -d "${DESTDIR}${BINDIR}" || return 1
  run_as_root install -m 0755 "$SUT" "$INSTALL_PATH" || return 1
  run_as_root ln -sf boot-splash "${DESTDIR}${BINDIR}/boot-splash-off" || return 1
  run_as_root ln -sf boot-splash "${DESTDIR}${BINDIR}/boot-splash-on" || return 1
  return 0
}

do_uninstall_files() {
  run_as_root rm -f "$INSTALL_PATH" \
        "${DESTDIR}${BINDIR}/boot-splash-off" \
        "${DESTDIR}${BINDIR}/boot-splash-on"
  return 0
}

act_install_and_enable() {
  ensure_root "$(t need.reason.enable)" || { pause; return 1; }
  printf '\n  %s%s%s\n\n' "$C_CYA" "$(t act.step1)" "$C_OFF"
  if is_installed; then
    log "$(t act.already "$INSTALL_PATH")"
  else
    if do_install_files; then
      ok "$(t act.installed "$INSTALL_PATH")"
      ok "$(t act.aliases)"
    else
      err "$(t act.install-fail)"; pause; return 1
    fi
  fi
  pause

  printf '\n  %s%s%s\n' "$C_CYA" "$(t act.step2)" "$C_OFF"
  printf '  %s%s%s\n' "$C_DIM" "$(t act.preview-hint)" "$C_OFF"
  show_run "$(t act.preview-title)" "$SUT" off --dry-run

  if ! ask_yn "$(t act.confirm-apply)"; then
    printf '\n'
    warn "$(t act.cancelled-nosys)"
    pause
    return 0
  fi
  show_run "$(t act.applying)" run_as_root "$SUT" off -y
  printf '\n'
  ok "$(t act.reboot)"
  pause
}

act_restore() {
  ensure_root "$(t need.reason.restore)" || { pause; return 1; }
  printf '\n  %s%s%s\n' "$C_CYA" "$(t act.restore-title)" "$C_OFF"
  printf '  %s%s%s\n' "$C_DIM" "$(t act.preview-hint)" "$C_OFF"
  show_run "$(t act.preview-on-title)" "$SUT" on --dry-run

  if ! ask_yn "$(t act.confirm-restore)"; then
    printf '\n'
    warn "$(t common.cancel)"
    pause
    return 0
  fi
  show_run "$(t act.restoring)" run_as_root "$SUT" on -y
  printf '\n'
  ok "$(t act.reboot)"
  pause
}

act_preview() {
  show_run "$(t act.preview-title)" "$SUT" off --dry-run
}

act_rollback() {
  ensure_root "$(t need.reason.rollback)" || { pause; return 1; }
  printf '\n  %s%s%s\n' "$C_CYA" "$(t act.rollback-title)" "$C_OFF"
  printf '  %s%s%s\n' "$C_DIM" "$(t act.rollback-hint)" "$C_OFF"
  if ! ask_yn "$(t act.confirm-rollback)"; then
    printf '\n'; warn "$(t common.cancel)"; pause; return 0
  fi
  show_run "$(t act.rolling)" run_as_root "$SUT" rollback -y
}

act_install_only() {
  ensure_root "$(t need.reason.install "$INSTALL_PATH")" || { pause; return 1; }
  printf '\n'
  if do_install_files; then
    ok "$(t act.installed "$INSTALL_PATH")"
    ok "$(t act.aliases)"
    printf '\n  %s%s%s\n' "$C_DIM" "$(t act.no-syscfg)" "$C_OFF"
  else
    err "$(t act.install-fail)"
  fi
  pause
}

act_uninstall() {
  ensure_root "$(t need.reason.uninstall "$INSTALL_PATH")" || { pause; return 1; }
  printf '\n'
  warn "$(t act.uninstall-warn)"
  if [ -f "$STATE_FILE" ]; then
    printf '    %s\n' "$(t act.uninstall-hint "$C_GRN" "$C_OFF")"
  fi
  if ! ask_yn "$(t act.confirm-uninstall)"; then
    printf '\n'; warn "$(t common.cancel)"; pause; return 0
  fi
  if do_uninstall_files; then ok "$(t act.uninstalled)"; else err "$(t act.uninstall-fail)"; fi
  pause
}

act_status() { show_run "$(t act.status-title)" "$SUT" status; }

act_switch_lang() {
  printf '\n'
  select_language "$LANG_CODE" || true
  save_lang
  build_elev_env
}

# ---------- 语言选择 ---------------------------------------------------------

select_language() { # $1=默认值；设置全局 LANG_CODE
  local def="${1:-en}" ans
  while :; do
    draw_lang_menu "$def"
    IFS= read -r ans || { printf '\n'; UI_EOF=yes; LANG_CODE="$def"; return 0; }
    case "$ans" in
      1) LANG_CODE=en; return 0 ;;
      2) LANG_CODE=zh; return 0 ;;
      "") LANG_CODE="$def"; return 0 ;;
      *) LANG_CODE="$def"; return 0 ;;
    esac
  done
}

# ---------- 主循环 -----------------------------------------------------------

main_loop() {
  # 命令行/环境变量已指定语言时不再询问
  if [ "$LANG_PRESET" != yes ]; then
    select_language "$LANG_DEFAULT"
    [ "$UI_EOF" = yes ] && return 0
    save_lang
    build_elev_env
  fi

  while :; do
    draw
    printf '\n  %s: ' "$(t menu.prompt)"
    local choice
    IFS= read -r choice || { printf '\n'; UI_EOF=yes; }
    [ "$UI_EOF" = yes ] && { printf '\n'; break; }

    case "$choice" in
      1) act_install_and_enable ;;
      2) act_restore ;;
      3) act_preview ;;
      4) act_rollback ;;
      5) act_install_only ;;
      6) act_uninstall ;;
      7) act_status ;;
      8) act_switch_lang ;;
      0|q|Q) clear_screen; printf '\n  %s\n\n' "$(t common.exit)"; break ;;
      "") ;;
      *) printf '\n'; err "$(t common.invalid "$choice")"; pause ;;
    esac
    [ "$UI_EOF" = yes ] && { printf '\n'; break; }
  done
}

# ---------- 非交互入口 -------------------------------------------------------

usage() {
  if [ "$LANG_CODE" = zh ]; then
    cat <<EOF
$SELF $VERSION — boot-splash 的 TUI 安装 / 管理器

交互模式（启动时先选语言；不需要提前 sudo，需要时会提示输入密码）：
  $SELF                     进入 TUI 菜单（安装 / 启用 / 恢复 / 回滚 / 卸载）
  sudo $SELF                也可以直接用 root 运行，那样全程不询问

非交互模式：
       $SELF --install           只安装程序文件
       $SELF --uninstall         卸载程序文件（不动系统配置）
       $SELF --status            打印详细状态
       $SELF --tui               强制进入 TUI（即使 stdin 不是终端）
       $SELF --install-and-off   安装并直接关闭开机动画
       $SELF --on                恢复图形开机动画

选项：
  --lang=zh|en               指定界面语言，跳过启动时的语言选择

环境变量：
  BOOT_SPLASH_LANG           界面语言（zh | en），会透传给 boot-splash
  DESTDIR                    安装根目录前缀（默认空 = /），测试用
  BINDIR                     安装到哪个 bin 目录（默认 /usr/local/bin）
  BOOT_SPLASH_ROOT           影子根目录，透传给 boot-splash，测试用
  BOOT_SPLASH_NO_ELEVATE=1   禁用自动提权，需要 root 时直接报错
EOF
  else
    cat <<EOF
$SELF $VERSION — TUI installer / manager for boot-splash

Interactive (picks a language at startup; no sudo needed up front — it asks
for a password in the UI when privileges are required):
  $SELF                     Enter the TUI menu (install / enable / restore /
                            rollback / uninstall)
  sudo $SELF                Or run as root directly; nothing is ever asked

Non-interactive:
       $SELF --install           Install the program files only
       $SELF --uninstall         Remove the program files (leaves system config)
       $SELF --status            Print detailed status
       $SELF --tui               Force the TUI (even if stdin is not a terminal)
       $SELF --install-and-off   Install and turn the boot splash off
       $SELF --on                Restore the graphical boot splash

Options:
  --lang=zh|en              Set the UI language and skip the startup picker

Environment:
  BOOT_SPLASH_LANG          UI language (zh | en); passed through to boot-splash
  DESTDIR                   Install root prefix (default empty = /), for testing
  BINDIR                    Which bin directory (default /usr/local/bin)
  BOOT_SPLASH_ROOT          Shadow root, passed through to boot-splash
  BOOT_SPLASH_NO_ELEVATE=1  Disable automatic privilege elevation
EOF
  fi
}

main() {
  local mode="" arg
  # 环境变量已指定语言时同样跳过启动时的语言选择（脚本化调用依赖这一点）
  if [ -n "${BOOT_SPLASH_LANG:-}" ]; then LANG_PRESET=yes; fi
  for arg in "$@"; do
    case "$arg" in
      --tui) mode=tui ;;
      --install) mode=install ;;
      --uninstall) mode=uninstall ;;
      --status) mode=status ;;
      --install-and-off) mode=install-off ;;
      --on|--restore) mode=on ;;
      --lang=*) LANG_CODE="${arg#*=}"; LANG_PRESET=yes ;;
      --lang)   mode="lang-missing" ;;
      -h|--help) mode=help ;;
      -V|--version) printf '%s %s\n' "$SELF" "$VERSION"; exit 0 ;;
      *) err "$(t err.unknownarg "$arg")"; usage >&2; exit 1 ;;
    esac
  done

  # 语言解析：命令行/环境变量 > 已保存的选择 > 系统 locale > en
  if [ "$LANG_PRESET" = yes ]; then
    case "$LANG_CODE" in zh|en) ;; *) LANG_CODE="$(detect_lang)" ;; esac
  else
    local saved
    saved="$(load_saved_lang || true)"
    if [ -n "$saved" ]; then LANG_DEFAULT="$saved"
    else LANG_DEFAULT="$(detect_lang)"; fi
    LANG_CODE="$LANG_DEFAULT"
  fi

  if [ "$mode" = lang-missing ]; then
    err "--lang needs a value (zh | en)"; usage >&2; exit 1
  fi
  if [ "$mode" = help ]; then usage; exit 0; fi

  if [ -z "$mode" ]; then
    if [ -t 0 ] || [ -t 1 ]; then
      mode=tui
    else
      err "$(t err.noterm)"
      exit 1
    fi
  fi

  [ -f "$SUT" ] || { err "$(t err.noscript "$SUT")"; exit 1; }

  build_elev_env
  trap 'stop_keepalive' EXIT
  trap 'stty echo 2>/dev/null; stop_keepalive; exit 130' INT TERM

  case "$mode" in
    tui) main_loop ;;
    install)
      # DESTDIR is a local staging tree and does not require privilege.
      if [ -z "$DESTDIR" ]; then
        ensure_root "$(t need.reason.install "$INSTALL_PATH")" || exit 1
      fi
      do_install_files && log "$(t act.installed "$INSTALL_PATH")" || exit 1 ;;
    uninstall)
      # DESTDIR is a local staging tree and does not require privilege.
      if [ -z "$DESTDIR" ]; then
        ensure_root "$(t need.reason.uninstall "$INSTALL_PATH")" || exit 1
      fi
      do_uninstall_files && log "$(t act.uninstalled)" ;;
    status)
      BOOT_SPLASH_LANG="$LANG_CODE" "$SUT" status ;;
    install-off)
      ensure_root "$(t need.reason.enable)" || exit 1
      do_install_files || exit 1
      log "$(t act.installed "$INSTALL_PATH")"
      run_as_root "$SUT" off -y ;;
    on)
      ensure_root "$(t need.reason.restore)" || exit 1
      run_as_root "$SUT" on -y ;;
  esac
}

main "$@"
