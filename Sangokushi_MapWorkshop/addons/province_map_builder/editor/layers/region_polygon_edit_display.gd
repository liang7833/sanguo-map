@tool
extends Control
class_name RegionPolygonEditDisplay

# Expected setup:
#   - Size policy: expand to fill available space (set in scene)
#   - mouse_filter: MOUSE_FILTER_STOP (default for Control)

const SNAP_RADIUS: float = 8.0
const EDGE_HANDLE_RADIUS: float = 5.0

const REGION_OUTLINE_COLOR: Color = Color(0.1, 0.1, 0.1, 0.8)
const REGION_OUTLINE_WIDTH: float = 1.0
const VERTEX_COLOR: Color = Color.WHITE
const VERTEX_HOVER_COLOR: Color = Color.YELLOW
const EDGE_HANDLE_COLOR: Color = Color(0.9, 0.9, 0.9, 0.55)
const SHARED_EDGE_HANDLE_COLOR: Color = Color(0.4, 0.9, 0.4, 0.7)

@export var margin: float = 10.0:
	set(value):
		margin = value
		queue_redraw()

var province_map: ProvinceMap:
	set(value):
		province_map = value
		_rebuild_vertex_groups()
		queue_redraw()

var layer: MapLayer:
	set(value):
		if layer != value:
			_reset_interaction_state()
		layer = value
		_rebuild_vertex_groups()
		queue_redraw()

# Emitted on drag release.
signal vertex_group_moved(global_idx: int, new_pos: Vector2)

# Emitted on edge-insert release.
signal vertex_inserted(edge_a_idx: int, edge_b_idx: int, pos: Vector2)

# Emitted on right-click delete (single non-shared vertex only).
signal vertex_deleted(region: Region, poly_idx: int, vert_idx: int)

# ---------- vertex group structures ----------
# Each group: {"global_idx": int, "members": Array}
# members entries: {"region": Region, "poly_idx": int, "vert_idx": int}
var _vertex_groups: Array = []
var _global_idx_to_group: Dictionary = {}   # global vertex index -> index into _vertex_groups

# ---------- interaction state ----------
var _hovered_group_idx: int = -1
var _hovered_edge_region: Region = null
var _hovered_edge_poly: int = -1
var _hovered_edge_after: int = -1

var _is_dragging: bool = false
var _drag_has_moved: bool = false
var _drag_current_map_pos: Vector2

var _drag_group_idx: int = -1       # >= 0: dragging an existing vertex group
var _pending_edge_a_idx: int = -1   # global vertex index A for edge-insert drag
var _pending_edge_b_idx: int = -1   # global vertex index B for edge-insert drag


func _reset_interaction_state() -> void:
	_hovered_group_idx = -1
	_hovered_edge_region = null
	_hovered_edge_poly = -1
	_hovered_edge_after = -1
	_is_dragging = false
	_drag_has_moved = false
	_drag_group_idx = -1
	_pending_edge_a_idx = -1
	_pending_edge_b_idx = -1


# ---------- vertex group management ----------

func _rebuild_vertex_groups() -> void:
	_vertex_groups = []
	_global_idx_to_group = {}
	if not layer or not province_map:
		return
	for region: Region in layer.regions:
		for pi: int in range(region.polygon_indices.size()):
			for vi: int in range(region.polygon_indices[pi].size()):
				var g: int = region.polygon_indices[pi][vi]
				if not _global_idx_to_group.has(g):
					_global_idx_to_group[g] = _vertex_groups.size()
					_vertex_groups.append({"global_idx": g, "members": []})
				(_vertex_groups[_global_idx_to_group[g]]["members"] as Array).append(
					{"region": region, "poly_idx": pi, "vert_idx": vi})


# ---------- transform ----------

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _calculate_transform() -> Dictionary:
	if not province_map or province_map.size == Vector2.ZERO:
		return {"scale": 1.0, "offset": Vector2.ZERO}
	var available_size: Vector2 = size - Vector2(margin * 2.0, margin * 2.0)
	var sc: float = min(available_size.x / province_map.size.x, available_size.y / province_map.size.y)
	var off: Vector2 = (size - province_map.size * sc) / 2.0
	return {"scale": sc, "offset": off}


# ---------- drawing ----------

