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
	print("[MapRenderer] 加载完成，共 ", _province_ids.size(), " 个郡县")


# ============================================================
# _draw — 郡县底层 + 州边界顶层
# ============================================================

func _draw() -> void:
	if not _data_loaded:
		return
	
	# 下层：郡边界 + 郡治
	for entry in _provinces.values():
		draw_polyline(entry.border_pts, Color.BLACK, 1.5, true)
		draw_circle(entry.capital_pos, 8.0, Color.WHITE)
		draw_circle(entry.capital_pos, 6.0, entry.data.fill_color.darkened(0.3))
	
	# 中层：辖县小圆点
	for entry in _provinces.values():
		for city_pos in entry.sub_city_positions:
			draw_circle(city_pos, 4.0, Color.WHITE)
			draw_circle(city_pos, 3.0, Color.BLACK)
	
	# 上层：州边界 + 州名（放在最上面，50% 透明度）
	_draw_state_boundaries()


# ============================================================
# 州边界绘制
# ============================================================

## 州轮廓颜色（50% 透明度）
const STATE_COLORS: Dictionary = {
	"司州": Color(0.6, 0.2, 0.2, 0.5),
	"兖州": Color(0.3, 0.5, 0.8, 0.5),
	"豫州": Color(0.2, 0.6, 0.3, 0.5),
	"徐州": Color(0.7, 0.5, 0.2, 0.5),
	"青州": Color(0.2, 0.7, 0.7, 0.5),
	"冀州": Color(0.7, 0.3, 0.5, 0.5),
	"幽州": Color(0.5, 0.3, 0.1, 0.5),
	"并州": Color(0.4, 0.2, 0.6, 0.5),
	"凉州": Color(0.6, 0.5, 0.2, 0.5),
	"雍州": Color(0.5, 0.5, 0.5, 0.5),
	"益州": Color(0.1, 0.5, 0.4, 0.5),
	"荆州": Color(0.8, 0.4, 0.1, 0.5),
	"扬州": Color(0.1, 0.6, 0.8, 0.5),
	"交州": Color(0.7, 0.2, 0.7, 0.5),
}


func _draw_state_boundaries() -> void:
	# 按州分组郡
	var state_provinces: Dictionary = {}  # state_name -> [entry]
	for entry in _provinces.values():
		var sn: String = entry.data.state_name
		if not state_provinces.has(sn):
			state_provinces[sn] = []
		state_provinces[sn].append(entry)
	
	for state_name: String in state_provinces:
		var entries: Array = state_provinces[state_name]
		var outline_color: Color = STATE_COLORS.get(state_name, Color(0.4, 0.4, 0.4, 0.85))
		
		# 使用哈希计数：每条边出现次数
		# 共享边（同州内两个郡相邻）出现 2 次，外边界出现 1 次
		var edge_count: Dictionary = {}  # "key" -> count
		var edge_data: Dictionary = {}  # "key" -> {from, to}
		
		for entry in entries:
			var pts: PackedVector2Array = entry.border_pts
			for i in range(pts.size()):
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[(i + 1) % pts.size()]
				# 规范化边：总是从"较小"坐标到"较大"坐标
				# 注意：由于多边形顶点是网格对齐的，直接比较即可
				var key: String
				if a.x < b.x or (a.x == b.x and a.y < b.y):
					key = "%.0f,%.0f-%.0f,%.0f" % [a.x, a.y, b.x, b.y]
				else:
					key = "%.0f,%.0f-%.0f,%.0f" % [b.x, b.y, a.x, a.y]
				
				edge_count[key] = edge_count.get(key, 0) + 1
				edge_data[key] = {"from": a, "to": b}
		
		# 只绘制出现 1 次的边（外边界）
		for key: String in edge_count:
			if edge_count[key] == 1:
				var e = edge_data[key]
				draw_line(e["from"], e["to"], outline_color, 4.0, true)
		
		# 绘制州名标签
		_draw_state_label(state_name, entries, outline_color)


