class_name VoronoiGeometry


static func circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var ad: float = a.length_squared()
	var bd: float = b.length_squared()
	var cd: float = c.length_squared()
	var D: float = 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if abs(D) < 0.0001:
		return (a + b + c) / 3.0
	return Vector2(
		(ad * (b.y - c.y) + bd * (c.y - a.y) + cd * (a.y - b.y)) / D,
		(ad * (c.x - b.x) + bd * (a.x - c.x) + cd * (b.x - a.x)) / D
	)


static func sort_clockwise(vertices: Array, center: Vector2) -> Array:
	var sorted: Array = vertices.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return (a - center).angle() < (b - center).angle()
	)
	return sorted


static func ghost_points_for_polygon(polygon: PackedVector2Array) -> Array[Vector2]:
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for point: Vector2 in polygon:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)
	var margin: float = max(max_x - min_x, max_y - min_y) * 2.0
	return [
		Vector2(min_x - margin, min_y - margin),
		Vector2(max_x + margin, min_y - margin),
		Vector2(max_x + margin, max_y + margin),
		Vector2(min_x - margin, max_y + margin),
		Vector2((min_x + max_x) / 2.0, min_y - margin),
		Vector2(max_x + margin, (min_y + max_y) / 2.0),
		Vector2((min_x + max_x) / 2.0, max_y + margin),
		Vector2(min_x - margin, (min_y + max_y) / 2.0),
	]


## Groups point indices by which piece polygon contains them.
## Returns { piece_index -> Array[int] } covering all pieces (empty arrays included).
static func group_points_by_piece(points: Array[Vector2], map_shape: Array[PackedVector2Array]) -> Dictionary:
	var piece_to_points: Dictionary = {}
	for i: int in range(map_shape.size()):
		piece_to_points[i] = []
	for point_idx: int in range(points.size()):
		for piece_idx: int in range(map_shape.size()):
			if Geometry2D.is_point_in_polygon(points[point_idx], map_shape[piece_idx]):
				piece_to_points[piece_idx].append(point_idx)
				break
	return piece_to_points


## Clips a Voronoi cell polygon to a boundary polygon.
## Returns all resulting intersection pieces as separate Arrays.
static func clip_cell_to_polygon(vertices: Array, polygon: PackedVector2Array, center: Vector2) -> Array:
	if vertices.is_empty() or polygon.size() < 3:
		return []

	var voronoi_cell: PackedVector2Array = PackedVector2Array()
	for vertex: Vector2 in vertices:
		voronoi_cell.append(vertex)

	if Geometry2D.is_polygon_clockwise(voronoi_cell):
		voronoi_cell.reverse()

	var clip_polygon: PackedVector2Array = polygon
	if Geometry2D.is_polygon_clockwise(clip_polygon):
		clip_polygon = polygon.duplicate()
		clip_polygon.reverse()

	var intersection: Array[PackedVector2Array] = Geometry2D.intersect_polygons(voronoi_cell, clip_polygon)

	if intersection.is_empty():
		if Geometry2D.is_point_in_polygon(center, polygon):
			push_warning("Voronoi clipping failed for point at ", center, " - using unclipped cell")
			return [vertices]
		return []

	var result: Array = []
	for poly: PackedVector2Array in intersection:
		var cell_vertices: Array = []
		for vertex: Vector2 in poly:
			cell_vertices.append(vertex)
		if cell_vertices.size() >= 3:
			result.append(cell_vertices)
	return result


## Builds Voronoi cells for a single piece, returning all cells as an Array.
static func voronoi_cells_for_piece(global_indices: Array, polygon: PackedVector2Array, points: Array[Vector2]) -> Array:
	var data: Dictionary = _collect_circumcenters(global_indices, polygon, points)
	var local_voronoi: Dictionary = data.local_voronoi
	var local_points: PackedVector2Array = data.local_points

	var result: Array = []
	for local_idx: int in local_voronoi.keys():
		var vertices: Array = local_voronoi[local_idx]
		if vertices.size() < 3:
			continue
		var sorted: Array = sort_clockwise(vertices, local_points[local_idx])
		for cell: Array in clip_cell_to_polygon(sorted, polygon, local_points[local_idx]):
			if cell.size() >= 3:
				result.append(cell)
	return result


