extends RefCounted
class_name QuickAccessResolver
## 1/2同一组三武器槽；3可读主背包；4/5/6只读快捷取用位置。
const SLOTS := {1:"ranged",2:"melee",3:"tool",4:"medical",5:"food_drink",6:"vision"}

func get_candidates(category: int, weapon_slots: Array[Dictionary],
                    quick_container_items: Array[Dictionary], backpack_items: Array[Dictionary]) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if category not in SLOTS:return result
    var src: Array[Dictionary] = []
    if category in [1,2]:src = weapon_slots
    elif category == 3:
        src.append_array(quick_container_items)
        src.append_array(backpack_items)
    else:src = quick_container_items
    var seen: Dictionary = {}
    for entry in src:
        if entry.get("count",1) <= 0:continue
        var type: String = entry.get("category", "")
        var matches := (
            (category == 1 and type == "ranged") or
            (category == 2 and type == "melee") or
            (category == 3 and type == "tool") or
            (category == 4 and type == "medical") or
            (category == 5 and type in ["food","drink"]) or
            (category == 6 and type == "vision")
        )
        if not matches:continue
        var key: String = entry.get("definition_id", "")
        if not seen.has(key):
            seen[key] = true
            result.append(entry)
    return result

func selection_action(candidates: Array[Dictionary]) -> String:
    if candidates.size() == 0:return "NO_ITEM"
    if candidates.size() == 1:return "EQUIP_DIRECT"
    return "OPEN_RADIAL_MENU"
