extends Node2D
class_name MapRenderer
## 自包含的三国地图渲染器 — 不依赖第三方插件
## 使用 Polygon2D + Area2D 渲染可交互的郡县地图
## 导出为 .pck 后供主游戏挂载

const ProvinceDataClass = preload("res://scripts/map/ProvinceData.gd")

# ============================================================
# 信号
# ============================================================

signal province_clicked(province_id: String)
signal province_hovered(province_id: String)
signal province_unhovered(province_id: String)

# ============================================================
# 配置常量
# ============================================================

const PROVINCE_DATA_DIR := "res://resources/provinces/"

# ============================================================
# 内部状态
# ============================================================

var _provinces: Dictionary = {}      # province_id → {polygon, area, label, data, border_pts, city_pts}
var _owner_colors: Dictionary = {}
var _province_ids: Array[String] = []
var _data_loaded := false
var _adjacency: Dictionary = {}       # province_id → [adjacent province_ids]
var _adjacency_pairs: Array = []      # [ {from: Vector2, to: Vector2} ]  for drawing
var _hovered_id := ""
var _hover_panel: Panel = null
var _hover_labels: Dictionary = {}   # field_name → Label

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	_create_hover_panel()
	call_deferred("_deferred_load")

func _deferred_load() -> void:
	load_all_provinces()
	queue_redraw()

func load_all_provinces() -> void:
	if _data_loaded:
		return
	var dir := DirAccess.open(PROVINCE_DATA_DIR)
	if dir == null:
		push_error("[MapRenderer] 无法打开郡县数据目录: ", PROVINCE_DATA_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path := PROVINCE_DATA_DIR + file_name
			var data = load(path) as ProvinceDataClass
			if data and not data.province_id.is_empty():
				_create_province_nodes(data)
				_province_ids.append(data.province_id)
		file_name = dir.get_next()
	dir.list_dir_end()
	_data_loaded = true
	_compute_adjacency()
	print("[MapRenderer] 加载完成，共 ", _province_ids.size(), " 个郡县")


# ============================================================
# _draw — 郡县底层 + 州边界顶层
# ============================================================

func _draw() -> void:
	if not _data_loaded:
		return
	
	# 下层：接壤郡治连线
	for pair in _adjacency_pairs:
		draw_line(pair.from, pair.to, Color(0.6, 0.5, 0.4, 0.45), 0.75, true)


# ============================================================
# 内部 — 创建郡县渲染节点
# ============================================================

func _create_province_nodes(data: Resource) -> void:
	var polygon_points: PackedVector2Array = data.province_polygon
	if polygon_points.is_empty():
		polygon_points = _generate_default_polygon(data.capital_coordinates, data.map_size)
		data.province_polygon = polygon_points

	# === Polygon2D 填充 ===
	var polygon := Polygon2D.new()
	polygon.name = data.province_id
	polygon.polygon = polygon_points
	polygon.color = data.fill_color
	polygon.modulate = Color(1, 1, 1, 0.0)  # 透明：不显示填充色
	add_child(polygon)

	# === Area2D 交互 — 三角剖分法，三角向外微扩防间隙 ===
	var area := Area2D.new()
	area.name = data.province_id + "_area"
	area.input_pickable = true

	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(polygon_points)
	if triangles.size() >= 3:
		for i in range(0, triangles.size(), 3):
			var p0: Vector2 = polygon_points[triangles[i]]
			var p1: Vector2 = polygon_points[triangles[i + 1]]
			var p2: Vector2 = polygon_points[triangles[i + 2]]
			# 向外扩大 2%，确保相邻郡三角有微小重叠，防止 mouse_entered 漏触发
			var center_tri: Vector2 = (p0 + p1 + p2) / 3.0
			const EXPAND: float = 1.02
			p0 = center_tri + (p0 - center_tri) * EXPAND
			p1 = center_tri + (p1 - center_tri) * EXPAND
			p2 = center_tri + (p2 - center_tri) * EXPAND
			var shape := ConvexPolygonShape2D.new()
			shape.points = PackedVector2Array([p0, p1, p2])
			var collision := CollisionShape2D.new()
			collision.shape = shape
			area.add_child(collision)
	else:
		# 三角剖分失败时回退到凸包（同样扩大）
		var hull: PackedVector2Array = Geometry2D.convex_hull(polygon_points)
		var hull_center := _polygon_center(hull)
		const HULL_EXPAND: float = 1.03
		for j in range(hull.size()):
			hull[j] = hull_center + (hull[j] - hull_center) * HULL_EXPAND
		var shape := ConvexPolygonShape2D.new()
		shape.points = hull
		var collision := CollisionShape2D.new()
		collision.shape = shape
		area.add_child(collision)
	area.mouse_entered.connect(_on_province_mouse_entered.bind(data.province_id))
	area.mouse_exited.connect(_on_province_mouse_exited.bind(data.province_id))
	area.input_event.connect(_on_province_input_event.bind(data.province_id))
	add_child(area)

	# === Label 郡治名 ===
	var label := Label.new()
	label.name = data.province_id + "_label"
	label.text = data.capital_city
	# 文字居中于圆点
	label.size = Vector2(0, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.position = data.capital_coordinates - label.size * 0.5
	# 延迟一帧设置（需要等 label 计算 intrinsic size）
	label.ready.connect(func():
		label.position = data.capital_coordinates - label.size * 0.5
	, CONNECT_ONE_SHOT)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	# 存储
	_provinces[data.province_id] = {
		"polygon": polygon,
		"area": area,
		"label": label,
		"data": data,
		"border_pts": polygon_points,
		"capital_pos": data.capital_coordinates,
	}

	_owner_colors[data.province_id] = data.fill_color


# ============================================================
# 悬停信息面板
# ============================================================

func _create_hover_panel() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HoverCanvas"
	canvas.layer = 100
	add_child(canvas)

	_hover_panel = Panel.new()
	_hover_panel.name = "HoverPanel"
	_hover_panel.visible = false
	_hover_panel.size = Vector2(240, 240)
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_hover_panel)

	# 面板样式
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.6)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_hover_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.position = Vector2(8, 8)
	vbox.size = Vector2(224, 224)
	vbox.add_theme_constant_override("separation", 4)
	_hover_panel.add_child(vbox)

	_hover_labels["name"] = _make_hover_label("", 18, Color(1.0, 0.9, 0.5))
	vbox.add_child(_hover_labels["name"])
	_hover_labels["state"] = _make_hover_label("", 14, Color(0.7, 0.8, 1.0))
	vbox.add_child(_hover_labels["state"])

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_hover_labels["capital"] = _make_hover_label("", 14, Color(1.0, 0.8, 0.6))
	vbox.add_child(_hover_labels["capital"])
	_hover_labels["sub"] = _make_hover_label("", 13, Color(0.6, 0.6, 0.6))
	vbox.add_child(_hover_labels["sub"])

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	_hover_labels["stats"] = _make_hover_label("", 13, Color(0.8, 0.8, 0.8))
	vbox.add_child(_hover_labels["stats"])


