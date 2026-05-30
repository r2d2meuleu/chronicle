extends RefCounted

static var _results: Array[Dictionary] = []
static var _run_file: String = ""


static func record(tier: String, suite: String, bench_name: String, scale: int, scale_label: String, unit: String, stats: Dictionary, samples: Array) -> void:
	_results.append({
		tier = tier,
		suite = suite,
		name = bench_name,
		scale = scale,
		scale_label = scale_label,
		unit = unit,
		stats = stats,
		samples = samples,
	})


static func flush() -> void:
	if _results.is_empty():
		return

	if _run_file.is_empty():
		var timestamp: String = Time.get_datetime_string_from_system(true).replace(":", "-") + "Z"
		var commit: String = _get_commit()
		_run_file = "res://bench_results/%s_%s.json" % [timestamp, commit]

	var dir_path: String = "res://bench_results"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var existing: Dictionary = {}
	if FileAccess.file_exists(_run_file):
		var f: FileAccess = FileAccess.open(_run_file, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				existing = parsed

	if existing.is_empty():
		existing = _build_meta()

	if not existing.has("results"):
		existing["results"] = []

	for entry: Dictionary in _results:
		existing["results"].append(entry)

	var json_text: String = JSON.stringify(existing, "\t")
	var f: FileAccess = FileAccess.open(_run_file, FileAccess.WRITE)
	if f == null:
		push_warning("[BenchResults] Cannot write to %s: %s" % [_run_file, error_string(FileAccess.get_open_error())])
		return
	f.store_string(json_text)
	f.close()
	_results.clear()


static func reset() -> void:
	_results.clear()
	_run_file = ""


static func _build_meta() -> Dictionary:
	var vi: Dictionary = Engine.get_version_info()
	return {
		meta = {
			timestamp = Time.get_datetime_string_from_system(true) + "Z",
			commit = _get_commit(),
			godot_version = "%d.%d" % [vi.major, vi.minor],
			os = OS.get_name().to_lower(),
			warmup = 20,
			iterations = 200,
		},
		results = [],
	}


static func _get_commit() -> String:
	var output: Array = []
	var code: int = OS.execute("git", PackedStringArray(["rev-parse", "--short", "HEAD"]), output)
	if code != 0:
		return "unknown"
	var sha: String = str(output[0]).strip_edges()
	var dirty_out: Array = []
	OS.execute("git", PackedStringArray(["status", "--porcelain"]), dirty_out)
	if dirty_out.size() > 0 and str(dirty_out[0]).strip_edges() != "":
		sha += "-dirty"
	return sha
