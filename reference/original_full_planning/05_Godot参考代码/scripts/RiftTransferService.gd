extends RefCounted
class_name RiftTransferService
## 车辆+乘员+拖车一次性迁移：先验证，再写暂存，最后整体提交；不生成复制车。
var ledger := EventLedger.new()

func validate_transfer(entities: Dictionary,vehicle_id: String,
                       destination_layer: String,rift: Dictionary) -> Dictionary:
    if not entities.has(vehicle_id):return {"ok":false,"error":"vehicle not found"}
    if destination_layer not in ["MAIN_WORLD","INVERTED_WORLD"]:
        return {"ok":false,"error":"bad layer"}
    var vehicle: Dictionary = entities[vehicle_id]
    if destination_layer == vehicle.get("active_world_layer", ""):
        return {"ok":false,"error":"same layer"}
    if not rift.get("vehicle_allowed",false):return {"ok":false,"error":"rift not wide enough"}
    if float(vehicle.get("mass_kg",0)) > float(rift.get("mass_limit_kg",0)):
        return {"ok":false,"error":"mass limit"}
    var group: Array = [vehicle_id]
    for occupant in vehicle.get("seat_occupants",[]):
        if not entities.has(occupant):return {"ok":false,"error":"missing occupant"}
        group.append(occupant)
    var tow: String = vehicle.get("tow_vehicle_id","")
    if not tow.is_empty():
        if not rift.get("allow_tow",false):return {"ok":false,"error":"tow denied"}
        if not entities.has(tow):return {"ok":false,"error":"tow missing"}
        group.append(tow)
    return {"ok":true,"group":group}

func transfer_atomic(event_id: String,entities: Dictionary,vehicle_id: String,
                     to_layer: String,rift: Dictionary) -> Dictionary:
    var check := validate_transfer(entities,vehicle_id,to_layer,rift)
    if not check.ok:return check
    if not ledger.begin(event_id,{"vehicle":vehicle_id,"to":to_layer}):
        return {"ok":false,"error":"event duplicate"}
    # staged copy: 原实体不变，直到所有检查及写盘预提交成功
    var staged: Dictionary = entities.duplicate(true)
    for id in check.group:
        staged[id]["active_world_layer"] = to_layer
        staged[id]["last_transfer_id"] = event_id
    # 生产版：此处必须先持久写入pending WAL，验证安全落点/场景层后再提交。
    if not ledger.commit(event_id):return {"ok":false,"error":"ledger"}
    return {"ok":true,"entities":staged,"group":check.group}
