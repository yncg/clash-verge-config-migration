#!/usr/bin/env bash
#
# sanitize-check.sh
# 在把 Clash 配置提交到 Git / 分享给别人之前，扫描里面可能泄露的敏感信息
#
# 用法:
#   ./sanitize-check.sh ~/Library/Application\ Support/io.github.clash-verge-rev.clash-verge-rev
#   ./sanitize-check.sh examples/ profiles.yaml
#   ./sanitize-check.sh --quiet <路径>     # 只输出结论，不打印匹配行
#
# 退出码:
#   0 = 未发现明显敏感信息
#   1 = 发现疑似敏感信息（会打印位置）
#
set -uo pipefail

QUIET=0
if [ "${1:-}" = "--quiet" ]; then
  QUIET=1
  shift
fi

if [ $# -eq 0 ]; then
  echo "用法: $0 [--quiet] <文件或目录> [更多路径...]"
  exit 1
fi

# macOS 自带 grep 支持 -E -r -n
FOUND_TOTAL=0

c_ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
c_warn() { printf '\033[33m!\033[0m %s\n' "$1"; }
c_err()  { printf '\033[31m✗\033[0m %s\n' "$1" >&2; }
hdr()    { printf '\n\033[1m%s\033[0m\n' "$1"; }

# 扫描某一类模式
# 参数: <说明> <grep 正则> <严重级别>
scan() {
  local label="$1"
  local pattern="$2"
  local level="$3"      # HIGH / MED
  local hits

  hits=$(grep -rInE "$pattern" "$@" 2>/dev/null \
         | grep -v "^Binary file" \
         | head -40)

  if [ -n "$hits" ]; then
    FOUND_TOTAL=$((FOUND_TOTAL + 1))
    if [ "$level" = "HIGH" ]; then
      c_err "$label"
    else
      c_warn "$label"
    fi
    if [ "$QUIET" -eq 0 ]; then
      printf '%s\n' "$hits" | while IFS= read -r line; do
        # 把过长的行截断，避免刷屏；同时屏蔽疑似凭据的连续十六进制串
        local trimmed
        trimmed=$(printf '%s' "$line" | cut -c1-160)
        trimmed=$(printf '%s' "$trimmed" | sed -E 's/(token=)[A-Za-z0-9_-]{6,}/\1***REDACTED***/g')
        trimmed=$(printf '%s' "$trimmed" | sed -E 's/(password: *)[^,}]{4,}/\1***REDACTED***/g')
        trimmed=$(printf '%s' "$trimmed" | sed -E 's/(uuid: *)[0-9a-fA-F-]{8,}/\1***REDACTED***/g')
        printf '    %s\n' "$trimmed"
      done
      echo
    fi
  fi
}

hdr "Clash 配置敏感信息自查"
echo "扫描目标: $*"

# ---- 1. 订阅链接里的凭据 ----
scan "订阅 URL 中携带凭据（token / key / uuid / sub）" \
     '(https?://[^"'"'"' ]*[?&](token|access_key|key|uuid|sub|auth)=[A-Za-z0-9_-]{6,})' \
     HIGH

# ---- 2. 节点密码字段 ----
scan "节点密码 / 密钥字段（password / uuid / private-key）" \
     '^[^#]*(password|uuid|private-key|auth-str|auth_str)[[:space:]]*:' \
     HIGH

# ---- 3. 节点服务器地址 ----
scan "节点服务器地址（server 字段）" \
     '^[^#]*[^-]server[[:space:]]*:' \
     HIGH

# ---- 4. 内网 / 私有 IP ----
scan "内网 IP 地址（暴露局域网结构）" \
     '(^|[^0-9])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3})' \
     MED

# ---- 5. 公网 IP 字面量 ----
scan "公网 IP 字面量（可能是节点地址）" \
     '(server|address|host)[^:]{0,20}:[[:space:]]*"?([0-9]{1,3}\.){3}[0-9]{1,3}"?' \
     MED

# ---- 6. 机场话题域名关键词 ----
scan "疑似机场 / 订阅服务域名关键词" \
     '(sub|subscribe|subscribe-url|airport|jichang|v2ray|ssr|clash)[^:]{0,10}:[[:space:]]*https?://' \
     MED

# ---- 7. 常见凭据占位符检查（提醒你别忘了替换） ----
echo
printf '\033[1m%s\033[0m\n' "占位符残留检查"
PLACEHOLDER_COUNT=0
for ph in "YOUR_TOKEN_HERE" "REDACTED" "example.com" "127.0.0.1"; do
  if grep -rIq "$ph" "$@" 2>/dev/null; then
    c_ok "已使用占位符: $ph"
    PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT + 1))
  fi
done
if [ "$PLACEHOLDER_COUNT" -eq 0 ]; then
  c_warn "未发现任何占位符——如果你以为文件已脱敏，请再检查一遍"
fi

# ---- 结论 ----
hdr "结论"
if [ "$FOUND_TOTAL" -eq 0 ]; then
  c_ok "未发现明显敏感信息，可以提交"
  exit 0
else
  c_err "发现 $FOUND_TOTAL 类疑似敏感信息，请先脱敏再提交"
  echo
  echo "建议处理方式："
  echo "  订阅 URL        -> https://example.com/subscribe?token=YOUR_TOKEN_HERE"
  echo "  server 字段     -> example.com 或 127.0.0.1"
  echo "  password / uuid -> REDACTED"
  echo "  内网 IP         -> 192.168.1.100"
  echo
  echo "或直接删掉整个 profiles/ 与 profiles.yaml，只保留脱敏后的示例。"
  exit 1
fi
