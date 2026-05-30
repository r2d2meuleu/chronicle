class_name MemoryTracker
extends RefCounted


static func snapshot() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC))


static func delta_since(baseline: int) -> int:
	return snapshot() - baseline


static func assert_no_major_growth(test: Object, baseline: int, max_growth_bytes: int, label: String) -> void:
	var growth := delta_since(baseline)
	test.assert_lte(
		growth, max_growth_bytes,
		"%s: memory grew by %s (limit: %s)" % [label, format_bytes(growth), format_bytes(max_growth_bytes)]
	)


static func format_bytes(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
