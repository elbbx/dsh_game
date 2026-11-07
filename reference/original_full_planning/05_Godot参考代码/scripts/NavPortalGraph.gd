extends RefCounted
class_name NavPortalGraph
## 世界粗路径图；近景运动仍使用NavigationAgent3D和NavMesh。
var astar := AStar3D.new()
var _key_to_id: Dictionary = {}
var _id_to_position: Dictionary = {}
var _next_id := 1

func add_portal(key: String, point: Vector3) -> int:
    if _key_to_id.has(key):return _key_to_id[key]
    var id := _next_id;_next_id += 1
    _key_to_id[key] = id;_id_to_position[id] = point
    astar.add_point(id,point)
    return id

func connect_portals(a_key: String,b_key: String,bidirectional := true) -> bool:
    if not _key_to_id.has(a_key) or not _key_to_id.has(b_key):return false
    var a: int = _key_to_id[a_key];var b: int = _key_to_id[b_key]
    if not astar.are_points_connected(a,b,bidirectional):
        astar.connect_points(a,b,bidirectional)
    return true

func set_portal_enabled(key: String, enabled: bool) -> void:
    if not _key_to_id.has(key):return
    astar.set_point_disabled(_key_to_id[key],not enabled)

func coarse_route(start_key: String,end_key: String) -> PackedVector3Array:
    if not _key_to_id.has(start_key) or not _key_to_id.has(end_key):
        return PackedVector3Array()
    return astar.get_point_path(_key_to_id[start_key],_key_to_id[end_key])
