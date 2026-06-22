class_name ProvinceData
extends Resource
## 郡县静态地理数据（地图包自有，存档绝不覆盖）
## 所有数据基于史实初始化，一旦导出为 .pck 则保持不变
## 动态游戏状态在主游戏的 ProvinceStateData 中单独存储

# ============================================================
# 基础标识
# ============================================================

## 郡ID（唯一标识，如 "chenliu"，存档通过此ID关联）
## ★ 关键约定：一旦发布，此ID绝不可变，否则旧存档数据无法匹配
@export var province_id: String = ""

## 郡名（如 "陈留郡"）
@export var province_name: String = ""

## 所属州（如 "兖州"、"豫州"）
@export var state_name: String = ""

# ============================================================
# 郡城信息
# ============================================================

## 郡治（主城名，如 "陈留"）
@export var capital_city: String = ""

## 郡治在地图上的坐标（像素/世界坐标，由 Province Map Builder 填充）
@export var capital_coordinates: Vector2 = Vector2.ZERO

## 下辖小型城市列表（5~6个，如 ["己吾", "襄邑", "外黄", "雍丘", "尉氏", "考城"]）
@export var sub_cities: Array[String] = []

# ============================================================
# 开局基准值（静态，存档初始化时读取一次）
# ============================================================

## 农业基准值（0~1000）
@export var agriculture_base: int = 0

## 商业基准值（0~1000）
@export var commerce_base: int = 0

## 人口基准值
@export var population_base: int = 0

## 民心基准值（0~100）
@export var loyalty_base: int = 0

## 城防基准值（0~1000）
@export var defense_base: int = 0

# ============================================================
# 初始归属（仅作开局参考，进入游戏后由存档决定）
# ============================================================

## 初始所属势力ID（如 "cao_cao"、"liu_bei"、"sun_quan"，开局参考值）
@export var faction_initial: String = ""

## 初始太守（如 "张邈"）
@export var prefect_initial: String = ""

# ============================================================
# 渲染相关（由 Province Map Builder 管理）
# ============================================================

## 地图渲染用 — 郡县多边形顶点（PackedVector2Array）
## 由 MapRenderer 自动生成，可在 Godot 编辑器手动精调
@export var province_polygon: PackedVector2Array = []

## 地图渲染用 — 郡县近似尺寸（用于自动生成多边形时）
@export var map_size: Vector2 = Vector2(120, 100)

## 郡县填充颜色（可在编辑器中手动调整）
@export var fill_color: Color = Color.DARK_GRAY

## 郡县边框颜色
@export var border_color: Color = Color.BLACK


# ============================================================
# 实用方法
# ============================================================

## 获取郡治全名
func get_capital_full_name() -> String:
	return capital_city + "（" + province_name + "）"

## 获取所有城市（主城 + 小城）列表
func get_all_cities() -> Array[String]:
	var cities: Array[String] = [capital_city]
	cities.append_array(sub_cities)
	return cities

## 判断某个城市是否属于本郡
func has_city(city_name: String) -> bool:
	if city_name == capital_city:
		return true
	return city_name in sub_cities

## 获取城市总数
func get_city_count() -> int:
	return 1 + sub_cities.size()
