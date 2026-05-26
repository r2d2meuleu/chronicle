extends RefCounted

signal rebuilt

const _EXCLUDED_DIRS: PackedStringArray = ["addons", "test", "tests", "test_project"]

const _SCAN_NEEDLES: PackedStringArray = [
	"set_fact(\"", "toggle_fact(\"", "erase_fact(\"",
	"increment_fact(\"", "clamp_fact(\""
]

var _known_keys: Dictionary[String, bool] = {}


func rebuild(scan_root: String = "res://") -> void:
	_known_keys.clear()
	_scan_cfg()
	_scan_scene_resources(scan_root)
	_scan_gd(scan_root)
	rebuilt.emit()


func is_known(key: String) -> bool:
	return key in _known_keys


func is_empty() -> bool:
	return _known_keys.is_empty()


func _scan_cfg() -> void:
	var path: String = "res://chronicle_facts.cfg"
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not f:
		return
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.begins_with("#"):
			continue
		var comment_idx: int = line.find("#")
		if comment_idx >= 0:
			line = line.left(comment_idx).strip_edges()
		if not line.is_empty():
			_known_keys[line] = true


func _scan_scene_resources(scan_root: String = "res://") -> void:
	_scan_dir(scan_root, ".tscn", PackedStringArray(['fact_key = "']))
	_scan_dir(scan_root, ".tres", PackedStringArray(['fact_key = "']))


func _scan_gd(scan_root: String = "res://") -> void:
	# Note: set_facts() takes a Dictionary argument, not string literal keys,
	# so its keys cannot be statically extracted by needle scanning.
	_scan_dir(scan_root, ".gd", _SCAN_NEEDLES)


func _scan_dir(root: String, ext: String, needles: PackedStringArray, depth: int = 0) -> void:
	if depth > 32:
		return
	var dir: DirAccess = DirAccess.open(root)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		var full: String = root.path_join(file_name)
		if dir.current_is_dir() and not file_name.begins_with("."):
			if file_name not in _EXCLUDED_DIRS:
				_scan_dir(full, ext, needles, depth + 1)
		elif file_name.ends_with(ext):
			_extract_keys(full, needles)
		file_name = dir.get_next()
	dir.list_dir_end()


func _extract_keys(path: String, needles: PackedStringArray) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not f:
		return
	var text: String = f.get_as_text()
	for needle: String in needles:
		var idx: int = text.find(needle)
		while idx != -1:
			_extract_key_at(text, idx + needle.length())
			idx = text.find(needle, idx + 1)


func _extract_key_at(text: String, start: int) -> void:
	var end: int = text.find('"', start)
	if end < 0:
		return
	if end > start:
		var key: String = text.substr(start, end - start)
		if "\n" in key or "\"" in key:
			return
		_known_keys[key] = true
