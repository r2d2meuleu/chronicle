extends ChronicleTestSuite

# ── Store Scale Tests ──
# Validates Chronicle store correctness and performance at enterprise scale.
# Every test asserts correct values first, timing second.

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")


# Bulk write at indie scale — baseline correctness
func test_bulk_write_small() -> void:
	var tier := ScaleHelper.SMALL
	ScaleHelper.generate_entity_facts(_chronicle, tier.facts / 5, 5)
	assert_fact_count("*", tier.facts)
	for i in 10:
		# key_0 of entity i was generated from seed (i * keys_per_entity + 0) = i * 5.
		var expected: Variant = ScaleHelper._random_value(i * 5)
		assert_fact("entity_%d.key_0" % i, expected)


# Bulk write at mid-production scale
func test_bulk_write_medium() -> void:
	var tier := ScaleHelper.MEDIUM
	var entities: int = tier.facts / 5
	ScaleHelper.generate_entity_facts(_chronicle, entities, 5)
	assert_fact_count("*", tier.facts)
	# Spot-check computed values for the first and last entity.
	# entity e, key_k was generated from seed (e * keys_per_entity + k), keys_per_entity = 5.
	assert_fact("entity_0.key_0", ScaleHelper._random_value(0))
	var last: int = entities - 1
	assert_fact("entity_%d.key_4" % last, ScaleHelper._random_value(last * 5 + 4))


# Bulk write at large open-world scale
func test_bulk_write_large() -> void:
	var tier := ScaleHelper.LARGE
	var entities: int = tier.facts / 5
	ScaleHelper.generate_entity_facts(_chronicle, entities, 5)
	assert_fact_count("*", tier.facts)
	# Spot-check computed values for the first and last entity.
	assert_fact("entity_0.key_0", ScaleHelper._random_value(0))
	var last: int = entities - 1
	assert_fact("entity_%d.key_4" % last, ScaleHelper._random_value(last * 5 + 4))


# Bulk write at enterprise ceiling
func test_bulk_write_extreme() -> void:
	var tier := ScaleHelper.EXTREME
	var entities: int = tier.facts / 5
	ScaleHelper.generate_entity_facts(_chronicle, entities, 5)
	assert_fact_count("*", tier.facts)
	# Spot-check computed values for the first and last entity.
	assert_fact("entity_0.key_0", ScaleHelper._random_value(0))
	var last: int = entities - 1
	assert_fact("entity_%d.key_4" % last, ScaleHelper._random_value(last * 5 + 4))


# Read-back correctness after bulk write
func test_bulk_read_after_write() -> void:
	var count := 10000
	var expected := {}
	for i in count:
		var key := "read_%d.val" % i
		var val := i * 3
		_chronicle.set_fact(key, val)
		expected[key] = val
	for key in expected:
		assert_fact(key, expected[key])


# Overwrite all facts with new values
func test_overwrite_churn() -> void:
	var count := 10000
	for i in count:
		_chronicle.set_fact("churn_%d.v" % i, i)
	for i in count:
		_chronicle.set_fact("churn_%d.v" % i, i + count)
	for i in count:
		assert_fact("churn_%d.v" % i, i + count)


# Mixed value types at scale
func test_mixed_value_types() -> void:
	ScaleHelper.generate_mixed_type_facts(_chronicle, 10000)
	assert_fact_count("*", 10000)
	assert_eq(typeof(_chronicle.get_fact("mixed_0.fact")), TYPE_BOOL)
	assert_eq(typeof(_chronicle.get_fact("mixed_1.fact")), TYPE_INT)
	assert_eq(typeof(_chronicle.get_fact("mixed_2.fact")), TYPE_FLOAT)
	assert_eq(typeof(_chronicle.get_fact("mixed_3.fact")), TYPE_STRING)
	assert_eq(typeof(_chronicle.get_fact("mixed_4.fact")), TYPE_ARRAY)
	assert_eq(typeof(_chronicle.get_fact("mixed_5.fact")), TYPE_DICTIONARY)


# Nested dictionaries stress deep_copy
func test_nested_dict_values() -> void:
	for i in 1000:
		var nested := ScaleHelper.generate_nested_value(3, 3)
		_chronicle.set_fact("nested_%d.data" % i, nested)
	for i in 1000:
		var retrieved: Dictionary = _chronicle.get_fact("nested_%d.data" % i)
		assert_has(retrieved, "branch_0")
		assert_has(retrieved["branch_0"], "branch_0")
		assert_has(retrieved["branch_0"]["branch_0"], "branch_0")
		assert_eq(retrieved["branch_0"]["branch_0"]["branch_0"]["leaf"], true)
	var original: Dictionary = _chronicle.get_fact("nested_0.data")
	original["branch_0"] = "mutated"
	var fresh: Dictionary = _chronicle.get_fact("nested_0.data")
	assert_true(fresh["branch_0"] is Dictionary, "Deep copy prevents aliasing")


# Erase all facts at scale
func test_erase_at_scale() -> void:
	ScaleHelper.generate_entity_facts(_chronicle, 10000, 5)
	assert_fact_count("*", 50000)
	var keys = _chronicle.get_fact_keys("*")
	for key in keys:
		_chronicle.erase_fact(key)
	assert_fact_count("*", 0)


# Hard cap rejects writes beyond limit
func test_hard_cap_rejection() -> void:
	_chronicle.set_store_hard_cap(1000)
	for i in 1000:
		_chronicle.set_fact("cap_%d.v" % i, i)
	assert_fact_count("*", 1000)
	_chronicle.set_fact("cap_overflow.v", 999)
	assert_no_fact("cap_overflow.v")
	assert_fact("cap_0.v", 0)
	_chronicle.set_store_hard_cap(0)


# Repeated get_fact_keys("*") allocation pressure
func test_keys_allocation_pressure() -> void:
	ScaleHelper.generate_entity_facts(_chronicle, 10000, 5)
	for i in 100:
		var keys = _chronicle.get_fact_keys("*")
		assert_eq(keys.size(), 50000)


# Entity-partitioned access via pattern query
func test_entity_partitioned_access() -> void:
	ScaleHelper.generate_entity_facts(_chronicle, 100, 100)
	var keys = _chronicle.get_fact_keys("entity_50.*")
	assert_eq(keys.size(), 100)
	for key in keys:
		assert_true(key.begins_with("entity_50."), "Key %s should start with entity_50." % key)
