@tool
extends EditorPlugin

### CONSTANTS ###
# UI Sizing
const PREVIEW_SIZE := Vector2(250, 250)
const MAX_PREVIEW_SIZE := Vector2(800, 800)
const MIN_WINDOW_SIZE := Vector2(100, 100)
const SCALE_THRESHOLD := 600 # Pixels
const MARGIN_MIN := 10
const MARGIN_SCALE_FACTOR := 0.05

# File Types
const IMAGE_EXTS := ["png", "jpg", "jpeg", "tga", "bmp", "webp"]
const SCENE_EXTS := ["tscn", "scn"]
const SCRIPT_EXTS := ["gd"]
const FONT_EXTS := ["otf", "ttf"]
const AUDIO_EXTS := ["wav", "ogg", "mp3"]
const RESOURCE_EXTS := ["tres"]

# Animation
const SPINNER_ROTATION_SPEED := 5.0

### UI ELEMENTS ###
var preview_popup: Popup
var preview_texture: TextureRect
var file_info_label: Label
var spinner: TextureRect

### FILE SYSTEM ###
var file_system_dock: Control
var file_tree: Tree

### STATE ###
var current_preview_path: String = ""
var is_mouse_over_file: bool = false
var spinner_rotation: float = 0.0

var is_press_ctrl = false

func _enter_tree() -> void:
    # 创建预览窗口
    create_preview_popup()
    
    # 获取文件系统Dock
    find_file_system_dock()
    
    # 连接信号
    connect_signals()
    
    print("文件预览加载")

func _exit_tree() -> void:
    if preview_popup:
        preview_popup.queue_free()
    print("文件预览卸载")

var vbox: VBoxContainer

func setup_preview_window() -> void:
    # 清除现有子节点
    for child in preview_popup.get_children():
        child.queue_free()
    
    # 创建主容器
    var margin_container = MarginContainer.new()
    margin_container.add_theme_constant_override("margin_left", 10)
    margin_container.add_theme_constant_override("margin_right", 10)
    margin_container.add_theme_constant_override("margin_top", 10)
    margin_container.add_theme_constant_override("margin_bottom", 10)
    preview_popup.add_child(margin_container)
    
    vbox = VBoxContainer.new()
    vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
    margin_container.add_child(vbox)
    
    # 创建预览纹理
    preview_texture = TextureRect.new()
    preview_texture.custom_minimum_size = PREVIEW_SIZE
    preview_texture.expand = true
    preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    vbox.add_child(preview_texture)
    
    # 创建加载指示器
    spinner = TextureRect.new()
    spinner.texture = get_editor_interface().get_base_control().get_theme_icon("Progress1", "EditorIcons")
    spinner.size = Vector2(32, 32)
    spinner.position = PREVIEW_SIZE / 2 - spinner.size / 2
    spinner.hide()
    preview_texture.add_child(spinner)
    
    # 创建文件信息标签
    file_info_label = Label.new()
    file_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    file_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    
    # 使用编辑器主题颜色
    var editor_interface = get_editor_interface()
    var base_control = editor_interface.get_base_control()
    file_info_label.add_theme_color_override("font_color", base_control.get_theme_color("font_color", "Editor"))
    
    vbox.add_child(file_info_label)

func create_preview_popup() -> void:
    # 创建弹出窗口
    preview_popup = Popup.new()
    preview_popup.set_size(Vector2(200, 200)) # 初始最小尺寸
    preview_popup.hide()
    preview_popup.gui_embed_subwindows = true
    preview_popup.unfocusable = true
    preview_popup.mouse_passthrough = true
    add_child(preview_popup)
    
    # 使用编辑器主题样式
    var editor_interface = get_editor_interface()
    var base_control = editor_interface.get_base_control()
    
    # 应用编辑器主题
    preview_popup.add_theme_stylebox_override("panel", base_control.get_theme_stylebox("panel", "EditorStyles"))
    preview_popup.add_theme_constant_override("border_width", 1)
    
    setup_preview_window()

func find_file_system_dock() -> void:
    # 查找文件系统Dock
    var docks = get_editor_interface().get_base_control().find_children("*", "FileSystemDock", true, false)
    if docks.size() == 0:
        printerr("Failed to find FileSystemDock")
        return
        
    file_system_dock = docks[0]
    
    # 方法1：递归查找第一个Tree节点
    file_tree = find_first_tree(file_system_dock)
    if file_tree:
        pass
        # print("Found Tree using recursive search")
    else:
        # 方法2：尝试获取当前聚焦的Tree控件（需要额外类型检查）
        var focused = get_viewport().gui_get_focus_owner()
        if focused and focused is Tree:
            file_tree = focused
            # print("Found focused Tree control")
        else:
            printerr("Could not find Tree node in FileSystemDock")

func find_first_tree(node: Node) -> Tree:
    if node is Tree:
        return node
    for child in node.get_children():
        var result = find_first_tree(child)
        if result:
            return result
    return null

