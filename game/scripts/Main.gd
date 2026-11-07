extends Node2D
## 纯 2D 等距可玩原型。正式开发用 TileMapLayer 与独立场景重构，但保持逻辑坐标/交互语义。
##
## 本增量：两栋同模板房屋各有独立 RoomState（搜刮标记 / 室内敌人 / 返回锚点 /
## 室内存档坐标）。按 doc/独立室内切换与建筑.md 的「同模板双屋不串库存」验收。
## 仍是示例级：状态存内存 + 单个 JSON 存档，成品级事务留待 S2。

const TILE_W: float = 64.0
const TILE_H: float = 32.0
const SAVE_PATH: String = "user://overcastveil_prototype_save.json"
const GRASS: Texture2D = preload("res://art/grass.png")
const GRASS2: Texture2D = preload("res://art/grass2.png")
const DIRT: Texture2D = preload("res://art/dirt.png")
const ROAD: Texture2D = preload("res://art/road.png")
const FLOOR: Texture2D = preload("res://art/floor.png")
const FLOOR2: Texture2D = preload("res://art/floor2.png")
const HOUSE: Texture2D = preload("res://art/house.png")
const PLAYER: Texture2D = preload("res://art/player.png")
const ZOMBIE: Texture2D = preload("res://art/zombie.png")
const TREE: Texture2D = preload("res://art/tree.png")
const LOOT: Texture2D = preload("res://art/loot.png")
const EXIT: Texture2D = preload("res://art/exit.png")

## 同模板的两栋房屋：各自的门外锚点与室内入口坐标。
## template_id 相同，验证「同模板双屋不串库存」。
const HOUSES: Array[Dictionary] = [
    {"id": "BLD_A", "template": "house_01", "door": Vector2(14.0, 12.0), "entry": Vector2(2.0, 7.0)},
    {"id": "BLD_B", "template": "house_01", "door": Vector2(19.0, 17.0), "entry": Vector2(2.0, 7.0)},
]
const INTERIOR_EXIT: Vector2 = Vector2(2.0, 7.0)
const INTERIOR_LOOT: Vector2 = Vector2(7.0, 5.0)
const INTERIOR_CABINET: Vector2 = Vector2(6.0, 4.0)

@onready var camera: Camera2D = $Camera2D
@onready var hud: Label = $UI/HUD/Status
@onready var instructions: Label = $UI/Instructions
@onready var toast: Label = $UI/Toast
@onready var fade: ColorRect = $UI/Fade

var player_cell: Vector2 = Vector2(7.0, 9.0)
var outdoor_saved_cell: Vector2 = Vector2(7.0, 9.0)
var inside: bool = false
var transitioning: bool = false
var active_house_id: String = ""   # 当前所处房屋；室外为空
var player_hp: float = 100.0
var hunger: float = 4.0
var bandages: int = 2
var scrap: int = 0
var hour: float = 8.0
var attack_cooldown: float = 0.0
var hit_cooldown: float = 0.0
var toast_timer: float = 0.0
var zombies: Array = []   # 室外敌人（共用一张室外图）
## room_states[house_id] = {loot_claimed, interior_saved_cell, interior_zombies}
## 每栋房屋独立，绝不共享已搜刮标记或击杀记录。
var room_states: Dictionary = {}

func _ready() -> void:
    _reset_run()

func _fresh_room_state() -> Dictionary:
    return {
        "loot_claimed": false,
        "interior_saved_cell": Vector2(2.0, 7.0),
        "interior_zombies": [
            {"pos": Vector2(8.0, 4.0), "hp": 40.0, "inside": true}
        ],
    }

