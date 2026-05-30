extends BenchSuite




# 1. Chain depth 1 — baseline (watcher does nothing)
func test_bench_chain_depth_1() -> void:
	_chronicle.set_fact("chain_0", 0)
	_chronicle.watch("chain_0", func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	_chronicle.set_fact("chain_0", 1)
	guard(_chronicle.get_fact("chain_0") == 1, "chain_depth_1: chain_0 set")
	var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("chain_0", i)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_cascade_chain", "chain_depth_1", 1, "depth 1", "us/op", stats, samples)
	BenchHelper.print_table("macro/cascade :: chain_depth_1", [{scale_label = "depth 1", stats = stats}], "baseline: watcher does nothing")


# 2. Chain depth 3 — inline cascade A->B->C
func test_bench_chain_depth_3() -> void:
	_chronicle.clear()
	_chronicle.set_fact("c3_0", 0)
	_chronicle.set_fact("c3_1", 0)
	_chronicle.set_fact("c3_2", 0)
	_chronicle.watch("c3_0", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("c3_1", _v))
	_chronicle.watch("c3_1", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("c3_2", _v))
	_chronicle.watch("c3_2", func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	_chronicle.set_fact("c3_0", 1)
	guard(_chronicle.get_fact("c3_2") == 1, "chain_depth_3: cascade reached c3_2")
	var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("c3_0", i)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_cascade_chain", "chain_depth_3", 3, "depth 3", "us/op", stats, samples)
	BenchHelper.print_table("macro/cascade :: chain_depth_3", [{scale_label = "depth 3", stats = stats}])


# 3. Chain depth 7 — max inline depth
func test_bench_chain_depth_7() -> void:
	_chronicle.clear()
	for i: int in range(8):
		_chronicle.set_fact("c7_%d" % i, 0)
	for i: int in range(7):
		var next_key: String = "c7_%d" % (i + 1)
		_chronicle.watch("c7_%d" % i, func(_k: String, _v: Variant, _o: Variant, nk: String = next_key) -> void:
			_chronicle.set_fact(nk, _v))
	_chronicle.set_fact("c7_0", 1)
	guard(_chronicle.get_fact("c7_7") == 1, "chain_depth_7: cascade reached c7_7")
	var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("c7_0", i)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_cascade_chain", "chain_depth_7", 7, "depth 7", "us/op", stats, samples)
	BenchHelper.print_table("macro/cascade :: chain_depth_7", [{scale_label = "depth 7", stats = stats}])


# 4. Chain depth 8 — deferred queue activates
func test_bench_chain_depth_8_deferred() -> void:
	_chronicle.clear()
	for i: int in range(9):
		_chronicle.set_fact("c8_%d" % i, 0)
	for i: int in range(8):
		var next_key: String = "c8_%d" % (i + 1)
		_chronicle.watch("c8_%d" % i, func(_k: String, _v: Variant, _o: Variant, nk: String = next_key) -> void:
			_chronicle.set_fact(nk, _v))
	_chronicle.set_fact("c8_0", 1)
	guard(_chronicle.get_fact("c8_8") == 1, "chain_depth_8_deferred: cascade reached c8_8 via deferred queue")
	var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("c8_0", i)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_cascade_chain", "chain_depth_8_deferred", 8, "depth 8", "us/op", stats, samples)
	BenchHelper.print_table("macro/cascade :: chain_depth_8_deferred", [{scale_label = "depth 8", stats = stats}], "deferred queue kicks in at depth 8")


# 5. Fan-out 10 — 1 fact triggers 10 watchers each setting 1 fact
func test_bench_fan_out_10() -> void:
	_chronicle.clear()
	_chronicle.set_fact("root", 0)
	for i: int in range(10):
		_chronicle.set_fact("fan_%d" % i, 0)
		var fan_key: String = "fan_%d" % i
		_chronicle.watch("root", func(_k: String, _v: Variant, _o: Variant, fk: String = fan_key) -> void:
			_chronicle.set_fact(fk, _v))
	_chronicle.set_fact("root", 1)
	guard(_chronicle.get_fact("fan_9") == 1, "fan_out_10: all 10 fan-out watchers fired (fan_9 set)")
	var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("root", i)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_cascade_chain", "fan_out_10", 10, "1->10", "us/op", stats, samples)
	BenchHelper.print_table("macro/cascade :: fan_out_10", [{scale_label = "1->10", stats = stats}])


# 6. Fan-out 10 depth 3 — wide + deep (potentially 1000 set_facts)
func test_bench_fan_out_10_depth_3() -> void:
	_chronicle.clear()
	_chronicle.set_fact("root", 0)
	for i: int in range(10):
		var l1_key: String = "l1_%d" % i
		_chronicle.set_fact(l1_key, 0)
		_chronicle.watch("root", func(_k: String, _v: Variant, _o: Variant, k: String = l1_key) -> void:
			_chronicle.set_fact(k, _v))
		for j: int in range(10):
			var l2_key: String = "l2_%d_%d" % [i, j]
			_chronicle.set_fact(l2_key, 0)
			_chronicle.watch(l1_key, func(_k: String, _v: Variant, _o: Variant, k: String = l2_key) -> void:
				_chronicle.set_fact(k, _v))
	_chronicle.set_fact("root", 1)
	guard(_chronicle.get_fact("l2_9_9") == 1, "fan_out_10_depth_3: 2-level fan-out reached l2_9_9")
	var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("root", i)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_cascade_chain", "fan_out_10_depth_3", 110, "10x10", "us/op", stats, samples)
	BenchHelper.print_table("macro/cascade :: fan_out_10_depth_3", [{scale_label = "10x10", stats = stats}], "10-wide at 2 levels = 110 set_facts")


# 7. Deferred queue drain — fill then drain 32/64 entries
func test_bench_deferred_queue_drain() -> void:
	var rows: Array = []
	var queue_sizes: Array[int] = [32, 64]
	var labels: Array[String] = ["32", "64"]
	for qi: int in range(queue_sizes.size()):
		_chronicle.clear()
		var qs: int = queue_sizes[qi]
		for i: int in range(8):
			_chronicle.set_fact("deep_%d" % i, 0)
		for i: int in range(7):
			var next_key: String = "deep_%d" % (i + 1)
			_chronicle.watch("deep_%d" % i, func(_k: String, _v: Variant, _o: Variant, nk: String = next_key) -> void:
				_chronicle.set_fact(nk, _v))
		var batch: int = mini(qs, 56)
		for i: int in range(batch):
			_chronicle.set_fact("deferred_%d" % i, 0)
			_chronicle.watch("deep_7", func(_k: String, _v: Variant, _o: Variant, dk: String = "deferred_%d" % i) -> void:
				_chronicle.set_fact(dk, _v))
		if qi == 0:
			_chronicle.set_fact("deep_0", 1)
			guard(_chronicle.get_fact("deferred_0") == 1, "deferred_queue_drain: cascade drained to deferred_0")
		var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
			_chronicle.set_fact("deep_0", i)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = labels[qi], stats = stats})
		BenchResults.record("macro", "bench_cascade_chain", "deferred_queue_drain", qs, labels[qi], "us/op", stats, samples)
	BenchHelper.print_table("macro/cascade :: deferred_queue_drain", rows, "queue fill + drain cost")


# 8. Cascade with bulk set_facts
func test_bench_cascade_with_bulk() -> void:
	_chronicle.clear()
	var noop: Callable = func(_k: String, _v: Variant, _o: Variant) -> void: pass
	var batch: Dictionary = {}
	for i: int in range(10):
		var key: String = "bulk_%d" % i
		_chronicle.set_fact(key, 0)
		batch[key] = i + 1
		_chronicle.watch(key, noop)
		_chronicle.watch(key, noop)
	_chronicle.set_facts(batch)
	guard(_chronicle.get_fact("bulk_0") == 1, "cascade_with_bulk: bulk set_facts applied (bulk_0 == 1)")
	var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		var b: Dictionary = batch.duplicate(true)
		b["bulk_0"] = i
		_chronicle.set_facts(b)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_cascade_chain", "cascade_with_bulk", 10, "10 keys", "us/op", stats, samples)
	BenchHelper.print_table("macro/cascade :: cascade_with_bulk", [{scale_label = "10 keys", stats = stats}], "set_facts({10 keys}) each with 2 watchers")
