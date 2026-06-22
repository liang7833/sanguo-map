class_name LloydRelaxation


## Runs Lloyd relaxation on points within map shape pieces.
## Returns a new Array[Vector2] with updated point positions.
static func relax(points: Array[Vector2], map_shape: Array[PackedVector2Array], iterations: int, bounds: Vector2) -> Array[Vector2]:
	if iterations <= 0 or points.is_empty():
		return points

	var result: Array[Vector2] = points.duplicate()

	for _i: int in iterations:
		var piece_to_points: Dictionary = VoronoiGeometry.group_points_by_piece(result, map_shape)

		for piece_idx: int in range(map_shape.size()):
			var polygon: PackedVector2Array = map_shape[piece_idx]
			var global_indices: Array = piece_to_points.get(piece_idx, [])
			if global_indices.size() < 2:
				continue

			var point_to_cell: Dictionary = VoronoiGeometry.voronoi_cells_for_piece_tracked(
				global_indices, polygon, result
			)

			for global_idx: int in point_to_cell.keys():
				var cell_vertices: Array = point_to_cell[global_idx]
				if cell_vertices.size() < 3:
					continue
				var centroid: Vector2 = Vector2.ZERO
				for vertex: Vector2 in cell_vertices:
					centroid += vertex
				centroid /= cell_vertices.size()
				result[global_idx] = Vector2(
					clamp(centroid.x, 0.0, bounds.x),
					clamp(centroid.y, 0.0, bounds.y)
				)

	return result
