extends BenchSuite


const SCALES: Array[int] = [1000, 10000, 50000, 100000]
const LABELS: Array[String] = ["1K", "10K", "50K", "100K"]



# 1. find exact key — single lookup via find()
func test_bench_find_exact() -> void:
	populate_entities(100, 10)
	guard(_chronicle.get_fact_keys("entity_0.prop_0").size() == 1, "find_exact: exact key resolves to 1")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _r: Array = _chronicle.get_fact_keys("entity_0.prop_0")
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_query", "find_exact", 1000, "1K", "us/op", stats, samples)
	BenchHelper.print_table("micro/query :: find_exact", [{scale_label = "1K store", stats = stats}])


# 2. find glob with small bucket — entity index + 10 keys
func test_bench_find_glob_small_bucket() -> void:
	populate_entities(100, 10)
	guard(_chronicle.get_fact_keys("entity_0.*").size() == 10, "find_glob_small_bucket: 10 keys in bucket")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _r: Array = _chronicle.get_fact_keys("entity_0.*")
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_query", "find_glob_small_bucket", 10, "10 props", "us/op", stats, samples)
	BenchHelper.print_table("micro/query :: find_glob_small_bucket", [{scale_label = "10 props", stats = stats}], "entity_0.* with 10 keys in bucket")


# 3. find glob with large bucket — scaling bucket scan
func test_bench_find_glob_large_bucket() -> void:
	var rows: Array = []
	var bucket_sizes: Array[int] = [100, 500]
	var labels: Array[String] = ["100", "500"]
	for bi: int in range(bucket_sizes.size()):
		_chronicle.clear()
		populate_entities(1, bucket_sizes[bi])
		guard(_chronicle.get_fact_keys("entity_0.*").size() == bucket_sizes[bi], "find_glob_large_bucket: bucket has %d keys" % bucket_sizes[bi])
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _r: Array = _chronicle.get_fact_keys("entity_0.*")
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = labels[bi], stats = stats})
		BenchResults.record("micro", "bench_query", "find_glob_large_bucket", bucket_sizes[bi], labels[bi], "us/op", stats, samples)
	BenchHelper.print_table("micro/query :: find_glob_large_bucket", rows, "entity_0.* bucket scan cost")


# 4. find wildcard — full store scan
func test_bench_find_wildcard() -> void:
	var rows: Array = []
	for si: int in range(SCALES.size()):
		var n: int = SCALES[si]
		_chronicle.clear()
		populate_entities(n / 10, 10)
		guard(_chronicle.count_facts("*") == n, "find_wildcard: store has %d keys" % n)
		var samples: Array[float] = BenchHelper.measure(func() -> void:
			var _r: Array = _chronicle.get_fact_keys("*")
		)
		var stats: Dictionary = BenchHelper.compute_stats(samples)
		rows.append({scale_label = LABELS[si], stats = stats})
		BenchResults.record("micro", "bench_query", "find_wildcard", n, LABELS[si], "us/op", stats, samples)
	BenchHelper.print_table("micro/query :: find_wildcard", rows, "O(store_size) full scan")


# 5. count vs find — allocation savings
func test_bench_count_vs_find() -> void:
	populate_entities(1, 100)
	guard(_chronicle.count_facts("entity_0.*") == 100 and _chronicle.get_fact_keys("entity_0.*").size() == 100, "count_vs_find: both report 100 keys")
	var rows: Array = []
	var samples_find: Array[float] = BenchHelper.measure(func() -> void:
		var _r: Array = _chronicle.get_fact_keys("entity_0.*")
	)
	var stats_find: Dictionary = BenchHelper.compute_stats(samples_find)
	rows.append({scale_label = "find", stats = stats_find})
	BenchResults.record("micro", "bench_query", "count_vs_find_find", 100, "find", "us/op", stats_find, samples_find)

	var samples_count: Array[float] = BenchHelper.measure(func() -> void:
		var _r: int = _chronicle.count_facts("entity_0.*")
	)
	var stats_count: Dictionary = BenchHelper.compute_stats(samples_count)
	rows.append({scale_label = "count", stats = stats_count})
	BenchResults.record("micro", "bench_query", "count_vs_find_count", 100, "count", "us/op", stats_count, samples_count)
	BenchHelper.print_table("micro/query :: count vs find (100 keys)", rows)


# 6. first_change shallow — early match in timeline
func test_bench_first_change_shallow() -> void:
	for i: int in range(10000):
		_chronicle.set_game_time(float(i) * 0.01)
		_chronicle.set_fact("key_%d" % (i % 100), i)
	guard(_chronicle.get_first_change("key_0") != null, "first_change_shallow: key_0 has a first change")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _r: Variant = _chronicle.get_first_change("key_0")
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_query", "first_change_shallow", 10000, "t=0.0", "us/op", stats, samples)
	BenchHelper.print_table("micro/query :: first_change_shallow", [{scale_label = "10K tl", stats = stats}], "key_0 first appears at t=0")


# 7. first_change deep — late match in timeline
func test_bench_first_change_deep() -> void:
	_chronicle.clear()
	for i: int in range(9990):
		_chronicle.set_game_time(float(i) * 0.01)
		_chronicle.set_fact("filler_%d" % i, i)
	_chronicle.set_game_time(99.9)
	_chronicle.set_fact("late_key", 999)
	guard(_chronicle.get_first_change("late_key") != null, "first_change_deep: late_key has a first change")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _r: Variant = _chronicle.get_first_change("late_key")
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_query", "first_change_deep", 10000, "t=99.9", "us/op", stats, samples)
	BenchHelper.print_table("micro/query :: first_change_deep", [{scale_label = "10K tl", stats = stats}], "late_key appears near end of 10K timeline")