func connect_signals() -> void:
    if not file_tree:
        printerr("Cannot connect signals - file_tree is null")
        return
        
    # print("Connecting to file tree signals")
    
    # 连接鼠标进入和离开信号
    if file_tree.has_signal("mouse_entered"):
        file_tree.mouse_entered.connect(_on_file_tree_mouse_entered)
        # print("Connected mouse_entered signal")
    else:
        printerr("mouse_entered signal not found")
        
    if file_tree.has_signal("mouse_exited"):
        file_tree.mouse_exited.connect(_on_file_tree_mouse_exited)
        # print("Connected mouse_exited signal")
    else:
        printerr("mouse_exited signal not found")

var last_hovered_item: TreeItem = null

func _on_file_tree_mouse_entered() -> void:
    is_mouse_over_file = true
    # print("Mouse entered file tree")

func _on_file_tree_mouse_exited() -> void:
    is_mouse_over_file = false
    last_hovered_item = null
    preview_popup.hide()

func _process(delta: float) -> void:
    # 处理加载指示器旋转
    if spinner and spinner.visible and spinner.material:
        spinner_rotation += delta * SPINNER_ROTATION_SPEED
        spinner.material.set("rotation", spinner_rotation)
    
    if Input.is_physical_key_pressed(KEY_CTRL):
        is_press_ctrl = true
    if not Input.is_physical_key_pressed(KEY_CTRL):
        is_press_ctrl = false

    # 持续检查鼠标位置
    if is_mouse_over_file and file_tree:
        var mouse_pos = file_tree.get_local_mouse_position()
        var item = file_tree.get_item_at_position(mouse_pos)
        
        if item != last_hovered_item:
            last_hovered_item = item
            if item:
                var meta = item.get_metadata(0)
                if meta == null:
                    # print("No metadata found for item")
                    return
                
                var path = meta if meta is String else meta.get("path", "")
                if path is String and path != "":
                    # print("Hovering over file: ", path)
                    show_preview_for_item(item, path)
                else:
                    # print("Empty or invalid path in metadata")
                    pass
            else:
                # print("No item under mouse")
                if preview_popup.visible:
                    preview_popup.hide()

func show_preview_for_item(item: TreeItem, path: String) -> void:
    # 完全重置预览状态
    # preview_popup.mouse_passthrough = true
    # preview_popup.unfocusable = true
    preview_texture.texture = null
    preview_texture.custom_minimum_size = Vector2.ZERO
    preview_popup.size = MIN_WINDOW_SIZE
    file_info_label.text = ""
    current_preview_path = ""
    
    # 如果未按住Ctrl键则直接返回
    # if not Input.is_key_pressed(KEY_CTRL):
    #     preview_popup.hide()
    #     return
    
    # print("Showing preview for file: ", path)
    if not item:
        # print("No item at position")
        is_mouse_over_file = false
        preview_popup.hide()
        return
    
    # 获取文件路径
    # print("Getting file path metadata")
    var meta = item.get_metadata(0)
    if meta == null:
        # print("No metadata found for item")
        is_mouse_over_file = false
        preview_popup.hide()
        return
        
    path = meta if meta is String else meta.get("path", "")
    if not (path is String) or path == "":
        # print("Empty path metadata")
        is_mouse_over_file = false
        preview_popup.hide()
        return
    # print("File path: ", path)
    
    var dir = DirAccess.open(path.get_base_dir())
    if dir and dir.dir_exists(path):
        # print("Path is a directory, ignoring: ", path)
        preview_popup.hide()
        return
    
    # 跳过没有预览内容的.tres文件
    if path.get_extension().to_lower() == "tres":
        # print("Skipping .tres file with no preview content: ", path)
        preview_popup.hide()
        return
    
    # 设置当前预览状态
    # print("Showing preview for file: ", path)
    is_mouse_over_file = true
    current_preview_path = path
    
    # 显示加载指示器
    spinner.show()
    spinner.position = PREVIEW_SIZE / 2 - spinner.size / 2 + Vector2(10, 10)
    
    # 设置文件信息
    file_info_label.text = "%s (%s)" % [path.get_file(), format_file_size(path)]
    
    # 获取预览图
    get_preview(path)
    
    # 立即计算并设置窗口位置
    var viewport = get_viewport()
    var viewport_size = viewport.size
    var popup_size = preview_popup.size
    var mouse_pos = file_tree.get_global_mouse_position()
    
    # 计算初始位置并确保在屏幕边界内
    var popup_pos = Vector2(
        clamp(mouse_pos.x + 20, 0, viewport_size.x - popup_size.x),
        clamp(mouse_pos.y + 20, 0, viewport_size.y - popup_size.y)
    )
    
    # 原子化更新窗口位置和显示
    preview_popup.begin_bulk_theme_override()
    preview_popup.position = popup_pos
    preview_popup.end_bulk_theme_override()
    preview_popup.popup()


