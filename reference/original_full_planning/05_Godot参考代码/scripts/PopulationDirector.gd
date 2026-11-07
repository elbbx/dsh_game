extends Node
class_name PopulationDirector
## 逻辑人口池：实际敌人Node由外部Factory接收spawn_approved信号实例化。
signal spawn_approved(enemy_id: String, spawn_point: Vector3, type_id: String)
signal spawn_refused(reason: String)

@export var global_active_cap := 140
@export var per_chunk_active_cap := 18
@export var min_spawn_distance_m := 33.0
@export var max_spawn_distance_m := 115.0
@export var sight_protection_margin_m := 12.0
@export var per_update_spawn_budget := 4
@export var respawn_suppression_minutes := 120.0

var _population: Dictionary = {} # chunk_key:str -> persisted {alive_ids, active_ids, killed_ids,...}
var _active_ids: Dictionary = {}
var _last_counter := 0

func register_cell(chunk_id: String, persisted: Dictionary) -> void:
    _population[chunk_id] = persisted.duplicate(true)

func tick_spawn(player_pos: Vector3, candidates: Array[Dictionary],
                physics_space: PhysicsDirectSpaceState3D, camera: Camera3D,
                nav_map: RID, world_layer: String, now_minutes: float) -> void:
    if _active_ids.size() >= global_active_cap:
        spawn_refused.emit("global cap")
        return
    var successes := 0
    for request in candidates:
        if successes >= per_update_spawn_budget:
            break
        var key: String = request.get("chunk_id", "")
        if not _population.has(key):
            continue
        var cell: Dictionary = _population[key]
        if cell.get("active_ids", []).size() >= per_chunk_active_cap:
            continue
        if now_minutes < float(cell.get("suppressed_until_min", -1.0)):
            continue
        var p: Vector3 = request.get("position", Vector3.ZERO)
        var dist := p.distance_to(player_pos)
        if dist < min_spawn_distance_m or dist > max_spawn_distance_m:
            continue
        if request.get("ecosystem", "zombie") == "zombie" and world_layer != "MAIN_WORLD":
            continue
        if _point_visible(camera,p,physics_space):
            continue
        if NavigationServer3D.map_get_closest_point(nav_map,p).distance_to(p) > 2.5:
            continue
        var enemy_id: String = request.get("reserved_enemy_id", "")
        if enemy_id.is_empty() or _active_ids.has(enemy_id):
            continue
        # ID必须已在持久人口池预登记；不能无限生成新ID。
        if enemy_id not in cell.get("alive_ids", []):
            continue
        _active_ids[enemy_id] = key
        var ids: Array = cell.get("active_ids", [])
        ids.append(enemy_id)
        cell["active_ids"] = ids
        _population[key] = cell
        spawn_approved.emit(enemy_id,p,request.get("type_id","ENM_001"))
        successes += 1

func _point_visible(camera: Camera3D,p: Vector3,space: PhysicsDirectSpaceState3D) -> bool:
    if not camera.is_position_in_frustum(p):
        return false
    var origin := camera.global_position
    var q := PhysicsRayQueryParameters3D.create(origin,p)
    var hit := space.intersect_ray(q)
    # 摄像机看得到且没有有效遮挡，禁止生成。边缘还应做额外屏幕距离保护。
    return hit.is_empty() or hit.get("position", p).distance_to(p) < 1.0

func on_enemy_deactivated(enemy_id: String) -> void:
    if not _active_ids.has(enemy_id):return
    var key: String = _active_ids[enemy_id]
    _active_ids.erase(enemy_id)
    if _population.has(key):
        var cell: Dictionary = _population[key]
        var ids: Array = cell.get("active_ids", [])
        ids.erase(enemy_id)
        cell["active_ids"] = ids
        _population[key] = cell

func on_enemy_killed(enemy_id: String, now_minutes: float) -> void:
    if not _active_ids.has(enemy_id):return
    var key: String = _active_ids[enemy_id]
    on_enemy_deactivated(enemy_id)
    if _population.has(key):
        var c: Dictionary = _population[key]
        var live: Array = c.get("alive_ids", [])
        live.erase(enemy_id)
        c["alive_ids"] = live
        c["suppressed_until_min"] = now_minutes + respawn_suppression_minutes
        _population[key] = c
