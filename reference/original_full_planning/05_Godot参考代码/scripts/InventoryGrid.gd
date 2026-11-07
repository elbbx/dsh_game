extends RefCounted
class_name InventoryGrid
## 单一网格逻辑，支持多格、旋转、堆叠由外层物品系统管理。
var width: int
var height: int
var placements: Dictionary = {}  # instance_id -> {x,y,w,h}

func _init(w: int,h: int) -> void:
    width = w;height = h

func can_place(item_id: String,x: int,y: int,w: int,h: int) -> bool:
    if x < 0 or y < 0 or w < 1 or h < 1 or x+w > width or y+h > height:return false
    for existing_id in placements.keys():
        if existing_id == item_id:continue
        var r: Dictionary = placements[existing_id]
        if x < r.x+r.w and x+w > r.x and y < r.y+r.h and y+h > r.y:
            return false
    return true

func place(item_id: String,x: int,y: int,w: int,h: int) -> bool:
    if item_id.is_empty() or not can_place(item_id,x,y,w,h):return false
    placements[item_id] = {"x":x,"y":y,"w":w,"h":h}
    return true

func remove(item_id: String) -> void:
    placements.erase(item_id)

func try_rotate(item_id: String) -> bool:
    if not placements.has(item_id):return false
    var r: Dictionary = placements[item_id]
    if can_place(item_id,r.x,r.y,r.h,r.w):
        var old_w: int = r.w
        var old_h: int = r.h
        r.w = old_h
        r.h = old_w
        placements[item_id]=r
        return true
    return false
