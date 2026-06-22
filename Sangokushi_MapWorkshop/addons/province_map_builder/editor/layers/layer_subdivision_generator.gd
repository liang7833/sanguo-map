@tool
class_name SubdivisionGenerator extends Window

# Expected exports (wire in scene):
#   display: GeneratorPreviewDisplay — live preview canvas
#   points_spinbox: SpinBox — seed point count
#   relaxation_spinbox: SpinBox — Lloyd relaxation iterations
#   seed_spinbox: SpinBox — RNG seed
#   randomize_button: Button — randomize seed
#   generate_button: Button — run full re-generation
#   apply_button: Button — commit to real layer and close
#   info_label: Label — shows "Subdividing <Parent> → <Child>"
#   cell_opacity_slider: HSlider — controls Voronoi cell fill opacity

## Emitted after all data has been written to the child layer and province map.
## Connect to this to react after the generator commits (e.g. inserting a new layer).
signal applied

@export var display: GeneratorPreviewDisplay
@export var points_spinbox: SpinBox
@export var relaxation_spinbox: SpinBox
@export var seed_spinbox: SpinBox
@export var randomize_button: Button
@export var generate_button: Button
@export var apply_button: Button
@export var info_label: Label
@export var cell_opacity_slider: HSlider

var _province_map: ProvinceMap
var _parent_layer: MapLayer
var _child_layer: MapLayer
var _undo_redo: EditorUndoRedoManager
var _is_new_layer: bool = false
# Each entry: {"name": String, "color": Color, "polygons": Array[PackedVector2Array],
#              "generation_cell": PackedVector2Array, "child_indices": Array[int], "data": Dictionary}
var _working_data: Array = []
var _parent_to_children: Dictionary = {}

# Per-region local-space points and bounds, populated by _initialize_points()
var _local_points_per_region: Array = []   # Array[Array[Vector2]], one entry per parent region
var _region_bounds: Array[Rect2] = []      # bounding rect per parent region
var _flat_to_region: Array[Vector2i] = []  # flat_idx → Vector2i(region_idx, local_idx)
var _flat_world_points: Array[Vector2] = []
var _flat_world_cells: Array[PackedVector2Array] = []

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	set_unparent_when_invisible(true)
	close_requested.connect(_on_cancel)

	if randomize_button:
		randomize_button.pressed.connect(_on_randomize)
	if generate_button:
		generate_button.pressed.connect(_initialize_points)
	if apply_button:
		apply_button.pressed.connect(_on_apply)

	if points_spinbox:
		points_spinbox.value_changed.connect(func(_v): _initialize_points())
	if relaxation_spinbox:
		relaxation_spinbox.value_changed.connect(func(_v): _initialize_points())
	if seed_spinbox:
		seed_spinbox.value_changed.connect(func(_v): _initialize_points())

	if cell_opacity_slider and display:
		cell_opacity_slider.value = display.cell_opacity
		cell_opacity_slider.value_changed.connect(func(v): display.cell_opacity = v)
	if display:
		display.point_dragging.connect(_on_point_dragging)


## Open the generator for an existing child layer (re-subdivision) or a new layer not yet
## in the map. When child_layer is not yet in province_map.layers, pass parent_layer
## explicitly — the caller is responsible for inserting the layer on apply.
## Pass undo_redo to record the apply as an undoable action.
func open(province_map: ProvinceMap, child_layer: MapLayer,
		parent_layer: MapLayer = null,
		undo_redo: EditorUndoRedoManager = null) -> void:
	_province_map = province_map
	_child_layer = child_layer
	_undo_redo = undo_redo
	_is_new_layer = parent_layer != null
	_working_data = []
	_parent_to_children = {}

	if parent_layer:
		_parent_layer = parent_layer
	else:
		var child_idx: int = province_map.layers.find(child_layer)
		if child_idx <= 0:
			push_warning("LayerSubdivisionGenerator: child layer must be at index > 0")
			return
		_parent_layer = province_map.layers[child_idx - 1]

	if info_label:
		info_label.text = "Subdividing  %s  →  %s" % [_parent_layer.name, _child_layer.name]

	if display:
		display.province_map = province_map
		display.parent_layer = _parent_layer

	if apply_button:
		apply_button.disabled = true

	_initialize_points()


func _on_randomize() -> void:
	if seed_spinbox:
		seed_spinbox.value = randi()


