extends Node
class_name WorldNoiseBus
signal noise_emitted(data: Dictionary)
## 能让附近丧尸调查声音；克苏鲁听觉默认为关闭，仅特定敌人显式启用。
func emit_noise(event_id: String,position: Vector3,strength: float,
                radius_m: float,category: String,world_layer: String) -> void:
    if event_id.is_empty() or radius_m <= 0.0:return
    noise_emitted.emit({"event_id":event_id,"position":position,
        "strength":clampf(strength,0.0,1.0),"radius_m":radius_m,
        "category":category,"world_layer":world_layer})

func perceived_strength(event: Dictionary,listener: Vector3,
                        wall_occlusion_factor: float,weather_mask_factor: float) -> float:
    var d := listener.distance_to(event.get("position",Vector3.ZERO))
    var radius := maxf(0.1,float(event.get("radius_m",1.0)))
    if d >= radius:return 0.0
    return float(event.get("strength",1.0))*pow(1.0-d/radius,2.0)*clampf(wall_occlusion_factor,0,1)*clampf(weather_mask_factor,0,1)
