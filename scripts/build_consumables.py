#!/usr/bin/env python3
"""从 data/runtime/items.json 的 usage_rule_raw 提取可执行的消耗品效果。

输出 data/runtime/consumables.json，只保留能明确解析为
`hunger -N` / `thirst -N` 的规则；其它规则（制作、医疗、工具…）不猜测。
可重复运行，幂等。此步只做结构归一化，不等于游戏内已实装全部物品。
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "data" / "runtime" / "items.json"
# Godot 运行时只能读 res:// 下的文件，因此生成物同时落在 game/data/。
# 开发目录的 game 是指向顶层 D:\A_OVERCASTVIEW\game 的 junction，二者同一份。
DST = ROOT / "data" / "runtime" / "consumables.json"
GAME_DST = ROOT.parent.parent / "game" / "data" / "consumables.json"

HUNGER_RE = re.compile(r"hunger\s*-\s*(\d+(?:\.\d+)?)")
THIRST_RE = re.compile(r"thirst\s*-\s*(\d+(?:\.\d+)?)")


def main() -> int:
    items = json.loads(SRC.read_text("utf-8"))
    out = []
    for item in items:
        rule = item.get("usage_rule_raw") or ""
        hm = HUNGER_RE.search(rule)
        tm = THIRST_RE.search(rule)
        if not hm and not tm:
            continue
        effects = {}
        if hm:
            effects["hunger"] = -float(hm.group(1))
        if tm:
            effects["thirst"] = -float(tm.group(1))
        out.append({
            "id": item["id"],
            "display_name": item.get("display_name", item["id"]),
            "category": item.get("category"),
            "usage_rule_raw": rule,
            "effects": effects,
        })
    payload = {
        "schema": "overcastveil.consumables/1",
        "source": "data/runtime/items.json",
        "count": len(out),
        "items": out,
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    DST.write_text(text, encoding="utf-8")
    GAME_DST.parent.mkdir(parents=True, exist_ok=True)
    GAME_DST.write_text(text, encoding="utf-8")
    print(f"consumables: {len(out)} -> {DST} and {GAME_DST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