## Builds Voronoi cells for a single piece, returning a mapping of
## global point index -> best cell (used for Lloyd relaxation).
static func voronoi_cells_for_piece_tracked(global_indices: Array, polygon: PackedVector2Array, points: Array[Vector2]) -> Dictionary:
	var data: Dictionary = _collect_circumcenters(global_indices, polygon, points)
	var local_voronoi: Dictionary = data.local_voronoi
	var local_points: PackedVector2Array = data.local_points
	var local_to_global: Array = data.local_to_global

	var result: Dictionary = {}
	for local_idx: int in local_voronoi.keys():
		var vertices: Array = local_voronoi[local_idx]
		if vertices.size() < 3:
			continue
		var center: Vector2 = local_points[local_idx]
		var sorted: Array = sort_clockwise(vertices, center)
		var best_cell: Array = _pick_best_cell(clip_cell_to_polygon(sorted, polygon, center), center)
		if best_cell.size() >= 3:
			result[local_to_global[local_idx]] = best_cell
	return result


# Shared core: builds ghost-augmented Delaunay and collects circumcenters per local point.
static func _collect_circumcenters(global_indices: Array, polygon: PackedVector2Array, points: Array[Vector2]) -> Dictionary:
	var local_points: PackedVector2Array = PackedVector2Array()
	var local_to_global: Array[int] = []
	for global_idx: int in global_indices:
		local_points.append(points[global_idx])
		local_to_global.append(global_idx)

	var all_points: PackedVector2Array = local_points.duplicate()
	for ghost: Vector2 in ghost_points_for_polygon(polygon):
		all_points.append(ghost)

	var real_count: int = local_points.size()
	var indices: PackedInt32Array = Geometry2D.triangulate_delaunay(all_points)

	var min_bounds: Vector2 = Vector2(INF, INF)
	var max_bounds: Vector2 = Vector2(-INF, -INF)
	for v: Vector2 in polygon:
		min_bounds.x = min(min_bounds.x, v.x)
		min_bounds.y = min(min_bounds.y, v.y)
		max_bounds.x = max(max_bounds.x, v.x)
		max_bounds.y = max(max_bounds.y, v.y)
	var max_distance: float = (max_bounds - min_bounds).length() * 3.0
	var polygon_center: Vector2 = (min_bounds + max_bounds) / 2.0

	var local_voronoi: Dictionary = {}
	for i: int in range(real_count):
		local_voronoi[i] = []

	for i: int in range(0, indices.size(), 3):
		var idx0: int = indices[i]
		var idx1: int = indices[i + 1]
		var idx2: int = indices[i + 2]
		var center: Vector2 = circumcenter(all_points[idx0], all_points[idx1], all_points[idx2])
		if center.distance_to(polygon_center) > max_distance:
			continue
		if idx0 < real_count: local_voronoi[idx0].append(center)
		if idx1 < real_count: local_voronoi[idx1].append(center)
		if idx2 < real_count: local_voronoi[idx2].append(center)

	return { "local_voronoi": local_voronoi, "local_points": local_points, "local_to_global": local_to_global }


# Picks the cell containing center, or the one closest to it.
static func _pick_best_cell(cells: Array, center: Vector2) -> Array:
	var best_cell: Array = []
	var best_distance: float = INF
	for cell: Array in cells:
		if cell.size() < 3:
			continue
		var packed: PackedVector2Array = PackedVector2Array()
		for v: Vector2 in cell:
			packed.append(v)
		if Geometry2D.is_point_in_polygon(center, packed):
			return cell
		var centroid: Vector2 = Vector2.ZERO
		for v: Vector2 in cell:
			centroid += v
		centroid /= cell.size()
		var dist: float = center.distance_to(centroid)
		if dist < best_distance:
			best_distance = dist
			best_cell = cell
	return best_cell