func _initialize_points() -> void:
	if not _province_map or not _parent_layer or not _child_layer:
		return

	_local_points_per_region = []
	_region_bounds = []
	_flat_to_region = []
	_flat_world_points = []

	rng.seed = int(seed_spinbox.value) if seed_spinbox else 0
	var point_count: int = int(points_spinbox.value) if points_spinbox else 10
	var relax_iters: int = int(relaxation_spinbox.value) if relaxation_spinbox else 0

	for region_idx: int in range(_parent_layer.regions.size()):
		var parent_region: Region = _parent_layer.regions[region_idx]

		var gen_space: PackedVector2Array = _get_generation_space(parent_region)
		if gen_space.size() < 3:
			_local_points_per_region.append([])
			_region_bounds.append(Rect2())
			continue

		var bounds: Rect2 = _polygon_bounds(gen_space)
		var local_space: PackedVector2Array = _translate_polygon(gen_space, -bounds.position)

		var points: Array[Vector2] = PointGenerator.random_points(point_count, bounds.size, rng)
		if relax_iters > 0:
			points = LloydRelaxation.relax(points, [local_space], relax_iters, bounds.size)

		_local_points_per_region.append(points)
		_region_bounds.append(bounds)

		for local_idx: int in range(points.size()):
			_flat_to_region.append(Vector2i(region_idx, local_idx))
			_flat_world_points.append(points[local_idx] + bounds.position)

	_run_voronoi()


func _run_voronoi() -> void:
	_working_data = []
	_parent_to_children = {}
	_flat_world_cells = []

	for region_idx: int in range(_parent_layer.regions.size()):
		var parent_region: Region = _parent_layer.regions[region_idx]
		var child_indices: Array[int] = []

		if region_idx >= _local_points_per_region.size() \
				or (_local_points_per_region[region_idx] as Array).is_empty():
			_parent_to_children[region_idx] = child_indices
			continue

		var local_pts: Array[Vector2] = []
		local_pts.assign(_local_points_per_region[region_idx])

		var bounds: Rect2 = _region_bounds[region_idx]
		var gen_space: PackedVector2Array = _get_generation_space(parent_region)
		var local_space: PackedVector2Array = _translate_polygon(gen_space, -bounds.position)

		var cells: Array[Array] = VoronoiBuilder.build_cells(local_pts, [local_space])

		for cell: Array in cells:
			if cell.size() < 3:
				continue
			var world_cell: PackedVector2Array = PackedVector2Array()
			for v: Vector2 in cell:
				world_cell.append(v + bounds.position)

			var land_polygons: Array[PackedVector2Array] = _clip_to_region(world_cell, parent_region)
			if land_polygons.is_empty():
				continue

			# Preview shows clipped polygons (not raw cells) so they never overlap between regions
			for clipped: PackedVector2Array in land_polygons:
				_flat_world_cells.append(clipped)

			var entry: Dictionary = {
				"name": "Region %d" % _working_data.size(),
				"color": Color.from_hsv(
					fmod(float(_working_data.size()) * 0.618033988749895, 1.0), 0.6, 0.85
				),
				"polygons": land_polygons,
				"generation_cell": world_cell,
				"child_indices": [],
				"data": {}
			}
			child_indices.append(_working_data.size())
			_working_data.append(entry)

		_parent_to_children[region_idx] = child_indices

	if display:
		display.seed_points = _flat_world_points
		display.voronoi_cells = _flat_world_cells

	if apply_button:
		apply_button.disabled = _working_data.is_empty()


func _on_point_dragging(flat_idx: int, new_world_pos: Vector2) -> void:
	var ri: Vector2i = _flat_to_region[flat_idx]
	_local_points_per_region[ri.x][ri.y] = new_world_pos - _region_bounds[ri.x].position
	_flat_world_points[flat_idx] = new_world_pos
	_run_voronoi()


