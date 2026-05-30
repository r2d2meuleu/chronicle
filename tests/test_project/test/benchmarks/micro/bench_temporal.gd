extends BenchSuite


const SCALES: Array[int] = [1000, 10000, 50000]
const LABELS: Array[String] = ["1K", "10K", "50K"]



func _populate_timeline(count: int) -> void:
	# Raise the cap so the full depth survives (default cap is 10K — without this a 50K
	# populate would truncate to 10K and overstate the recorded scale). after_each restores it.
	_chronicle.set_timeline_cap(count + 1000)
	var step: float = 100.0 / float(count)
	for i: int in range(count):
		_chronicle.set_game_time(step * float(i + 1))
		_chronicle.set_fact("tl_key_%d" % (i % 100), i)


## Deterministic count of entries whose timestamp is > since (half-open: get_changes_since
## uses bisect_after, so the lower bound is EXCLUSIVE), for a populate of `count` entries
## at times step*(i+1) with step = 100/count.
func _expected_since(count: int, since: float) -> int:
	var step: float = 100.0 / float(count)
	var c: int = 0
	for i: int in range(count):
		if step * float(i + 1) > since:
			c += 1
	return c


## Deterministic count of entries in the half-open range (since, until] — get_changes_between
## bisect_after on both bounds: timestamp > since AND timestamp <= until.
func _expected_between(count: int, since: float, until: float) -> int:
	var step: float = 100.0 / float(count)
	var c: int = 0
	for i: int in range(count):
		var t: float = step * float(i + 1)
		if t > since and t <= until:
			c += 1
	return c


# 1. changes_since full — traverse entire timeline + deep copy
func test_bench_changes_since_full() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		var n: int = SCALES[si]
		_chronicle.clear()
		_populate_timeline(n)
		guard(_chronicle.get_changes_since(0.0).size() == n, "changes_since_full: %d timeline entries" % n)
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _r: Array = _chronicle.get_changes_since(0.0)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("micro", "bench_temporal", "changes_since_full", n, LABELS[si], "us", stats, samples)
	BenchHelper.print_table("micro/temporal :: changes_since_full", rows, "full timeline traversal + deep copy")


# 2. changes_since recent — bisect skip 99%
func test_bench_changes_since_recent() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		var n: int = SCALES[si]
		_chronicle.clear()
		_populate_timeline(n)
		var expected: int = _expected_since(n, 99.0)
		guard(_chronicle.get_changes_since(99.0).size() == expected, "changes_since_recent: recent slice has %d entries" % expected)
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _r: Array = _chronicle.get_changes_since(99.0)
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("micro", "bench_temporal", "changes_since_recent", n, LABELS[si], "us", stats, samples)
	BenchHelper.print_table("micro/temporal :: changes_since_recent", rows, "bisect to last 1% of timeline")


# 3. changes_between window — double bisect + bounded copy
func test_bench_changes_between_window() -> void:
	_populate_timeline(10000)
	var expected_window: int = _expected_between(10000, 50.0, 60.0)
	guard(_chronicle.get_changes_between(50.0, 60.0).size() == expected_window, "changes_between_window: window slice has %d entries" % expected_window)
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _r: Array = _chronicle.get_changes_between(50.0, 60.0)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_temporal", "changes_between_window", 10000, "10K", "us", stats, samples)
	BenchHelper.print_table("micro/temporal :: changes_between_window", [{scale_label = "10K tl", stats = stats}], "window 50.0-60.0 in 10K timeline")


# 4. fact_history hot key — key with many changes
func test_bench_fact_history_hot() -> void:
	var rows: Array = []
	var counts: Array[int] = [100, 500, 1000]
	var labels: Array[String] = ["100", "500", "1000"]
	for ci: int in range(counts.size()):
		_chronicle.clear()
		for i: int in range(counts[ci]):
			_chronicle.set_game_time(float(i))
			_chronicle.set_fact("hot_key", i)
		guard(_chronicle.get_fact_history("hot_key").size() == counts[ci], "fact_history_hot: %d changes recorded" % counts[ci])
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _r: Array = _chronicle.get_fact_history("hot_key")
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = labels[ci], stats = stats})
		BenchResults.record("micro", "bench_temporal", "fact_history_hot", counts[ci], labels[ci], "us", stats, samples)
	BenchHelper.print_table("micro/temporal :: fact_history_hot", rows, "single key with N changes")


# 5. fact_history cold key — few changes among many entries
func test_bench_fact_history_cold() -> void:
	_chronicle.clear()
	_chronicle.set_game_time(1.0)
	_chronicle.set_fact("cold_key", "first")
	for i: int in range(10000):
		_chronicle.set_game_time(float(i + 2))
		_chronicle.set_fact("noise_%d" % i, i)
	_chronicle.set_game_time(10002.0)
	_chronicle.set_fact("cold_key", "second")
	# Default timeline cap (10000) trims the oldest entries, so cold_key's earliest
	# "first" write is evicted; assert the surviving history reflects the current value.
	guard(_chronicle.get_fact_history("cold_key").back().value == "second", "fact_history_cold: cold key history ends at 'second'")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _r: Array = _chronicle.get_fact_history("cold_key")
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_temporal", "fact_history_cold", 10000, "2 in 10K", "us", stats, samples)
	BenchHelper.print_table("micro/temporal :: fact_history_cold", [{scale_label = "2 in 10K", stats = stats}], "2 entries for key among 10K total timeline entries")
