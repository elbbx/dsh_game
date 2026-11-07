extends Node2D
## 纯 2D 等距可玩原型。正式开发用 TileMapLayer 与独立场景重构，但保持逻辑坐标/交互语义。

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

@onready var camera: Camera2D = $Camera2D
@onready var hud: Label = $UI/HUD/Status
@onready var instructions: Label = $UI/Instructions
@onready var toast: Label = $UI/Toast
@onready var fade: ColorRect = $UI/Fade

var player_cell: Vector2 = Vector2(7.0, 9.0)
var outdoor_saved_cell: Vector2 = Vector2(7.0, 9.0)
var interior_saved_cell: Vector2 = Vector2(2.0, 7.0)
var inside: bool = false
var transitioning: bool = false
var player_hp: float = 100.0
var hunger: float = 4.0
var bandages: int = 2
var scrap: int = 0
var loot_claimed: bool = false
var hour: float = 8.0
var attack_cooldown: float = 0.0
var hit_cooldown: float = 0.0
var toast_timer: float = 0.0
var zombies: Array[Dictionary] = []

func _ready() -> void:
    zombies = [
        {"pos": Vector2(5.0, 15.0), "hp": 55.0, "inside": false},
        {"pos": Vector2(19.0, 13.0), "hp": 55.0, "inside": false},
        {"pos": Vector2(16.0, 18.0), "hp": 55.0, "inside": false},
        {"pos": Vector2(8.0, 4.0), "hp": 40.0, "inside": true}
    ]
    fade.color = Color(0, 0, 0, 0)
    _toast("EXTERIOR  |  Go to the house door and press E", 4.5)
    _update_ui()

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
        # Small cabinet blocks a corner in the prototype.
        return not (c.distance_to(Vector2(6.0, 4.0)) < 0.75)
    if c.x < 0.7 or c.y < 0.7 or c.x > 22.4 or c.y > 22.4: return false
    if c.distance_to(Vector2(12.0, 10.0)) < 1.6: return false
    return true

func _process_zombies(delta: float) -> void:
    for zombie in zombies:
        if bool(zombie["inside"]) != inside or float(zombie["hp"]) <= 0.0: continue
        var zp: Vector2 = zombie["pos"]
        var dist: float = zp.distance_to(player_cell)
        if dist > 0.8 and dist < 7.0:
            var target: Vector2 = zp.move_toward(player_cell, delta * 1.1)
            if _walkable(target): zombie["pos"] = target
        elif dist <= 0.8 and hit_cooldown <= 0.0:
            player_hp = maxf(0.0, player_hp - 8.0)
            hit_cooldown = 0.9
            _toast("ZOMBIE HIT!", 1.0)
    if player_hp <= 0.0: _toast("YOU DIED  |  F9 Load last save", 10.0)

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

func _interact() -> void:
    if transitioning or player_hp <= 0.0: return
    if inside:
        if player_cell.distance_to(Vector2(2.0, 7.0)) < 1.85:
            _transition(false)
            return
        if not loot_claimed and player_cell.distance_to(Vector2(7.0, 5.0)) < 1.8:
            loot_claimed = true
            scrap += 3
            bandages += 1
            _toast("LOOT: 3 scrap + 1 bandage", 2.4)
            return
        _toast("Find the exit or supply crate", 1.6)
        return
    if player_cell.distance_to(Vector2(14.0, 12.0)) < 2.1:
        _transition(true)
        return
    _toast("Go to the front door", 1.5)

func _attack() -> void:
    if transitioning or player_hp <= 0.0 or attack_cooldown > 0.0: return
    attack_cooldown = 0.45
    var found: bool = false
    for zombie in zombies:
        if bool(zombie["inside"]) != inside or float(zombie["hp"]) <= 0.0: continue
        var zp: Vector2 = zombie["pos"]
        if zp.distance_to(player_cell) <= 1.65:
            zombie["hp"] = maxf(0.0, float(zombie["hp"]) - 28.0)
            found = true
    _toast("HIT" if found else "Miss", 0.35)

func _transition(to_inside: bool) -> void:
    transitioning = true
    var tween: Tween = create_tween()
    tween.tween_property(fade, "color:a", 1.0, 0.14)
    tween.tween_callback(Callable(self, "_set_space").bind(to_inside))
    tween.tween_property(fade, "color:a", 0.0, 0.16)
    tween.tween_callback(Callable(self, "_finish_transition"))

func _finish_transition() -> void:
    transitioning = false

