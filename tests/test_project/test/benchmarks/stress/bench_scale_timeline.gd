extends BenchSuite


const SCALES: Array[int] = [1000, 5000, 10000, 50000, 100000]
const LABELS: Array[String] = ["1K", "5K", "10K", "50K", "100K"]



## Populates n timeline entries. key_mod bounds the distinct key count (default 200,
## matching the fact_history divisor); pass key_mod=n to give every entry a unique key
## so the fact store scales with n (used by serialize_at_depth).
func _populate_timeline(n: int, key_mod: int = 200) -> void:
	# Leave the elevated cap in place during the measured op so the timeline truly holds
	# all n entries (depth must be real). The base after_each restores the default cap.
	_chronicle.set_timeline_cap(n + 1000)
	var step: float = 100.0 / float(n)
	for i: int in range(n):
		_chronicle.set_game_time(step * float(i + 1))
		_chronicle.set_fact("tl_%d" % (i % key_mod), i)


## Deterministic count of timeline entries with timestamp > since (half-open: get_changes_since
## uses bisect_after — lower bound EXCLUSIVE) for a populate of n entries at times step*(i+1),
## step = 100/n.
func _expected_since(n: int, since: float) -> int:
	var step: float = 100.0 / float(n)
	var c: int = 0
	for i: int in range(n):
		if step * float(i + 1) > since:
			c += 1
	return c


# 1. Append at timeline depth
func test_bench_append_at_depth() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		_chronicle.clear()
		_populate_timeline(SCALES[si])
		guard(_chronicle.get_changes_since(0.0).size() == SCALES[si], "append_at_depth: timeline holds %d entries" % SCALES[si])
		var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
			_chronicle.set_game_time(100.0 + float(i) * 0.001)
			_chronicle.set_fact("append_test", i)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("stress", "bench_scale_timeline", "append_at_depth", SCALES[si], LABELS[si], "us/op", stats, samples)
	BenchHelper.print_stress_table("stress/scale_timeline :: append_at_depth", rows, "depth")


# 2. changes_since full scan
func test_bench_changes_since_full_scan() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		_chronicle.clear()
		_populate_timeline(SCALES[si])
		guard(_chronicle.get_changes_since(0.0).size() == SCALES[si], "changes_since_full_scan: %d entries scanned" % SCALES[si])
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _r: Array = _chronicle.get_changes_since(0.0)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("stress", "bench_scale_timeline", "changes_since_full_scan", SCALES[si], LABELS[si], "us", stats, samples)
	BenchHelper.print_stress_table("stress/scale_timeline :: changes_since_full_scan", rows, "depth")


# 3. changes_since bisect — query last 1%
func test_bench_changes_since_bisect() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		_chronicle.clear()
		_populate_timeline(SCALES[si])
		var expected_recent: int = _expected_since(SCALES[si], 99.0)
		guard(_chronicle.get_changes_since(99.0).size() == expected_recent, "changes_since_bisect: recent slice has %d entries" % expected_recent)
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _r: Array = _chronicle.get_changes_since(99.0)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("stress", "bench_scale_timeline", "changes_since_bisect", SCALES[si], LABELS[si], "us", stats, samples)
	BenchHelper.print_stress_table("stress/scale_timeline :: changes_since_bisect", rows, "depth")


# 4. fact_history at timeline depth
func test_bench_fact_history_at_depth() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		_chronicle.clear()
		_populate_timeline(SCALES[si])
		# tl_0 is written when i % 200 == 0 → i in {0, 200, 400, ...} → ceil(n/200) writes.
		var expected_hist: int = int(ceil(float(SCALES[si]) / 200.0))
		guard(_chronicle.get_fact_history("tl_0").size() == expected_hist, "fact_history_at_depth: tl_0 has %d history entries" % expected_hist)
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _r: Array = _chronicle.get_fact_history("tl_0")
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("stress", "bench_scale_timeline", "fact_history_at_depth", SCALES[si], LABELS[si], "us", stats, samples)
	BenchHelper.print_stress_table("stress/scale_timeline :: fact_history_at_depth", rows, "depth")


