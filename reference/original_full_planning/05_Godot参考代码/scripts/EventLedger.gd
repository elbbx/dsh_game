extends RefCounted
class_name EventLedger
## 只做去重与阶段记录；完整WAL持久化由SaveRepository实现。
var _committed: Dictionary = {}
var _pending: Dictionary = {}

func begin(id: String, payload: Dictionary) -> bool:
    if id.is_empty() or _committed.has(id) or _pending.has(id):return false
    _pending[id] = payload.duplicate(true)
    return true

func commit(id: String) -> bool:
    if _committed.has(id):return false
    if not _pending.has(id):return false
    _committed[id] = _pending[id].duplicate(true)
    _pending.erase(id)
    return true

func abort(id: String) -> void:
    _pending.erase(id)

func export_state() -> Dictionary:
    return {"committed": _committed.duplicate(true),"pending":_pending.duplicate(true)}

func import_state(value: Dictionary) -> void:
    _committed = value.get("committed",{}).duplicate(true)
    _pending = value.get("pending",{}).duplicate(true)
