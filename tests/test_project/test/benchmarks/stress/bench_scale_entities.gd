extends BenchSuite

const SCALES: Array[int] = [10, 100, 500, 1000, 5000]
const LABELS: Array[String] = ["10", "100", "500", "1K", "5K"]


# 1. find glob — entity count effect on lookup
func test_bench_find_glob_entity_count() -> void:
	BenchHelper.run_scale_bench("stress", "bench_scale_entities", "find_glob_entity_count", "us/op",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			populate_entities(scale, 10, "ent"),
		func() -> void:
			var _r: Array = _chronicle.get_fact_keys("ent_0.*"),
		BenchHelper.TableKind.STRESS, 0, "",
		func(_scale: int) -> void:
			guard(_chronicle.get_fact_keys("ent_0.*").size() == 10, "find_glob_entity_count: ent_0 bucket has 10 props"))


# 2. find glob — props per entity (bucket scan)
func test_bench_find_glob_props_per_entity() -> void:
	var prop_counts: Array[int] = [10, 100, 500, 1000]
	var labels: Array[String] = ["10", "100", "500", "1000"]
	BenchHelper.run_scale_bench("stress", "bench_scale_entities", "find_glob_props_per_entity", "us/op",
		prop_counts, labels,
		func(scale: int) -> void:
			_chronicle.clear()
			populate_entities(1, scale, "ent"),
		func() -> void:
			var _r: Array = _chronicle.get_fact_keys("ent_0.*"),
		BenchHelper.TableKind.STRESS, 0, "",
		func(scale: int) -> void:
			guard(_chronicle.get_fact_keys("ent_0.*").size() == scale, "find_glob_props_per_entity: ent_0 has %d props" % scale))


# 3. Insert new entity — cost at entity count
func test_bench_insert_new_entity() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		_chronicle.clear()
		populate_entities(SCALES[si], 10, "ent")
		guard(_chronicle.count_facts("*") == SCALES[si] * 10, "insert_new_entity: store populated to %d facts" % (SCALES[si] * 10))
		var counter: Array = [0]
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			counter[0] += 1
			_chronicle.set_fact("new_ent_%d.prop_0" % counter[0], 1)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("stress", "bench_scale_entities", "insert_new_entity", SCALES[si], LABELS[si], "us/op", stats, samples)
	BenchHelper.print_stress_table("stress/scale_entities :: insert_new_entity", rows, "entities")


# 4. find("*") vs entity-scoped — gap measurement
func test_bench_find_wildcard_vs_entities() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		_chronicle.clear()
		populate_entities(SCALES[si], 10, "ent")
		guard(_chronicle.count_facts("ent_0.*") == 10 and _chronicle.count_facts("*") == SCALES[si] * 10, "find_wildcard_vs_entities: glob=10 wild=%d" % (SCALES[si] * 10))
		var samples_glob: Array[float] = BenchHelper.measure(func() -> void:
			var _r: Array = _chronicle.get_fact_keys("ent_0.*")
		)
		var samples_wild: Array[float] = BenchHelper.measure(func() -> void:
			var _r: Array = _chronicle.get_fact_keys("*")
		)
		var stats_glob: Dictionary = BenchHelper.compute_stats(samples_glob)
		var stats_wild: Dictionary = BenchHelper.compute_stats(samples_wild)
		rows.append({scale_label = LABELS[si] + " glob", stats = stats_glob})
		rows.append({scale_label = LABELS[si] + " wild", stats = stats_wild})
		BenchResults.record("stress", "bench_scale_entities", "find_wildcard_vs_entities", SCALES[si], LABELS[si] + " glob", "us/op", stats_glob, samples_glob)
		BenchResults.record("stress", "bench_scale_entities", "find_wildcard_vs_entities", SCALES[si], LABELS[si] + " wild", "us/op", stats_wild, samples_wild)
	BenchHelper.print_stress_table("stress/scale_entities :: find_wildcard_vs_entities", rows, "query")


# 5. Expression evaluate with keys from N entities
func test_bench_expression_keys_scattered() -> void:
	var rows: Array = []
	var key_counts: Array[int] = [1, 5, 10, 20]
	var labels: Array[String] = ["1", "5", "10", "20"]
	for ki: int in range(key_counts.size()):
		_chronicle.clear()
		var n: int = key_counts[ki]
		var expr_parts: Array[String] = []
		for i: int in range(n):
			_chronicle.set_fact("ent_%d.flag" % i, true)
			expr_parts.append("ent_%d.flag" % i)
		var expr_str: String = " AND ".join(expr_parts)
		var ast: Variant = _engine.parse(expr_str)
		var resolver: Callable = func(key: String) -> Variant:
			return _chronicle.get_fact(key, null)
		guard(_engine.evaluate_ast(ast, resolver) == true, "expression_keys_scattered: %d-key all-true AND expr evaluates true" % n)
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _r: bool = _engine.evaluate_ast(ast, resolver)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = labels[ki], stats = stats})
		BenchResults.record("stress", "bench_scale_entities", "expression_keys_scattered", n, labels[ki], "us/op", stats, samples)
	BenchHelper.print_stress_table("stress/scale_entities :: expression_keys_scattered", rows, "keys")
