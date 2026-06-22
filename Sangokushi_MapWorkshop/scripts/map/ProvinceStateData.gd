class_name ProvinceStateData
extends Resource
## 单郡动态游戏状态（存档专用，不在地图包中）
## 通过 province_id 关联地图包中的 ProvinceData
## 开局时由 ProvinceData 的 _base 值初始化当前值，之后随游戏进程变化

const ProvinceDataRef = preload("res://scripts/map/ProvinceData.gd")

# ============================================================
# 关联标识
# ============================================================

## 关联地图包中的郡ID（如 "chenliu"）
@export var province_id: String = ""

# ============================================================
# 归属与人事
# ============================================================

## 当前归属势力ID（如 "cao_cao"）
@export var faction_id: String = ""

## 现任太守ID（如 "zhang_miao"）
@export var prefect_id: String = ""

# ============================================================
# 动态经济/军事数值
# ============================================================

## 当前农业值
@export var agriculture_cur: int = 0

## 当前商业值
@export var commerce_cur: int = 0

## 当前人口
@export var population_cur: int = 0

## 当前民心（0~100）
@export var loyalty_cur: int = 0

## 当前城防值
@export var defense_cur: int = 0

# ============================================================
# 扩展数据
# ============================================================

## 当前税率（0.0~1.0）
@export var tax_rate: float = 0.1

## 要塞化进度（0~100）
@export var fortification: int = 0

## 当前回合收成系数（受天灾、季节影响）
@export var harvest_modifier: float = 1.0

## 最近事件日志（最近 N 条摘要）
@export var recent_events: Array[String] = []

## 是否已被攻陷（城防归零后）
@export var is_captured: bool = false

## 当前驻扎兵力数量
@export var garrison_troops: int = 0


# ============================================================
# 初始化方法
# ============================================================

## 从 ProvinceData（地图包静态数据）初始化当前值
func init_from_static(static_data: Resource, faction: String = "", prefect: String = "") -> void:
	province_id = static_data.province_id
	agriculture_cur = static_data.agriculture_base
	commerce_cur = static_data.commerce_base
	population_cur = static_data.population_base
	loyalty_cur = static_data.loyalty_base
	defense_cur = static_data.defense_base
	faction_id = faction
	prefect_id = prefect
	is_captured = false

## 重置到从静态数据初始化的状态
func reset_to_base(static_data: Resource) -> void:
	init_from_static(static_data, faction_id, prefect_id)
	recent_events.clear()

## 添加事件日志
func add_event(event: String) -> void:
	recent_events.push_front(event)
	if recent_events.size() > 20:
		recent_events.resize(20)
