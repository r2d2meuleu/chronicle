extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")


# AST cache thrashing — 300 expressions exceed 256 cache capacity
func test_ast_cache_thrashing() -> void:
	for i in 300:
		_chronicle.set_fact("expr_%d.val" % i, i)
	for i in 300:
		var expr := "expr_%d.val >= 0" % i
		var result = _chronicle.evaluate(expr)
		assert_true(result, "Expression %d should evaluate true" % i)
	for i in 300:
		var expr := "expr_%d.val >= 0" % i
		var result = _chronicle.evaluate(expr)
		assert_true(result, "Re-evaluation %d should still be correct after cache eviction" % i)


# Wide AND chain with 100 terms — all must be true
func test_wide_and_chain_100() -> void:
	_run_wide_and(100)


# Wide AND chain with 1000 terms
func test_wide_and_chain_1000() -> void:
	_run_wide_and(1000)


func _run_wide_and(count: int) -> void:
	for i in count:
		_chronicle.set_fact("and_%d.v" % i, true)
	var parts: PackedStringArray = []
	for i in count:
		parts.append("and_%d.v" % i)
	var expr := " AND ".join(parts)
	var result = _chronicle.evaluate(expr)
	assert_true(result, "%d-term AND should be true when all terms are true" % count)
	_chronicle.set_fact("and_0.v", false)
	result = _chronicle.evaluate(expr)
	assert_false(result, "AND should short-circuit to false when first term is false")


# Deep NOT nesting at depth 30 (each NOT+parens = 2 depth, so 60 total, under MAX_DEPTH=64)
func test_deep_not_nesting() -> void:
	_chronicle.set_fact("deep.val", true)
	var expr := "deep.val"
	for i in 30:
		expr = "NOT (%s)" % expr
	var result = _chronicle.evaluate(expr)
	assert_eq(typeof(result), TYPE_BOOL)


# Depth limit rejection at 65 levels of parens
func test_depth_limit_rejection() -> void:
	_chronicle.set_fact("limit.val", true)
	var expr := "limit.val"
	for i in 65:
		expr = "(%s)" % expr
	var result = _chronicle.evaluate(expr)
	assert_null(result, "Should return null on parse error at depth > 64")


# 300 Gate nodes with distinct conditions — AST cache thrash + bulk re-evaluation
func test_many_gates_distinct_conditions() -> void:
	for i in 300:
		_chronicle.set_fact("gkey_%d.val" % i, i)
	var targets: Array[Node2D] = []
	for i in 300:
		var target := add_gate("gkey_%d.val >= %d" % [i, i])
		targets.append(target)
	for i in 300:
		assert_gate_open(targets[i])
	_chronicle.set_fact("gkey_0.val", -1)
	assert_gate_closed(targets[0])
	assert_gate_open(targets[1])


# Regex cache thrashing — 600 MATCHES expressions exceed 512 cache
func test_regex_cache_thrashing() -> void:
	for i in 600:
		_chronicle.set_fact("rx_%d.name" % i, "item_%d" % i)
	for i in 600:
		var expr := "rx_%d.name MATCHES \"item_%d\"" % [i, i]
		assert_true(_chronicle.evaluate(expr), "MATCHES should succeed for entry %d" % i)


# IN with large literal array
func test_in_large_array() -> void:
	_chronicle.set_fact("search.val", 500)
	var items: PackedStringArray = []
	for i in 1000:
		items.append(str(i))
	var expr := "search.val IN [%s]" % ", ".join(items)
	assert_true(_chronicle.evaluate(expr), "500 should be IN [0..999]")
	_chronicle.set_fact("search.val", 1001)
	assert_false(_chronicle.evaluate(expr), "1001 should NOT be IN [0..999]")


# Fact-to-fact comparisons at scale
func test_fact_to_fact_at_scale() -> void:
	for i in 1000:
		_chronicle.set_fact("left_%d.gold" % i, i * 10)
		_chronicle.set_fact("right_%d.debt" % i, i * 5)
	for i in 1000:
		var expr := "left_%d.gold >= right_%d.debt" % [i, i]
		assert_true(_chronicle.evaluate(expr), "gold (%d) >= debt (%d) for entry %d" % [i * 10, i * 5, i])
