@tool
extends Control
class_name ProvinceMapDisplay

enum DisplayMode {
	LAYER_REGIONS,        # Each region's polygons filled with region color
	LAYER_WITH_CHILDREN,  # Same, plus child region polygon outlines overlaid
}

@export var province_map: ProvinceMap:
	set(value):
		if province_map and province_map.changed.is_connected(_on_province_map_changed):
			province_map.changed.disconnect(_on_province_map_changed)
		province_map = value
		if province_map:
			province_map.changed.connect(_on_province_map_changed)
		queue_redraw()

var render_mode: DisplayMode = DisplayMode.LAYER_REGIONS:
	set(value):
		render_mode = value
		queue_redraw()

var active_layer: MapLayer = null:
	set(value):
		active_layer = value
		queue_redraw()

var highlighted_region: Region = null:
	set(value):
		highlighted_region = value
		queue_redraw()

# Optional per-region color overrides for live preview (region index → Color).
# Set by editors (MetadataEditor, RenderEditor) without touching region.color.
# Not persisted.
var region_color_overrides: Dictionary = {}:
	set(value):
		region_color_overrides = value
		queue_redraw()

@export_group("Display Settings")
@export var auto_scale: bool = true:
	set(value):
		auto_scale = value
		queue_redraw()

@export var margin: float = 10.0:
	set(value):
		margin = value
		queue_redraw()

@export_group("Regions")
@export var region_outline_color: Color = Color.BLACK:
	set(value):
		region_outline_color = value
		queue_redraw()

@export var region_outline_width: float = 1.0:
	set(value):
		region_outline_width = value
		queue_redraw()

@export var child_outline_color: Color = Color(0.2, 0.2, 0.2, 0.6):
	set(value):
		child_outline_color = value
		queue_redraw()

@export var child_outline_width: float = 0.5:
	set(value):
		child_outline_width = value
		queue_redraw()

@export var highlighted_outline_color: Color = Color.YELLOW:
	set(value):
		highlighted_outline_color = value
		queue_redraw()

@export var highlighted_outline_width: float = 2.0:
	set(value):
		highlighted_outline_width = value
		queue_redraw()


func _on_province_map_changed() -> void:
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _gui_input(_event: InputEvent) -> void:
	pass

# Hit-test: returns region index in layer, or -1. Not wired to input yet.
func get_region_at_position(pos: Vector2, layer: MapLayer) -> int:
	if not layer:
		return -1
	var transform_data: Dictionary = _calculate_transform()
	var map_pos: Vector2 = (pos - transform_data.offset) / transform_data.scale
	for i: int in range(layer.regions.size()):
		var region: Region = layer.regions[i]
		for polygon: PackedVector2Array in province_map.get_resolved_polygons(region):
			if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(map_pos, polygon):
				return i
	return -1

func _draw() -> void:
	if not province_map:
		return

	var transform_data: Dictionary = _calculate_transform()
	var sc: float = transform_data.scale
	var off: Vector2 = transform_data.offset

	if active_layer and not active_layer.regions.is_empty():
		match render_mode:
			DisplayMode.LAYER_REGIONS:
				_draw_layer_regions(active_layer, sc, off)
			DisplayMode.LAYER_WITH_CHILDREN:
				_draw_layer_regions(active_layer, sc, off)
				_draw_children_outlines(active_layer, sc, off)

func _draw_layer_regions(layer: MapLayer, sc: float, off: Vector2) -> void:
	for i: int in range(layer.regions.size()):
		var region: Region = layer.regions[i]
		var is_highlighted: bool = (region == highlighted_region)
		var fill_color: Color = region_color_overrides.get(i, region.color)
		for polygon: PackedVector2Array in province_map.get_resolved_polygons(region):
			if polygon.size() < 3:
				continue
			var t: PackedVector2Array = _transform_polygon(polygon, sc, off)
			draw_colored_polygon(t, fill_color)
			var out_c: Color = highlighted_outline_color if is_highlighted else region_outline_color
			var out_w: float = highlighted_outline_width if is_highlighted else region_outline_width
			if out_w > 0:
				draw_polyline(t, out_c, out_w, true)

func _draw_children_outlines(layer: MapLayer, sc: float, off: Vector2) -> void:
	if not province_map or province_map.layers.size() < 2:
		return
	var layer_idx: int = province_map.layers.find(layer)
	if layer_idx < 0 or layer_idx + 1 >= province_map.layers.size():
		return
	var child_layer: MapLayer = province_map.layers[layer_idx + 1]
	for region: Region in layer.regions:
		for child_idx: int in region.child_region_indices:
			if child_idx < 0 or child_idx >= child_layer.regions.size():
				continue
			var child_region: Region = child_layer.regions[child_idx]
			for polygon: PackedVector2Array in province_map.get_resolved_polygons(child_region):
				if polygon.size() < 3:
					continue
				var t: PackedVector2Array = _transform_polygon(polygon, sc, off)
				if child_outline_width > 0:
					draw_polyline(t, child_outline_color, child_outline_width, true)

func _transform_polygon(polygon: PackedVector2Array, sc: float, off: Vector2) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	result.resize(polygon.size())
	for i: int in range(polygon.size()):
		result[i] = polygon[i] * sc + off
	return result

func _calculate_transform() -> Dictionary:
	if not province_map or province_map.size == Vector2.ZERO:
		return {"scale": 1.0, "offset": Vector2.ZERO}
	var available_size: Vector2 = size - Vector2(margin * 2, margin * 2)
	var sc: float = min(available_size.x / province_map.size.x, available_size.y / province_map.size.y)
	var off: Vector2 = (size - province_map.size * sc) / 2.0
	return {"scale": sc, "offset": off}
