extends ChronicleTestSuite


# Deep-copy isolation on write (Dictionary)
# Set a Dictionary fact, mutate the original dict after set_fact.
# Verify _store is NOT corrupted.
func test_deep_copy_isolation_dict_on_write() -> void:
	var original: Dictionary = {"hp": 100, "nested": {"armor": 5}}
	_chronicle.set_fact("player.stats", original)

	# Mutate the original AFTER writing
	original["hp"] = 0
	original["nested"]["armor"] = 999
	original["new_key"] = "injected"

	# The store should still have the original values
	assert_fact("player.stats", {"hp": 100, "nested": {"armor": 5}})


# Deep-copy isolation on write (Array)
func test_deep_copy_isolation_array_on_write() -> void:
	var original: Array = [1, 2, [3, 4]]
	_chronicle.set_fact("data.list", original)

	# Mutate after writing
	original.append(99)
	original[2].append(5)

	assert_fact("data.list", [1, 2, [3, 4]])


# Deep-copy on read (Dictionary)
# Get a Dictionary fact via get_fact(), mutate the returned dict.
# Verify _store is NOT corrupted.
func test_deep_copy_on_read_dict() -> void:
	_chronicle.set_fact("player.inventory", {"sword": 1, "shield": 1})

	var returned: Variant = _chronicle.get_fact("player.inventory")
	assert_true(returned is Dictionary)

	# Mutate the returned value
	returned["sword"] = 999
	returned["poison"] = true

	# Re-read to verify store is unchanged
	assert_fact("player.inventory", {"sword": 1, "shield": 1})


# Deep-copy on read (Array)
func test_deep_copy_on_read_array() -> void:
	_chronicle.set_fact("data.items", ["a", "b", "c"])

	var returned: Variant = _chronicle.get_fact("data.items")
	returned.append("INJECTED")

	assert_fact("data.items", ["a", "b", "c"])


# Timeline deep-copy isolation
func test_timeline_deep_copy_isolation() -> void:
	_chronicle.set_fact("player.gear", {"helm": "iron", "boots": "leather"})

	var history: Array[Dictionary] = _chronicle.get_fact_history("player.gear")
	assert_gte(history.size(), 1, "timeline must have at least one entry")

	if history.size() >= 1:
		# Mutate the returned entry's value
		var entry_value: Variant = history[0].value
		if entry_value is Dictionary:
			entry_value["helm"] = "CORRUPTED"
			entry_value["injected"] = true

		# Re-fetch and check timeline is unmodified
		var history2: Array[Dictionary] = _chronicle.get_fact_history("player.gear")
		if history2.size() >= 1 and history2[0].value is Dictionary:
			assert_eq(history2[0].value.get("helm"), "iron")
			assert_does_not_have(history2[0].value, "injected")
		else:
			fail_test("timeline entry value should be a Dictionary")


# Concurrent writes to same key (1000 times)
func test_concurrent_writes_same_key() -> void:
	for i: int in range(1000):
		_chronicle.set_fact("stress.counter", i)

	# Final value should be 999
	assert_fact("stress.counter", 999)

	# Timeline should have 1000 entries for this key
	var history: Array[Dictionary] = _chronicle.get_fact_history("stress.counter")
	assert_eq(history.size(), 1000)

	# Verify timeline ordering
	if history.size() >= 1:
		assert_eq(history[0].value, 0)
		assert_eq(history[history.size() - 1].value, 999)


# Erase + re-set roundtrip
func test_erase_re_set_roundtrip() -> void:
	_chronicle.set_fact("a.b", 1)
	assert_fact("a.b", 1)

	_chronicle.erase_fact("a.b")
	assert_no_fact("a.b")

	# Entity index should be gone
	assert_eq(_chronicle.get_fact_keys("a.*").size(), 0)

	_chronicle.set_fact("a.b", 2)
	assert_fact("a.b", 2)

	# Entity index should be back
	assert_eq(_chronicle.get_fact_keys("a.*").size(), 1)

	# Timeline should have 3 entries: set(1), erase(null), set(2)
	assert_history("a.b", [1, null, 2])


