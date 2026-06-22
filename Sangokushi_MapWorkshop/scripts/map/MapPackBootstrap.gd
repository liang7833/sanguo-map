extends Node
## 地图包启动入口 — 初始化 MapRenderer 并加载所有郡县数据
## 当作为独立场景运行时，自动加载地图

@onready var map_renderer: MapRenderer = $WorldMap

func _ready() -> void:
	if map_renderer:
		map_renderer.load_all_provinces()
		print("[MapPack] 三国地图包已就绪，共 ", map_renderer.get_all_province_ids().size(), " 个郡县")
	else:
		printerr("[MapPack] 未找到 MapRenderer 节点！")