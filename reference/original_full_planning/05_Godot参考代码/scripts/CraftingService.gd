extends RefCounted
class_name CraftingService
## 材料检查与单次事务结算。动画/计时由外部CraftJob负责；不要在此反复扣料。
var ledger := EventLedger.new()

func can_craft(recipe: Dictionary,available: Dictionary,skill_level: int) -> bool:
    if skill_level < int(recipe.get("min_level",0)):return false
    for id in recipe.get("ingredients",{}):
        if int(available.get(id,0)) < int(recipe["ingredients"][id]):return false
    return true

func complete_job(event_id: String,recipe: Dictionary,available: Dictionary,
                  skill_level: int) -> Dictionary:
    if not can_craft(recipe,available,skill_level):return {"ok":false,"reason":"conditions"}
    if not ledger.begin(event_id,recipe):return {"ok":false,"reason":"duplicate"}
    var revised: Dictionary = available.duplicate(true)
    for id in recipe["ingredients"]:
        revised[id] = int(revised.get(id,0)) - int(recipe["ingredients"][id])
    var output: String = recipe.get("output_id","")
    if output.is_empty():ledger.abort(event_id);return {"ok":false,"reason":"output"}
    revised[output] = int(revised.get(output,0)) + int(recipe.get("quantity",1))
    ledger.commit(event_id)
    return {"ok":true,"inventory":revised}
