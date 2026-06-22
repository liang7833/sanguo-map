@tool
class_name GeneratorPreviewDisplay extends Control

# Expected setup:
#   - Size policy: expand to fill available space (set in scene)
#   - mouse_filter: MOUSE_FILTER_STOP (default for Control)

const SNAP_RADIUS: float = 8.0
const MAP_SHAPE_COLOR: Color = Color(0.75, 0.80, 0.85, 0.6)
const CELL_OUTLINE_COLOR: Color = Color(0.1, 0.1, 0.1, 1.0)

@export var province_map: ProvinceMap:
	set(value):
		province_map = value
		queue_redraw()

# When set, parent layer polygons are drawn as the background instead of map_shape
var parent_layer: MapLayer = null:
	set(value):
		parent_layer = value
		queue_redraw()

@export var cell_opacity: float = 0.4:
	set(value):
		cell_opacity = value
		queue_redraw()

@export var margin: float = 10.0:
	set(value):
		margin = value
		queue_redraw()

var seed_points: Array[Vector2] = []:
	set(value):
		seed_points = value
		_hovered_point = -1
		queue_redraw()

var voronoi_cells: Array[PackedVector2Array] = []:
	set(value):
		voronoi_cells = value
		queue_redraw()

signal point_dragging(index: int, new_world_pos: Vector2)

var _hovered_point: int = -1
var _drag_idx: int = -1
var _drag_current_world_pos: Vector2
var _is_dragging: bool = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _calculate_transform() -> Dictionary:
	if not province_map or province_map.size == Vector2.ZERO:
		return {"scale": 1.0, "offset": Vector2.ZERO}
	var available_size: Vector2 = size - Vector2(margin * 2, margin * 2)
	var sc: float = min(available_size.x / province_map.size.x, available_size.y / province_map.size.y)
	var off: Vector2 = (size - province_map.size * sc) / 2.0
	return {"scale": sc, "offset": off}


func _draw() -> void:
	if not province_map:
		return

	var t: Dictionary = _calculate_transform()
	var sc: float = t.scale
	var off: Vector2 = t.offset

	# 1. Background: parent layer polygons if available, else base layer (layers[0])
	var bg_layer: MapLayer = parent_layer
	if not bg_layer and province_map and not province_map.layers.is_empty():
		bg_layer = province_map.layers[0]
	if bg_layer and province_map:
		for region: Region in bg_layer.regions:
			for polygon: PackedVector2Array in province_map.get_resolved_polygons(region):
				if polygon.size() >= 3:
					draw_colored_polygon(_transform_polygon(polygon, sc, off), MAP_SHAPE_COLOR)

	# 2. Voronoi cells: golden-ratio hue fill at cell_opacity, 1px dark outline
	for i: int in range(voronoi_cells.size()):
		var cell: PackedVector2Array = voronoi_cells[i]
		if cell.size() < 3:
			continue
		var screen_cell: PackedVector2Array = _transform_polygon(cell, sc, off)
		var hue: float = fmod(float(i) * 0.618033988749895, 1.0)
		var fill: Color = Color.from_hsv(hue, 0.6, 0.85, cell_opacity)
		draw_colored_polygon(screen_cell, fill)
		draw_polyline(screen_cell, CELL_OUTLINE_COLOR, 1.0, true)

	# 3. Seed point handles: hovered/dragged point is yellow, others white
	for i: int in range(seed_points.size()):
		var world_pos: Vector2
		if _is_dragging and _drag_idx == i:
			world_pos = _drag_current_world_pos
		else:
			world_pos = seed_points[i]
		var color: Color = Color.YELLOW if (_hovered_point == i or (_is_dragging and _drag_idx == i)) else Color.WHITE
		_draw_diamond(world_pos * sc + off, color)


func _draw_diamond(pos: Vector2, color: Color) -> void:
	const OUTER: float = 5.5
	const INNER: float = 4.0
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0.0, -OUTER), pos + Vector2(OUTER, 0.0),
		pos + Vector2(0.0, OUTER), pos + Vector2(-OUTER, 0.0),
	]), Color.BLACK)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0.0, -INNER), pos + Vector2(INNER, 0.0),
		pos + Vector2(0.0, INNER), pos + Vector2(-INNER, 0.0),
	]), color)


func _gui_input(event: InputEvent) -> void:
	if seed_points.is_empty():
		return

	var t: Dictionary = _calculate_transform()
	var sc: float = t.scale
	var off: Vector2 = t.offset

	if event is InputEventMouseMotion:
		var screen_pos: Vector2 = event.position
		var world_pos: Vector2 = (screen_pos - off) / sc

		if _is_dragging:
			_drag_current_world_pos = world_pos
			queue_redraw()
			point_dragging.emit(_drag_idx, world_pos)
			accept_event()
			return

		var new_hover: int = _find_hovered_point(screen_pos, sc, off)
		if new_hover != _hovered_point:
			_hovered_point = new_hover
			queue_redraw()

	elif event is InputEventMouseButton:
		var screen_pos: Vector2 = event.position
		var world_pos: Vector2 = (screen_pos - off) / sc

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var idx: int = _find_hovered_point(screen_pos, sc, off)
				if idx != -1:
					_drag_idx = idx
					_drag_current_world_pos = world_pos
					_is_dragging = true
					accept_event()
			else:
				if _is_dragging:
					_is_dragging = false
					_drag_idx = -1
					queue_redraw()
					accept_event()


func _find_hovered_point(screen_pos: Vector2, sc: float, off: Vector2) -> int:
	var best_dist: float = SNAP_RADIUS
	var best: int = -1
	for i: int in range(seed_points.size()):
		var dist: float = screen_pos.distance_to(seed_points[i] * sc + off)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


func _transform_polygon(polygon: PackedVector2Array, sc: float, off: Vector2) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	result.resize(polygon.size())
	for i: int in range(polygon.size()):
		result[i] = polygon[i] * sc + off
	return result