func _on_apply() -> void:
	if not _child_layer or _working_data.is_empty():
		return

	# --- Snapshot old state before any mutations ---
	var old_vertices: Array[Vector2] = _province_map.vertices.duplicate()
	var old_child_regions: Array[Region] = _child_layer.regions.duplicate()
	var old_layers: Array[MapLayer] = _province_map.layers.duplicate()

	# Snapshot polygon_indices for all layers from root up to (and including) parent,
	# since cascade enrichment may modify ancestors above the parent layer.
	var parent_layer_idx: int = _province_map.layers.find(_parent_layer)
	var old_poly_indices: Dictionary = {}  # Region → Array[PackedInt32Array]
	for li: int in range(parent_layer_idx + 1):
		for region: Region in _province_map.layers[li].regions:
			old_poly_indices[region] = _copy_polygon_indices(region.polygon_indices)

	# Snapshot child_region_indices for parent regions
	var old_child_region_indices: Dictionary = {}  # Region → Array[int]
	for region: Region in _parent_layer.regions:
		old_child_region_indices[region] = region.child_region_indices.duplicate()

	# --- Run the mutation logic ---
	const EPSILON: float = 0.1
	var new_regions: Array[Region] = []
	var working_verts: Array[Vector2] = _province_map.vertices.duplicate()

	for entry: Dictionary in _working_data:
		var region: Region = Region.new()
		region.name = entry["name"]
		region.color = entry["color"]
		region.generation_cell = entry["generation_cell"]
		var ci: Array[int] = []
		ci.assign(entry["child_indices"])
		region.child_region_indices = ci
		region.data = _child_layer.make_region_data()

		var poly_indices: Array[PackedInt32Array] = []
		for raw_poly: PackedVector2Array in entry["polygons"]:
			var idx_poly: PackedInt32Array = PackedInt32Array()
			for pt: Vector2 in raw_poly:
				idx_poly.append(_resolve_or_add_vertex(pt, EPSILON, working_verts))
			poly_indices.append(idx_poly)
		region.polygon_indices = poly_indices
		new_regions.append(region)

	_sync_cross_parent_boundaries(new_regions, working_verts)

	for parent_idx: int in _parent_to_children:
		if parent_idx < _parent_layer.regions.size():
			var child_indices_for_parent: Array = _parent_to_children[parent_idx]
			var child_regions_for_parent: Array[Region] = []
			for ci: int in child_indices_for_parent:
				if ci < new_regions.size():
					child_regions_for_parent.append(new_regions[ci])
			_enrich_parent_polygon(
				_parent_layer.regions[parent_idx], child_regions_for_parent, working_verts)

	var cascade_child_li: int = _province_map.layers.find(_parent_layer)
	while cascade_child_li > 0:
		var ancestor_layer: MapLayer = _province_map.layers[cascade_child_li - 1]
		var cascade_child_layer: MapLayer = _province_map.layers[cascade_child_li]
		for ancestor_region: Region in ancestor_layer.regions:
			_enrich_parent_polygon(ancestor_region, cascade_child_layer.regions, working_verts)
		cascade_child_li -= 1

	_child_layer.regions = new_regions
	_province_map.vertices = working_verts

	for parent_idx: int in _parent_to_children:
		if parent_idx < _parent_layer.regions.size():
			var pci: Array[int] = []
			pci.assign(_parent_to_children[parent_idx])
			_parent_layer.regions[parent_idx].child_region_indices = pci

	# For a new layer: insert it into the map now (inside apply, so undo covers it).
	if _is_new_layer:
		var new_layers: Array[MapLayer] = _province_map.layers.duplicate()
		new_layers.append(_child_layer)
		_province_map.layers = new_layers

	# --- Record undo action (already applied, so commit_action(false)) ---
	if _undo_redo:
		var ur: EditorUndoRedoManager = _undo_redo
		var action_name: String = "Add Layer" if _is_new_layer else "Subdivide Layer"
		ur.create_action(action_name)

		# Vertices always change.
		ur.add_do_property(_province_map, "vertices", _province_map.vertices.duplicate())
		ur.add_undo_property(_province_map, "vertices", old_vertices)

		if _is_new_layer:
			# Undo removes the new layer from the map entirely.
			ur.add_do_property(_province_map, "layers", _province_map.layers.duplicate())
			ur.add_undo_property(_province_map, "layers", old_layers)
		else:
			# Undo restores the previous subdivision of the child layer.
			ur.add_do_property(_child_layer, "regions", _child_layer.regions.duplicate())
			ur.add_undo_property(_child_layer, "regions", old_child_regions)

		# Restore polygon_indices for all ancestors (cascade enrichment modified them).
		for li: int in range(parent_layer_idx + 1):
			for region: Region in _province_map.layers[li].regions:
				if old_poly_indices.has(region):
					ur.add_do_property(region, "polygon_indices",
						_copy_polygon_indices(region.polygon_indices))
					ur.add_undo_property(region, "polygon_indices", old_poly_indices[region])

		# Restore parent child_region_indices.
		for region: Region in _parent_layer.regions:
			ur.add_do_property(region, "child_region_indices",
				region.child_region_indices.duplicate())
			ur.add_undo_property(region, "child_region_indices",
				old_child_region_indices[region])

		ur.commit_action(false)

	applied.emit()
	hide()


