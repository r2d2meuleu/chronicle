@tool
extends EditorPlugin

const AUTOLOAD_NAME := ChronicleNodeUtils.AUTOLOAD_NAME
const AUTOLOAD_SCRIPT_PATH := "res://addons/chronicle/core/chronicle.gd"

var _inspector_plugin: EditorInspectorPlugin
var _export_plugin: EditorExportPlugin
var _rebuild_timer: Timer
var _editor_fs: EditorFileSystem


func _enable_plugin() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_SCRIPT_PATH)
	_register_settings()


func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
	_remove_settings()


func _remove_settings() -> void:
	# Note: Godot's ProjectSettings API does not provide a way to remove
	# property metadata (hint, hint_string, description) separately from
	# the value. Setting to null + save() removes the value but metadata
	# may linger in project.godot until next editor restart.
	for path: String in [
		"chronicle/storage/timeline_cap",
		"chronicle/storage/serialize_timeline_cap",
		"chronicle/debug/overlay_hotkey",
		"chronicle/debug/enabled_in_release",
		"chronicle/storage/store_hard_cap",
	]:
		if ProjectSettings.has_setting(path):
			ProjectSettings.set_setting(path, null)
	ProjectSettings.save()


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_inspector_plugin = preload("res://addons/chronicle/editor/inspector_plugin.gd").new()
		add_inspector_plugin(_inspector_plugin)

		_rebuild_timer = Timer.new()
		_rebuild_timer.one_shot = true
		_rebuild_timer.wait_time = 0.3
		_rebuild_timer.timeout.connect(_on_rebuild_timeout)
		add_child(_rebuild_timer)

		resource_saved.connect(_on_resource_saved)
		_editor_fs = EditorInterface.get_resource_filesystem()
		_editor_fs.filesystem_changed.connect(_on_filesystem_changed)

	_export_plugin = ChronicleExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _inspector_plugin:
		resource_saved.disconnect(_on_resource_saved)
		if _editor_fs and _editor_fs.filesystem_changed.is_connected(_on_filesystem_changed):
			_editor_fs.filesystem_changed.disconnect(_on_filesystem_changed)
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
	if _rebuild_timer != null:
		_rebuild_timer.queue_free()
		_rebuild_timer = null
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


func _on_resource_saved(_resource: Resource) -> void:
	if _rebuild_timer:
		_rebuild_timer.start()


func _on_filesystem_changed() -> void:
	if _rebuild_timer:
		_rebuild_timer.start()


func _on_rebuild_timeout() -> void:
	if _inspector_plugin:
		_inspector_plugin.rebuild_registry()


class ChronicleExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "Chronicle"

	func _export_file(path: String, _type: String, features: PackedStringArray) -> void:
		if path.begins_with("res://addons/chronicle/editor/"):
			skip()
			return
		if path.begins_with("res://addons/chronicle/debug/"):
			if ("template_release" in features or "release" in features) and not ProjectSettings.get_setting("chronicle/debug/enabled_in_release", false):
				skip()


func _register_settings() -> void:
	_add_setting("chronicle/storage/timeline_cap", TYPE_INT, 10000, PROPERTY_HINT_RANGE, "100,1000000")
	_add_setting("chronicle/storage/serialize_timeline_cap", TYPE_INT, 1000, PROPERTY_HINT_RANGE, "100,100000")
	_add_setting("chronicle/debug/overlay_hotkey", TYPE_STRING, "F9")
	_add_setting("chronicle/debug/enabled_in_release", TYPE_BOOL, false)
	_add_setting("chronicle/storage/store_hard_cap", TYPE_INT, 0, PROPERTY_HINT_RANGE, "0,1000000")


func _add_setting(path: String, type: int, default_value: Variant, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	if not ProjectSettings.has_setting(path):
		ProjectSettings.set_setting(path, default_value)
	ProjectSettings.set_initial_value(path, default_value)
	var info: Dictionary = {"name": path, "type": type}
	if hint != PROPERTY_HINT_NONE:
		info["hint"] = hint
		info["hint_string"] = hint_string
	ProjectSettings.add_property_info(info)
