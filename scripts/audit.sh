#!/usr/bin/env bash
# 用真实机场审计: 每个策略组"选中的节点是不是组内最快的", 以及分流命中
# 用法: bash scripts/audit.sh            # 审计 dist/config.yaml
#       CONFIG=config.yaml bash scripts/audit.sh
set -uo pipefail
cd "$(dirname "$0")/.."
CONFIG=${CONFIG:-dist/config.yaml}
BIN=${MIHOMO_BIN:-bin/mihomo}
[ -x "$BIN" ] || { echo "先跑 scripts/check.sh 把内核下下来"; exit 1; }
[ -f "$CONFIG" ] || { echo "找不到 $CONFIG (先 render.py)"; exit 1; }
D=$(mktemp -d); LOG=$D/run.log

"$BIN" -f "$CONFIG" -d "$D/data" > "$LOG" 2>&1 &
PID=$!
echo "等待内核加载并完成首轮测速 (20s)..."
sleep 20

python3 - "$LOG" <<'PY'
import json, re, subprocess, sys, time, urllib.parse, urllib.request
API = "http://127.0.0.1:9090"
def api(p, t=200):
    return json.load(urllib.request.urlopen(API + p, timeout=t))
try:
    proxies = api("/proxies")["proxies"]
except Exception as e:
    print("连不上 external-controller, 检查配置里的 external-controller 端口:", e); sys.exit(0)

def resolve(n, d=0):
    while d < 6 and n in proxies and proxies[n].get("type") != "Compatible":
        nx = proxies[n].get("now")
        if not nx or nx == n:
            break
        n, d = nx, d + 1
    return n

groups = [k for k, v in proxies.items()
          if v.get("type") in ("URLTest", "Fallback", "LoadBalance")]
print(f"\n== 测速型策略组 {len(groups)} 个: 选中 vs 组内最快 ==")
print(f"  {'组':20} {'类型':11} {'存活':>4} {'选中ms':>7} {'最快ms':>7} 判定")
ok = tot = 0
for g in groups:
    q = urllib.parse.urlencode({"url": "http://www.gstatic.com/generate_204", "timeout": 3000})
    try:
        d = api(f"/group/{urllib.parse.quote(g)}/delay?{q}")
    except Exception:
        continue
    proxies = api("/proxies")["proxies"]
    alive = {k: v for k, v in d.items() if v and v > 0}
    if not alive:
        continue
    now = resolve(proxies[g].get("now"))
    best, bestms = min(alive.items(), key=lambda x: x[1])
    good = now == best
    tot += 1
    ok += good
    print(f"  {g:20} {proxies[g]['type']:11} {len(alive):>4} {str(alive.get(now)):>7} {bestms:>7} "
          f"{'✅ 最快' if good else '⚠️ 非最快 (fallback 组属正常)'}")
print(f"  -> {ok}/{tot} 选中组内最快")

print("\n== 分流抽查(发真实请求, 读 debug 日志; 需要配置里 log-level: debug) ==")
for dm in ["www.netflix.com", "api.openai.com", "www.youtube.com", "www.taobao.com", "api.telegram.org"]:
    subprocess.run(["curl", "-s", "-o", "/dev/null", "-m", "6", "-x", "http://127.0.0.1:7893",
                    f"https://{dm}/"], capture_output=True)
time.sleep(1)
log = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for dm in ["www.netflix.com", "api.openai.com", "www.youtube.com", "www.taobao.com", "api.telegram.org"]:
    ln = next((l for l in log.split("\n") if dm in l and "match " in l), None)
    m = re.search(r"match ([^ \"]+)", ln) if ln else None
    print(f"  {dm:22} -> {m.group(1) if m else '(未捕获, 把 log-level 调成 debug 再看)'}")
PY

kill $PID 2>/dev/null; wait $PID 2>/dev/null
rm -rf "$D"
echo "### 完成 ###"
