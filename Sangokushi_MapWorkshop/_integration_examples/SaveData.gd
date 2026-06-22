extends Resource
## 完整游戏存档数据结构（示例，放在主游戏项目中）
## 序列化为 JSON 文件写入 user://saves/slot_{N}.save

# ============================================================
# 存档元信息
# ============================================================

## 存档版本号（用于兼容性检查）
@export var save_version: String = "1.0"

## 保存时间（Unix 时间戳）
@export var save_time: int = 0

## 当前回合数
@export var current_turn: int = 1

## 当前年份（如 190 = 初平元年）
@export var current_year: int = 190

# ============================================================
# 玩家数据
# ============================================================

## 玩家势力ID
@export var player_faction_id: String = ""

## 玩家当前官职品级（0=无, 1=低位, 2=中位, 3=高位）
@export var player_rank: int = 0

## 玩家金钱
@export var player_gold: int = 0

## 玩家粮草
@export var player_food: int = 0

# ============================================================
# ★ 核心：动态郡县状态数据
# ============================================================

## 所有郡县的动态状态（存档独占，地图包不包含这些）
@export var province_states: Array[ProvinceStateData] = []


# ============================================================
# 实用方法
# ============================================================

## 根据 province_id 查找状态
func get_province_state(province_id: String) -> ProvinceStateData:
	for state in province_states:
		if state.province_id == province_id:
			return state
	return null

## 获取玩家势力下所有郡县状态
func get_player_provinces() -> Array[ProvinceStateData]:
	var result: Array[ProvinceStateData] = []
	for state in province_states:
		if state.faction_id == player_faction_id:
			result.append(state)
	return result

## 势力更迭：变更某郡归属
func transfer_ownership(province_id: String, new_faction_id: String) -> bool:
	var state = get_province_state(province_id)
	if not state:
		return false
	state.faction_id = new_faction_id
	state.loyalty_cur = max(30, state.loyalty_cur - 20)  # 易主降民心
	return true
