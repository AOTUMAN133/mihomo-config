#!/usr/bin/env bash
# 本地模拟 CI: 起一个临时 http 服务托管假订阅, 渲染 4 机场 / 单机场两种形态, 用 mihomo 校验
set -uo pipefail
cd /root/mihomo-config

python3 -m http.server 18999 --directory tests/fixtures >/tmp/httpd.log 2>&1 &
HTTPD=$!
sleep 1
RAW="http://127.0.0.1:18999"

cat > /tmp/airports-4.yaml <<EOF
airports:
  - {id: A, name: 机场一, url: "$RAW/sub-a.yaml"}
  - {id: B, name: 机场二, url: "$RAW/sub-b.yaml"}
  - {id: C, name: 机场三, url: "$RAW/sub-a.yaml"}
  - {id: D, name: 机场四, url: "$RAW/sub-b.yaml"}
EOF
cat > /tmp/airports-1.yaml <<EOF
airports:
  - {id: B, name: 机场二, url: "$RAW/sub-b.yaml"}
EOF

echo "=== 渲染 4 机场 ==="
python3 scripts/render.py --airports /tmp/airports-4.yaml --out /tmp/config-4.yaml
echo "=== 渲染 单机场(应把 A/C/D 整块剔除) ==="
python3 scripts/render.py --airports /tmp/airports-1.yaml --out /tmp/config-1.yaml
if grep -q "机场三\|机场一\|机场四" /tmp/config-1.yaml; then
  echo "❌ 单机场裁剪失败: 仍残留未配置机场"
else
  echo "✅ 单机场裁剪干净"
fi
echo "=== 占位未填时应报错 ==="
python3 scripts/render.py --airports airports.example.yaml --out /tmp/should-fail.yaml && echo "❌ 没报错" || echo "✅ 报错退出(符合预期)"

echo "=== mihomo -t 4 机场 ==="
./bin/mihomo -t -f /tmp/config-4.yaml -d /tmp/d4 2>&1 | tail -2
echo "=== mihomo -t 单机场 ==="
./bin/mihomo -t -f /tmp/config-1.yaml -d /tmp/d1 2>&1 | tail -2

kill $HTTPD 2>/dev/null || true
