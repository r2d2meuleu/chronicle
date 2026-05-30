extends BenchSuite


const SCALES: Array[int] = [1000, 10000, 50000, 100000]
const LABELS: Array[String] = ["1K", "10K", "50K", "100K"]
const WATCHER_COUNTS: Array[int] = [0, 10, 50, 100, 200]
const BULK_SIZES: Array[int] = [10, 50, 200]

var _keys: Dictionary = {}


func before_all() -> void:
	for n: int in SCALES:
		var arr: Array[String] = []
		var entities: int = n / 10
		for e: int in range(entities):
			for p: int in range(10):
				arr.append("entity_%d.prop_%d" % [e, p])
		_keys[n] = arr



func _get_keys(scale: int) -> Array[String]:
	return _keys[scale]


func _populate(scale: int) -> void:
	var keys: Array[String] = _get_keys(scale)
	for key: String in keys:
		_chronicle.set_fact(key, 1)


# 1. Insert into empty store — base write cost
# Each measured iteration clears + re-writes ALL N keys, so cost is ITER * WARMUP * N
# writes per scale. At 100K that is ~22M set_facts and cannot finish in a timeout window,
# so this bench caps the top scale at 50K and uses a reduced iteration/warmup budget.
const INSERT_EMPTY_SCALES: Array[int] = [1000, 10000, 50000]
const INSERT_EMPTY_LABELS: Array[String] = ["1K", "10K", "50K"]
const INSERT_EMPTY_ITER: int = 30
const INSERT_EMPTY_WARMUP: int = 3
func test_bench_insert_empty_store() -> void:
	var rows: Array = []
	for si: int in range(INSERT_EMPTY_SCALES.size()):
		var n: int = INSERT_EMPTY_SCALES[si]
		var keys: Array[String] = _get_keys(n)
		_chronicle.clear()
		for key: String in keys:
			_chronicle.set_fact(key, 1)
		guard(_chronicle.count_facts("*") == n, "insert_empty_store: all %d keys written" % n)
		var samples: Array[float] = BenchHelper.measure_batched(func() -> void:
			_chronicle.clear()
			for key: String in keys:
				_chronicle.set_fact(key, 1)
		, n, INSERT_EMPTY_ITER, INSERT_EMPTY_WARMUP)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = INSERT_EMPTY_LABELS[si], stats = stats})
		BenchResults.record("micro", "bench_fact_write", "insert_empty_store", n, INSERT_EMPTY_LABELS[si], "us/op", stats, samples)
		_chronicle.clear()
	BenchHelper.print_table("micro/fact_write :: insert_empty_store", rows, "per-op cost (total / N), capped at 50K")


# 2. Insert into populated store — entity index insertion cost at occupancy
func test_bench_insert_populated_store() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		var n: int = SCALES[si]
		_populate(n)
		var hot_key: String = "new_entity_999.new_prop"
		guard(_chronicle.count_facts("*") == n, "insert_populated_store: store populated to %d" % n)
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			_chronicle.set_fact(hot_key, 1)
			_chronicle.erase_fact(hot_key)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("micro", "bench_fact_write", "insert_populated_store", n, LABELS[si], "us/op", stats, samples)
		_chronicle.clear()
	BenchHelper.print_table("micro/fact_write :: insert_populated_store", rows, "insert+erase new key at store occupancy N")


# 3. Overwrite existing key with primitive — no index update needed
func test_bench_overwrite_primitive() -> void:
	var rows: Array = []
	const BATCH: int = 100
	for si: int in range(SCALES.size()):
		var n: int = SCALES[si]
		_populate(n)
		var hot_key: String = "entity_0.prop_0"
		_chronicle.set_fact(hot_key, 7)
		guard(_chronicle.get_fact(hot_key) == 7, "overwrite_primitive: hot key overwrite took effect")
		var samples: Array[float] = BenchHelper.measure_batched(func() -> void:
			for bi: int in range(BATCH):
				_chronicle.set_fact(hot_key, bi)
		, BATCH)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("micro", "bench_fact_write", "overwrite_primitive", n, LABELS[si], "us/op", stats, samples)
		_chronicle.clear()
	BenchHelper.print_table("micro/fact_write :: overwrite_primitive", rows)