# Transient flag lifecycle
func test_transient_flag_locking() -> void:
	_chronicle.set_fact("player.temp", 1, true, 0.0)
	# Verify transient: key is in memory but excluded from serialization
	assert_does_not_have(_chronicle.serialize()["facts"], "player.temp", "transient key excluded from serialize")

	# Second write with transient=false should clear transient (C1 fix)
	_chronicle.set_fact("player.temp", 2)
	assert_has(_chronicle.serialize()["facts"], "player.temp", "non-transient key included after re-set")

	# Verify value updated
	assert_eq(_chronicle.get_fact("player.temp"), 2)

	# Serialize — non-transient key must be included
	var data: Dictionary = _chronicle.serialize()
	assert_has(data["facts"], "player.temp", "non-transient key present in serialize")

	# Re-setting as transient again should exclude from serialization
	_chronicle.set_fact("player.temp", 3, true, 0.0)
	assert_eq(_chronicle.get_fact("player.temp"), 3)
	var data2: Dictionary = _chronicle.serialize()
	assert_does_not_have(data2["facts"], "player.temp", "re-marked transient key excluded again")


# Normalize/denormalize roundtrip (dotless keys)
func test_normalize_denormalize_roundtrip() -> void:
	_chronicle.set_fact("flag", true)

	# Deliberate assert_eq(..., true): the dotless key must resolve to the real bool true.
	assert_eq(_chronicle.get_fact("flag"), true, "dotless flag resolves to bool true")
	assert_true(_chronicle.has_fact("flag"))

	# find("*") should return "flag" not "_global.flag"
	var all: Array[String] = _chronicle.get_fact_keys("*")
	assert_has(all, "flag")
	assert_does_not_have(all, "_global.flag")

	# fact_history should work with the dotless key
	var history: Array[Dictionary] = _chronicle.get_fact_history("flag")
	assert_gte(history.size(), 1, "dotless key must have history")
	if history.size() >= 1:
		assert_eq(history[0].key, "flag")
		# Deliberate assert_eq(..., true): the recorded value is the real bool true.
		assert_eq(history[0].value, true, "history entry value is bool true")


# All 6 types serialize/deserialize roundtrip
func test_all_six_types_serialize_roundtrip() -> void:
	_chronicle.set_fact("t.bool_val", false)
	_chronicle.set_fact("t.int_val", -42)
	_chronicle.set_fact("t.float_val", 2.718281828)
	_chronicle.set_fact("t.str_val", "hello world")
	_chronicle.set_fact("t.arr_val", [true, 1, 2.5, "x", [10], {"k": "v"}])
	_chronicle.set_fact("t.dict_val", {"a": 1, "b": [2, 3], "c": {"d": true}})

	var c2 := serialize_into_new()

	# bool
	var v_bool: Variant = c2.get_fact("t.bool_val")
	# Deliberate assert_eq(..., false) + TYPE_BOOL: verifies bool fidelity, not just falsiness.
	assert_eq(v_bool, false, "bool roundtrips as bool false")
	assert_eq(typeof(v_bool), TYPE_BOOL)

	# int — NOTE: JSON round-trips whole numbers as float in Godot, so int may become float.
	var v_int: Variant = c2.get_fact("t.int_val")
	assert_eq(v_int, -42)

	# float
	var v_float: Variant = c2.get_fact("t.float_val")
	assert_almost_eq(v_float, 2.718281828, 0.0001)

	# String
	var v_str: Variant = c2.get_fact("t.str_val")
	assert_eq(v_str, "hello world")
	assert_eq(typeof(v_str), TYPE_STRING)

	# Array
	var v_arr: Variant = c2.get_fact("t.arr_val")
	assert_true(v_arr is Array)
	assert_eq(v_arr.size(), 6)

	# Dictionary
	var v_dict: Variant = c2.get_fact("t.dict_val")
	assert_true(v_dict is Dictionary)
	assert_eq(v_dict.get("a"), 1)
	assert_true(v_dict.get("b") is Array)
	assert_true(v_dict.get("c") is Dictionary)


# Rejected types (parameterized)
var _rejected_type_params = ParameterFactory.named_parameters(
	["key", "value"],
	[
		["bad.rid", RID()],
	]
)

func test_rejected_type(p = use_parameters(_rejected_type_params)) -> void:
	_chronicle.set_fact(p.key, p.value)
	assert_no_fact(p.key)


