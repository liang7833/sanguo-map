@tool
extends Control
class_name PolygonDisplay

@export var polygons: Array[PackedVector2Array] = []:
	set(value):
		polygons = value
		queue_redraw()

@export var original_size: Vector2 = Vector2.ZERO:
	set(value):
		original_size = value
		queue_redraw()

@export var auto_scale: bool = true:
	set(value):
		auto_scale = value
		queue_redraw()

@export var margin: float = 10.0:
	set(value):
		margin = value
		queue_redraw()

@export var fill_color: Color = Color(0.5, 0.7, 0.9, 0.7):
	set(value):
		fill_color = value
		queue_redraw()

@export var outline_color: Color = Color.BLACK:
	set(value):
		outline_color = value
		queue_redraw()

@export var outline_width: float = 1.0:
	set(value):
		outline_width = value
		queue_redraw()

@export var use_random_colors: bool = true:
	set(value):
		use_random_colors = value
		queue_redraw()

func _draw() -> void:
	if polygons.is_empty():
		return
	
	var display_polygons: Array[PackedVector2Array] = polygons
	
	if auto_scale:
		display_polygons = _get_scaled_polygons()
	
	for i in range(display_polygons.size()):
		var polygon: PackedVector2Array = display_polygons[i]
		
		# Determine color
		var color: Color = fill_color
		if use_random_colors:
			var hue: float = fmod(i * 0.618033988749895, 1.0)
			color = Color.from_hsv(hue, 0.6, 0.9, 0.7)
		
		# Draw polygon
		draw_colored_polygon(polygon, color)
		draw_polyline(polygon, outline_color, outline_width, true)

func _get_scaled_polygons() -> Array[PackedVector2Array]:
	if polygons.is_empty():
		return []
	
	# Use original_size if available, otherwise fall back to bounding box
	var bounds_size: Vector2
	var min_point: Vector2
	
	if original_size != Vector2.ZERO:
		bounds_size = original_size
		min_point = Vector2.ZERO
	else:
		# Fall back to calculating bounding box
		min_point = Vector2(INF, INF)
		var max_point: Vector2 = Vector2(-INF, -INF)
		
		for polygon in polygons:
			for point in polygon:
				min_point.x = min(min_point.x, point.x)
				min_point.y = min(min_point.y, point.y)
				max_point.x = max(max_point.x, point.x)
				max_point.y = max(max_point.y, point.y)
		
		bounds_size = max_point - min_point
	
	var available_size: Vector2 = size - Vector2(margin * 2, margin * 2)
	
	# Calculate scale
	var scale: float = min(available_size.x / bounds_size.x, available_size.y / bounds_size.y)
	
	# Calculate offset to center
	var scaled_size: Vector2 = bounds_size * scale
	var offset: Vector2 = (size - scaled_size) / 2.0 - min_point * scale
	
	# Transform all polygons
	var result: Array[PackedVector2Array] = []
	for polygon in polygons:
		var transformed: PackedVector2Array = PackedVector2Array()
		for point in polygon:
			transformed.append(point * scale + offset)
		result.append(transformed)
	
	return result

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