## Restart a fresh run after death. Keeps the save file intact (F9 still works).
func _reset_run() -> void:
    player_cell = Vector2(7.0, 9.0)
    outdoor_saved_cell = Vector2(7.0, 9.0)
    inside = false
    transitioning = false
    active_house_id = ""
    player_hp = 100.0
    hunger = 4.0
    bandages = 2
    scrap = 0
    hour = 8.0
    attack_cooldown = 0.0
    hit_cooldown = 0.0
    toast_timer = 0.0
    zombies = [
        {"pos": Vector2(5.0, 15.0), "hp": 55.0, "inside": false},
        {"pos": Vector2(19.0, 13.0), "hp": 55.0, "inside": false},
        {"pos": Vector2(16.0, 18.0), "hp": 55.0, "inside": false},
    ]
    room_states = {}
    for h in HOUSES:
        room_states[String(h["id"])] = _fresh_room_state()
    fade.color = Color(0, 0, 0, 0)
    camera.position = cell_to_screen(player_cell).round()
    _toast("EXTERIOR  |  Two houses: approach a door and press E", 4.5)
    _update_ui()
    queue_redraw()

func _room() -> Dictionary:
    if active_house_id.is_empty() or not room_states.has(active_house_id):
        return {}
    return room_states[active_house_id]

func cell_to_screen(c: Vector2) -> Vector2:
    return Vector2((c.x - c.y) * TILE_W * 0.5, (c.x + c.y) * TILE_H * 0.5)

func screen_to_cell(p: Vector2) -> Vector2:
    return Vector2(p.y / TILE_H + p.x / TILE_W, p.y / TILE_H - p.x / TILE_W)

func _process(delta: float) -> void:
    var d: Vector2 = Vector2.ZERO
    if not transitioning and player_hp > 0.0:
        if Input.is_key_pressed(KEY_A): d.x -= 1.0
        if Input.is_key_pressed(KEY_D): d.x += 1.0
        if Input.is_key_pressed(KEY_W): d.y -= 1.0
        if Input.is_key_pressed(KEY_S): d.y += 1.0
        if d.length_squared() > 0.0:
            d = d.normalized()
            var step: Vector2 = Vector2(d.x / 64.0 + d.y / 32.0, -d.x / 64.0 + d.y / 32.0) * delta * 68.0
            var next: Vector2 = player_cell + step
            if _walkable(next): player_cell = next
    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    hit_cooldown = maxf(0.0, hit_cooldown - delta)
    toast_timer -= delta
    if toast_timer <= 0.0: toast.text = ""
    hour = fmod(hour + delta / 48.0, 24.0)
    hunger = minf(100.0, hunger + delta / 150.0)
    if hunger > 85.0:
        player_hp = maxf(0.0, player_hp - delta * 0.6)
    if not transitioning and player_hp > 0.0: _process_zombies(delta)
    camera.position = cell_to_screen(player_cell).round()
    _update_ui()
    queue_redraw()

func _walkable(c: Vector2) -> bool:
    if inside:
        if c.x < 0.7 or c.y < 0.7 or c.x > 10.3 or c.y > 8.3: return false
        return not (c.distance_to(INTERIOR_CABINET) < 0.75)
    if c.x < 0.7 or c.y < 0.7 or c.x > 22.4 or c.y > 22.4: return false
    for h in HOUSES:
        if c.distance_to(h["door"] - Vector2(2.0, 2.0)) < 1.6: return false
    return true

func _active_enemies() -> Array:
    ## RoomState 存在 Dictionary 中，取出的数组是无类型 Array；统一返回 Array
    ## 避免 GDScript 4 的 typed-array 返回类型检查报错。
    if inside:
        var r: Dictionary = _room()
        if r.is_empty(): return []
        return r["interior_zombies"]
    return zombies

func _process_zombies(delta: float) -> void:
    for zombie in _active_enemies():
        if float(zombie["hp"]) <= 0.0: continue
        var zp: Vector2 = zombie["pos"]
        var dist: float = zp.distance_to(player_cell)
        if dist > 0.8 and dist < 7.0:
            var target: Vector2 = zp.move_toward(player_cell, delta * 1.1)
            if _walkable(target): zombie["pos"] = target
        elif dist <= 0.8 and hit_cooldown <= 0.0:
            player_hp = maxf(0.0, player_hp - 8.0)
            hit_cooldown = 0.9
            _toast("ZOMBIE HIT!", 1.0)
    if player_hp <= 0.0: _toast("YOU DIED  |  R New run  |  F9 Load last save", 10.0)

