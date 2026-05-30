extends BenchSuite


const SCALES: Array[int] = [1000, 5000, 10000, 50000, 100000, 200000]
const LABELS: Array[String] = ["1K", "5K", "10K", "50K", "100K", "200K"]



func _populate(n: int) -> void:
	var entities: int = n / 10
	for e: int in range(entities):
		for p: int in range(10):
			_chronicle.set_fact("e_%d.p_%d" % [e, p], e * 10 + p)


# 1. Insert at scale — does set_fact degrade with store size?
func test_bench_insert_at_scale() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		_chronicle.clear()
		var n: int = SCALES[si]
		_populate(n)
		guard(_chronicle.count_facts("*") == n, "insert_at_scale: store populated to %d facts" % n)
		var counter: Array = [0]
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			counter[0] += 1
			_chronicle.set_fact("new_e.insert_%d" % counter[0], counter[0])
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("stress", "bench_scale_facts", "insert_at_scale", n, LABELS[si], "us/op", stats, samples)
	BenchHelper.print_stress_table("stress/scale_facts :: insert_at_scale", rows)


# 2. Get at scale — does get_fact remain O(1)?
func test_bench_get_at_scale() -> void:
	BenchHelper.run_scale_bench("stress", "bench_scale_facts", "get_at_scale", "us/op",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			_populate(scale),
		func() -> void:
			var _v: Variant = _chronicle.get_fact("e_0.p_0"),
		BenchHelper.TableKind.STRESS, 0, "",
		func(_scale: int) -> void:
			guard(_chronicle.get_fact("e_0.p_0") == 0, "get_at_scale: e_0.p_0 readable"))


# 3. Overwrite at scale — store occupancy effect
func test_bench_overwrite_at_scale() -> void:
	# Alternate the value each call so every overwrite genuinely changes the fact — a
	# constant-value set_fact is short-circuited by the coordinator and would measure a
	# no-op. The guard is READ-ONLY so it does not perturb the timed loop.
	var flip: Array[bool] = [false]
	BenchHelper.run_scale_bench("stress", "bench_scale_facts", "overwrite_at_scale", "us/op",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			_populate(scale)
			flip[0] = false,
		func() -> void:
			flip[0] = not flip[0]
			_chronicle.set_fact("e_0.p_0", 1 if flip[0] else 2),
		BenchHelper.TableKind.STRESS, 0, "",
		func(_scale: int) -> void:
			guard(_chronicle.has_fact("e_0.p_0"), "overwrite_at_scale: e_0.p_0 present before overwrite"))


# 4. Erase at scale — index cleanup cost
func test_bench_erase_at_scale() -> void:
	BenchHelper.run_scale_bench("stress", "bench_scale_facts", "erase_at_scale", "us/op",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			_populate(scale),
		func() -> void:
			_chronicle.erase_fact("e_0.p_0")
			_chronicle.set_fact("e_0.p_0", 1),
		BenchHelper.TableKind.STRESS, 0, "",
		func(_scale: int) -> void:
			guard(_chronicle.has_fact("e_0.p_0"), "erase_at_scale: e_0.p_0 present before erase"))


# 5. has_fact at scale — pure lookup constant?
func test_bench_has_fact_at_scale() -> void:
	BenchHelper.run_scale_bench("stress", "bench_scale_facts", "has_fact_at_scale", "us/op",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			_populate(scale),
		func() -> void:
			var _v: bool = _chronicle.has_fact("e_0.p_0"),
		BenchHelper.TableKind.STRESS, 0, "",
		func(_scale: int) -> void:
			guard(_chronicle.has_fact("e_0.p_0"), "has_fact_at_scale: e_0.p_0 present"))


# 6. Memory per fact — OS memory delta per 1K facts
func test_bench_memory_per_fact() -> void:
	var rows: Array = []
	var mem_scales: Array[int] = [1000, 10000, 100000]
	var mem_labels: Array[String] = ["1K", "10K", "100K"]
	for si: int in range(mem_scales.size()):
		var n: int = mem_scales[si]
		_chronicle.clear()
		var before: int = OS.get_static_memory_usage()
		_populate(n)
		var after: int = OS.get_static_memory_usage()
		# Guard runs OUTSIDE the timed memory window (after `after` is sampled) so it cannot
		# perturb the delta, while still proving the populate actually happened.
		guard(_chronicle.count_facts("*") == n, "memory_per_fact: populate wrote %d facts" % n)
		var raw_delta: int = after - before
		var bytes_per_fact: float = 0.0
		if raw_delta > 0:
			bytes_per_fact = float(raw_delta) / float(n)
		else:
			# Allocator pooling / GC can hide the delta — flag it rather than report a bogus value.
			print("  [warn] memory_per_fact %s: non-positive raw delta (%d bytes) — measurement unreliable, row skipped" % [mem_labels[si], raw_delta])
			continue
		var stats: Dictionary = {min = bytes_per_fact, p5 = bytes_per_fact, p25 = bytes_per_fact, median = bytes_per_fact, p75 = bytes_per_fact, p95 = bytes_per_fact, max = bytes_per_fact, mean = bytes_per_fact, stddev = 0.0}
		rows.append({scale_label = mem_labels[si], stats = stats, raw_delta = raw_delta})
		BenchResults.record("stress", "bench_scale_facts", "memory_per_fact", n, mem_labels[si], "bytes/fact", stats, [bytes_per_fact])
	print("")
	print("[bench] stress/scale_facts :: memory_per_fact")
	print("  scale  | bytes/fact | raw delta")
	print("  -------+------------+-----------")
	for row: Dictionary in rows:
		print("  %-6s | %8.1f   | %d bytes" % [row.scale_label, row.stats.median, row.raw_delta])