func _make_hover_label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _update_hover_panel(province_id: String, mouse_pos: Vector2) -> void:
	var entry = _provinces.get(province_id)
	if not entry:
		return
	var data = entry.data

	_hover_labels["name"].text = data.province_name + "  " + data.capital_city
	_hover_labels["state"].text = "所属州：" + data.state_name
	_hover_labels["capital"].text = "郡治：" + data.capital_city
	var sub_text: String = ""
	for i in data.sub_cities.size():
		if i > 0:
			sub_text += ", "
		sub_text += data.sub_cities[i]
	_hover_labels["sub"].text = "辖县：" + sub_text
	_hover_labels["stats"].text = "人口:{0}  农业:{1}  商业:{2}\n城防:{3}  民心:{4}".format([
		data.population_base, data.agriculture_base,
		data.commerce_base, data.defense_base, data.loyalty_base
	])

	# 定位面板在鼠标右下方，避免超出屏幕
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_pos := mouse_pos + Vector2(16, 16)
	if panel_pos.x + 240 > viewport_size.x:
		panel_pos.x = mouse_pos.x - 250
	if panel_pos.y + 250 > viewport_size.y:
		panel_pos.y = mouse_pos.y - 260
	_hover_panel.position = panel_pos
	_hover_panel.visible = true


# ============================================================
# 公共 API
# ============================================================

func update_province_owner(province_id: String, faction_color: Color) -> void:
	_owner_colors[province_id] = faction_color
	var entry = _provinces.get(province_id)
	if entry:
		entry.polygon.color = faction_color

func highlight_province(province_id: String, highlight: bool) -> void:
	var entry = _provinces.get(province_id)
	if entry:
		entry.polygon.modulate = Color(1, 1, 1, 0.25) if highlight else Color(1, 1, 1, 0.0)

func batch_update_owners(owner_map: Dictionary) -> void:
	for pid: String in owner_map:
		update_province_owner(pid, owner_map[pid])

## 加载群雄割据势力数据（约199年）
## 返回 Dictionary: { "faction_name": color }
func load_warlord_factions() -> Dictionary:
	var path := "res://resources/warlord_factions.json"
	if not FileAccess.file_exists(path):
		push_error("[MapRenderer] 群雄势力文件不存在: ", path)
		return {}
	
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("[MapRenderer] JSON解析失败")
		return {}
	
	var data: Array = json.get_data()
	var owner_map: Dictionary = {}       # province_id → Color
	var faction_colors: Dictionary = {}  # faction_name → Color
	
	for entry in data:
		var pid: String = entry["id"]
		var col_arr: Array = entry["color"]
		var color := Color(col_arr[0], col_arr[1], col_arr[2], col_arr[3])
		owner_map[pid] = color
		var fname: String = entry["faction"]
		faction_colors[fname] = color
	
	batch_update_owners(owner_map)
	print("[MapRenderer] 群雄割据势力已加载: ", faction_colors.size(), " 个势力")
	return faction_colors

## 恢复三国鼎立默认颜色（从 .tres 文件重新加载）
func restore_default_colors() -> void:
	for entry in _provinces.values():
		entry.polygon.color = entry.data.fill_color
		_owner_colors[entry.data.province_id] = entry.data.fill_color
	print("[MapRenderer] 已恢复三国鼎立默认颜色")

