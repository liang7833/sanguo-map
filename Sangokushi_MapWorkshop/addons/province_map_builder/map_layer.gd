@tool
class_name MapLayer extends Resource

@export var name: String:
	set(value):
		name = value
		changed.emit()

# Assign a Script that extends RegionDataSchema to define per-region properties.
# When changed, all existing regions are migrated to the new schema.
@export var data_schema: Script:
	set(value):
		data_schema = value
		_migrate_all_regions()
		changed.emit()

@export var regions: Array[Region]:
	set(value):
		regions = value
		changed.emit()

# Generation metadata stored per layer for inspection / re-generation reference
@export var generation_points: Array[Vector2]:
	set(value):
		generation_points = value
		changed.emit()

@export var generation_triangles: Array:
	set(value):
		generation_triangles = value
		changed.emit()


# Migrates all region data to match the current data_schema.
# Regions already holding the correct schema type are left untouched.
# Called automatically when data_schema changes; also safe to call manually.
func _migrate_all_regions() -> void:
	for region: Region in regions:
		if not data_schema:
			region.data = null
			continue
		if region.data != null and region.data.get_script() == data_schema:
			continue
		var schema_instance: RegionDataSchema = data_schema.new() as RegionDataSchema
		if schema_instance:
			region.data = schema_instance.migrate_data(region.data)
		else:
			push_warning("MapLayer: data_schema '%s' does not extend RegionDataSchema" \
					% data_schema.resource_path)


# Creates a default data Resource for a new region on this layer.
# Returns null if no data_schema is assigned.
func make_region_data() -> Resource:
	if not data_schema:
		return null
	var schema_instance: RegionDataSchema = data_schema.new() as RegionDataSchema
	return schema_instance.make_default_data() if schema_instance else null