# Rejected types: store unchanged after all rejections
func test_rejected_types_store_unchanged() -> void:
	_chronicle.set_fact("safe.value", 42)
	var count_before: int = _chronicle.get_fact_keys("*").size()

	_chronicle.set_fact("bad.rid", RID())

	assert_eq(_chronicle.get_fact_keys("*").size(), count_before)
	assert_eq(_chronicle.get_fact("safe.value"), 42)

# Trim direction — newest entries preserved, oldest dropped
func test_trim_preserves_newest_drops_oldest() -> void:
	for i: int in range(11001):
		_chronicle.set_fact("dir.key%d" % i, i)
	assert_eq(_chronicle.get_stats().timeline_size, 10000,
		"timeline trimmed to exactly 10000")
	var first: Variant = _chronicle.get_first_change("*")
	assert_not_null(first)
	assert_eq(first.value, 1001,
		"first surviving entry is value 1001 (oldest 1001 dropped)")
	var last: Variant = _chronicle.get_last_change("*")
	assert_not_null(last)
	assert_eq(last.value, 11000,
		"last entry is value 11000 (the final write)")

# NaN and INF as fact values
func test_nan_inf_fact_values() -> void:
	_chronicle.set_fact("val.nan", NAN)
	assert_true(_chronicle.has_fact("val.nan"), "NaN stored as fact")
	assert_true(is_nan(_chronicle.get_fact("val.nan")), "NaN retrieved correctly")

	_chronicle.set_fact("val.inf", INF)
	assert_true(_chronicle.has_fact("val.inf"), "INF stored as fact")
	assert_true(is_inf(_chronicle.get_fact("val.inf")), "INF retrieved correctly")

	var c2 := serialize_into_new()
	var nan_after: Variant = c2.get_fact("val.nan")
	var inf_after: Variant = c2.get_fact("val.inf")
	# In-memory serialize/deserialize is lossless for NaN/INF (deep_copy preserves them).
	assert_true(is_nan(nan_after), "NaN fact survives the in-memory roundtrip exactly")
	assert_true(is_inf(inf_after) and inf_after > 0, "INF fact survives the in-memory roundtrip exactly")

# Store 10k warning path
func test_store_10k_warning_path() -> void:
	for i in range(10000):
		_chronicle.set_fact("bulk.key%d" % i, i)
	assert_fact_count("*", 10000)
	_chronicle.set_fact("bulk.extra", true)
	assert_fact("bulk.extra", true)

# Multiple trim cycles — 22000 appends trigger 11 trims
func test_multiple_trim_cycles() -> void:
	for i: int in range(22000):
		_chronicle.set_fact("multi.k%d" % i, i)
	assert_eq(_chronicle.get_stats().timeline_size, 10000,
		"after trim cycles, timeline has 10000 entries (cap)")
	var first: Variant = _chronicle.get_first_change("*")
	assert_not_null(first)
	assert_eq(first.value, 12000,
		"first surviving entry is value 12000")
	var last: Variant = _chronicle.get_last_change("*")
	assert_not_null(last)
	assert_eq(last.value, 21999,
		"last entry is value 21999 (the final write)")


# get_value returns independent copy (Dictionary)
# Two consecutive reads must be fully independent — mutating one must not
# affect the other or the store.
func test_get_value_returns_independent_copy_dict() -> void:
	_chronicle.set_fact("isolation.dict", {"x": 1, "nested": [10, 20]})
	var a: Variant = _chronicle.get_fact("isolation.dict")
	var b: Variant = _chronicle.get_fact("isolation.dict")
	assert_true(a is Dictionary)
	assert_true(b is Dictionary)
	a["x"] = 999
	a["nested"].append(30)
	a["injected"] = true
	assert_eq(b.get("x"), 1)
	assert_eq(b.get("nested"), [10, 20])
	assert_does_not_have(b, "injected")
	assert_fact("isolation.dict", {"x": 1, "nested": [10, 20]})


# get_value returns independent copy (Array)
func test_get_value_returns_independent_copy_array() -> void:
	_chronicle.set_fact("isolation.array", [1, 2, [3, 4]])
	var a: Variant = _chronicle.get_fact("isolation.array")
	assert_true(a is Array)
	a.append(99)
	a[2].append(5)
	assert_fact("isolation.array", [1, 2, [3, 4]])
