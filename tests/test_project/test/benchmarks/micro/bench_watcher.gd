extends BenchSuite


# 1. Register exact watchers — registration cost
func test_bench_register_exact() -> void:
	const COUNT: int = 100
	_chronicle.clear()
	for i: int in range(COUNT):
		_chronicle.watch("key_%d" % i, _noop)
	guard(_chronicle.get_stats().watcher_count == COUNT, "register_exact: %d watchers registered" % COUNT)
	var samples: Array[float] = BenchHelper.measure_batched(func() -> void:
		_chronicle.clear()
		for i: int in range(COUNT):
			_chronicle.watch("key_%d" % i, _noop)
	, COUNT)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_watcher", "register_exact", COUNT, "100", "us/op", stats, samples)
	BenchHelper.print_table("micro/watcher :: register_exact", [{scale_label = "100", stats = stats}])


# 2. Register glob watchers
func test_bench_register_glob() -> void:
	const COUNT: int = 100
	_chronicle.clear()
	for i: int in range(COUNT):
		_chronicle.watch("entity_%d.*" % i, _noop)
	guard(_chronicle.get_stats().watcher_count == COUNT, "register_glob: %d glob watchers registered" % COUNT)
	var samples: Array[float] = BenchHelper.measure_batched(func() -> void:
		_chronicle.clear()
		for i: int in range(COUNT):
			_chronicle.watch("entity_%d.*" % i, _noop)
	, COUNT)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_watcher", "register_glob", COUNT, "100", "us/op", stats, samples)
	BenchHelper.print_table("micro/watcher :: register_glob", [{scale_label = "100", stats = stats}])


# 3. Unwatch cost — cleanup with reverse map
func test_bench_unwatch_cost() -> void:
	const COUNT: int = 100
	var ids: Array[int] = []
	for i: int in range(COUNT):
		ids.append(_chronicle.watch("key_%d" % i, _noop))
	guard(_chronicle.get_stats().watcher_count == COUNT, "unwatch_cost: %d watchers registered before unwatch" % COUNT)
	var samples: Array[float] = BenchHelper.measure_batched(func() -> void:
		for id: int in ids:
			_chronicle.unwatch(id)
		ids.clear()
		for i: int in range(COUNT):
			ids.append(_chronicle.watch("key_%d" % i, _noop))
	, COUNT)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_watcher", "unwatch_cost", COUNT, "100", "us/op", stats, samples)
	BenchHelper.print_table("micro/watcher :: unwatch_cost", [{scale_label = "100", stats = stats}])


# 4. Dispatch exact — scaling with watcher count on same key
func test_bench_dispatch_exact_scaling() -> void:
	var rows: Array = []
	var counts: Array[int] = [1, 10, 50, 100, 200]
	for wc: int in counts:
		_chronicle.clear()
		_chronicle.set_fact("hot", 0)
		for _i: int in range(wc):
			_chronicle.watch("hot", _noop)
		guard(_chronicle.get_stats().watcher_count == wc, "dispatch_exact_scaling: %d watchers on hot key" % wc)
		var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
			_chronicle.set_fact("hot", i)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		var label: String = str(wc)
		rows.append({scale_label = label, stats = stats})
		BenchResults.record("micro", "bench_watcher", "dispatch_exact_scaling", wc, label, "us/op", stats, samples)
	BenchHelper.print_table("micro/watcher :: dispatch_exact_scaling", rows, "set_fact with N exact watchers on same key")


# 5. Dispatch glob — scaling with pattern count
func test_bench_dispatch_glob_scaling() -> void:
	var rows: Array = []
	var counts: Array[int] = [1, 10, 50, 100]
	for gc: int in counts:
		_chronicle.clear()
		_chronicle.set_fact("entity_0.prop_0", 0)
		for i: int in range(gc):
			_chronicle.watch("entity_%d.*" % (i % 10), _noop)
		if gc == counts[0]:
			guard(_chronicle.get_stats().watcher_count == gc, "dispatch_glob_scaling: %d glob watchers registered" % gc)
		var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
			_chronicle.set_fact("entity_0.prop_0", i)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		var label: String = str(gc)
		rows.append({scale_label = label, stats = stats})
		BenchResults.record("micro", "bench_watcher", "dispatch_glob_scaling", gc, label, "us/op", stats, samples)
	BenchHelper.print_table("micro/watcher :: dispatch_glob_scaling", rows, "set_fact with N glob watchers")