# 5. Rollback at depth — restore N entries
func test_bench_rollback_at_depth() -> void:
	var rows: Array = []
	var rollback_counts: Array[int] = [10, 100, 500, 1000, 5000]
	var rb_labels: Array[String] = ["10", "100", "500", "1K", "5K"]
	for ri: int in range(rollback_counts.size()):
		_chronicle.clear()
		var n: int = rollback_counts[ri]
		var orig_cap: int = _chronicle.get_timeline_cap()
		_chronicle.set_timeline_cap(n + 1000)
		_chronicle.set_game_time(0.0)
		_chronicle.set_fact("anchor", "base")
		for i: int in range(n):
			_chronicle.set_game_time(float(i + 1))
			_chronicle.set_fact("rb.k_%d" % (i % 50), i)
		if ri == 0:
			_chronicle.rollback_to(0.5)
			guard(_chronicle.get_fact("anchor") == "base", "rollback_at_depth: anchor restored to base")
			for i: int in range(n):
				_chronicle.set_game_time(float(i + 1))
				_chronicle.set_fact("rb.k_%d" % (i % 50), i)
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			_chronicle.rollback_to(0.5)
			for i: int in range(n):
				_chronicle.set_game_time(float(i + 1))
				_chronicle.set_fact("rb.k_%d" % (i % 50), i)
		)
		# Workload scales with n: after rollback_to(0.5) the timeline holds just the anchor
		# (t=0), then the op re-appends n entries (t=1..n) → timeline_size == n + 1. Keys cycle
		# rb.k_0..rb.k_49, so distinct facts == min(n, 50) (use a valid dotted glob — "rb_*"
		# would be an invalid partial-segment glob on a dotless key).
		guard(_chronicle.get_stats().timeline_size == n + 1, "rollback_at_depth: %d timeline entries after rollback+rewrite" % (n + 1))
		guard(_chronicle.count_facts("rb.*") == mini(n, 50), "rollback_at_depth: %d distinct rb keys" % mini(n, 50))
		_chronicle.set_timeline_cap(orig_cap)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = rb_labels[ri], stats = stats})
		BenchResults.record("stress", "bench_scale_timeline", "rollback_at_depth", n, rb_labels[ri], "us", stats, samples)
	BenchHelper.print_stress_table("stress/scale_timeline :: rollback_at_depth", rows, "entries")


# 6. Timeline cap trim — write cost while at cap (trim runs each append)
func test_bench_timeline_cap_trim() -> void:
	_chronicle.clear()
	var orig_cap: int = _chronicle.get_timeline_cap()
	_chronicle.set_timeline_cap(1000)
	for i: int in range(1099):
		_chronicle.set_game_time(float(i))
		_chronicle.set_fact("trim_%d" % (i % 50), i)
	guard(_chronicle.get_stats().timeline_size == 1000, "timeline_cap_trim: timeline trimmed to cap of 1000")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		_chronicle.set_fact("trigger_trim", 1)
		_chronicle.erase_fact("trigger_trim")
	)
	_chronicle.set_timeline_cap(orig_cap)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("stress", "bench_scale_timeline", "timeline_cap_trim", 1000, "1K cap", "us", stats, samples)
	BenchHelper.print_table("stress/scale_timeline :: timeline_cap_trim", [{scale_label = "1K", stats = stats}], "write cost at timeline cap")


# 7. Serialize at timeline depth
func test_bench_serialize_at_depth() -> void:
	var rows: Array = []
	var ser_scales: Array[int] = [1000, 10000, 50000]
	var ser_labels: Array[String] = ["1K", "10K", "50K"]
	for si: int in range(ser_scales.size()):
		var n: int = ser_scales[si]
		_chronicle.clear()
		# Unique key per entry so the serialized fact store scales with n (not capped at 200).
		_populate_timeline(n, n)
		guard(_chronicle.get_changes_since(0.0).size() == n, "serialize_at_depth: %d timeline entries to serialize" % n)
		guard(_chronicle.count_facts("*") == n, "serialize_at_depth: %d distinct facts to serialize" % n)
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _d: Dictionary = _chronicle.serialize(Chronicle.SERIALIZE_ALL)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = ser_labels[si], stats = stats})
		BenchResults.record("stress", "bench_scale_timeline", "serialize_at_depth", ser_scales[si], ser_labels[si], "us", stats, samples)
	BenchHelper.print_stress_table("stress/scale_timeline :: serialize_at_depth", rows, "depth")
