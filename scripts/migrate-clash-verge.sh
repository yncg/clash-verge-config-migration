#!/usr/bin/env bash
#
# migrate-clash-verge.sh
# 在 macOS 上把 Clash Verge 的配置从一个系统账户迁移到另一个账户
#
# 用法:
#   ./migrate-clash-verge.sh --src-user yg --dst-user zz
#   ./migrate-clash-verge.sh --src-user yg --dst-user zz --dry-run
#   ./migrate-clash-verge.sh --src-path /Volumes/Backup/Users/yg/... --dst-user zz
#
# 参数:
#   --src-user <name>   源账户名（会自动拼出绝对路径）
#   --src-path <path>   直接指定源配置目录（用于外接硬盘/网络共享等场景）
#   --dst-user <name>   目标账户名（默认当前登录用户）
#   --dry-run           只打印将要执行的操作，不实际复制
#   --yes               跳过退出应用的确认提示
#   --keep-geo          连 geoip/geosite/country/asn 数据库一起复制（默认跳过，体积大）
#   -h, --help          显示帮助
#
# 说明:
#   迁移顺序必须是 退出应用 -> 复制 -> 重新启动，否则运行中的应用会把内存里的
#   配置写回磁盘，覆盖你刚复制过去的文件。
#
set -euo pipefail

# ---------- 默认值 ----------
CONF_SUBPATH="Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
DATA_VOLUME="/Volumes/Macintosh HD - Data"

SRC_USER=""
SRC_PATH=""
DST_USER="$(id -un)"
DRY_RUN=0
ASSUME_YES=0
KEEP_GEO=0

# 需要迁移的文件（相对配置目录）
FILES_TO_COPY=(
  "profiles.yaml"
  "verge.yaml"
  "config.yaml"
  "dns_config.yaml"
)
# 需要迁移的目录（内容合并，不删除目标端已有文件）
DIRS_TO_COPY=(
  "profiles"
)
# 可选目录
OPTIONAL_DIRS=(
  "icons"
)
# 体积大、可自动重新生成的数据库文件
GEO_FILES=(
  "geoip.dat"
  "geosite.dat"
  "Country.mmdb"
  "ASN.mmdb"
)
# 明确不要迁移的东西
SKIP_PATTERNS=(
  "cache.db"
  "singleton-instance.json"
  "singleton-instance.lock"
  "logs"
  "service-logs"
  ".window-state.json"
  "window_state.json"
)

# ---------- 输出辅助 ----------
c_ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
c_warn() { printf '\033[33m!\033[0m %s\n' "$1"; }
c_err()  { printf '\033[31m✗\033[0m %s\n' "$1" >&2; }
c_info() { printf '  %s\n' "$1"; }
hdr()    { printf '\n\033[1m%s\033[0m\n' "$1"; }

usage() {
  sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------- 解析参数 ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --src-user)  SRC_USER="$2"; shift 2 ;;
    --src-path)  SRC_PATH="$2"; shift 2 ;;
    --dst-user)  DST_USER="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --yes)       ASSUME_YES=1; shift ;;
    --keep-geo)  KEEP_GEO=1; shift ;;
    -h|--help)   usage ;;
    *)           c_err "未知参数: $1"; echo "用 --help 查看用法"; exit 1 ;;
  esac
done

# ---------- 计算路径 ----------
if [ -n "$SRC_PATH" ]; then
  SRC_DIR="$SRC_PATH"
elif [ -n "$SRC_USER" ]; then
  # 优先用 Data 卷绝对路径（不依赖 firmlink，更稳）；不存在则退回 /Users
  if [ -d "$DATA_VOLUME/Users/$SRC_USER" ]; then
    SRC_DIR="$DATA_VOLUME/Users/$SRC_USER/$CONF_SUBPATH"
  else
    SRC_DIR="/Users/$SRC_USER/$CONF_SUBPATH"
  fi
else
  c_err "必须指定 --src-user 或 --src-path"
  echo "用 --help 查看用法"
  exit 1
fi

