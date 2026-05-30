extends RefCounted

const WARMUP: int = 20
const ITERATIONS: int = 200
const FRAME_BUDGET_US: float = 16600.0

enum TableKind { STRESS, FRAME, TABLE }

const BenchResults := preload("res://test/benchmarks/core/bench_results.gd")


static func compute_stats(samples: Array) -> Dictionary:
	var sorted: Array = samples.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	if n == 0:
		return {min=0.0, p5=0.0, p25=0.0, median=0.0, p75=0.0, p95=0.0, max=0.0,
			mean=0.0, stddev=0.0, valid=false, count=0}

	var total: float = 0.0
	for s in sorted:
		total += float(s)
	var mean: float = total / float(n)

	var variance: float = 0.0
	for s in sorted:
		var diff: float = float(s) - mean
		variance += diff * diff
	variance /= float(n)
	var stddev: float = sqrt(variance)

	return {
		min = float(sorted[0]),
		p5 = _percentile(sorted, 0.05),
		p25 = _percentile(sorted, 0.25),
		median = _percentile(sorted, 0.50),
		p75 = _percentile(sorted, 0.75),
		p95 = _percentile(sorted, 0.95),
		max = float(sorted[n - 1]),
		mean = mean,
		stddev = stddev,
		valid = true,
		count = n,
	}


## Linear-interpolated percentile over a pre-sorted array. q in [0,1].
static func _percentile(sorted: Array, q: float) -> float:
	var n: int = sorted.size()
	if n == 1:
		return float(sorted[0])
	var pos: float = clampf(q, 0.0, 1.0) * float(n - 1)
	var lo: int = int(floor(pos))
	var hi: int = int(ceil(pos))
	var frac: float = pos - float(lo)
	return lerpf(float(sorted[lo]), float(sorted[hi]), frac)


static func print_table(title: String, rows: Array, note: String = "") -> void:
	print("")
	print("[bench] %s" % title)
	print("  %-6s |  %5s |  %5s |  %5s |  %5s |  %5s |  mean +/- std" % [
		"scale", "min", "p5", "med", "p95", "max"])
	print("  -------+--------+--------+--------+--------+--------+--------------")
	for row: Dictionary in rows:
		print("  %-6s | %5.1f  | %5.1f  | %5.1f  | %5.1f  | %5.1f  | %5.1f +/- %.1f us" % [
			row.scale_label,
			row.stats.min, row.stats.p5, row.stats.median,
			row.stats.p95, row.stats.max,
			row.stats.mean, row.stats.stddev])
	if not note.is_empty():
		print("  note: %s" % note)


static func print_frame_table(title: String, rows: Array, note: String = "") -> void:
	print("")
	print("[bench] %s" % title)
	print("  %-6s |  med/frame | frames/ms | %% of %.1fms" % ["scale", FRAME_BUDGET_US / 1000.0])
	print("  -------+------------+-----------+-------------")
	for row: Dictionary in rows:
		var med: float = row.stats.median
		var frames_per_ms: int = int(1000.0 / maxf(1.0, med))
		var pct: float = (med / FRAME_BUDGET_US) * 100.0
		print("  %-6s |  %6.1f us |    %5d  |    %.1f%%" % [
			row.scale_label, med, frames_per_ms, pct])
	if not note.is_empty():
		print("  note: %s" % note)


static func print_stress_table(title: String, rows: Array, scale_col: String = "scale", note: String = "") -> void:
	print("")
	print("[bench] %s" % title)
	print("  %-9s |  %5s |  %5s |  %5s |  %5s | scaling" % [
		scale_col, "min", "med", "p95", "max"])
	print("  ----------+--------+--------+--------+--------+---------")
	for i: int in range(rows.size()):
		var row: Dictionary = rows[i]
		var scaling_str: String = "   --"
		if i > 0 and rows[i - 1].stats.median > 0:
			var factor: float = float(row.stats.median) / float(rows[i - 1].stats.median)
			scaling_str = "  %.1fx" % factor
			if factor > 2.0:
				scaling_str += "  <- knee"
		print("  %9s | %5.1f  | %5.1f  | %5.1f  | %5.1f  | %s" % [
			row.scale_label,
			row.stats.min, row.stats.median, row.stats.p95, row.stats.max,
			scaling_str])
	if not note.is_empty():
		print("  note: %s" % note)


static func measure(callable: Callable, iterations: int = ITERATIONS, warmup: int = WARMUP) -> Array[float]:
	for _w: int in range(warmup):
		callable.call()
	var samples: Array[float] = []
	samples.resize(iterations)
	for i: int in range(iterations):
		var t0: int = Time.get_ticks_usec()
		callable.call()
		samples[i] = float(Time.get_ticks_usec() - t0)
	return samples


## Like measure(), but passes the iteration index to the op so it can write a
## value that genuinely CHANGES each call. Use for any op whose cost depends on a
## real state change (watcher/cascade/reactor dispatch) — an unchanged-value write
## is short-circuited by the write coordinator and would measure a no-op.
## op: func(i: int) -> void
static func measure_each(op: Callable, iterations: int = ITERATIONS, warmup: int = WARMUP) -> Array[float]:
	for w: int in range(warmup):
		op.call(-1 - w)
	var samples: Array[float] = []
	samples.resize(iterations)
	for i: int in range(iterations):
		var t0: int = Time.get_ticks_usec()
		op.call(i)
		samples[i] = float(Time.get_ticks_usec() - t0)
	return samples


static func measure_batched(callable: Callable, batch_size: int, iterations: int = ITERATIONS, warmup: int = WARMUP) -> Array[float]:
	assert(batch_size > 0, "measure_batched: batch_size must be > 0")
	for _w: int in range(warmup):
		callable.call()
	var samples: Array[float] = []
	samples.resize(iterations)
	for i: int in range(iterations):
		var t0: int = Time.get_ticks_usec()
		callable.call()
		samples[i] = float(Time.get_ticks_usec() - t0) / float(batch_size)
	return samples


## Runs a scale loop: for each scale, setup_fn(scale) then measures op_fn, records,
## accumulates a row, and prints the appropriate table. Eliminates the repeated
## clear/populate/measure/stats/record/row/print boilerplate.
## setup_fn: func(scale: int) -> void   op_fn: func() -> void
## guard_fn: optional func(scale: int) -> void. Takes the current scale (int) and
## runs for EVERY scale, outside the timed region, so a correctness check verifies
## each scale's setup without perturbing the timed loop.
static func run_scale_bench(tier: String, suite: String, bench_name: String, unit: String,
		scales: Array, labels: Array, setup_fn: Callable, op_fn: Callable,
		table_kind: TableKind = TableKind.STRESS, batch_size: int = 0, note: String = "",
		guard_fn: Callable = Callable(), scale_col: String = "scale") -> void:
	assert(scales.size() == labels.size())
	var rows: Array = []
	for si: int in range(scales.size()):
		setup_fn.call(scales[si])
		if guard_fn.is_valid():
			guard_fn.call(scales[si])
		var samples: Array = (measure_batched(op_fn, batch_size) if batch_size > 0 else measure(op_fn))
		var stats: Dictionary = compute_stats(samples)
		rows.append({scale_label = labels[si], stats = stats})
		BenchResults.record(tier, suite, bench_name, scales[si], labels[si], unit, stats, samples)
	var title: String = "%s/%s :: %s" % [tier, suite, bench_name]
	match table_kind:
		TableKind.STRESS: print_stress_table(title, rows, scale_col, note)
		TableKind.FRAME: print_frame_table(title, rows, note)
		_: print_table(title, rows, note)
