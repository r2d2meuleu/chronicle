extends BenchSuite


const BATCH: int = 100



# 1. get_fact with primitive value — O(1) lookup, no deep copy overhead
func test_bench_get_primitive() -> void:
	for i: int in range(BATCH):
		_chronicle.set_fact("key_%d" % i, i)
	var keys: Array[String] = []
	for i: int in range(BATCH):
		keys.append("key_%d" % i)
	guard(_chronicle.get_fact("key_0") == 0, "get_primitive: key_0 holds its value")
	var samples: Array[float] = BenchHelper.measure_batched(func() -> void:
		for key: String in keys:
			var _v: Variant = _chronicle.get_fact(key)
	, BATCH)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_fact_read", "get_primitive", BATCH, "int", "us/op", stats, samples)
	BenchHelper.print_table("micro/fact_read :: get_primitive", [{scale_label = "int", stats = stats}])


# 2. get_fact returning shallow array — Array.duplicate() cost
func test_bench_get_array_shallow() -> void:
	var arr: Array = []
	for i: int in range(10):
		arr.append(i)
	_chronicle.set_fact("arr_key", arr)
	guard(_chronicle.get_fact("arr_key").size() == 10, "get_array_shallow: array of 10 readable")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _v: Variant = _chronicle.get_fact("arr_key")
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_fact_read", "get_array_shallow", 10, "10 ints", "us/op", stats, samples)
	BenchHelper.print_table("micro/fact_read :: get_array_shallow", [{scale_label = "10 ints", stats = stats}])


# 3. get_fact returning deep array — recursive deep copy
func test_bench_get_array_deep() -> void:
	var arr: Array = []
	for i: int in range(10):
		arr.append({"idx": i, "data": {"nested": true}})
	_chronicle.set_fact("deep_arr", arr)
	guard(_chronicle.get_fact("deep_arr")[0]["data"]["nested"] == true, "get_array_deep: nested value readable")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _v: Variant = _chronicle.get_fact("deep_arr")
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_fact_read", "get_array_deep", 10, "10 dicts", "us/op", stats, samples)
	BenchHelper.print_table("micro/fact_read :: get_array_deep", [{scale_label = "10 dicts", stats = stats}])


# 4. get_fact with nested dictionary — deep copy scales with depth
func test_bench_get_dictionary_nested() -> void:
	var rows: Array = []
	var depths: Array[int] = [1, 3, 5]
	var labels: Array[String] = ["depth 1", "depth 3", "depth 5"]
	for di: int in range(depths.size()):
		var val: Dictionary = {"leaf": 42}
		for _d: int in range(depths[di] - 1):
			val = {"child": val}
		var key: String = "nested_%d" % depths[di]
		_chronicle.set_fact(key, val)
		if di == 0:
			guard(_chronicle.get_fact(key) != null, "get_dictionary_nested: nested dict readable")
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _v: Variant = _chronicle.get_fact(key)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = labels[di], stats = stats})
		BenchResults.record("micro", "bench_fact_read", "get_dictionary_nested", depths[di], labels[di], "us/op", stats, samples)
	BenchHelper.print_table("micro/fact_read :: get_dictionary_nested", rows)


# 5. get_fact with Godot value types — Vector2, Color, Transform2D
func test_bench_get_godot_types() -> void:
	var rows: Array = []
	var types: Dictionary = {
		"Vector2": Vector2(1, 2),
		"Color": Color.RED,
		"Transform2D": Transform2D.IDENTITY,
	}
	var guarded: bool = false
	for type_name: String in types:
		var key: String = "type_%s" % type_name.to_lower()
		_chronicle.set_fact(key, types[type_name])
		if not guarded:
			guard(_chronicle.get_fact(key) == types[type_name], "get_godot_types: value type stored")
			guarded = true
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _v: Variant = _chronicle.get_fact(key)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = type_name, stats = stats})
		BenchResults.record("micro", "bench_fact_read", "get_godot_types", 1, type_name, "us/op", stats, samples)
	BenchHelper.print_table("micro/fact_read :: get_godot_types", rows)


# 6. has_fact — pure lookup, no copy
func test_bench_has_fact() -> void:
	for i: int in range(BATCH):
		_chronicle.set_fact("exists_%d" % i, i)
	var rows: Array = []
	var existing_keys: Array[String] = []
	for i: int in range(BATCH):
		existing_keys.append("exists_%d" % i)
	guard(_chronicle.has_fact("exists_0") and not _chronicle.has_fact("missing_0"), "has_fact: hit/miss keys correct")
	var samples_hit: Array[float] = BenchHelper.measure_batched(func() -> void:
		for key: String in existing_keys:
			var _v: bool = _chronicle.has_fact(key)
	, BATCH)
	var stats_hit: Dictionary = BenchHelper.compute_stats(samples_hit)
	rows.append({scale_label = "hit", stats = stats_hit})
	BenchResults.record("micro", "bench_fact_read", "has_fact_hit", BATCH, "hit", "us/op", stats_hit, samples_hit)

	var missing_keys: Array[String] = []
	for i: int in range(BATCH):
		missing_keys.append("missing_%d" % i)
	var samples_miss: Array[float] = BenchHelper.measure_batched(func() -> void:
		for key: String in missing_keys:
			var _v: bool = _chronicle.has_fact(key)
	, BATCH)
	var stats_miss: Dictionary = BenchHelper.compute_stats(samples_miss)
	rows.append({scale_label = "miss", stats = stats_miss})
	BenchResults.record("micro", "bench_fact_read", "has_fact_miss", BATCH, "miss", "us/op", stats_miss, samples_miss)
	BenchHelper.print_table("micro/fact_read :: has_fact", rows)


# 7. is_marked — lookup + truthy check on various types
func test_bench_is_marked() -> void:
	_chronicle.set_fact("bool_true", true)
	_chronicle.set_fact("int_one", 1)
	_chronicle.set_fact("str_hello", "hello")
	_chronicle.set_fact("int_zero", 0)
	guard(_chronicle.is_marked("bool_true") and not _chronicle.is_marked("int_zero"), "is_marked: truthy/falsy distinguished")
	var rows: Array = []
	var keys_and_labels: Array = [
		["bool_true", "bool"],
		["int_one", "int 1"],
		["str_hello", "string"],
		["int_zero", "int 0"],
	]
	for pair: Array in keys_and_labels:
		var key: String = pair[0]
		var label: String = pair[1]
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _v: bool = _chronicle.is_marked(key)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = label, stats = stats})
		BenchResults.record("micro", "bench_fact_read", "is_marked", 1, label, "us/op", stats, samples)
	BenchHelper.print_table("micro/fact_read :: is_marked", rows)