func get_province_data(province_id: String) -> Resource:
	var entry = _provinces.get(province_id)
	return entry.data if entry else null

func get_all_province_ids() -> Array[String]:
	return _province_ids.duplicate()

func set_map_visible(v: bool) -> void:
	visible = v


# ============================================================
# 鼠标交互
# ============================================================

func _on_province_mouse_entered(province_id: String) -> void:
	_hovered_id = province_id
	highlight_province(province_id, true)
	_update_hover_panel(province_id, get_viewport().get_mouse_position())
	province_hovered.emit(province_id)

func _on_province_mouse_exited(province_id: String) -> void:
	_hovered_id = ""
	highlight_province(province_id, false)
	if _hover_panel:
		_hover_panel.visible = false
	province_unhovered.emit(province_id)

func _on_province_input_event(viewport: Node, event: InputEvent, shape_idx: int, province_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		province_clicked.emit(province_id)

func _process(_delta: float) -> void:
	# 鼠标移动时更新悬停面板位置
	if _hovered_id != "" and _hover_panel and _hover_panel.visible:
		_hover_panel.position = get_viewport().get_mouse_position() + Vector2(16, 16)


# ============================================================
# 邻接关系计算
# ============================================================

## 通过共享边判断两郡是否接壤
## 多边形顶点为网格对齐的整数坐标，共享边归一化为字符串后匹配
func _compute_adjacency() -> void:
	# edge_key → [province_id, ...]
	var edge_map: Dictionary = {}
	
	for pid in _province_ids:
		var entry = _provinces[pid]
		var pts: PackedVector2Array = entry.border_pts
		for i in range(pts.size()):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			# 归一化：总是从"较小"坐标到"较大"坐标
			var key: String
			if a.x < b.x or (a.x == b.x and a.y < b.y):
				key = "%d,%d-%d,%d" % [int(a.x), int(a.y), int(b.x), int(b.y)]
			else:
				key = "%d,%d-%d,%d" % [int(b.x), int(b.y), int(a.x), int(a.y)]
			
			if not edge_map.has(key):
				edge_map[key] = []
			# 避免同一个郡的同一条边重复添加
			if edge_map[key].size() == 0 or edge_map[key].back() != pid:
				edge_map[key].append(pid)
	
	# 找出共享边（恰好 2 个郡共享）= 接壤
	_adjacency_pairs.clear()
	for pid in _province_ids:
		_adjacency[pid] = []
	
	for key in edge_map:
		var pids: Array = edge_map[key]
		if pids.size() == 2:
			var a: String = pids[0]
			var b: String = pids[1]
			_adjacency[a].append(b)
			_adjacency[b].append(a)
		elif pids.size() > 2:
			# 多郡共点或共边，两两之间也算接壤
			for i in range(pids.size()):
				for j in range(i + 1, pids.size()):
					var a: String = pids[i]
					var b: String = pids[j]
					_adjacency[a].append(b)
					_adjacency[b].append(a)
	
	# 去重并生成画线用的 pair 列表
	var drawn: Dictionary = {}
	for pid in _province_ids:
		var cap_a: Vector2 = _provinces[pid].capital_pos
		for neighbor in _adjacency[pid]:
			# 用排序后的 key 确保每对只画一次
			var pair_key: String
			if pid < neighbor:
				pair_key = pid + "||" + neighbor
			else:
				pair_key = neighbor + "||" + pid
			if not drawn.has(pair_key):
				drawn[pair_key] = true
				var cap_b: Vector2 = _provinces[neighbor].capital_pos
				_adjacency_pairs.append({"from": cap_a, "to": cap_b})
	
	print("[MapRenderer] 邻接关系：", _adjacency_pairs.size(), " 条连线")


# ============================================================
# 几何工具
# ============================================================

func _generate_default_polygon(center: Vector2, size: Vector2) -> PackedVector2Array:
	# 生成不规则多边形 — 模拟真实郡界的不规则形状
	var pts := PackedVector2Array()
	var rx := maxf(size.x, 50.0) * 0.5
	var ry := maxf(size.y, 50.0) * 0.5
	# 顶点数 6~10，不同郡不一样
	var vertex_count: int = 6 + (hash(center.x * 1000 + center.y) % 5)
	# 随机种子（基于坐标，保证同一郡每次生成相同多边形）
	var seed_base: float = center.x * 137.0 + center.y * 251.0

	for i in range(vertex_count):
		var angle: float = TAU * i / vertex_count
		# 角度微调，让多边形更自然
		angle += sin(seed_base + i * 1.7) * 0.15
		# 半径在 60%~115% 之间随机变化，模拟不规则边界
		var r_factor: float = 0.65 + 0.5 * (sin(seed_base * 3.3 + i * 2.1) * 0.5 + 0.5)
		var x: float = center.x + rx * r_factor * cos(angle)
		var y: float = center.y + ry * r_factor * sin(angle)
		pts.append(Vector2(x, y))
	return pts

func _polygon_center(pts: PackedVector2Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in pts:
		sum += p
	return sum / pts.size()