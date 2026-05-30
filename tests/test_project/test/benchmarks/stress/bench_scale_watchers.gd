extends BenchSuite


const SCALES: Array[int] = [10, 50, 100, 200, 500, 1000]
const LABELS: Array[String] = ["10", "50", "100", "200", "500", "1000"]


# 1. Exact watchers on hot key — dispatch linear with count?
func test_bench_exact_watchers_on_hot_key() -> void:
	# Vary the value each call so the write genuinely changes and ALL `scale` watchers
	# actually dispatch — a constant-value write is short-circuited before dispatch
	# (write_coordinator.gd:158) and would measure the suppress path, not dispatch.
	var v: Array[int] = [0]
	BenchHelper.run_scale_bench("stress", "bench_scale_watchers", "exact_watchers_on_hot_key", "us/op",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			_chronicle.set_fact("hot", 0)
			v[0] = 0
			for _i: int in range(scale):
				_chronicle.watch("hot", _noop),
		func() -> void:
			v[0] += 1
			_chronicle.set_fact("hot", v[0]),
		BenchHelper.TableKind.STRESS, 0, "",
		func(scale: int) -> void:
			guard(_chronicle.get_stats().watcher_count == scale, "exact_watchers_on_hot_key: %d watchers registered" % scale))


# 2. Glob watchers unique patterns
func test_bench_glob_watchers_unique_patterns() -> void:
	var scales: Array[int] = [10, 50, 100, 200, 500]
	var labels: Array[String] = ["10", "50", "100", "200", "500"]
	# Vary the written value each call so the matching glob watcher actually dispatches.
	var v: Array[int] = [0]
	BenchHelper.run_scale_bench("stress", "bench_scale_watchers", "glob_watchers_unique_patterns", "us/op",
		scales, labels,
		func(scale: int) -> void:
			_chronicle.clear()
			_chronicle.set_fact("entity_0.prop_0", 0)
			v[0] = 0
			for i: int in range(scale):
				_chronicle.watch("entity_%d.*" % i, _noop),
		func() -> void:
			v[0] += 1
			_chronicle.set_fact("entity_0.prop_0", v[0]),
		BenchHelper.TableKind.STRESS, 0, "",
		func(scale: int) -> void:
			guard(_chronicle.get_stats().watcher_count == scale, "glob_watchers_unique_patterns: %d glob watchers registered" % scale))


# 3. Glob watchers same pattern — cache helps?
func test_bench_glob_watchers_same_pattern() -> void:
	var scales: Array[int] = [10, 50, 100, 200]
	var labels: Array[String] = ["10", "50", "100", "200"]
	# Vary the written value each call so all `scale` same-pattern watchers dispatch.
	var v: Array[int] = [0]
	BenchHelper.run_scale_bench("stress", "bench_scale_watchers", "glob_watchers_same_pattern", "us/op",
		scales, labels,
		func(scale: int) -> void:
			_chronicle.clear()
			_chronicle.set_fact("entity_0.prop_0", 0)
			v[0] = 0
			for _i: int in range(scale):
				_chronicle.watch("entity_0.*", _noop),
		func() -> void:
			v[0] += 1
			_chronicle.set_fact("entity_0.prop_0", v[0]),
		BenchHelper.TableKind.STRESS, 0, "",
		func(scale: int) -> void:
			guard(_chronicle.get_stats().watcher_count == scale, "glob_watchers_same_pattern: %d watchers on same pattern" % scale))


# 4. Registration at scale
func test_bench_registration_at_scale() -> void:
	BenchHelper.run_scale_bench("stress", "bench_scale_watchers", "registration_at_scale", "us/op",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			for i: int in range(scale):
				_chronicle.watch("existing_%d" % i, _noop),
		func() -> void:
			_chronicle.watch("new_key", _noop),
		BenchHelper.TableKind.STRESS, 0, "",
		func(scale: int) -> void:
			guard(_chronicle.get_stats().watcher_count == scale, "registration_at_scale: %d existing watchers before insert" % scale))


# 5. Unwatch at scale
func test_bench_unwatch_at_scale() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		_chronicle.clear()
		var ids: Array[int] = []
		for i: int in range(SCALES[si]):
			ids.append(_chronicle.watch("key_%d" % i, _noop))
		guard(_chronicle.get_stats().watcher_count == SCALES[si], "unwatch_at_scale: %d watchers registered" % SCALES[si])
		# Array holder for reference semantics: GDScript lambdas capture primitives BY
		# VALUE, so a plain `target_id =` inside the closure would NOT persist across
		# calls — the unwatch would degrade to a lookup-miss no-op after the first
		# iteration. The holder makes each call unwatch the watcher the previous call made.
		var target_id: Array[int] = [ids[0]]
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			_chronicle.unwatch(target_id[0])
			target_id[0] = _chronicle.watch("key_0", _noop)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("stress", "bench_scale_watchers", "unwatch_at_scale", SCALES[si], LABELS[si], "us/op", stats, samples)
	BenchHelper.print_stress_table("stress/scale_watchers :: unwatch_at_scale", rows, "total")


# 6. Mixed exact/glob ratio effect
func test_bench_mixed_exact_glob_ratio() -> void:
	var rows: Array = []
	var ratios: Array = [[100, 100], [160, 40], [190, 10]]
	var labels: Array[String] = ["50/50", "80/20", "95/5"]
	for ri: int in range(ratios.size()):
		_chronicle.clear()
		_chronicle.set_fact("hot.key", 0)
		for _i: int in range(ratios[ri][0]):
			_chronicle.watch("hot.key", _noop)
		for _i: int in range(ratios[ri][1]):
			_chronicle.watch("hot.*", _noop)
		guard(_chronicle.get_stats().watcher_count == ratios[ri][0] + ratios[ri][1], "mixed_exact_glob_ratio: %d total watchers" % (ratios[ri][0] + ratios[ri][1]))
		# Vary the value each call so the write changes and all watchers dispatch.
		var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
			_chronicle.set_fact("hot.key", i)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = labels[ri], stats = stats})
		BenchResults.record("stress", "bench_scale_watchers", "mixed_exact_glob_ratio", 200, labels[ri], "us/op", stats, samples)
	BenchHelper.print_stress_table("stress/scale_watchers :: mixed_exact_glob_ratio (200 total)", rows, "ratio")