func _draw_state_label(state_name: String, entries: Array, color: Color) -> void:
	# 计算州中心（所有郡中心的平均值）
	var sum := Vector2.ZERO
	var count := 0
	for entry in entries:
		sum += entry.data.capital_coordinates
		count += 1
	if count == 0:
		return
	var center := sum / count
	
	# 大号州名
	var font := ThemeDB.get_fallback_font()
	var font_size := 46
	var outline_color := Color(0, 0, 0, 0.5)
	var text := state_name
	var pos := center - Vector2(0, font_size * 0.5)
	
	# 描边
	draw_string(font, pos + Vector2(2, 0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, outline_color)
	draw_string(font, pos + Vector2(-2, 0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, outline_color)
	draw_string(font, pos + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, outline_color)
	draw_string(font, pos + Vector2(0, -2), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, outline_color)
	# 主文字
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)


# ============================================================
# 内部 — 创建郡县渲染节点
# ============================================================

func _create_province_nodes(data: Resource) -> void:
	var polygon_points: PackedVector2Array = data.province_polygon
	if polygon_points.is_empty():
		polygon_points = _generate_default_polygon(data.capital_coordinates, data.map_size)
		data.province_polygon = polygon_points

	# 计算多边形中心（用于标签定位）
	var center := _polygon_center(polygon_points)

	# 生成下属城市坐标
	var sub_city_positions: Array[Vector2] = []
	var sub_count: int = data.sub_cities.size()
	if sub_count > 0:
		sub_city_positions = _generate_sub_city_positions(data.capital_coordinates, polygon_points, sub_count)

	# === Polygon2D 填充 ===
	var polygon := Polygon2D.new()
	polygon.name = data.province_id
	polygon.polygon = polygon_points
	polygon.color = data.fill_color
	polygon.modulate = Color(1, 1, 1, 0.75)
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

	# === Label 郡名（中层，字体中） ===
	var label := Label.new()
	label.name = data.province_id + "_label"
	label.text = data.province_name
	label.position = center - Vector2(60, 14)
	label.size = Vector2(120, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	# === 辖县标签（上层，字体小） ===
	var sub_city_labels: Array[Label] = []
	for idx in range(sub_city_positions.size()):
		var city_name: String = data.sub_cities[idx] if idx < data.sub_cities.size() else ""
		var city_label := Label.new()
		city_label.name = data.province_id + "_city_" + str(idx)
		city_label.text = city_name
		# 标签放在小圆点右上方
		city_label.position = sub_city_positions[idx] + Vector2(6, -12)
		city_label.size = Vector2(72, 14)
		city_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		city_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		city_label.add_theme_font_size_override("font_size", 11)
		city_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		city_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		city_label.add_theme_constant_override("outline_size", 1)
		city_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(city_label)
		sub_city_labels.append(city_label)

	# 存储
	_provinces[data.province_id] = {
		"polygon": polygon,
		"area": area,
		"label": label,
		"data": data,
		"border_pts": polygon_points,
		"capital_pos": data.capital_coordinates,
		"sub_city_positions": sub_city_positions,
		"sub_city_labels": sub_city_labels,
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
		entry.polygon.modulate = Color(1.4, 1.4, 1.4, 0.9) if highlight else Color(1, 1, 1, 0.75)

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

func _generate_sub_city_positions(capital: Vector2, polygon: PackedVector2Array, count: int) -> Array[Vector2]:
	if polygon.size() < 3:
		return []
	
	# 计算多边形的包围盒
	var min_x := polygon[0].x
	var max_x := polygon[0].x
	var min_y := polygon[0].y
	var max_y := polygon[0].y
	for p in polygon:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	
	var center := _polygon_center(polygon)
	var rx := (max_x - min_x) * 0.35
	var ry := (max_y - min_y) * 0.35
	
	# 确保治所在多边形内；若不在，用中心代替
	var origin := capital if _point_in_polygon(capital, polygon) else center
	
	var positions: Array[Vector2] = []
	var seed_base: float = abs(origin.x * 137.0 + origin.y * 251.0)
	
	for i in count:
		# 用确定的抖动替代 randf_range，确保同一郡每次位置一致
		var angle_noise := sin(seed_base + i * 1.7) * 0.25
		var radius_scale: float = 0.6 + 0.4 * abs(sin(seed_base * 3.3 + i * 2.1))
		
		# 多次尝试：从大半径逐渐缩小，直到落在多边形内
		var found := false
		var r_factor := radius_scale
		while r_factor > 0.15:
			var angle := TAU * i / count + angle_noise
			var candidate := Vector2(
				origin.x + rx * r_factor * cos(angle),
				origin.y + ry * r_factor * sin(angle)
			)
			if _point_in_polygon(candidate, polygon):
				positions.append(candidate)
				found = true
				break
			r_factor -= 0.08
		
		if not found:
			# 兜底：放在多边形中心与治所之间
			var fallback := (origin + center) * 0.5
			positions.append(fallback)
	
	return positions


func _point_in_polygon(point: Vector2, poly: PackedVector2Array) -> bool:
	# 射线法判断点是否在多边形内
	if poly.size() < 3:
		return false
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in range(n):
		var pi := poly[i]
		var pj := poly[j]
		if ((pi.y > point.y) != (pj.y > point.y)) and \
		   (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x):
			inside = not inside
		j = i
	return inside