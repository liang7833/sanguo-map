class_name PointGenerator


static func random_points(count: int, bounds: Vector2, rng: RandomNumberGenerator) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for i: int in count:
		points.append(Vector2(rng.randf_range(0, bounds.x), rng.randf_range(0, bounds.y)))
	return points


static func grid_points(cols: int, rows: int, bounds: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var interval_x: float = bounds.x / (cols + 1)
	var interval_y: float = bounds.y / (rows + 1)
	for x: int in cols:
		for y: int in rows:
			points.append(Vector2((x + 1) * interval_x, (y + 1) * interval_y))
	return points