func _unhandled_key_input(event: InputEvent) -> void:
    if not (event is InputEventKey): return
    var key_event: InputEventKey = event as InputEventKey
    if not key_event.pressed or key_event.echo: return
    match key_event.keycode:
        KEY_E: _interact()
        KEY_SPACE: _attack()
        KEY_H:
            if bandages > 0 and player_hp < 100.0:
                bandages -= 1
                player_hp = minf(100.0, player_hp + 32.0)
                _toast("Used bandage", 1.4)
        KEY_F5: _save_game()
        KEY_F9: _load_game()
        KEY_R:
            if player_hp <= 0.0:
                _reset_run()
                _toast("NEW RUN  |  Back to the street", 2.2)

func _house_near_player() -> Dictionary:
    for h in HOUSES:
        if player_cell.distance_to(h["door"]) < 2.1:
            return h
    return {}

func _interact() -> void:
    if transitioning or player_hp <= 0.0: return
    if inside:
        if player_cell.distance_to(INTERIOR_EXIT) < 1.85:
            _transition(false)
            return
        var r: Dictionary = _room()
        if not bool(r.get("loot_claimed", true)) and player_cell.distance_to(INTERIOR_LOOT) < 1.8:
            r["loot_claimed"] = true
            scrap += 3
            bandages += 1
            _toast("LOOT (this house): 3 scrap + 1 bandage", 2.4)
            return
        _toast("Find the exit or supply crate", 1.6)
        return
    var h: Dictionary = _house_near_player()
    if not h.is_empty():
        _transition(true, String(h["id"]))
        return
    _toast("Go to a front door", 1.5)

func _attack() -> void:
    if transitioning or player_hp <= 0.0 or attack_cooldown > 0.0: return
    attack_cooldown = 0.45
    var found: bool = false
    for zombie in _active_enemies():
        if float(zombie["hp"]) <= 0.0: continue
        var zp: Vector2 = zombie["pos"]
        if zp.distance_to(player_cell) <= 1.65:
            zombie["hp"] = maxf(0.0, float(zombie["hp"]) - 28.0)
            found = true
    _toast("HIT" if found else "Miss", 0.35)

func _transition(to_inside: bool, house_id: String = "") -> void:
    transitioning = true
    var tween: Tween = create_tween()
    tween.tween_property(fade, "color:a", 1.0, 0.14)
    tween.tween_callback(Callable(self, "_set_space").bind(to_inside, house_id))
    tween.tween_property(fade, "color:a", 0.0, 0.16)
    tween.tween_callback(Callable(self, "_finish_transition"))

func _finish_transition() -> void:
    transitioning = false

func _set_space(to_inside: bool, house_id: String) -> void:
    if to_inside:
        outdoor_saved_cell = player_cell
        active_house_id = house_id
        var r: Dictionary = _room()
        player_cell = r.get("interior_saved_cell", Vector2(2.0, 7.0))
        inside = true
        _toast("INSIDE %s   |   Press E near exit to leave" % house_id, 3.0)
    else:
        var r: Dictionary = _room()
        r["interior_saved_cell"] = player_cell
        player_cell = outdoor_saved_cell
        inside = false
        active_house_id = ""
        _toast("RETURNED OUTSIDE", 2.0)
    camera.position = cell_to_screen(player_cell).round()
    queue_redraw()

func _serialize_zombies(arr: Array) -> Array:
    var out: Array = []
    for z in arr:
        var p: Vector2 = z["pos"]
        out.append({"x": p.x, "y": p.y, "hp": z["hp"]})
    return out

func _save_game() -> void:
    if transitioning: return
    var rooms: Dictionary = {}
    for h in HOUSES:
        var hid: String = String(h["id"])
        var r: Dictionary = room_states.get(hid, _fresh_room_state())
        rooms[hid] = {
            "loot_claimed": bool(r.get("loot_claimed", false)),
            "interior_saved": [r["interior_saved_cell"].x, r["interior_saved_cell"].y],
            "interior_zombies": _serialize_zombies(r["interior_zombies"]),
        }
    var state: Dictionary = {
        "version": 2, "inside": inside, "house": active_house_id,
        "player": [player_cell.x, player_cell.y],
        "outside": [outdoor_saved_cell.x, outdoor_saved_cell.y],
        "hp": player_hp, "hunger": hunger, "hour": hour,
        "bandages": bandages, "scrap": scrap,
        "zombies": _serialize_zombies(zombies), "rooms": rooms,
    }
    var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        _toast("Save failed", 2.0)
        return
    file.store_string(JSON.stringify(state))
    file.close()
    _toast("Saved to user://", 1.8)

