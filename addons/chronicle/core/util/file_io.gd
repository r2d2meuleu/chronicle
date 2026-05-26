class_name ChronicleFileIO
extends RefCounted


## Atomic JSON write via tmp/bak rotation. Rejects paths outside user:// and res://.
static func save_to_file(path: String, data: Dictionary) -> Error:
	var normalized: String = path.simplify_path()
	if not normalized.begins_with("user://") and not normalized.begins_with("res://"):
		push_error("[Chronicle] File path rejected — must begin with \"user://\" or \"res://\". Got: \"%s\" (resolved to: \"%s\")" % [path, normalized])
		return ERR_FILE_BAD_PATH
	path = normalized
	var json_text: String = JSON.stringify(data, "\t")
	var tmp_path: String = path + ".tmp"
	var bak_path: String = path + ".bak"

	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		var err: Error = FileAccess.get_open_error()
		if err == OK:
			err = FAILED
		push_error("[Chronicle] save_to_file() could not open \"%s\" for writing. Error: %s" % [tmp_path, error_string(err)])
		return err
	file.store_string(json_text)
	file.flush()
	file.close()

	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		var rename_err: Error = DirAccess.rename_absolute(path, bak_path)
		if rename_err != OK:
			push_error("[Chronicle] save_to_file() could not rename \"%s\" to \"%s\": %s" % [path, bak_path, error_string(rename_err)])
			DirAccess.remove_absolute(tmp_path)
			return rename_err

	var final_rename_err: Error = DirAccess.rename_absolute(tmp_path, path)
	if final_rename_err != OK:
		push_error("[Chronicle] save_to_file() could not rename \"%s\" to \"%s\": %s — .tmp preserved for recovery." % [tmp_path, path, error_string(final_rename_err)])
		if FileAccess.file_exists(bak_path):
			var rollback_err: Error = DirAccess.rename_absolute(bak_path, path)
			if rollback_err != OK:
				push_error("[Chronicle] CRITICAL: backup restore failed for \"%s\": %s — data may be lost" % [path, error_string(rollback_err)])
		return final_rename_err

	return OK


## Fallback chain: primary -> .bak -> .tmp. Returns null if all are missing/corrupt.
static func load_from_file(path: String) -> Variant:
	var normalized: String = path.simplify_path()
	if not normalized.begins_with("user://") and not normalized.begins_with("res://"):
		push_error("[Chronicle] File path rejected — must begin with \"user://\" or \"res://\". Got: \"%s\" (resolved to: \"%s\")" % [path, normalized])
		return null
	path = normalized
	var bak_path: String = path + ".bak"

	if FileAccess.file_exists(path):
		var result: Variant = _parse_json_file(path)
		if result != null:
			return result
		push_warning("[Chronicle] load_from_file() primary file \"%s\" is corrupt, falling back to .bak." % path)

	if FileAccess.file_exists(bak_path):
		var result: Variant = _parse_json_file(bak_path)
		if result != null:
			if FileAccess.file_exists(path):
				DirAccess.rename_absolute(path, path + ".corrupt")
			return result
		push_warning("[Chronicle] load_from_file() backup file \"%s\" is also corrupt." % bak_path)

	var tmp_path: String = path + ".tmp"
	if FileAccess.file_exists(tmp_path):
		var tmp_result: Variant = _parse_json_file(tmp_path)
		if tmp_result != null:
			push_warning("[Chronicle] Recovered from .tmp file for \"%s\"." % path)
			DirAccess.rename_absolute(tmp_path, path)
			if FileAccess.file_exists(bak_path):
				DirAccess.rename_absolute(bak_path, bak_path + ".old")
			return tmp_result

	return null



static func _parse_json_file(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		var err: Error = FileAccess.get_open_error()
		if err == OK:
			err = FAILED
		push_warning("[Chronicle] Could not open \"%s\" for reading. Error: %s" % [path, error_string(err)])
		return null
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_warning("[Chronicle] \"%s\" contains invalid JSON." % path)
		return null
	if not (parsed is Dictionary):
		push_warning("[Chronicle] \"%s\" parsed but is not a Dictionary." % path)
		return null
	return parsed