func _resolve_or_add_vertex(pos: Vector2, epsilon: float, verts: Array[Vector2]) -> int:
	for i: int in range(verts.size()):
		if pos.distance_squared_to(verts[i]) < epsilon * epsilon:
			return i
	verts.append(pos)
	return verts.size() - 1


func _on_cancel() -> void:
	hide()


func _get_generation_space(region: Region) -> PackedVector2Array:
	if region.generation_cell.size() >= 3:
		return region.generation_cell
	var all_pts: PackedVector2Array = PackedVector2Array()
	for polygon: PackedVector2Array in _province_map.get_resolved_polygons(region):
		all_pts.append_array(polygon)
	if all_pts.is_empty():
		return PackedVector2Array()
	var bounds: Rect2 = _polygon_bounds(all_pts)
	var rect: PackedVector2Array = PackedVector2Array()
	rect.append(bounds.position)
	rect.append(Vector2(bounds.end.x, bounds.position.y))
	rect.append(bounds.end)
	rect.append(Vector2(bounds.position.x, bounds.end.y))
	return rect


func _clip_to_region(world_cell: PackedVector2Array, region: Region) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for poly: PackedVector2Array in _province_map.get_resolved_polygons(region):
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(world_cell, poly):
			if piece.size() >= 3:
				result.append(piece)
	return result


# Ensure adjacent child regions from different parent regions share global vertex indices
# at their cross-parent boundary edge.
# Problem: A-side children have vertices at positions P1,P2 on edge [G1,G2]; B-side children
# have vertices at Q1,Q2 at *different* positions on the same edge (independent Voronoi).
# Fix: insert each side's vertices into the other side as collinear splits (no shape change,
# but now both sides reference the same global indices → moving one moves the other).
func _sync_cross_parent_boundaries(new_regions: Array[Region],
		working_verts: Array[Vector2]) -> void:
	const EPSILON: float = 0.5

	# Map each edge key → list of parent region indices that own it
	var edge_parents: Dictionary = {}
	for pi: int in range(_parent_layer.regions.size()):
		for poly: PackedInt32Array in _parent_layer.regions[pi].polygon_indices:
			var n: int = poly.size()
			for vi: int in range(n):
				var a: int = poly[vi]
				var b: int = poly[(vi + 1) % n]
				var key: String = "%d_%d" % [min(a, b), max(a, b)]
				if not edge_parents.has(key):
					edge_parents[key] = []
				if not (pi in edge_parents[key]):
					(edge_parents[key] as Array).append(pi)

	for key: String in edge_parents:
		if (edge_parents[key] as Array).size() != 2:
			continue
		var pa_idx: int = (edge_parents[key] as Array)[0]
		var pb_idx: int = (edge_parents[key] as Array)[1]

		var parts: PackedStringArray = key.split("_")
		var g1: int = int(parts[0])
		var g2: int = int(parts[1])
		var p1: Vector2 = working_verts[g1]
		var p2: Vector2 = working_verts[g2]
		var edge_vec: Vector2 = p2 - p1
		var edge_len_sq: float = edge_vec.length_squared()
		if edge_len_sq < EPSILON * EPSILON:
			continue

		# Collect all child vertices from both sides that lie on this edge, keyed by t-value
		var verts_on_edge: Dictionary = {}  # global_idx → float t
		for side: int in [pa_idx, pb_idx]:
			if not _parent_to_children.has(side):
				continue
			for ci: int in _parent_to_children[side]:
				if ci >= new_regions.size():
					continue
				for poly: PackedInt32Array in new_regions[ci].polygon_indices:
					for g: int in poly:
						if g == g1 or g == g2 or verts_on_edge.has(g):
							continue
						var pt: Vector2 = working_verts[g]
						var t: float = edge_vec.dot(pt - p1) / edge_len_sq
						if t <= 0.001 or t >= 0.999:
							continue
						var proj: Vector2 = p1 + t * edge_vec
						if pt.distance_squared_to(proj) < EPSILON * EPSILON:
							verts_on_edge[g] = t

		if verts_on_edge.is_empty():
			continue

		# For every child polygon on either side, insert any missing collinear vertices
		# into each sub-edge of this shared boundary
		for side: int in [pa_idx, pb_idx]:
			if not _parent_to_children.has(side):
				continue
			for ci: int in _parent_to_children[side]:
				if ci >= new_regions.size():
					continue
				var cr: Region = new_regions[ci]
				var new_poly_indices: Array[PackedInt32Array] = []
				var changed: bool = false

				for poly: PackedInt32Array in cr.polygon_indices:
					var n: int = poly.size()
					var new_poly: PackedInt32Array = PackedInt32Array()

					for vi: int in range(n):
						var va: int = poly[vi]
						var vb: int = poly[(vi + 1) % n]
						new_poly.append(va)

						var ta: float = _t_on_edge(va, g1, g2, verts_on_edge)
						var tb: float = _t_on_edge(vb, g1, g2, verts_on_edge)
						if ta < 0.0 or tb < 0.0:
							continue  # At least one endpoint not on this shared edge

						# Insert any vertices strictly between ta and tb
						var t_lo: float = min(ta, tb)
						var t_hi: float = max(ta, tb)
						var between: Array = []
						for g: int in verts_on_edge:
							var t: float = verts_on_edge[g]
							if t > t_lo + 0.001 and t < t_hi - 0.001:
								between.append({"g": g, "t": t})

						if between.is_empty():
							continue

						between.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
							return x.t < y.t if ta < tb else x.t > y.t)
						for sv: Dictionary in between:
							new_poly.append(sv.g)
						changed = true

					new_poly_indices.append(new_poly)

				if changed:
					cr.polygon_indices = new_poly_indices


