#!/usr/bin/env python3
"""用 airports.yaml 里的真实订阅链接渲染出可用的 mihomo 配置。

为什么要有这一步:
  config.yaml 是**模板**(公开仓库/可以随便分享), 里面只有 REPLACE_ME_A ~ REPLACE_ME_D 占位;
  真实的机场订阅链接是凭证, 只放在本地 airports.yaml(.gitignore 已排除) 里。

用法:
  cp airports.example.yaml airports.yaml   # 然后填链接
  python3 scripts/render.py                # 输出 dist/config.yaml
  bash scripts/check.sh                    # 用 mihomo 校验语法
"""
import argparse
import os
import re
import shutil
import sys

SLOTS = [("A", "机场一", "1️⃣"), ("B", "机场二", "2️⃣"), ("C", "机场三", "3️⃣"), ("D", "机场四", "4️⃣")]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_airports(path):
    try:
        import yaml
    except ImportError:
        sys.exit("需要 pyyaml:  pip install pyyaml   (或 apt install python3-yaml)")
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    items = data.get("airports") or []
    if not items:
        sys.exit(f"{path} 里没有 airports 列表")
    out = {}
    for it in items:
        aid = str(it.get("id", "")).strip().upper()
        url = (it.get("url") or "").strip()
        if aid not in {s[0] for s in SLOTS}:
            sys.exit(f"未知 slot id: {aid!r} (只支持 A/B/C/D)")
        if not url or url.startswith("REPLACE_ME") or any(
            k in url for k in ("你的", "替换", "填这里", "https://example.com")
        ):
            sys.exit(f"slot {aid} 的 url 还是占位内容, 没填真实订阅链接: {url!r}")
        out[aid] = {"name": it.get("name") or dict((s[0], s[1]) for s in SLOTS)[aid], "url": url}
    return out


def drop_provider_block(text, name):
    """删掉某个机场的 proxy-providers 块"""
    lines = text.split("\n")
    out, skipping = [], False
    for ln in lines:
        if ln.startswith(f'  "{name}":'):
            skipping = True
            continue
        if skipping:
            # provider 块内容: 4 空格起的键值对 / 6 空格起的子键 / 6 空格起的注释
            if ln.startswith("    ") or ln.startswith("      "):
                continue
            skipping = False
        out.append(ln)
    return "\n".join(out)


def drop_group_block(text, name):
    """删掉某个以 '- name: <name>' 开头的策略组块(到下一个顶格 '- name:' 为止)"""
    lines = text.split("\n")
    start = None
    for i, ln in enumerate(lines):
        if ln.startswith("- name: ") and name in ln:
            start = i
            break
    if start is None:
        return text
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("- name: "):
            end = j
            break
    return "\n".join(lines[:start] + lines[end:])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--airports", default=os.path.join(ROOT, "airports.yaml"))
    ap.add_argument("--template", default=os.path.join(ROOT, "config.yaml"))
    ap.add_argument("--out", default=os.path.join(ROOT, "dist", "config.yaml"))
    args = ap.parse_args()

    if not os.path.exists(args.airports):
        sys.exit(f"找不到 {args.airports}\n先 cp airports.example.yaml airports.yaml 并填链接")

    airports = load_airports(args.airports)
    text = open(args.template, encoding="utf-8").read()

    filled, dropped = [], []
    for tag, name, _ in SLOTS:
        if tag in airports:
            text = text.replace(f"REPLACE_ME_{tag}", airports[tag]["url"])
            filled.append(f"{name}({tag})")
        else:
            text = drop_provider_block(text, name)
            text = drop_group_block(text, f"{SLOTS[[s[0] for s in SLOTS].index(tag)][2]} {name}")
            text = text.replace(f"  - {name}\n", "")
            dropped.append(name)

    # 只检查"非注释行"的残留占位(头部说明和示例块里的 REPLACE_ME_* 是给人看的)
    left = []
    for ln in text.split("\n"):
        if ln.lstrip().startswith("#"):
            continue
        left += re.findall(r"REPLACE_ME_[A-Z]+", ln)
    if left:
        sys.exit(f"模板里仍有未替换占位: {sorted(set(left))}")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    open(args.out, "w", encoding="utf-8").write(text)
    print(f"已用 {len(filled)} 个机场: {', '.join(filled)}")
    if dropped:
        print(f"未配置(已从模板中整块剔除): {', '.join(dropped)}")
    print(f"输出: {args.out}")
    print("下一步: bash scripts/check.sh")


if __name__ == "__main__":
    main()
