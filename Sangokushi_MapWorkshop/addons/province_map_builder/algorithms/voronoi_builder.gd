class_name VoronoiBuilder


## Builds Voronoi cells for all map shape pieces from a set of points.
## Returns an Array of cells, each cell being an Array[Vector2] of vertices.
static func build_cells(points: Array[Vector2], map_shape: Array[PackedVector2Array]) -> Array[Array]:
	var cells: Array[Array] = []
	if map_shape.is_empty():
		return cells

	if points.is_empty():
		for polygon: PackedVector2Array in map_shape:
			var vertices: Array = []
			for v: Vector2 in polygon:
				vertices.append(v)
			cells.append(vertices)
		return cells

	var piece_to_points: Dictionary = VoronoiGeometry.group_points_by_piece(points, map_shape)

	for piece_idx: int in range(map_shape.size()):
		var polygon: PackedVector2Array = map_shape[piece_idx]
		var global_indices: Array = piece_to_points.get(piece_idx, [])

		if global_indices.size() <= 1:
			var vertices: Array = []
			for v: Vector2 in polygon:
				vertices.append(v)
			cells.append(vertices)
		else:
			for cell: Array in VoronoiGeometry.voronoi_cells_for_piece(global_indices, polygon, points):
				cells.append(cell)

	return cells