func _draw() -> void:
	if not layer or not province_map:
		return

	var t: Dictionary = _calculate_transform()
	var sc: float = t.scale
	var off: Vector2 = t.offset

	# Draw all region polygons
	for region: Region in layer.regions:
		for pi: int in range(region.polygon_indices.size()):
			var screen_poly: PackedVector2Array = _screen_polygon(region, pi, sc, off)
			if screen_poly.size() < 3:
				continue
			# Skip fill if invalid (e.g. self-intersecting during drag) to avoid console errors.
			if not Geometry2D.triangulate_polygon(screen_poly).is_empty():
				draw_colored_polygon(screen_poly, region.color)
			draw_polyline(screen_poly, REGION_OUTLINE_COLOR, REGION_OUTLINE_WIDTH, true)

	# Draw edge ghost handle for hovered edge
	if _hovered_edge_region != null and not _is_dragging:
		var poly: PackedInt32Array = _hovered_edge_region.polygon_indices[_hovered_edge_poly]
		var n: int = poly.size()
		if n >= 2:
			var v_a: Vector2 = province_map.vertices[poly[_hovered_edge_after]] * sc + off
			var v_b: Vector2 = province_map.vertices[poly[(_hovered_edge_after + 1) % n]] * sc + off
			var mid: Vector2 = (v_a + v_b) / 2.0
			var is_shared: bool = _is_shared_edge(
				_hovered_edge_region, _hovered_edge_poly, _hovered_edge_after)
			var handle_color: Color = SHARED_EDGE_HANDLE_COLOR if is_shared else EDGE_HANDLE_COLOR
			draw_circle(mid, EDGE_HANDLE_RADIUS + 1.0, Color.BLACK)
			draw_circle(mid, EDGE_HANDLE_RADIUS, handle_color)

	# Draw one diamond per vertex group
	for group_idx: int in range(_vertex_groups.size()):
		var screen_v: Vector2 = _group_screen_pos(group_idx, sc, off)
		var is_hovered: bool = (_hovered_group_idx == group_idx)
		_draw_diamond(screen_v, VERTEX_HOVER_COLOR if is_hovered else VERTEX_COLOR)

	# Ghost diamond at cursor during edge-insert drag
	if _is_dragging and _pending_edge_a_idx >= 0:
		_draw_diamond(_drag_current_map_pos * sc + off, VERTEX_HOVER_COLOR)


# Build screen polygon with live substitution for drag/insert.
func _screen_polygon(region: Region, poly_idx: int, sc: float, off: Vector2) -> PackedVector2Array:
	var indices: PackedInt32Array = region.polygon_indices[poly_idx]
	var n: int = indices.size()

	# Pending edge-insert: show ghost vertex in this polygon if it contains the pending edge
	if _is_dragging and _pending_edge_a_idx >= 0:
		var found_at: int = _find_edge_in_poly(indices, _pending_edge_a_idx, _pending_edge_b_idx)
		if found_at >= 0:
			var result: PackedVector2Array = PackedVector2Array()
			for i: int in range(n):
				result.append(province_map.vertices[indices[i]] * sc + off)
				if i == found_at:
					result.append(_drag_current_map_pos * sc + off)
			return result

	# Vertex group drag: substitute all occurrences of the dragged global index
	if _is_dragging and _drag_group_idx >= 0:
		var drag_g: int = _vertex_groups[_drag_group_idx]["global_idx"]
		var result: PackedVector2Array = PackedVector2Array()
		for i: int in range(n):
			if indices[i] == drag_g:
				result.append(_drag_current_map_pos * sc + off)
			else:
				result.append(province_map.vertices[indices[i]] * sc + off)
		return result

	var result: PackedVector2Array = PackedVector2Array()
	for i: int in range(n):
		result.append(province_map.vertices[indices[i]] * sc + off)
	return result


# Returns the index vi such that the edge starting at vi matches [a_idx, b_idx] or [b_idx, a_idx].
func _find_edge_in_poly(indices: PackedInt32Array, a_idx: int, b_idx: int) -> int:
	var n: int = indices.size()
	for vi: int in range(n):
		var next: int = (vi + 1) % n
		if (indices[vi] == a_idx and indices[next] == b_idx) or \
				(indices[vi] == b_idx and indices[next] == a_idx):
			return vi
	return -1