func _set_space(to_inside: bool) -> void:
    if to_inside:
        outdoor_saved_cell = player_cell
        player_cell = interior_saved_cell
        inside = true
        _toast("INSIDE HOUSE   |   Press E near exit to leave", 3.0)
    else:
        interior_saved_cell = player_cell
        player_cell = outdoor_saved_cell
        inside = false
        _toast("RETURNED OUTSIDE", 2.0)
    camera.position = cell_to_screen(player_cell).round()
    queue_redraw()

func _save_game() -> void:
    if transitioning: return
    var enemy_data: Array = []
    for z in zombies:
        var p: Vector2 = z["pos"]
        enemy_data.append({"x": p.x, "y": p.y, "hp": z["hp"], "inside": z["inside"]})
    var state: Dictionary = {
        "version": 1, "inside": inside,
        "player": [player_cell.x, player_cell.y],
        "outside": [outdoor_saved_cell.x, outdoor_saved_cell.y],
        "inside_saved": [interior_saved_cell.x, interior_saved_cell.y],
        "hp": player_hp, "hunger": hunger, "hour": hour,
        "bandages": bandages, "scrap": scrap, "loot_claimed": loot_claimed,
        "zombies": enemy_data
    }
    var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        _toast("Save failed", 2.0)
        return
    file.store_string(JSON.stringify(state))
    file.close()
    _toast("Saved to user://", 1.8)

func _load_game() -> void:
    if transitioning: return
    if not FileAccess.file_exists(SAVE_PATH):
        _toast("No save yet (F5)", 2.0)
        return
    var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null: return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != 1:
        _toast("Unsupported save", 2.0)
        return
    var a: Array = parsed.get("player", [7, 9])
    var b: Array = parsed.get("outside", [7, 9])
    var c: Array = parsed.get("inside_saved", [2, 7])
    if a.size() != 2 or b.size() != 2 or c.size() != 2: return
    player_cell = Vector2(float(a[0]), float(a[1]))
    outdoor_saved_cell = Vector2(float(b[0]), float(b[1]))
    interior_saved_cell = Vector2(float(c[0]), float(c[1]))
    inside = bool(parsed.get("inside", false))
    player_hp = clampf(float(parsed.get("hp", 100)), 0.0, 100.0)
    hunger = clampf(float(parsed.get("hunger", 4)), 0.0, 100.0)
    hour = float(parsed.get("hour", 8))
    bandages = int(parsed.get("bandages", 0))
    scrap = int(parsed.get("scrap", 0))
    loot_claimed = bool(parsed.get("loot_claimed", false))
    zombies.clear()
    var saved_zombies: Array = parsed.get("zombies", [])
    for z in saved_zombies:
        if typeof(z) == TYPE_DICTIONARY:
            zombies.append({"pos": Vector2(float(z.get("x", 0)), float(z.get("y", 0))), "hp": float(z.get("hp", 0)), "inside": bool(z.get("inside", false))})
    camera.position = cell_to_screen(player_cell).round()
    _toast("Save loaded", 2.0)

func _toast(message: String, seconds: float) -> void:
    toast.text = message
    toast_timer = seconds

func _update_ui() -> void:
    var time_text: String = "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]
    hud.text = "OVERCASTVEIL / %s / %s\nHP:%d   HUNGER:%d   BANDAGE:%d   SCRAP:%d" % ["INTERIOR" if inside else "EXTERIOR", time_text, int(player_hp), int(hunger), bandages, scrap]
    if inside:
        instructions.text = "WASD Move  |  E Loot / Exit  |  Space Attack  |  H Heal  |  F5 Save  F9 Load"
    else:
        instructions.text = "WASD Move  |  E Enter house  |  Space Attack  |  H Heal  |  F5 Save  F9 Load"

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
        sortable.append({"pos": Vector2(12.0, 10.0), "tex": HOUSE, "shift": Vector2(75.0, 112.0)})
        sortable.append({"pos": Vector2(4.0, 5.0), "tex": TREE, "shift": Vector2(30.0, 82.0)})
        sortable.append({"pos": Vector2(20.0, 5.0), "tex": TREE, "shift": Vector2(30.0, 82.0)})
        sortable.append({"pos": Vector2(20.0, 19.0), "tex": TREE, "shift": Vector2(30.0, 82.0)})
        sortable.append({"pos": Vector2(14.0, 12.0), "tex": EXIT, "shift": Vector2(13.0, 31.0)})
    else:
        sortable.append({"pos": Vector2(2.0, 7.0), "tex": EXIT, "shift": Vector2(13.0, 31.0)})
        if not loot_claimed:
            sortable.append({"pos": Vector2(7.0, 5.0), "tex": LOOT, "shift": Vector2(11.0, 22.0)})
    for z in zombies:
        if bool(z["inside"]) == inside and float(z["hp"]) > 0.0:
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
    # Isometric back-wall line as self-contained 2D pixel silhouettes.
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
