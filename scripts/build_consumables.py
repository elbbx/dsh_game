#!/usr/bin/env python3
"""从 data/runtime/items.json 的 usage_rule_raw 提取可执行的消耗品效果。

两类来源：
1. 数值规则：`hunger -N` / `thirst -N`，按解析到的字面数值执行。
2. 医疗规则：原文只给效果类别、不给数值，按类别映射到保守默认值，
   并在条目上标 `derived: true` 与 `derived_from`，绝不伪装成原始数值。

输出 data/runtime/consumables.json（并同步一份到 game/data/）。
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

# 医疗规则原文 -> 保守默认效果。数值是原型占位，不是原表数值。
MEDICAL_RULES = {
    "use MedicalSystem; target injury/infection": {
        "hp": 25.0, "infection": -10.0,
    },
    "body-part bleeding control; action time 2-5s": {
        "hp": 15.0,
    },
    "decrease ZombieInfection; never cure common cold": {
        "infection": -20.0,
    },
}


def main() -> int:
    items = json.loads(SRC.read_text("utf-8"))
    out = []
    for item in items:
        rule = item.get("usage_rule_raw") or ""
        effects = {}
        derived = False
        if rule in MEDICAL_RULES:
            effects = dict(MEDICAL_RULES[rule])
            derived = True
        else:
            hm = HUNGER_RE.search(rule)
            tm = THIRST_RE.search(rule)
            if hm:
                effects["hunger"] = -float(hm.group(1))
            if tm:
                effects["thirst"] = -float(tm.group(1))
        if not effects:
            continue
        entry = {
            "id": item["id"],
            "display_name": item.get("display_name", item["id"]),
            "category": item.get("category"),
            "usage_rule_raw": rule,
            "effects": effects,
        }
        if derived:
            entry["derived"] = True
            entry["derived_from"] = rule
        out.append(entry)
    payload = {
        "schema": "overcastveil.consumables/2",
        "source": "data/runtime/items.json",
        "count": len(out),
        "items": out,
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    DST.write_text(text, encoding="utf-8")
    GAME_DST.parent.mkdir(parents=True, exist_ok=True)
    GAME_DST.write_text(text, encoding="utf-8")
    med = sum(1 for e in out if e.get("derived"))
    print(f"consumables: {len(out)} ({med} derived medical) -> {DST} and {GAME_DST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
