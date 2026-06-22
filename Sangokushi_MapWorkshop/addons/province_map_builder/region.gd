@tool
class_name Region extends Resource

@export var name: String:
	set(value):
		name = value
		changed.emit()

@export var color: Color:
	set(value):
		color = value
		changed.emit()

@export var data: Resource:
	set(value):
		data = value
		changed.emit()

# Indices into the child MapLayer's regions array
@export var child_region_indices: Array[int]:
	set(value):
		child_region_indices = value
		changed.emit()

# Centroid of all polygon vertices. Not exported — recomputed by ProvinceMap whenever vertices
# or layers change. Safe to read at runtime; do not set manually.
var center: Vector2

# Land area — rendered directly. Indices into ProvinceMap.vertices. Multi-piece (island support).
@export var polygon_indices: Array[PackedInt32Array]:
	set(value):
		polygon_indices = value
		changed.emit()

# Full Voronoi cell area including sea — used only as generation space for children.
# Empty means "fall back to bounding rect of polygons".
@export var generation_cell: PackedVector2Array:
	set(value):
		generation_cell = value
		changed.emit()
