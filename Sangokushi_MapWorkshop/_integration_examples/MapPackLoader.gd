extends Node
## 主游戏—地图包挂载器（示例，放在主游戏项目中）
## 负责加载 .pck 文件、实例化地图场景、连接信号

## 已挂载的地图实例
var map_renderer: MapRenderer = null
## 地图场景根节点
var map_root: Node2D = null


## 挂载地图包
## @param pack_path: .pck 文件路径，如 "res://packs/sangokushi_map_v1.0.pck"
## @return: 是否挂载成功
func mount_map_pack(pack_path: String) -> bool:
	# 1. 加载资源包
	var ok = ProjectSettings.load_resource_pack(pack_path, false)
	if not ok:
		push_error("[MapPackLoader] 地图包加载失败: ", pack_path)
		return false

	# 2. 加载地图场景
	var MapScene: PackedScene = load("res://scenes/MapMain.tscn")
	if not MapScene:
		push_error("[MapPackLoader] 地图场景加载失败")
		return false

	# 3. 实例化
	map_root = MapScene.instantiate()
	map_renderer = map_root.get_node_or_null("WorldMap") as MapRenderer
	if not map_renderer:
		# 兼容：如果根节点本身就是 MapRenderer
		map_renderer = map_root as MapRenderer
	if not map_renderer:
		push_error("[MapPackLoader] 未找到 MapRenderer 节点")
		return false

	add_child(map_root)
	move_child(map_root, 0)  # 放在最底层

	# 4. 加载所有郡县数据
	map_renderer.load_all_provinces()

	print("[MapPackLoader] 地图包挂载成功: ", pack_path)
	return true


## 连接地图信号到主游戏逻辑
func connect_signals(target: Object) -> void:
	if not map_renderer:
		return
	map_renderer.province_clicked.connect(target._on_province_clicked)
	map_renderer.province_hovered.connect(target._on_province_hovered)
	map_renderer.province_unhovered.connect(target._on_province_unhovered)


## 卸载地图包
func unmount_map() -> void:
	if map_root:
		map_root.queue_free()
		map_root = null
		map_renderer = null
