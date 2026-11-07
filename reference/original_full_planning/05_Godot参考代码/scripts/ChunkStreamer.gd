extends Node
class_name ChunkStreamer
## 参考：64m区块状态机。请求/生成部分调用外部ChunkProvider；节点增删只在主线程执行。
signal chunk_requested(key: Vector2i, request_version: int)
signal chunk_activate(key: Vector2i, manifest: Dictionary)
signal chunk_deactivate(key: Vector2i)
signal chunk_save_requested(key: Vector2i, snapshot: Dictionary)

@export var chunk_size_m: float = 64.0
@export var active_radius_chunks: int = 2
@export var prefetched_radius_chunks: int = 4
@export var unload_hysteresis_chunks: int = 2
@export var max_new_requests_per_update: int = 5
@export var max_activations_per_update: int = 2
@export var update_interval_s: float = 0.25

var _time_accum := 0.0
var _requests: Dictionary = {}  # Vector2i -> {version, state, manifest}
var _desired_active: Dictionary = {}
var _next_version := 1
var _ready_queue: Array[Vector2i] = []
var _last_center := Vector2i.ZERO

func world_to_chunk(global_position: Vector3) -> Vector2i:
    return Vector2i(floori(global_position.x / chunk_size_m), floori(global_position.z / chunk_size_m))

func _process(delta: float) -> void:
    _time_accum += delta
    if _time_accum < update_interval_s:
        return
    _time_accum = 0.0
    # 宿主通过update_streaming传入角色与车辆预测位置。

func update_streaming(player_position: Vector3, predicted_position: Vector3) -> void:
    var center := world_to_chunk(player_position)
    var ahead := world_to_chunk(predicted_position)
    _last_center = center
    var wanted: Dictionary = {}
    for x in range(-prefetched_radius_chunks, prefetched_radius_chunks + 1):
        for z in range(-prefetched_radius_chunks, prefetched_radius_chunks + 1):
            var key := ahead + Vector2i(x, z)
            var dist: int = maxi(abs(key.x - center.x), abs(key.y - center.y))
            if dist <= prefetched_radius_chunks + 1:
                wanted[key] = true
    # 速度预测区块之外，也必须预取玩家当前位置的核心块。
    for x in range(-active_radius_chunks, active_radius_chunks + 1):
        for z in range(-active_radius_chunks, active_radius_chunks + 1):
            wanted[center + Vector2i(x,z)] = true
    _desired_active.clear()
    for x in range(-active_radius_chunks, active_radius_chunks + 1):
        for z in range(-active_radius_chunks, active_radius_chunks + 1):
            _desired_active[center + Vector2i(x,z)] = true
    var keys: Array = wanted.keys()
    keys.sort_custom(func(a, b): return _distance_sq(a, center) < _distance_sq(b, center))
    var requested := 0
    for key in keys:
        if requested >= max_new_requests_per_update:
            break
        if _requests.has(key):
            continue
        var ver := _next_version
        _next_version += 1
        _requests[key] = {"version":ver, "state":"REQUESTED", "manifest":{}}
        chunk_requested.emit(key, ver)
        requested += 1
    _activate_ready_chunks()
    for key in _requests.keys():
        var dist := maxi(abs(key.x - center.x), abs(key.y - center.y))
        if dist > prefetched_radius_chunks + unload_hysteresis_chunks:
            _start_unload(key)

func receive_manifest(key: Vector2i, request_version: int, manifest: Dictionary) -> void:
    # 由数据准备层在主线程回调，不可在工作线程直接对场景树操作。
    if not _requests.has(key):
        return
    var entry: Dictionary = _requests[key]
    if entry["version"] != request_version or entry["state"] != "REQUESTED":
        return  # 作废的异步结果被丢弃
    entry["state"] = "DATA_READY"
    entry["manifest"] = manifest.duplicate(true)
    _requests[key] = entry
    _ready_queue.append(key)

func _activate_ready_chunks() -> void:
    var processed := 0
    var remaining: Array[Vector2i] = []
    for key in _ready_queue:
        if not _requests.has(key):
            continue
        var entry: Dictionary = _requests[key]
        if processed >= max_activations_per_update or not _desired_active.has(key):
            remaining.append(key)
            continue
        if entry["state"] == "DATA_READY":
            entry["state"] = "ACTIVE"
            _requests[key] = entry
            chunk_activate.emit(key, entry["manifest"])
            processed += 1
    _ready_queue = remaining

func on_chunk_snapshot_committed(key: Vector2i) -> void:
    if not _requests.has(key):
        return
    if _requests[key]["state"] == "SERIALIZING":
        chunk_deactivate.emit(key)
        _requests.erase(key)

func _start_unload(key: Vector2i) -> void:
    var entry: Dictionary = _requests.get(key, {})
    if entry.is_empty() or entry.get("state", "") == "SERIALIZING":
        return
    if entry["state"] != "ACTIVE":
        _requests.erase(key)
        return
    entry["state"] = "SERIALIZING"
    _requests[key] = entry
    chunk_save_requested.emit(key, {"chunk_key":str(key), "version":entry["version"]})
    # 必须等待SaveRepository确认后调用on_chunk_snapshot_committed，不能立刻删除Node。

func _distance_sq(a: Vector2i, b: Vector2i) -> int:
    var d: Vector2i = a - b
    return d.x * d.x + d.y * d.y
