extends RefCounted
class_name PowerGridService
## 简化电网每tick进行Wh守恒结算：发电优先负载，余电充电；不足时放电。
var nodes: Dictionary = {} # id -> {type,production_w,load_w,priority,battery_wh,max_wh}
var adjacency: Dictionary = {} # id -> [neighbor_id]

func register_node(id: String, attrs: Dictionary) -> void:
    nodes[id]=attrs.duplicate(true)
    if not adjacency.has(id):adjacency[id]=[]

func connect_nodes(a: String,b: String) -> void:
    if not nodes.has(a) or not nodes.has(b):return
    if b not in adjacency[a]:adjacency[a].append(b)
    if a not in adjacency[b]:adjacency[b].append(a)

func network_components() -> Array:
    var visited: Dictionary = {};var comps: Array[Array] = []
    for first in nodes.keys():
        if visited.has(first):continue
        var queue: Array = [first];var comp: Array=[];visited[first]=true
        while not queue.is_empty():
            var id = queue.pop_front();comp.append(id)
            for adjacent in adjacency.get(id,[]):
                if nodes.has(adjacent) and not visited.has(adjacent):
                    visited[adjacent]=true;queue.append(adjacent)
        comps.append(comp)
    return comps

func simulate_step(delta_hours: float) -> Dictionary:
    var reports: Dictionary={}
    for comp in network_components():
        var generation := 0.0;var loads: Array=[];var batteries: Array=[]
        for id in comp:
            var node: Dictionary=nodes[id]
            generation += maxf(0.0,float(node.get("production_w",0.0)))*delta_hours
            if node.get("type","")=="battery":batteries.append(id)
            elif float(node.get("load_w",0.0))>0.0:loads.append(id)
        loads.sort_custom(func(a,b):return int(nodes[a].get("priority",5)) < int(nodes[b].get("priority",5)))
        var available := generation
        for id in batteries:
            available += maxf(0.0,float(nodes[id].get("battery_wh",0.0)))
        var draw := 0.0;var enabled: Array=[]
        for id in loads:
            var need := float(nodes[id].get("load_w",0.0))*delta_hours
            if draw + need <= available + 0.0001:draw += need;enabled.append(id)
        # generation used first; drain batteries sequentially for uncovered part
        var needed_battery := maxf(0.0,draw-generation)
        for id in batteries:
            var battery: Dictionary=nodes[id]
            var removed := minf(float(battery.get("battery_wh",0)),needed_battery)
            battery["battery_wh"] = float(battery.get("battery_wh",0))-removed
            needed_battery -= removed
            nodes[id]=battery
        var surplus := maxf(0.0,generation-draw)
        for id in batteries:
            var battery: Dictionary=nodes[id]
            var free := maxf(0.0,float(battery.get("max_wh",0))-float(battery.get("battery_wh",0)))
            var charge := minf(surplus,free)
            battery["battery_wh"] = float(battery.get("battery_wh",0))+charge
            nodes[id]=battery;surplus-=charge
        reports[str(comp)]={"generated_Wh":generation,"used_Wh":draw,"enabled":enabled,"curtailed_Wh":surplus}
    return reports
