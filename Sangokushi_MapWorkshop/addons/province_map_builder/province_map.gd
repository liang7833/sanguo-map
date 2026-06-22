@tool
@icon("province_map_icon.svg")
class_name ProvinceMap extends Resource


@export var size: Vector2:
	set(value):
		size = value
		changed.emit()

@export var layers: Array[MapLayer]:
	set(value):
		_disconnect_layers()
		layers = value
		_connect_layers()
		_sync_region_centers()
		changed.emit()

# Global vertex pool — single source of truth for all polygon vertex positions.
# Declared after layers so it loads last from .tres, preserving saved child vertices.
@export var vertices: Array[Vector2]:
	set(value):
		vertices = value
		_sync_region_centers()
		changed.emit()


func _connect_layers() -> void:
	for layer: MapLayer in layers:
		if not layer.changed.is_connected(changed.emit):
			layer.changed.connect(changed.emit)


func _disconnect_layers() -> void:
	for layer: MapLayer in layers:
		if layer.changed.is_connected(changed.emit):
			layer.changed.disconnect(changed.emit)


func _sync_region_centers() -> void:
	for layer: MapLayer in layers:
		for region: Region in layer.regions:
			var total_area: float = 0.0
			var weighted: Vector2 = Vector2.ZERO
			for idx_poly: PackedInt32Array in region.polygon_indices:
				if idx_poly.size() < 3:
					continue
				# Skip if vertices haven't loaded yet (layers loads before vertices from .tres).
				var in_bounds: bool = true
				for idx: int in idx_poly:
					if idx >= vertices.size():
						in_bounds = false
						break
				if not in_bounds:
					continue
				# Compute signed area and centroid of this polygon piece via the shoelace formula.
				var area: float = 0.0
				var cx: float = 0.0
				var cy: float = 0.0
				var n: int = idx_poly.size()
				for i: int in range(n):
					var a: Vector2 = vertices[idx_poly[i]]
					var b: Vector2 = vertices[idx_poly[(i + 1) % n]]
					var cross: float = a.x * b.y - b.x * a.y
					area += cross
					cx += (a.x + b.x) * cross
					cy += (a.y + b.y) * cross
				area *= 0.5
				var abs_area: float = abs(area)
				if abs_area > 0.0:
					weighted += Vector2(cx, cy) / (6.0 * area) * abs_area
					total_area += abs_area
			if total_area > 0.0:
				region.center = weighted / total_area


func get_resolved_polygons(region: Region) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for idx_poly: PackedInt32Array in region.polygon_indices:
		var poly: PackedVector2Array = PackedVector2Array()
		for idx: int in idx_poly:
			poly.append(vertices[idx])
		result.append(poly)
	return result


func initialize_from_image(polygons: Array[PackedVector2Array], map_size: Vector2) -> void:
	# Build the vertex pool and base layer from image-extracted polygons.
	# All existing child layer regions are cleared because their polygon_indices
	# would reference stale positions.
	size = map_size
	var new_vertices: Array[Vector2] = []
	var base_poly_indices: Array[PackedInt32Array] = []
	for polygon: PackedVector2Array in polygons:
		var idx_poly: PackedInt32Array = PackedInt32Array()
		for pt: Vector2 in polygon:
			idx_poly.append(new_vertices.size())
			new_vertices.append(pt)
		base_poly_indices.append(idx_poly)
	vertices = new_vertices

	var min_pt: Vector2 = Vector2(INF, INF)
	var max_pt: Vector2 = Vector2(-INF, -INF)
	for pt: Vector2 in vertices:
		min_pt.x = min(min_pt.x, pt.x)
		min_pt.y = min(min_pt.y, pt.y)
		max_pt.x = max(max_pt.x, pt.x)
		max_pt.y = max(max_pt.y, pt.y)

	var bounding_rect: PackedVector2Array = PackedVector2Array()
	if min_pt.x < INF:
		bounding_rect.append(min_pt)
		bounding_rect.append(Vector2(max_pt.x, min_pt.y))
		bounding_rect.append(max_pt)
		bounding_rect.append(Vector2(min_pt.x, max_pt.y))

	var base_region: Region = Region.new()
	base_region.name = "Map"
	base_region.color = Color(0.5, 0.7, 0.9)
	base_region.polygon_indices = base_poly_indices
	base_region.generation_cell = bounding_rect

	var base_layer: MapLayer = MapLayer.new()
	base_layer.name = "Base"
	base_layer.regions = [base_region]

	if layers.is_empty():
		layers = [base_layer]
	else:
		layers[0] = base_layer
		for i: int in range(1, layers.size()):
			layers[i].regions = []
	_sync_region_centers()
	changed.emit()