func _deserialize_zombies(arr: Array, inside_flag: bool) -> Array:
    var out: Array = []
    for z in arr:
        if typeof(z) == TYPE_DICTIONARY:
            out.append({"pos": Vector2(float(z.get("x", 0)), float(z.get("y", 0))), "hp": float(z.get("hp", 0)), "inside": inside_flag})
    return out

## v1 存档（单屋、全局 loot_claimed）平滑迁移为 v2 双屋结构。
func _migrate_v1(p: Dictionary) -> void:
    var claimed: bool = bool(p.get("loot_claimed", false))
    var a: Dictionary = room_states.get("BLD_A", _fresh_room_state())
    a["loot_claimed"] = claimed
    var zs: Array = p.get("zombies", [])
    var interior: Array[Dictionary] = []
    for z in zs:
        if typeof(z) == TYPE_DICTIONARY and bool(z.get("inside", false)):
            interior.append(z)
    if not interior.is_empty():
        a["interior_zombies"] = _deserialize_zombies(interior, true)

func _load_game() -> void:
    if transitioning: return
    if not FileAccess.file_exists(SAVE_PATH):
        _toast("No save yet (F5)", 2.0)
        return
    var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null: return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        _toast("Unsupported save", 2.0)
        return
    var p: Dictionary = parsed
    var ver: int = int(p.get("version", 0))
    if ver != 2 and ver != 1:
        _toast("Unsupported save", 2.0)
        return
    var a: Array = p.get("player", [7, 9])
    var b: Array = p.get("outside", [7, 9])
    if a.size() != 2 or b.size() != 2: return
    player_cell = Vector2(float(a[0]), float(a[1]))
    outdoor_saved_cell = Vector2(float(b[0]), float(b[1]))
    inside = bool(p.get("inside", false))
    player_hp = clampf(float(p.get("hp", 100)), 0.0, 100.0)
    hunger = clampf(float(p.get("hunger", 4)), 0.0, 100.0)
    hour = float(p.get("hour", 8))
    bandages = int(p.get("bandages", 0))
    scrap = int(p.get("scrap", 0))
    zombies.clear()
    var outdoor: Array[Dictionary] = []
    for z in p.get("zombies", []):
        if typeof(z) == TYPE_DICTIONARY and not bool(z.get("inside", false)):
            outdoor.append(z)
    zombies = _deserialize_zombies(outdoor, false)
    if zombies.is_empty():
        zombies = [
            {"pos": Vector2(5.0, 15.0), "hp": 55.0, "inside": false},
            {"pos": Vector2(19.0, 13.0), "hp": 55.0, "inside": false},
            {"pos": Vector2(16.0, 18.0), "hp": 55.0, "inside": false},
        ]
    room_states = {}
    for h in HOUSES:
        room_states[String(h["id"])] = _fresh_room_state()
    if ver == 2:
        active_house_id = String(p.get("house", ""))
        var rooms: Dictionary = p.get("rooms", {})
        for h in HOUSES:
            var hid: String = String(h["id"])
            if rooms.has(hid):
                var rs: Dictionary = rooms[hid]
                var st: Dictionary = _fresh_room_state()
                st["loot_claimed"] = bool(rs.get("loot_claimed", false))
                var ip: Array = rs.get("interior_saved", [2, 7])
                if ip.size() == 2:
                    st["interior_saved_cell"] = Vector2(float(ip[0]), float(ip[1]))
                var iz: Array = rs.get("interior_zombies", [])
                if not iz.is_empty():
                    st["interior_zombies"] = _deserialize_zombies(iz, true)
                room_states[hid] = st
    else:
        active_house_id = "BLD_A" if inside else ""
        _migrate_v1(p)
    if inside and active_house_id.is_empty():
        inside = false
    camera.position = cell_to_screen(player_cell).round()
    _toast("Save loaded (v%d)" % ver, 2.0)

