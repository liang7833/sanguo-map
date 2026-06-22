extends Node
## 游戏状态管理器（示例，放在主游戏项目中）
## 管理所有郡县的动态状态，负责与地图包联动

# ============================================================
# 成员变量
# ============================================================

## 地图包加载器引用
var map_loader: MapPackLoader

## 当前游戏状态（所有郡县的动态数据）
var province_states: Dictionary = {}  # province_id → ProvinceStateData

## 势力颜色表（faction_id → Color）
var faction_colors: Dictionary = {}


# ============================================================
# 初始化
# ============================================================

## 新游戏初始化：从地图包静态数据创建所有动态状态
func init_new_game(map_renderer: MapRenderer, player_faction: String) -> void:
	province_states.clear()
	var all_ids = map_renderer.get_all_province_ids()
	for pid in all_ids:
		var static_data = map_renderer.get_province_data(pid)
		if static_data:
			var state = ProvinceStateData.new()
			state.init_from_static(static_data, static_data.faction_initial, static_data.prefect_initial)
			province_states[pid] = state

	_init_faction_colors()
	map_renderer.batch_update_owners(_build_owner_color_map())
	print("[GameState] 新游戏初始化完成，共 ", province_states.size(), " 个郡县")


## 从存档加载
func load_from_save(map_renderer: MapRenderer, save_data: SaveData) -> void:
	province_states.clear()
	for state in save_data.province_states:
		province_states[state.province_id] = state

	_init_faction_colors()
	map_renderer.batch_update_owners(_build_owner_color_map())
	print("[GameState] 存档加载完成")


## 导出为存档数据
func to_save_data() -> SaveData:
	var save = SaveData.new()
	save.province_states.assign(province_states.values())
	return save


# ============================================================
# 查询
# ============================================================

## 获取某郡的动态状态
func get_state(province_id: String) -> ProvinceStateData:
	return province_states.get(province_id, null)

## 获取某势力的全部郡县
func get_faction_provinces(faction_id: String) -> Array[ProvinceStateData]:
	var result: Array[ProvinceStateData] = []
	for state in province_states.values():
		if state.faction_id == faction_id:
			result.append(state)
	return result


# ============================================================
# 操作
# ============================================================

## 势力更迭
func change_ownership(province_id: String, new_faction: String, new_prefect: String = "") -> void:
	var state = get_state(province_id)
	if not state:
		return
	state.faction_id = new_faction
	if new_prefect:
		state.prefect_id = new_prefect
	state.loyalty_cur = max(20, state.loyalty_cur - 25)
	state.is_captured = false

	# 刷新地图显示
	if map_loader and map_loader.map_renderer:
		var color = faction_colors.get(new_faction, Color.GRAY)
		map_loader.map_renderer.update_province_owner(province_id, color)


## 回合更新（示例：收成计算）
func process_turn() -> void:
	for state in province_states.values():
		# 农业产出
		var harvest = state.agriculture_cur * state.harvest_modifier
		# 商业税收
		var tax = state.commerce_cur * state.tax_rate
		# 民心自然恢复（倾向于基准值）
		if state.loyalty_cur < 60:
			state.loyalty_cur += randi_range(1, 3)
		elif state.loyalty_cur > 70:
			state.loyalty_cur -= randi_range(0, 1)
		state.loyalty_cur = clampi(state.loyalty_cur, 0, 100)


# ============================================================
# 内部方法
# ============================================================

func _init_faction_colors() -> void:
	faction_colors = {
		"cao_cao": Color(0.2, 0.3, 0.9),   # 蓝
		"liu_bei": Color(0.2, 0.8, 0.3),   # 绿
		"sun_quan": Color(0.9, 0.2, 0.2),  # 红
		"dong_zhuo": Color(0.6, 0.1, 0.6),  # 紫
		"yuan_shao": Color(1.0, 0.8, 0.1),  # 金
		"yuan_shu": Color(0.8, 0.6, 0.1),   # 暗金
		"liu_biao": Color(0.1, 0.6, 0.6),   # 青
		"liu_zhang": Color(0.5, 0.5, 0.1),  # 橄榄
		"ma_teng": Color(0.8, 0.4, 0.1),    # 橙
		"zhang_lu": Color(0.4, 0.7, 0.4),   # 浅绿（天师道）
		"han_fu": Color(0.5, 0.5, 0.5),     # 灰
		"tao_qian": Color(0.6, 0.7, 0.3),   # 黄绿
		"kong_rong": Color(0.4, 0.6, 0.8),  # 浅蓝
		"gongsun_zan": Color(0.9, 0.5, 0.5), # 浅红
		"shi_xie": Color(0.3, 0.3, 0.3),    # 深灰
		"meng_huo": Color(0.7, 0.3, 0.1),   # 棕
		"independent": Color(0.7, 0.7, 0.7), # 独立/中立
	}

func _build_owner_color_map() -> Dictionary:
	var color_map: Dictionary = {}
	for pid in province_states:
		var state = province_states[pid]
		var color = faction_colors.get(state.faction_id, Color.GRAY)
		color_map[pid] = color
	return color_map
