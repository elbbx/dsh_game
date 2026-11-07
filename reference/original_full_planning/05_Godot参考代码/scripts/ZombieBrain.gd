extends CharacterBody3D
class_name ZombieBrain
## 薄行为层：路径由NavigationAgent3D，感知与人口逻辑由外部服务提供。
enum State { WANDER, INVESTIGATE, CHASE, LAST_KNOWN, SEARCH, ATTACK, RETURN }
@export var walk_speed := 1.2
@export var chase_speed := 2.0
@export var attack_distance := 1.5
@export var last_seen_memory_s := 9.0
@export var search_duration_s := 8.0
@export var repath_interval_s := 0.65
@export var gravity := 18.0
@onready var nav: NavigationAgent3D = $NavigationAgent3D
var state := State.WANDER
var target: Node3D = null
var last_seen := Vector3.ZERO
var lost_timer := 0.0
var search_timer := 0.0
var repath_timer := 0.0
var target_visible := false

func notice_target(visible: bool, entity: Node3D) -> void:
    # 外部PerceptionSystem必须先做范围/角度/遮挡判定。
    target_visible = visible and is_instance_valid(entity)
    if target_visible:
        target = entity
        last_seen = entity.global_position
        lost_timer = 0.0
        state = State.CHASE
    elif state == State.CHASE:
        state = State.LAST_KNOWN

func hear_sound(position: Vector3, strength: float) -> void:
    if state in [State.CHASE, State.ATTACK]:return
    if strength <= 0.0:return
    last_seen = position
    state = State.INVESTIGATE
    nav.target_position = position

func _physics_process(delta: float) -> void:
    repath_timer += delta
    if state == State.CHASE:
        if not is_instance_valid(target):
            state = State.LAST_KNOWN
        elif target_visible:
            last_seen = target.global_position
            if repath_timer > repath_interval_s:
                nav.target_position = last_seen
                repath_timer = 0.0
            if global_position.distance_to(last_seen) <= attack_distance:
                state = State.ATTACK
        else:
            state = State.LAST_KNOWN
    elif state == State.LAST_KNOWN:
        lost_timer += delta
        if repath_timer > repath_interval_s:
            nav.target_position = last_seen
            repath_timer = 0.0
        if global_position.distance_to(last_seen) < 1.5 or lost_timer > last_seen_memory_s:
            search_timer = 0.0
            state = State.SEARCH
    elif state == State.SEARCH:
        search_timer += delta
        if search_timer > search_duration_s:state = State.RETURN
    elif state == State.ATTACK:
        if not target_visible or not is_instance_valid(target):state = State.LAST_KNOWN
        elif global_position.distance_to(target.global_position) > attack_distance * 1.25:state = State.CHASE
        else:
            velocity.x = 0.0;velocity.z = 0.0
            _apply_gravity(delta);move_and_slide();return
    if state in [State.CHASE, State.LAST_KNOWN, State.INVESTIGATE, State.SEARCH, State.RETURN]:
        if nav.is_navigation_finished():
            velocity.x = 0.0;velocity.z = 0.0
        else:
            var next_point := nav.get_next_path_position() # 每个物理帧更新已有路径
            var direction := next_point - global_position
            direction.y = 0.0
            var speed := chase_speed if state == State.CHASE else walk_speed
            if direction.length_squared() > 0.01:
                direction = direction.normalized()
            velocity.x = direction.x * speed
            velocity.z = direction.z * speed
    else:
        velocity.x = 0.0;velocity.z = 0.0
    _apply_gravity(delta)
    move_and_slide()

func _apply_gravity(delta: float) -> void:
    if not is_on_floor():velocity.y -= gravity * delta
    else:velocity.y = 0.0
