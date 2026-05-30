extends BenchSuite




func _populate_for_rollback(entry_count: int) -> void:
	_chronicle.set_game_time(0.0)
	_chronicle.set_fact("anchor", "start")
	for i: int in range(entry_count):
		_chronicle.set_game_time(float(i + 1))
		_chronicle.set_fact("rb_key_%d" % (i % 50), i)


# 1. Rollback shallow — restore 10 entries
func test_bench_rollback_to_shallow() -> void:
	_populate_for_rollback(10)
	_chronicle.rollback_to(0.5)
	guard(_chronicle.get_fact("anchor") == "start", "rollback_to_shallow: anchor restored to start")
	_populate_for_rollback(10)
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		_chronicle.rollback_to(0.5)
		_populate_for_rollback(10)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_rollback", "rollback_to_shallow", 10, "10", "us/op", stats, samples)
	BenchHelper.print_table("micro/rollback :: rollback_to_shallow", [{scale_label = "10", stats = stats}])


# 2. Rollback deep — 100/500/1000 entries
func test_bench_rollback_to_deep() -> void:
	var rows: Array = []
	var depths: Array[int] = [100, 500, 1000]
	var labels: Array[String] = ["100", "500", "1000"]
	for di: int in range(depths.size()):
		_chronicle.clear()
		_populate_for_rollback(depths[di])
		if di == 0:
			_chronicle.rollback_to(0.5)
			guard(_chronicle.get_fact("anchor") == "start", "rollback_to_deep: anchor restored to start")
			_populate_for_rollback(depths[di])
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			_chronicle.rollback_to(0.5)
			_populate_for_rollback(depths[di])
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = labels[di], stats = stats})
		BenchResults.record("micro", "bench_rollback", "rollback_to_deep", depths[di], labels[di], "us/op", stats, samples)
	BenchHelper.print_table("micro/rollback :: rollback_to_deep", rows, "entries restored after rollback point")


# 3. Rollback steps — step-counting overhead
func test_bench_rollback_steps() -> void:
	var rows: Array = []
	var step_counts: Array[int] = [1, 10, 50]
	var labels: Array[String] = ["1", "10", "50"]
	for si: int in range(step_counts.size()):
		_chronicle.clear()
		for i: int in range(100):
			_chronicle.set_game_time(float(i))
			_chronicle.set_fact("step_key_%d" % i, i)
		if si == 0:
			_chronicle.rollback_steps(step_counts[0])
			guard(not _chronicle.has_fact("step_key_99"), "rollback_steps: last step undone (step_key_99 gone)")
			for i: int in range(100):
				_chronicle.set_game_time(float(i))
				_chronicle.set_fact("step_key_%d" % i, i)
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			_chronicle.rollback_steps(step_counts[si])
			for i: int in range(100):
				_chronicle.set_game_time(float(i))
				_chronicle.set_fact("step_key_%d" % i, i)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = labels[si], stats = stats})
		BenchResults.record("micro", "bench_rollback", "rollback_steps", step_counts[si], labels[si], "us/op", stats, samples)
	BenchHelper.print_table("micro/rollback :: rollback_steps", rows)


# 4. Rollback with complex values — deep copy cost during restore
func test_bench_rollback_complex_values() -> void:
	_chronicle.set_game_time(0.0)
	for i: int in range(50):
		_chronicle.set_fact("complex_%d" % i, {"a": {"b": {"c": i}}})
	_chronicle.set_game_time(1.0)
	for i: int in range(50):
		_chronicle.set_fact("complex_%d" % i, {"a": {"b": {"c": i + 100}}})
	_chronicle.rollback_to(0.5)
	guard(_chronicle.get_fact("complex_0") == {"a": {"b": {"c": 0}}}, "rollback_complex_values: nested dict restored")
	_chronicle.set_game_time(1.0)
	for i: int in range(50):
		_chronicle.set_fact("complex_%d" % i, {"a": {"b": {"c": i + 100}}})
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		_chronicle.rollback_to(0.5)
		_chronicle.set_game_time(1.0)
		for i: int in range(50):
			_chronicle.set_fact("complex_%d" % i, {"a": {"b": {"c": i + 100}}})
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_rollback", "rollback_complex_values", 50, "50 dicts", "us/op", stats, samples)
	BenchHelper.print_table("micro/rollback :: rollback_complex_values", [{scale_label = "50 dicts", stats = stats}], "50 keys with nested Dict values")


# 5. Rollback with active watchers — notification cost
func test_bench_rollback_with_watchers() -> void:
	var noop: Callable = func(_k: String, _v: Variant, _o: Variant) -> void: pass
	_chronicle.set_game_time(0.0)
	for i: int in range(50):
		_chronicle.set_fact("watched_%d" % i, 0)
		_chronicle.watch("watched_%d" % i, noop)
	_chronicle.set_game_time(1.0)
	for i: int in range(50):
		_chronicle.set_fact("watched_%d" % i, 1)
	_chronicle.rollback_to(0.5)
	guard(_chronicle.get_fact("watched_0") == 0, "rollback_with_watchers: watched_0 restored to 0")
	_chronicle.set_game_time(1.0)
	for i: int in range(50):
		_chronicle.set_fact("watched_%d" % i, 1)
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		_chronicle.rollback_to(0.5)
		_chronicle.set_game_time(1.0)
		for i: int in range(50):
			_chronicle.set_fact("watched_%d" % i, 1)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_rollback", "rollback_with_watchers", 50, "50w", "us/op", stats, samples)
	BenchHelper.print_table("micro/rollback :: rollback_with_watchers", [{scale_label = "50w", stats = stats}], "50 keys each with 1 exact watcher")


# 6. Rollback with transient keys — skip filtering cost
func test_bench_rollback_transient_skip() -> void:
	_chronicle.set_game_time(0.0)
	for i: int in range(100):
		var transient: bool = (i % 2 == 0)
		_chronicle.set_fact("mixed_%d" % i, 0, transient, 0.0)
	_chronicle.set_game_time(1.0)
	for i: int in range(100):
		var transient: bool = (i % 2 == 0)
		_chronicle.set_fact("mixed_%d" % i, 1, transient, 0.0)
	_chronicle.rollback_to(0.5)
	guard(_chronicle.get_fact("mixed_1") == 0, "rollback_transient_skip: non-transient key restored to 0")
	_chronicle.set_game_time(1.0)
	for i: int in range(100):
		var t: bool = (i % 2 == 0)
		_chronicle.set_fact("mixed_%d" % i, 1, t, 0.0)
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		_chronicle.rollback_to(0.5)
		_chronicle.set_game_time(1.0)
		for i: int in range(100):
			var transient: bool = (i % 2 == 0)
			_chronicle.set_fact("mixed_%d" % i, 1, transient, 0.0)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_rollback", "rollback_transient_skip", 100, "50% trans", "us/op", stats, samples)
	BenchHelper.print_table("micro/rollback :: rollback_transient_skip", [{scale_label = "50%", stats = stats}], "100 keys, 50% transient (skipped by rollback)")