func _group_screen_pos(group_idx: int, sc: float, off: Vector2) -> Vector2:
	if _is_dragging and _drag_group_idx == group_idx:
		return _drag_current_map_pos * sc + off
	var g: int = _vertex_groups[group_idx]["global_idx"]
	return province_map.vertices[g] * sc + off


func _draw_diamond(pos: Vector2, color: Color) -> void:
	const OUTER: float = 5.5
	const INNER: float = 4.0
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0.0, -OUTER), pos + Vector2(OUTER, 0.0),
		pos + Vector2(0.0, OUTER), pos + Vector2(-OUTER, 0.0),
	]), Color.BLACK)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0.0, -INNER), pos + Vector2(INNER, 0.0),
		pos + Vector2(0.0, INNER), pos + Vector2(-INNER, 0.0),
	]), color)


# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if not layer or not province_map:
		return

	var t: Dictionary = _calculate_transform()
	var sc: float = t.scale
	var off: Vector2 = t.offset

	if event is InputEventMouseMotion:
		_drag_current_map_pos = (event.position - off) / sc

		if _is_dragging:
			_drag_has_moved = true
			queue_redraw()
			accept_event()
			return

		var new_hg: int = _find_hovered_group(event.position, sc, off)
		var new_he: Dictionary = {}
		if new_hg < 0:
			new_he = _find_hovered_edge(event.position, sc, off)

		var new_he_region: Region = new_he.get("region", null)
		var new_he_poly: int = new_he.get("poly_idx", -1)
		var new_he_after: int = new_he.get("after_idx", -1)

		if new_hg != _hovered_group_idx or new_he_region != _hovered_edge_region \
				or new_he_poly != _hovered_edge_poly or new_he_after != _hovered_edge_after:
			_hovered_group_idx = new_hg
			_hovered_edge_region = new_he_region
			_hovered_edge_poly = new_he_poly
			_hovered_edge_after = new_he_after
			queue_redraw()

	elif event is InputEventMouseButton:
		var map_pos: Vector2 = (event.position - off) / sc

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hg: int = _find_hovered_group(event.position, sc, off)
				if hg >= 0:
					_drag_group_idx = hg
					_pending_edge_a_idx = -1
					_pending_edge_b_idx = -1
					_drag_current_map_pos = map_pos
					_is_dragging = true
					_drag_has_moved = false
					accept_event()
				else:
					var he: Dictionary = _find_hovered_edge(event.position, sc, off)
					if not he.is_empty():
						var he_region: Region = he["region"]
						var he_poly: int = he["poly_idx"]
						var he_after: int = he["after_idx"]
						var poly: PackedInt32Array = he_region.polygon_indices[he_poly]
						_pending_edge_a_idx = poly[he_after]
						_pending_edge_b_idx = poly[(he_after + 1) % poly.size()]
						_drag_group_idx = -1
						_drag_current_map_pos = map_pos
						_is_dragging = true
						_drag_has_moved = false
						_hovered_edge_region = null
						_hovered_edge_poly = -1
						_hovered_edge_after = -1
						accept_event()
			else:
				if _is_dragging:
					if _drag_has_moved or _pending_edge_a_idx >= 0:
						if _drag_group_idx >= 0:
							vertex_group_moved.emit(
								_vertex_groups[_drag_group_idx]["global_idx"],
								_drag_current_map_pos)
						elif _pending_edge_a_idx >= 0:
							vertex_inserted.emit(
								_pending_edge_a_idx, _pending_edge_b_idx, _drag_current_map_pos)
					_is_dragging = false
					_drag_has_moved = false
					_drag_group_idx = -1
					_pending_edge_a_idx = -1
					_pending_edge_b_idx = -1
					queue_redraw()
					accept_event()

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var hg: int = _find_hovered_group(event.position, sc, off)
			if hg >= 0:
				var group: Dictionary = _vertex_groups[hg]
				var members: Array = group["members"] as Array
				var seen_regions: Dictionary = {}
				var members_ok: bool = true
				for mem: Dictionary in members:
					var rid: int = (mem["region"] as Region).get_instance_id()
					if seen_regions.has(rid):
						members_ok = false
						break
					seen_regions[rid] = true

				var error_msg: String = ""
				if not members_ok:
					error_msg = "Cannot delete vertex: appears in multiple polygon pieces of the same region"
				elif seen_regions.size() > 2:
					error_msg = "Cannot delete vertex: shared by more than 2 regions"
				else:
					error_msg = _deletion_blocked_reason(group["global_idx"])

				if error_msg.is_empty():
					var m: Dictionary = members[0]
					vertex_deleted.emit(m["region"], m["poly_idx"], m["vert_idx"])
					_hovered_group_idx = -1
				else:
					EditorInterface.get_editor_toaster().push_toast(
						error_msg, EditorToaster.SEVERITY_WARNING)
				accept_event()