# 4. Overwrite with complex value — deep copy cost on timeline append
func test_bench_overwrite_complex() -> void:
	var complex_val: Dictionary = {"a": {"b": {"c": {"d": {"e": 42}}}}}
	_chronicle.set_fact("complex_key", {})
	var rows: Array = []
	_chronicle.set_fact("complex_key", complex_val)
	guard(_chronicle.get_fact("complex_key") == complex_val, "overwrite_complex: nested dict stored")
	# Vary the leaf each iteration so the value genuinely changes — an identical Dict
	# write is short-circuited by the write coordinator and would measure a no-op.
	var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("complex_key", {"a": {"b": {"c": {"d": {"e": i}}}}})
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	rows.append({scale_label = "5-deep", stats = stats})
	BenchResults.record("micro", "bench_fact_write", "overwrite_complex", 1, "5-deep", "us/op", stats, samples)
	BenchHelper.print_table("micro/fact_write :: overwrite_complex", rows, "nested Dict 5 levels deep")


# 5. Overwrite with varying watcher counts — isolates dispatch cost
func test_bench_overwrite_with_watchers() -> void:
	var rows: Array = []
	var noop: Callable = func(_k: String, _v: Variant, _o: Variant) -> void: pass
	for wc: int in WATCHER_COUNTS:
		_chronicle.clear()
		_chronicle.set_fact("hot_key", 0)
		for i: int in range(wc):
			_chronicle.watch("hot_key", noop)
		guard(_chronicle.get_stats().watcher_count == wc, "overwrite_with_watchers: %d watchers registered" % wc)
		var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
			_chronicle.set_fact("hot_key", i)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		var label: String = "%dw" % wc
		rows.append({scale_label = label, stats = stats})
		BenchResults.record("micro", "bench_fact_write", "overwrite_with_watchers", wc, label, "us/op", stats, samples)
	BenchHelper.print_table("micro/fact_write :: overwrite_with_watchers", rows, "differential: watcher count effect on set_fact")


# 6. Bulk set_facts — overhead vs N * single
func test_bench_set_facts_bulk() -> void:
	var rows: Array = []
	for bs: int in BULK_SIZES:
		_chronicle.clear()
		# Two batches differing in EVERY value, alternated per measured call so every
		# key genuinely changes — an unchanged-value write is short-circuited by the
		# coordinator (write_coordinator.gd:158) and would measure a no-op. Both batches
		# are built OUTSIDE the timed region so timing reflects set_facts cost, not dict
		# construction.
		var batch_a: Dictionary = {}
		var batch_b: Dictionary = {}
		for i: int in range(bs):
			batch_a["bulk_entity.prop_%d" % i] = i
			batch_b["bulk_entity.prop_%d" % i] = i + bs
		_chronicle.set_facts(batch_a)
		guard(_chronicle.count_facts("bulk_entity.*") == bs, "set_facts_bulk: %d keys written" % bs)
		var flip: Array[bool] = [false]
		var samples: Array[float] = BenchHelper.measure_batched(func() -> void:
			flip[0] = not flip[0]
			_chronicle.set_facts(batch_b if flip[0] else batch_a)
		, bs)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		var label: String = "%d keys" % bs
		rows.append({scale_label = label, stats = stats})
		BenchResults.record("micro", "bench_fact_write", "set_facts_bulk", bs, label, "us/op", stats, samples)
	BenchHelper.print_table("micro/fact_write :: set_facts_bulk", rows, "per-key cost in bulk operation")


# 7. Increment — arithmetic + set_fact combined
func test_bench_increment() -> void:
	var rows: Array = []
	for si: int in range(3):
		var n: int = SCALES[si]
		_populate(n)
		_chronicle.set_fact("counter", 0)
		_chronicle.increment_fact("counter")
		guard(_chronicle.get_fact("counter") == 1, "increment: counter incremented")
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			_chronicle.increment_fact("counter")
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("micro", "bench_fact_write", "increment", n, LABELS[si], "us/op", stats, samples)
		_chronicle.clear()
	BenchHelper.print_table("micro/fact_write :: increment", rows)


# 8. Erase — index cleanup + timeline
func test_bench_erase() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		var n: int = SCALES[si]
		_populate(n)
		var target_key: String = "entity_0.prop_0"
		guard(_chronicle.erase_fact(target_key), "erase: target key existed and was erased")
		_chronicle.set_fact(target_key, 1)
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			_chronicle.erase_fact(target_key)
			_chronicle.set_fact(target_key, 1)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("micro", "bench_fact_write", "erase", n, LABELS[si], "us/op", stats, samples)
		_chronicle.clear()
	BenchHelper.print_table("micro/fact_write :: erase", rows, "erase + re-insert to isolate erase cost")
