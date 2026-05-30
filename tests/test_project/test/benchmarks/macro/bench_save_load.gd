extends BenchSuite

const FACT_COUNT: int = 10000
const SAVE_PATH: String = "res://bench_results/_bench_save_test.json"


func after_all() -> void:
	super.after_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".bak"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".tmp"))


func _populate_primitives() -> void:
	for i: int in range(FACT_COUNT):
		var entity: int = i / 10
		var prop: int = i % 10
		match prop % 3:
			0: _chronicle.set_fact("e_%d.p_%d" % [entity, prop], i)
			1: _chronicle.set_fact("e_%d.p_%d" % [entity, prop], i % 2 == 0)
			_: _chronicle.set_fact("e_%d.p_%d" % [entity, prop], "val_%d" % i)


func _populate_mixed() -> void:
	for i: int in range(FACT_COUNT):
		var entity: int = i / 10
		var prop: int = i % 10
		if prop < 6:
			_chronicle.set_fact("e_%d.p_%d" % [entity, prop], i)
		elif prop < 9:
			_chronicle.set_fact("e_%d.p_%d" % [entity, prop], Vector2(float(i), float(i + 1)))
		else:
			_chronicle.set_fact("e_%d.p_%d" % [entity, prop], {"nested": {"value": i}})


# 1. Serialize primitives only
func test_bench_serialize_primitives() -> void:
	_populate_primitives()
	guard(_chronicle.count_facts("*") == FACT_COUNT, "serialize_primitives: %d facts to serialize" % FACT_COUNT)
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _d: Dictionary = _chronicle.serialize()
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_save_load", "serialize_primitives", FACT_COUNT, "10K", "us", stats, samples)
	BenchHelper.print_table("macro/save_load :: serialize_primitives", [{scale_label = "10K", stats = stats}])


# 2. Serialize mixed types — TypeSerializer overhead
func test_bench_serialize_mixed_types() -> void:
	_populate_mixed()
	guard(_chronicle.count_facts("*") == FACT_COUNT, "serialize_mixed_types: %d facts to serialize" % FACT_COUNT)
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _d: Dictionary = _chronicle.serialize()
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_save_load", "serialize_mixed_types", FACT_COUNT, "10K mix", "us", stats, samples)
	BenchHelper.print_table("macro/save_load :: serialize_mixed_types", [{scale_label = "10K mix", stats = stats}], "60% prim + 30% Vector2 + 10% nested Dict")


# 3. Serialize with large timeline
func test_bench_serialize_large_timeline() -> void:
	for i: int in range(FACT_COUNT):
		_chronicle.set_game_time(float(i) * 0.01)
		_chronicle.set_fact("tl_%d" % (i % 100), i)
	guard(_chronicle.has_fact("tl_0") and _chronicle.has_fact("tl_99"), "serialize_large_timeline: timeline facts populated")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _d: Dictionary = _chronicle.serialize()
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_save_load", "serialize_large_timeline", FACT_COUNT, "10K tl", "us", stats, samples)
	BenchHelper.print_table("macro/save_load :: serialize_large_timeline", [{scale_label = "10K tl", stats = stats}], "10K timeline entries")


# 4. Deserialize cold — into empty chronicle
func test_bench_deserialize_cold() -> void:
	_populate_primitives()
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	_chronicle.deserialize(data)
	guard(_chronicle.count_facts("*") == FACT_COUNT, "deserialize_cold: %d facts restored" % FACT_COUNT)
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		_chronicle.clear()
		_chronicle.deserialize(data)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_save_load", "deserialize_cold", FACT_COUNT, "10K", "us", stats, samples)
	BenchHelper.print_table("macro/save_load :: deserialize_cold", [{scale_label = "10K", stats = stats}])


# 5. Deserialize replace — into pre-populated chronicle (load-game pattern)
func test_bench_deserialize_replace() -> void:
	_populate_primitives()
	var data: Dictionary = _chronicle.serialize()
	_populate_mixed()
	_chronicle.deserialize(data)
	guard(_chronicle.count_facts("*") == FACT_COUNT, "deserialize_replace: %d facts after replace" % FACT_COUNT)
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		_chronicle.deserialize(data)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_save_load", "deserialize_replace", FACT_COUNT, "10K", "us", stats, samples)
	BenchHelper.print_table("macro/save_load :: deserialize_replace", [{scale_label = "10K", stats = stats}], "deserialize overwrites existing 10K facts")


# 6. File write + read cycle
func test_bench_file_write_read() -> void:
	_populate_primitives()
	var data: Dictionary = _chronicle.serialize()
	if not DirAccess.dir_exists_absolute("res://bench_results"):
		DirAccess.make_dir_recursive_absolute("res://bench_results")
	ChronicleFileIO.save_to_file(SAVE_PATH, data)
	guard(read_file(SAVE_PATH) != null, "file_write_read: save+load roundtrip returns data")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		ChronicleFileIO.save_to_file(SAVE_PATH, data)
		var _loaded: Variant = read_file(SAVE_PATH)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_save_load", "file_write_read", FACT_COUNT, "10K", "us", stats, samples)
	BenchHelper.print_table("macro/save_load :: file_write_read", [{scale_label = "10K", stats = stats}], "save_to_file + load_from_file full cycle")


# 7. Atomic write overhead — .tmp -> rename vs raw write
func test_bench_atomic_write_overhead() -> void:
	_populate_primitives()
	var data: Dictionary = _chronicle.serialize()
	var json_text: String = JSON.stringify(data)
	if not DirAccess.dir_exists_absolute("res://bench_results"):
		DirAccess.make_dir_recursive_absolute("res://bench_results")
	var rows: Array = []

	ChronicleFileIO.save_to_file(SAVE_PATH, data)
	guard(read_file(SAVE_PATH) != null, "atomic_write_overhead: atomic save produced a readable file")
	var samples_atomic: Array[float] = BenchHelper.measure(func() -> void:
		ChronicleFileIO.save_to_file(SAVE_PATH, data)
	)
	var stats_atomic: Dictionary = BenchHelper.compute_stats(samples_atomic)
	rows.append({scale_label = "atomic", stats = stats_atomic})
	BenchResults.record("macro", "bench_save_load", "atomic_write_overhead_atomic", FACT_COUNT, "atomic", "us", stats_atomic, samples_atomic)

	var raw_path: String = SAVE_PATH + ".raw"
	var samples_raw: Array[float] = BenchHelper.measure(func() -> void:
		var f: FileAccess = FileAccess.open(raw_path, FileAccess.WRITE)
		f.store_string(json_text)
		f.close()
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(raw_path))
	var stats_raw: Dictionary = BenchHelper.compute_stats(samples_raw)
	rows.append({scale_label = "raw", stats = stats_raw})
	BenchResults.record("macro", "bench_save_load", "atomic_write_overhead_raw", FACT_COUNT, "raw", "us", stats_raw, samples_raw)
	BenchHelper.print_table("macro/save_load :: atomic_write_overhead", rows, "atomic (.tmp+rename+.bak) vs raw FileAccess.WRITE")
