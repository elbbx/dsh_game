class_name SurvivalStats
extends RefCounted
## 纯数据生存状态（M02 2D 适配）。
##
## 规范 doc/功能系统落地细则.md：固定时钟负责统计，UI 只订阅事件，
## 存档需保存时间戳和上次统计值。本类不含任何节点/渲染依赖，
## 可脱离场景在 headless 下单独测试。
##
## 命名统一 0..100，"*_need" 越大越缺（hunger/thirst/fatigue），
## hp/stamina/sanity 越大越好，infection/cold 越大越危险。

const STAT_KEYS: Array[String] = [
    "hp", "hunger", "thirst", "fatigue", "sanity", "stamina", "infection", "cold",
]
const STEP_SECONDS: float = 0.25  ## 固定结算步长，与渲染 FPS 解耦

var hp: float = 100.0
var hunger: float = 4.0        ## hunger_need
var thirst: float = 6.0         ## thirst_need
var fatigue: float = 0.0
var sanity: float = 100.0
var stamina: float = 100.0
var infection: float = 0.0
var cold: float = 0.0

## 累计结算次数（存档时钟）与累计实时总秒数。
## 用「总秒数 / 步长」推导 ticks，避免逐次浮点累加在步长边界漂移，
## 从而保证任意 delta 分片序列（帧率）下结果一致。
var clock_ticks: int = 0
var _total_seconds: float = 0.0
## 每次固定结算后发出，供 UI 订阅（本类不持有任何 UI 引用）。
signal stats_ticked(ticks: int)

func reset() -> void:
    hp = 100.0
    hunger = 4.0
    thirst = 6.0
    fatigue = 0.0
    sanity = 100.0
    stamina = 100.0
    infection = 0.0
    cold = 0.0
    clock_ticks = 0
    _total_seconds = 0.0

func clamp_all() -> void:
    hp = clampf(hp, 0.0, 100.0)
    hunger = clampf(hunger, 0.0, 100.0)
    thirst = clampf(thirst, 0.0, 100.0)
    fatigue = clampf(fatigue, 0.0, 100.0)
    sanity = clampf(sanity, 0.0, 100.0)
    stamina = clampf(stamina, 0.0, 100.0)
    infection = clampf(infection, 0.0, 100.0)
    cold = clampf(cold, 0.0, 100.0)

## 累积实时秒数并只按固定步长结算。不同 delta 序列只要总时长相同，
## 结算次数与状态推进就一致（帧率无关）。
func advance(seconds: float) -> int:
    if seconds <= 0.0:
        return 0
    _total_seconds += seconds
    var due: int = int(floor(_total_seconds / STEP_SECONDS + 1e-9))
    var ticks: int = due - clock_ticks
    var i: int = 0
    while i < ticks:
        _tick()
        i += 1
    return ticks

## 单个固定步长内的规则（原型数值，正式数值从数据表提取）。
func _tick() -> void:
    clock_ticks += 1
    hunger = minf(100.0, hunger + STEP_SECONDS / 150.0)
    thirst = minf(100.0, thirst + STEP_SECONDS / 110.0)
    fatigue = minf(100.0, fatigue + STEP_SECONDS / 260.0)
    if hunger > 85.0:
        hp = maxf(0.0, hp - STEP_SECONDS * 0.6)
    if thirst > 90.0:
        hp = maxf(0.0, hp - STEP_SECONDS * 0.4)
    if cold > 70.0:
        fatigue = minf(100.0, fatigue + STEP_SECONDS * 0.2)
    clamp_all()
    stats_ticked.emit(clock_ticks)

func to_dict() -> Dictionary:
    return {
        "hp": hp, "hunger": hunger, "thirst": thirst, "fatigue": fatigue,
        "sanity": sanity, "stamina": stamina, "infection": infection, "cold": cold,
        "clock_ticks": clock_ticks, "total_seconds": _total_seconds,
    }

func from_dict(d: Dictionary) -> void:
    reset()
    hp = clampf(float(d.get("hp", 100.0)), 0.0, 100.0)
    hunger = clampf(float(d.get("hunger", 4.0)), 0.0, 100.0)
    thirst = clampf(float(d.get("thirst", 6.0)), 0.0, 100.0)
    fatigue = clampf(float(d.get("fatigue", 0.0)), 0.0, 100.0)
    sanity = clampf(float(d.get("sanity", 100.0)), 0.0, 100.0)
    stamina = clampf(float(d.get("stamina", 100.0)), 0.0, 100.0)
    infection = clampf(float(d.get("infection", 0.0)), 0.0, 100.0)
    cold = clampf(float(d.get("cold", 0.0)), 0.0, 100.0)
    clock_ticks = maxi(0, int(d.get("clock_ticks", 0)))
    var ts: float = float(d.get("total_seconds", d.get("accumulator", 0.0)))
    _total_seconds = maxf(float(clock_ticks) * STEP_SECONDS, ts)
