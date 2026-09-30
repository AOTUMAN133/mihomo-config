#!/usr/bin/env bash
# 用 mihomo 内核校验配置: 先语法校验, 再加 --run 做真机加载(provider/策略组)检查
# 用法: bash scripts/check.sh                 # 校验 dist/config.yaml
#       bash scripts/check.sh --run           # 再实际拉起 8 秒, 看节点/provider 加载日志
#       CONFIG=xxx.yaml bash scripts/check.sh # 指定别的配置文件
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${CONFIG:-dist/config.yaml}
if [ ! -f "$CONFIG" ]; then
  echo "找不到 $CONFIG —— 先跑 python3 scripts/render.py (或直接把 config.yaml 填好当配置用)"
  exit 1
fi

BIN=${MIHOMO_BIN:-bin/mihomo}
if [ ! -x "$BIN" ]; then
  echo "==> 下载 mihomo 内核 (compatible 版, 兼容老 CPU)"
  mkdir -p bin
  # 走宿主机代理时取消下面一行的注释
  # export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
  URL=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
        | grep -oE '"browser_download_url": *"[^"]*linux-amd64-compatible-[^"]*\.gz"' \
        | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
  [ -n "$URL" ] || { echo "取不到下载地址(网络? 开代理后再试)"; exit 1; }
  echo "    $URL"
  curl -sL "$URL" -o bin/mihomo.gz && gunzip -f bin/mihomo.gz && chmod +x bin/mihomo
fi
"$BIN" -v | head -1

echo "==> 1/2 语法校验: $CONFIG"
TMP=$(mktemp -d)
# -d 指定工作目录, 避免 provider/规则缓存写进当前目录
"$BIN" -t -f "$CONFIG" -d "$TMP"
echo "    ✅ 语法 OK"

if [ "${1:-}" = "--run" ]; then
  echo "==> 2/2 真机加载 8 秒 (检查 provider / 策略组)"
  "$BIN" -f "$CONFIG" -d "$TMP" > "$TMP/run.log" 2>&1 &
  PID=$!
  sleep 8
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  echo "--- provider 加载 ---"
  grep -iE "provider|proxy.*(loaded|update)" "$TMP/run.log" | head -20 || true
  echo "--- 错误/告警 ---"
  grep -iE "error|warn|fatal" "$TMP/run.log" | head -20 || echo "    (无)"
  echo "--- 端口监听 ---"
  grep -iE "listening|start" "$TMP/run.log" | head -10 || true
fi
rm -rf "$TMP"