DST_DIR="/Users/$DST_USER/$CONF_SUBPATH"
BACKUP_DIR="${DST_DIR}.backup-$(date +%Y%m%d-%H%M%S)"

hdr "Clash Verge 配置迁移"
c_info "源目录:   $SRC_DIR"
c_info "目标目录: $DST_DIR"
c_info "备份到:   $BACKUP_DIR"
[ "$DRY_RUN" -eq 1 ] && c_warn "DRY-RUN 模式：不会实际写入任何文件"

# ---------- 前置检查 ----------
hdr "1. 前置检查"

if [ ! -d "$SRC_DIR" ]; then
  c_err "源配置目录不存在: $SRC_DIR"
  echo "  请确认账户名/路径是否正确，或应用是否安装过。"
  exit 1
fi
c_ok "源配置目录存在"

if [ -r "$SRC_DIR/profiles.yaml" ]; then
  c_ok "源目录可读（profiles.yaml 可访问）"
else
  c_warn "读不到 $SRC_DIR/profiles.yaml"
  echo "  可能是权限不足（另一个账户的家目录默认只有本人和管理员组可读）。"
  echo "  建议用管理员账户执行，或先给当前终端「完全磁盘访问权限」。"
fi

if [ ! -d "$DST_DIR" ]; then
  c_warn "目标配置目录不存在，将创建: $DST_DIR"
  [ "$DRY_RUN" -eq 0 ] && mkdir -p "$DST_DIR"
fi
c_ok "目标目录就绪"

# ---------- 进程检查 ----------
hdr "2. 检查 Clash Verge 是否在运行"

RUNNING=$(pgrep -fl "Clash Verge|verge-mihomo" 2>/dev/null || true)
if [ -n "$RUNNING" ]; then
  c_warn "检测到正在运行的进程："
  echo "$RUNNING" | sed 's/^/    /'
  echo
  echo "  迁移前必须先退出应用，否则它会把内存中的配置写回磁盘，覆盖复制结果。"
  if [ "$ASSUME_YES" -eq 1 ]; then
    REPLY="y"
  else
    printf "  现在帮你退出 Clash Verge？[y/N] "
    read -r REPLY
  fi
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      c_info "[dry-run] 将执行: osascript -e 'quit app \"Clash Verge\"'"
    else
      osascript -e 'quit app "Clash Verge"' 2>/dev/null || true
      sleep 3
      if pgrep -f "Clash Verge|verge-mihomo" >/dev/null 2>&1; then
        c_warn "仍有残留进程，强制结束"
        pkill -f "Clash Verge" 2>/dev/null || true
        pkill -f "verge-mihomo" 2>/dev/null || true
        sleep 2
      fi
    fi
    if pgrep -f "Clash Verge|verge-mihomo" >/dev/null 2>&1; then
      c_err "仍有进程未退出，请手动关闭后重试"
      exit 1
    fi
    c_ok "Clash Verge 已退出"
  else
    c_err "已取消：请先手动退出 Clash Verge 再运行本脚本"
    exit 1
  fi
else
  c_ok "Clash Verge 未在运行"
fi

# ---------- 备份 ----------
hdr "3. 备份目标端现有配置"
if [ "$DRY_RUN" -eq 1 ]; then
  c_info "[dry-run] 将执行: cp -R \"$DST_DIR\" \"$BACKUP_DIR\""
else
  cp -R "$DST_DIR" "$BACKUP_DIR"
  c_ok "已备份: $BACKUP_DIR"
fi