# ---------- deletion check ----------

# Returns empty string if vertex g can be safely deleted, or a human-readable reason if not.
# Checks each layer recursively:
# - 3+ regions share g → ambiguous T/Y junction, block
# - 2 regions share g AND g is on the map boundary → block (restructures external outline)
# - any polygon containing g has <= 3 vertices → would collapse, block
func _deletion_blocked_reason(g: int, layer_idx: int = 0) -> String:
	if not province_map or layer_idx >= province_map.layers.size():
		return ""
	var l: MapLayer = province_map.layers[layer_idx]
	var regions_with_g: int = 0
	for r: Region in l.regions:
		for pi: int in range(r.polygon_indices.size()):
			if g in r.polygon_indices[pi]:
				regions_with_g += 1
				if r.polygon_indices[pi].size() <= 3:
					return "Cannot delete vertex: polygon would have fewer than 3 vertices"
				break  # count each region only once
	if regions_with_g >= 3:
		return "Cannot delete vertex: shared by 3 or more regions"
	if regions_with_g == 2 and _is_on_map_boundary(g):
		return "Cannot delete vertex: on the map boundary shared between two regions"
	return _deletion_blocked_reason(g, layer_idx + 1)


# True if g is present in the base layer (layer 0) polygon — i.e. it's on the external map outline.
func _is_on_map_boundary(g: int) -> bool:
	if not province_map or province_map.layers.is_empty():
		return false
	for r: Region in province_map.layers[0].regions:
		for poly: PackedInt32Array in r.polygon_indices:
			if g in poly:
				return true
	return false


# ---------- hit-testing ----------

func _find_hovered_group(screen_pos: Vector2, sc: float, off: Vector2) -> int:
	var best_dist: float = SNAP_RADIUS
	var best_idx: int = -1
	for group_idx: int in range(_vertex_groups.size()):
		var g: int = _vertex_groups[group_idx]["global_idx"]
		var vpos: Vector2 = province_map.vertices[g] * sc + off
		var dist: float = screen_pos.distance_to(vpos)
		if dist < best_dist:
			best_dist = dist
			best_idx = group_idx
	return best_idx


# Returns {"region", "poly_idx", "after_idx", "is_shared"} or empty dict.
func _find_hovered_edge(screen_pos: Vector2, sc: float, off: Vector2) -> Dictionary:
	var best_dist: float = SNAP_RADIUS
	var best: Dictionary = {}
	for region: Region in layer.regions:
		for pi: int in range(region.polygon_indices.size()):
			var poly: PackedInt32Array = region.polygon_indices[pi]
			var n: int = poly.size()
			if n < 2:
				continue
			for j: int in range(n):
				var v_a: Vector2 = province_map.vertices[poly[j]] * sc + off
				var v_b: Vector2 = province_map.vertices[poly[(j + 1) % n]] * sc + off
				var mid: Vector2 = (v_a + v_b) / 2.0
				var dist: float = screen_pos.distance_to(mid)
				if dist < best_dist:
					best_dist = dist
					best = {"region": region, "poly_idx": pi, "after_idx": j,
						"is_shared": _is_shared_edge(region, pi, j)}
	return best


# True if another region in this layer has the reversed edge [B→A], meaning a shared boundary.
func _is_shared_edge(region: Region, poly_idx: int, after_idx: int) -> bool:
	var poly: PackedInt32Array = region.polygon_indices[poly_idx]
	var n: int = poly.size()
	var idx_a: int = poly[after_idx]
	var idx_b: int = poly[(after_idx + 1) % n]
	for other: Region in layer.regions:
		if other == region:
			continue
		for pi: int in range(other.polygon_indices.size()):
			var op: PackedInt32Array = other.polygon_indices[pi]
			var m: int = op.size()
			for vi: int in range(m):
				if op[vi] == idx_b and op[(vi + 1) % m] == idx_a:
					return true
	return false
