class_name Consumables
extends RefCounted
## 消耗品效果服务（纯数据，从 data/runtime/items.json 归一化生成的
## res://data/consumables.json 读取）。不持有节点/渲染依赖，可在 headless
## 下单独测试。规则只解析明确写明的 `hunger -N` / `thirst -N`，
## 其它 usage_rule_raw（制作/医疗/工具）不猜测、不执行。

const TABLE_PATH: String = "res://data/consumables.json"

var table: Dictionary = {}          ## item_id -> effects Dictionary
var inventory: Dictionary = {}       ## item_id -> 剩余数量（原型用计数，非矩形格）
var load_error: String = ""

func _init() -> void:
    reload()

## 重新从资源加载效果表；失败时保留空表并记录错误（不静默吞掉）。
func reload() -> void:
    table = {}
    load_error = ""
    if not FileAccess.file_exists(TABLE_PATH):
        load_error = "missing " + TABLE_PATH
        return
    var file: FileAccess = FileAccess.open(TABLE_PATH, FileAccess.READ)
    if file == null:
        load_error = "cannot open " + TABLE_PATH
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        load_error = "invalid consumables json"
        return
    var p: Dictionary = parsed
    var items: Array = p.get("items", [])
    for entry in items:
        if typeof(entry) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = entry
        var eid: String = String(e.get("id", ""))
        if eid.is_empty():
            continue
        var eff: Dictionary = {}
        var raw_eff: Variant = e.get("effects", {})
        if typeof(raw_eff) == TYPE_DICTIONARY:
            for k in raw_eff.keys():
                var key: String = String(k)
                if key == "hunger" or key == "thirst":
                    eff[key] = float(raw_eff[k])
        if not eff.is_empty():
            table[eid] = eff

func has_item(item_id: String) -> bool:
    return table.has(item_id)

func effect_of(item_id: String) -> Dictionary:
    if not table.has(item_id):
        return {}
    return (table[item_id] as Dictionary).duplicate()

func add(item_id: String, amount: int = 1) -> bool:
    if not has_item(item_id) or amount <= 0:
        return false
    inventory[item_id] = int(inventory.get(item_id, 0)) + amount
    return true

func count(item_id: String) -> int:
    return int(inventory.get(item_id, 0))

func total_count() -> int:
    var n: int = 0
    for k in inventory.keys():
        n += int(inventory[k])
    return n

## 消耗一个物品并把效果应用到 SurvivalStats。
## 返回是否成功：未知 id / 库存为 0 / stats 为 null 均拒绝且不修改任何状态。
func consume(item_id: String, stats: SurvivalStats) -> bool:
    if not has_item(item_id) or count(item_id) <= 0 or stats == null:
        return false
    var eff: Dictionary = effect_of(item_id)
    if eff.is_empty():
        return false
    inventory[item_id] = count(item_id) - 1
    if inventory[item_id] <= 0:
        inventory.erase(item_id)
    if eff.has("hunger"):
        stats.hunger = clampf(stats.hunger + float(eff["hunger"]), 0.0, 100.0)
    if eff.has("thirst"):
        stats.thirst = clampf(stats.thirst + float(eff["thirst"]), 0.0, 100.0)
    return true

## 找到库存中第一个能降低指定 need 的物品（用于 F/G 快捷键）。
func first_for(need: String) -> String:
    var best: String = ""
    for k in inventory.keys():
        var iid: String = String(k)
        if int(inventory[iid]) <= 0:
            continue
        var eff: Dictionary = effect_of(iid)
        if eff.has(need) and float(eff[need]) < 0.0:
            if best.is_empty() or iid < best:
                best = iid
    return best

func inventory_to_dict() -> Dictionary:
    var out: Dictionary = {}
    for k in inventory.keys():
        out[String(k)] = int(inventory[k])
    return out

func inventory_from_dict(d: Dictionary) -> void:
    inventory = {}
    for k in d.keys():
        var iid: String = String(k)
        var n: int = int(d[k])
        if has_item(iid) and n > 0:
            inventory[iid] = n