# ---------- 复制文件 ----------
hdr "4. 复制核心配置文件"
for f in "${FILES_TO_COPY[@]}"; do
  if [ -f "$SRC_DIR/$f" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      c_info "[dry-run] cp -f \"$SRC_DIR/$f\" \"$DST_DIR/$f\""
    else
      cp -f "$SRC_DIR/$f" "$DST_DIR/$f"
    fi
    c_ok "$f"
  else
    c_warn "源目录缺少 $f，跳过"
  fi
done

hdr "5. 复制订阅目录"
for d in "${DIRS_TO_COPY[@]}"; do
  if [ -d "$SRC_DIR/$d" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      c_info "[dry-run] cp -R \"$SRC_DIR/$d/.\" \"$DST_DIR/$d/\""
    else
      mkdir -p "$DST_DIR/$d"
      # 用 /. 合并内容：不删除目标端已有文件
      cp -R "$SRC_DIR/$d/." "$DST_DIR/$d/"
    fi
    COUNT=$(ls -1 "$SRC_DIR/$d" 2>/dev/null | wc -l | tr -d ' ')
    c_ok "$d/  ($COUNT 个条目)"
  else
    c_warn "源目录缺少 $d/，跳过"
  fi
done

hdr "6. 复制可选目录"
for d in "${OPTIONAL_DIRS[@]}"; do
  if [ -d "$SRC_DIR/$d" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      c_info "[dry-run] cp -R \"$SRC_DIR/$d/.\" \"$DST_DIR/$d/\""
    else
      mkdir -p "$DST_DIR/$d"
      cp -R "$SRC_DIR/$d/." "$DST_DIR/$d/" 2>/dev/null || true
    fi
    c_ok "$d/"
  else
    c_info "$d/ 不存在，跳过"
  fi
done

if [ "$KEEP_GEO" -eq 1 ]; then
  hdr "7. 复制 GeoIP/GeoSite 数据库"
  for f in "${GEO_FILES[@]}"; do
    if [ -f "$SRC_DIR/$f" ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        c_info "[dry-run] cp -f \"$SRC_DIR/$f\" \"$DST_DIR/$f\""
      else
        cp -f "$SRC_DIR/$f" "$DST_DIR/$f"
      fi
      c_ok "$f"
    fi
  done
else
  hdr "7. GeoIP/GeoSite 数据库"
  c_info "已跳过（体积大且可自动生成）。如需一并复制，加 --keep-geo"
fi

# ---------- 校验 ----------
hdr "8. 校验"

if [ "$DRY_RUN" -eq 0 ]; then
  for f in "${FILES_TO_COPY[@]}"; do
    if [ -f "$SRC_DIR/$f" ] && [ -f "$DST_DIR/$f" ]; then
      if diff -q "$SRC_DIR/$f" "$DST_DIR/$f" >/dev/null 2>&1; then
        c_ok "$f 内容一致"
      else
        c_warn "$f 内容不一致，请检查"
      fi
    fi
  done

  SRC_N=$(ls -1 "$SRC_DIR/profiles" 2>/dev/null | wc -l | tr -d ' ')
  DST_N=$(ls -1 "$DST_DIR/profiles" 2>/dev/null | wc -l | tr -d ' ')
  c_info "profiles/ 条目数: 源 $SRC_N / 目标 $DST_N"
  [ "$SRC_N" -le "$DST_N" ] && c_ok "订阅目录已同步" || c_warn "目标端条目少于源端"

  if [ -f "$DST_DIR/profiles.yaml" ]; then
    CURRENT=$(grep -m1 '^current:' "$DST_DIR/profiles.yaml" | sed 's/^current: *//')
    c_info "当前订阅 (current): $CURRENT"
  fi
fi

# ---------- 明确不迁移的项 ----------
hdr "已按策略跳过以下内容"
for p in "${SKIP_PATTERNS[@]}"; do
  c_info "$p"
done

# ---------- 完成 ----------
hdr "完成"
echo "接下来："
echo "  1) 启动应用:   open -a \"Clash Verge\""
echo "  2) 确认内核:   pgrep -fl verge-mihomo"
echo "  3) 看日志:     tail -20 \"$DST_DIR/logs/sidecar/sidecar_latest.log\""
echo
echo "如果出问题要回滚："
echo "  rm -rf \"$DST_DIR\" && mv \"$BACKUP_DIR\" \"$DST_DIR\""
echo
c_warn "安全提醒：profiles.yaml 与 profiles/ 内含订阅 token 和节点密码，切勿提交到公开仓库。"