# 6. Dispatch mixed — realistic 20 exact + 10 glob
func test_bench_dispatch_mixed() -> void:
	_chronicle.set_fact("entity_0.health", 100)
	for i: int in range(20):
		_chronicle.watch("entity_0.health", _noop)
	for i: int in range(10):
		_chronicle.watch("entity_0.*", _noop)
	guard(_chronicle.get_stats().watcher_count == 30, "dispatch_mixed: 20 exact + 10 glob = 30 watchers")
	var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("entity_0.health", i)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_watcher", "dispatch_mixed", 30, "20e+10g", "us/op", stats, samples)
	BenchHelper.print_table("micro/watcher :: dispatch_mixed", [{scale_label = "20e+10g", stats = stats}])


# 7. watch_once overhead vs persistent
func test_bench_watch_once_overhead() -> void:
	var rows: Array = []
	_chronicle.set_fact("once_key", 0)
	for _i: int in range(50):
		_chronicle.watch("once_key", _noop)
	guard(_chronicle.get_stats().watcher_count == 50, "watch_once_overhead: 50 persistent watchers registered")
	var samples_persist: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("once_key", i)
	)
	var stats_persist: Dictionary = BenchHelper.compute_stats(samples_persist)
	rows.append({scale_label = "persist", stats = stats_persist})
	BenchResults.record("micro", "bench_watcher", "watch_once_vs_persistent_persist", 50, "persist", "us/op", stats_persist, samples_persist)

	_chronicle.clear()
	_chronicle.set_fact("once_key", 0)
	for _i: int in range(50):
		_chronicle.watch("once_key", _noop, true)
	var samples_once: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("once_key", i)
		for _j: int in range(50):
			_chronicle.watch("once_key", _noop, true)
	)
	var stats_once: Dictionary = BenchHelper.compute_stats(samples_once)
	rows.append({scale_label = "once", stats = stats_once})
	BenchResults.record("micro", "bench_watcher", "watch_once_vs_persistent_once", 50, "once", "us/op", stats_once, samples_once)
	BenchHelper.print_table("micro/watcher :: watch_once vs persistent (50 watchers)", rows)


# 8. Glob cache invalidation — rebuild cost
func test_bench_cache_invalidation() -> void:
	_chronicle.set_fact("entity_0.prop_0", 0)
	for i: int in range(50):
		_chronicle.watch("entity_%d.*" % i, _noop)
	guard(_chronicle.get_stats().watcher_count == 50, "cache_invalidation: 50 glob watchers registered")
	var rows: Array = []
	var samples_cached: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("entity_0.prop_0", i)
	)
	var stats_cached: Dictionary = BenchHelper.compute_stats(samples_cached)
	rows.append({scale_label = "cached", stats = stats_cached})
	BenchResults.record("micro", "bench_watcher", "cache_invalidation_cached", 50, "cached", "us/op", stats_cached, samples_cached)

	var samples_dirty: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.watch("entity_99.*", _noop)
		_chronicle.set_fact("entity_0.prop_0", i)
	)
	var stats_dirty: Dictionary = BenchHelper.compute_stats(samples_dirty)
	rows.append({scale_label = "dirty", stats = stats_dirty})
	BenchResults.record("micro", "bench_watcher", "cache_invalidation_dirty", 50, "dirty", "us/op", stats_dirty, samples_dirty)
	BenchHelper.print_table("micro/watcher :: cache_invalidation", rows, "cached vs dirty glob cache")