func _t_on_edge(g: int, g1: int, g2: int, verts_on_edge: Dictionary) -> float:
	if g == g1:
		return 0.0
	if g == g2:
		return 1.0
	if verts_on_edge.has(g):
		return float(verts_on_edge[g])
	return -1.0


# Insert child boundary vertices that lie on a parent polygon edge into that edge,
# so shared boundary points have the same global index in both parent and child layers.
# Call _sync_cross_parent_boundaries first so the child vertices are symmetric across
# shared parent edges — otherwise enrichment would be asymmetric and cause tears.
func _enrich_parent_polygon(parent_region: Region, child_regions: Array[Region],
		working_verts: Array[Vector2]) -> void:
	# Collect all vertex indices used by the child regions
	var child_vert_set: Dictionary = {}
	for cr: Region in child_regions:
		for pi: int in range(cr.polygon_indices.size()):
			for idx: int in cr.polygon_indices[pi]:
				child_vert_set[idx] = true

	const EPSILON: float = 0.5
	var new_poly_indices: Array[PackedInt32Array] = []

	for pi: int in range(parent_region.polygon_indices.size()):
		var poly: PackedInt32Array = parent_region.polygon_indices[pi]
		var n: int = poly.size()
		var new_poly: PackedInt32Array = PackedInt32Array()

		for vi: int in range(n):
			var a_idx: int = poly[vi]
			var b_idx: int = poly[(vi + 1) % n]
			var pa: Vector2 = working_verts[a_idx]
			var pb: Vector2 = working_verts[b_idx]
			new_poly.append(a_idx)

			var edge_vec: Vector2 = pb - pa
			var edge_len_sq: float = edge_vec.length_squared()
			if edge_len_sq < EPSILON * EPSILON:
				continue

			# Find child vertices that lie strictly between A and B on this edge
			var on_edge: Array = []
			for child_idx: int in child_vert_set:
				if child_idx == a_idx or child_idx == b_idx:
					continue
				var pt: Vector2 = working_verts[child_idx]
				var t: float = edge_vec.dot(pt - pa) / edge_len_sq
				if t <= 0.001 or t >= 0.999:
					continue
				var proj: Vector2 = pa + t * edge_vec
				if pt.distance_squared_to(proj) < EPSILON * EPSILON:
					on_edge.append({"t": t, "idx": child_idx})

			on_edge.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["t"] < y["t"])
			for entry: Dictionary in on_edge:
				new_poly.append(entry["idx"])

		new_poly_indices.append(new_poly)

	parent_region.polygon_indices = new_poly_indices


func _copy_polygon_indices(src: Array[PackedInt32Array]) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for poly: PackedInt32Array in src:
		result.append(PackedInt32Array(poly))
	return result


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var rect: Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for pt: Vector2 in polygon:
		rect = rect.expand(pt)
	return rect


func _translate_polygon(polygon: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	result.resize(polygon.size())
	for i: int in polygon.size():
		result[i] = polygon[i] + offset
	return result