func get_preview(path: String) -> void:
    var extension = path.get_extension().to_lower()
    
    # 对于图片文件直接加载原图
    if extension in IMAGE_EXTS:
        # print("Loading full resolution image: ", path)
        var image = Image.new()
        var e = ResourceLoader.load(path) as Texture2D
        image = e.get_image()
        # var err = image.load(path)
        if image and not image.is_empty():
            var texture = ImageTexture.create_from_image(image)
            _on_preview_loaded(path, texture)
        else:
            print("Failed to load image: ", path)
            # 回退到内置预览生成器
            _fallback_to_preview_generator(path)
    else:
        _fallback_to_preview_generator(path)

func _fallback_to_preview_generator(path: String) -> void:
    # print("Using preview generator for: ", path)
    var preview_generator = get_editor_interface().get_resource_previewer()
    preview_generator.queue_resource_preview(path, self, "_on_preview_generated", null)

func _on_preview_generated(path: String, preview: Texture, thumbnail: Texture, userdata) -> void:
    # print("Preview generated for: ", path)
    _on_preview_loaded(path, preview)

func _on_preview_loaded(path: String, texture: Texture) -> void:
    # 确保当前预览的仍然是同一个文件
    if path != current_preview_path or not is_mouse_over_file:
        # print("Preview no longer needed for: ", path)
        return
    
    spinner.hide()
    
    if not texture:
        # 对于没有预览的文件类型，清除并隐藏窗口
        preview_texture.texture = null
        preview_texture.custom_minimum_size = Vector2.ZERO
        preview_popup.size = MIN_WINDOW_SIZE
        preview_popup.hide()
        return
        
    # 重建预览窗口
    setup_preview_window()
    
    # 设置预览纹理
    preview_texture.texture = texture
    preview_texture.expand = true
    preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    
    # 设置文件信息
    file_info_label.text = "%s (%s)" % [path.get_file(), format_file_size(path)]
    
    # 动态调整窗口大小
    if texture is ImageTexture:
        var img_size = texture.get_size()
        var target_size = img_size
        
        # 计算缩放比例
        if img_size.x < SCALE_THRESHOLD and img_size.y < SCALE_THRESHOLD:
            target_size = img_size.max(MIN_WINDOW_SIZE)
        else:
            var scale_ratio = min(
                (MAX_PREVIEW_SIZE.x - 40) / img_size.x,
                (MAX_PREVIEW_SIZE.y - 60) / img_size.y
            )
            target_size = img_size * scale_ratio
        
        # 设置纹理尺寸
        preview_texture.custom_minimum_size = target_size
        
        # 让VBoxContainer自动计算窗口大小
        preview_popup.size = Vector2.ZERO

func get_file_type_icon(path: String) -> Texture:
    # 根据文件扩展名返回对应的图标
    var extension = path.get_extension().to_lower()
    var editor_interface = get_editor_interface()
    
    match extension:
        "png", "jpg", "jpeg", "tga", "bmp", "webp":
            return editor_interface.get_base_control().get_theme_icon("ImageTexture", "EditorIcons")
        "tscn", "scn":
            return editor_interface.get_base_control().get_theme_icon("PackedScene", "EditorIcons")
        "gd":
            return editor_interface.get_base_control().get_theme_icon("GDScript", "EditorIcons")
        "otf", "ttf":
            return editor_interface.get_base_control().get_theme_icon("Font", "EditorIcons")
        "wav", "ogg", "mp3":
            return editor_interface.get_base_control().get_theme_icon("AudioStreamSample", "EditorIcons")
        "tres":
            return editor_interface.get_base_control().get_theme_icon("Resource", "EditorIcons")
        _:
            return editor_interface.get_base_control().get_theme_icon("File", "EditorIcons")

func format_file_size(path: String) -> String:
    var file = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return "未知大小"
    
    var size = file.get_length()
    file = null
    
    if size < 1024:
        return str(size) + " B"
    elif size < 1024 * 1024:
        return "%.1f KB" % (size / 1024.0)
    else:
        return "%.1f MB" % (size / (1024.0 * 1024.0))

# 创建加载指示器的材质
func _ready() -> void:
    if spinner:
        var shader = Shader.new()
        shader.code = """
            shader_type canvas_item;
            uniform float rotation;
            void fragment() {
                vec2 uv = UV - vec2(0.5);
                float r = length(uv);
                float a = atan(uv.y, uv.x) + rotation;
                float f = smoothstep(0.4, 0.5, r) - smoothstep(0.5, 0.6, r);
                f *= smoothstep(-0.1, 0.1, cos(a * 4.0 + rotation * 2.0));
                COLOR = texture(TEXTURE, UV) * vec4(vec3(f), 1.0);
            }
        """
        var material = ShaderMaterial.new()
        material.shader = shader
        material.set("rotation", 0.0)
        spinner.material = material