func _toast(message: String, seconds: float) -> void:
    toast.text = message
    toast_timer = seconds

func _update_ui() -> void:
    var time_text: String = "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]
    var where: String = "INTERIOR %s" % active_house_id if inside else "EXTERIOR"
    hud.text = "OVERCASTVEIL / %s / %s\nHP:%d   HUNGER:%d   BANDAGE:%d   SCRAP:%d" % [where, time_text, int(player_hp), int(hunger), bandages, scrap]
    if inside:
        instructions.text = "WASD Move  |  E Loot / Exit  |  Space Attack  |  H Heal  |  F5 Save  F9 Load  |  R New run (on death)"
    else:
        instructions.text = "WASD Move  |  E Enter house (2 doors)  |  Space Attack  |  H Heal  |  F5 Save  F9 Load  |  R New run (on death)"

func _ground_tex(x: int, y: int) -> Texture2D:
    if inside: return FLOOR if posmod(x + y, 4) != 0 else FLOOR2
    if abs(x - y + 4) <= 1: return ROAD
    if posmod(x * 17 + y * 43, 11) == 0: return DIRT
    return GRASS2 if posmod(x * 7 + y * 3, 5) == 0 else GRASS

func _draw() -> void:
    if inside:
        _draw_interior()
    else:
        _draw_exterior()
    var sortable: Array[Dictionary] = []
    if not inside:
        for h in HOUSES:
            var door: Vector2 = h["door"]
            sortable.append({"pos": door - Vector2(2.0, 2.0), "tex": HOUSE, "shift": Vector2(75.0, 112.0)})
            sortable.append({"pos": door, "tex": EXIT, "shift": Vector2(13.0, 31.0)})
        sortable.append({"pos": Vector2(4.0, 5.0), "tex": TREE, "shift": Vector2(30.0, 82.0)})
        sortable.append({"pos": Vector2(20.0, 5.0), "tex": TREE, "shift": Vector2(30.0, 82.0)})
        sortable.append({"pos": Vector2(4.0, 19.0), "tex": TREE, "shift": Vector2(30.0, 82.0)})
    else:
        sortable.append({"pos": INTERIOR_EXIT, "tex": EXIT, "shift": Vector2(13.0, 31.0)})
        var r: Dictionary = _room()
        if not bool(r.get("loot_claimed", true)):
            sortable.append({"pos": INTERIOR_LOOT, "tex": LOOT, "shift": Vector2(11.0, 22.0)})
    for z in _active_enemies():
        if float(z["hp"]) > 0.0:
            sortable.append({"pos": z["pos"], "tex": ZOMBIE, "shift": Vector2(12.0, 36.0)})
    sortable.append({"pos": player_cell, "tex": PLAYER, "shift": Vector2(12.0, 36.0)})
    sortable.sort_custom(_compare_drawables)
    for obj in sortable:
        draw_texture(obj["tex"], (cell_to_screen(obj["pos"]) - obj["shift"]).round())

func _draw_exterior() -> void:
    for y in range(24):
        for x in range(24):
            var p: Vector2 = cell_to_screen(Vector2(x, y))
            draw_texture(_ground_tex(x, y), p - Vector2(32, 16))

func _draw_interior() -> void:
    for y in range(10):
        for x in range(12):
            var p: Vector2 = cell_to_screen(Vector2(x, y))
            draw_texture(_ground_tex(x, y), p - Vector2(32, 16))
    for x in range(12):
        var top: Vector2 = cell_to_screen(Vector2(x, 0))
        draw_line(top + Vector2(-30, -18), top + Vector2(0, -34), Color("776a65"), 12.0)
    for y in range(10):
        var left: Vector2 = cell_to_screen(Vector2(0, y))
        draw_line(left + Vector2(-32, -18), left + Vector2(-32, -40), Color("756d67"), 12.0)

func _compare_drawables(a: Dictionary, b: Dictionary) -> bool:
    var av: Vector2 = a["pos"]
    var bv: Vector2 = b["pos"]
    return av.x + av.y < bv.x + bv.y
