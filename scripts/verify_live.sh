#!/usr/bin/env bash
# 临时验证: 拉起 mihomo 后通过 RESTful API 看每个 provider 到底拉到了多少节点
set -uo pipefail
cd /root/mihomo-config
TMP=$(mktemp -d)
./bin/mihomo -f dist/config.yaml -d "$TMP" > "$TMP/run.log" 2>&1 &
PID=$!
sleep 14
echo "=== provider 拉取日志 ==="
grep -iE "provider|proxy.*(init|load|update)" "$TMP/run.log" | head -20
echo "=== API: 每个 provider 的节点数 ==="
curl -s -m 10 http://127.0.0.1:9090/providers/proxies > "$TMP/api.json"
python3 - "$TMP/api.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for name, p in d.get("providers", {}).items():
    vn = p.get("vehicleType")
    if vn == "Compatible":
        print(f"  {name}: {len(p.get('proxies') or [])} 个节点  (type={p.get('type')})")
print("  ---")
print("  路由表里的组数:", len([k for k, v in d.get('providers', {}).items() if v.get('vehicleType') != 'Compatible']))
PY
echo "=== API: 策略组与候选数 ==="
curl -s -m 10 http://127.0.0.1:9090/proxies > "$TMP/groups.json"
python3 - "$TMP/groups.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
g = d.get("proxies", {})
groups = [(k, v) for k, v in g.items() if v.get("type") in ("Selector", "URLTest", "Fallback", "LoadBalance")]
print(f"  策略组总数: {len(groups)}")
for k, v in groups:
    if any(t in k for t in ("手动选择", "自动选择", "故障转移", "负载均衡", "机场", "香港", "美国", "漏网之鱼")):
        print(f"   {k:16} {v['type']:12} 候选={len(v.get('all') or [])} 当前={v.get('now')}")
PY
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
rm -rf "$TMP"
