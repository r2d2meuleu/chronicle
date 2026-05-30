extends ChronicleTestSuite


# Within-range value is unchanged, no event fires
func test_within_range_no_op() -> void:
	_chronicle.set_fact("score", 50)
	var c := watch_events("score")
	_chronicle.clamp_fact("score", 0.0, 100.0)
	c.assert_count(0)
	assert_fact("score", 50)


# Below min clamps up to min
func test_below_min_clamps_up() -> void:
	_chronicle.set_fact("score", -10)
	_chronicle.clamp_fact("score", 0.0, 100.0)
	assert_fact("score", 0)


# Above max clamps down to max
func test_above_max_clamps_down() -> void:
	_chronicle.set_fact("score", 150)
	_chronicle.clamp_fact("score", 0.0, 100.0)
	assert_fact("score", 100)


# Non-numeric value is left unchanged
func test_non_numeric_no_op() -> void:
	_chronicle.set_fact("name", "hello")
	_chronicle.clamp_fact("name", 0.0, 100.0)
	assert_fact("name", "hello")


# Absent key is a no-op
func test_absent_key_no_op() -> void:
	_chronicle.clamp_fact("missing", 0.0, 100.0)
	assert_no_fact("missing")


# NaN bounds are rejected, value unchanged
func test_nan_bounds_rejected() -> void:
	_chronicle.set_fact("score", 50)
	_chronicle.clamp_fact("score", NAN, 100.0)
	assert_fact("score", 50)
