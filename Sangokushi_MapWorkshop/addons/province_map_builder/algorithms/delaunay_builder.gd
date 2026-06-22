class_name DelaunayBuilder


## Triangulates points grouped by map shape piece.
## Returns an Array of triangles, each triangle being Array[Vector2] of 3 vertices.
static func build_triangles(points: Array[Vector2], map_shape: Array[PackedVector2Array]) -> Array:
	var triangles: Array = []
	if points.is_empty() or map_shape.is_empty():
		return triangles

	var piece_to_points: Dictionary = VoronoiGeometry.group_points_by_piece(points, map_shape)

	for piece_idx: int in range(map_shape.size()):
		var global_indices: Array = piece_to_points.get(piece_idx, [])
		if global_indices.size() < 3:
			continue

		var local_points: PackedVector2Array = PackedVector2Array()
		for global_idx: int in global_indices:
			local_points.append(points[global_idx])

		var local_indices: PackedInt32Array = Geometry2D.triangulate_delaunay(local_points)
		for i: int in range(0, local_indices.size(), 3):
			triangles.append([
				local_points[local_indices[i]],
				local_points[local_indices[i + 1]],
				local_points[local_indices[i + 2]],
			])

	return triangles
