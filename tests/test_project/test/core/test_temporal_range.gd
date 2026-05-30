extends ChronicleTestSuite


# changes_between returns entries in (since, until] window (exclusive lower, inclusive upper)
func test_changes_between_basic_window() -> void:
	set_time(0.0)
	_chronicle.set_fact("player.a", 1)
	set_time(5.0)
	_chronicle.set_fact("player.b", 2)
	set_time(10.0)
	_chronicle.set_fact("player.c", 3)
	set_time(15.0)
	_chronicle.set_fact("player.d", 4)

	var result: Array[Dictionary] = _chronicle.get_changes_between(4.0, 10.0)
	assert_eq(result.size(), 2, "window (4,10] returns 2 entries (at t=5 and t=10)")
	assert_eq(result[0].key as String, "player.b")
	assert_eq(result[0].value, 2)
	assert_eq(result[0].time, 5.0)
	assert_eq(result[1].key as String, "player.c")
	assert_eq(result[1].value, 3)
	assert_eq(result[1].time, 10.0)


# changes_between excludes entry at since_time (exclusive lower bound)
func test_excludes_since_time() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(10.0)
	_chronicle.set_fact("player.gold", 50)

	var result: Array[Dictionary] = _chronicle.get_changes_between(5.0, 15.0)
	assert_eq(result.size(), 1, "(5,15] excludes entry at t=5, includes t=10")
	assert_eq(result[0].key as String, "player.gold")


# changes_between includes entry at until_time (inclusive upper bound)
func test_includes_until_time() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(10.0)
	_chronicle.set_fact("player.gold", 50)

	var result: Array[Dictionary] = _chronicle.get_changes_between(0.0, 10.0)
	assert_eq(result.size(), 2, "[0,10] includes entry at t=10")
	assert_eq(result[0].key as String, "player.hp")
	assert_eq(result[1].key as String, "player.gold")


# changes_between returns {key, value, old_value, time} format (tick hidden from public API)
func test_return_format() -> void:
	set_time(3.0)
	_chronicle.set_fact("quest.done", true)

	var result: Array[Dictionary] = _chronicle.get_changes_between(0.0, 5.0)
	assert_eq(result.size(), 1)
	var entry: Dictionary = result[0]
	assert_has(entry, "key")
	assert_has(entry, "value")
	assert_has(entry, "old_value")
	assert_has(entry, "time")
	assert_eq(entry.size(), 4, "key, value, old_value, time")
	assert_eq(entry.key as String, "quest.done")
	assert_eq(entry.value, true, "timeline entry value should be bool true")
	assert_eq(entry.time, 3.0)


# changes_between on empty timeline returns []
func test_empty_timeline() -> void:
	var result: Array[Dictionary] = _chronicle.get_changes_between(0.0, 10.0)
	assert_eq(result.size(), 0, "empty timeline returns []")


# Window before all entries returns []
func test_window_before_all_entries() -> void:
	set_time(10.0)
	_chronicle.set_fact("player.hp", 100)
	var result: Array[Dictionary] = _chronicle.get_changes_between(0.0, 5.0)
	assert_eq(result.size(), 0, "window before entries returns []")


# Window after all entries returns []
func test_window_after_all_entries() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)
	var result: Array[Dictionary] = _chronicle.get_changes_between(10.0, 20.0)
	assert_eq(result.size(), 0, "window after entries returns []")


# since_time == until_time returns empty (half-open: (5,5] is empty)
func test_same_time_interval() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)
	var result: Array[Dictionary] = _chronicle.get_changes_between(5.0, 5.0)
	assert_eq(result.size(), 0, "(5,5] is empty — exclusive lower bound")


# Inverted range (since > until) returns []
func test_inverted_range() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)
	var result: Array[Dictionary] = _chronicle.get_changes_between(10.0, 5.0)
	assert_eq(result.size(), 0, "inverted range returns []")


# NaN in since_time returns []
func test_nan_since_time() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)
	var result: Array[Dictionary] = _chronicle.get_changes_between(NAN, 10.0)
	assert_eq(result.size(), 0, "NaN since_time returns []")


# NaN in until_time returns []
func test_nan_until_time() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)
	var result: Array[Dictionary] = _chronicle.get_changes_between(0.0, NAN)
	assert_eq(result.size(), 0, "NaN until_time returns []")


# INF as since_time returns []
func test_inf_since_time() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)
	var result: Array[Dictionary] = _chronicle.get_changes_between(INF, INF)
	assert_eq(result.size(), 0, "INF since_time returns []")


# INF as until_time is rejected (returns [])
func test_inf_until_time() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(10.0)
	_chronicle.set_fact("player.gold", 50)
	var result: Array[Dictionary] = _chronicle.get_changes_between(5.0, INF)
	assert_eq(result.size(), 0, "INF until_time returns []")


# Negative since_time is rejected — returns empty
func test_negative_since_time() -> void:
	set_time(0.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(5.0)
	_chronicle.set_fact("player.gold", 50)
	var result: Array[Dictionary] = _chronicle.get_changes_between(-10.0, 3.0)
	assert_eq(result.size(), 0, "negative since_time is rejected — returns empty")


# Same-timestamp cluster at since_time — all included, plus until_time entry
func test_same_timestamp_cluster_at_since() -> void:
	set_time(5.0)
	_chronicle.set_facts({"player.a": 1, "player.b": 2, "player.c": 3})
	set_time(10.0)
	_chronicle.set_fact("player.d", 4)
	# get_changes_between uses half-open interval (since, until] — exclusive lower bound.
	# Entries at t=5.0 are excluded, only t=10.0 entry is included.
	var result: Array[Dictionary] = _chronicle.get_changes_between(5.0, 10.0)
	assert_eq(result.size(), 1, "only entry at t=10 included — t=5 excluded by (since, until]")


# Same-timestamp cluster at until_time — all included (closed interval)
func test_same_timestamp_cluster_at_until() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.a", 1)
	set_time(10.0)
	_chronicle.set_facts({"player.b": 2, "player.c": 3, "player.d": 4})
	var result: Array[Dictionary] = _chronicle.get_changes_between(0.0, 10.0)
	assert_eq(result.size(), 4, "cluster at t=10 included in [0,10]")
	assert_eq(result[0].key as String, "player.a")


# Half-open intervals (since, until] — exclusive lower, inclusive upper
func test_closed_interval_coverage() -> void:
	set_time(0.0)
	_chronicle.set_fact("a", 1)
	set_time(5.0)
	_chronicle.set_fact("b", 2)
	set_time(10.0)
	_chronicle.set_fact("c", 3)
	set_time(15.0)
	_chronicle.set_fact("d", 4)

	var w1: Array[Dictionary] = _chronicle.get_changes_between(0.0, 5.0)
	var w2: Array[Dictionary] = _chronicle.get_changes_between(5.0, 10.0)
	var w3: Array[Dictionary] = _chronicle.get_changes_between(10.0, 20.0)
	assert_eq(w1.size(), 1, "(0,5] has 1 entry (t=5)")
	assert_eq(w2.size(), 1, "(5,10] has 1 entry (t=10)")
	assert_eq(w3.size(), 1, "(10,20] has 1 entry (t=15)")

	var all: Array[Dictionary] = _chronicle.get_changes_between(0.0, 20.0)
	assert_eq(all.size(), 3, "(0,20] returns 3 (excludes t=0)")


# Deep copy — modifying returned values does not corrupt timeline
func test_deep_copy_isolation() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.items", ["sword", "shield"])

	var result: Array[Dictionary] = _chronicle.get_changes_between(0.0, 10.0)
	assert_eq(result.size(), 1)

	# Mutate the returned array value
	(result[0].value as Array).append("axe")

	# Re-query — original should be unchanged
	var result2: Array[Dictionary] = _chronicle.get_changes_between(0.0, 10.0)
	assert_eq((result2[0].value as Array).size(), 2, "original has 2 items, not 3")


# fact_changes_between returns only entries matching key (half-open interval)
func test_fact_changes_between_key_filter() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(5.0)
	_chronicle.set_fact("player.gold", 50)
	_chronicle.set_fact("enemy.hp", 30)
	set_time(10.0)
	_chronicle.set_fact("player.hp", 80)
	_chronicle.set_fact("player.gold", 75)

	var result: Array[Dictionary] = _chronicle.get_fact_changes_between("player.hp", 0.0, 15.0)
	assert_eq(result.size(), 2, "only player.hp entries returned")
	assert_eq(result[0].value, 100)
	assert_eq(result[0].time, 1.0)
	assert_eq(result[1].value, 80)
	assert_eq(result[1].time, 10.0)


# fact_changes_between respects half-open interval (since, until]
func test_fact_changes_between_closed() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(10.0)
	_chronicle.set_fact("player.hp", 80)
	set_time(15.0)
	_chronicle.set_fact("player.hp", 60)

	var result: Array[Dictionary] = _chronicle.get_fact_changes_between("player.hp", 5.0, 15.0)
	assert_eq(result.size(), 2, "(5,15] includes t=10 and t=15")
	assert_eq(result[0].value, 80)
	assert_eq(result[1].value, 60)


# fact_changes_between with key not in window returns []
func test_fact_changes_between_key_not_in_window() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(10.0)
	_chronicle.set_fact("player.gold", 50)

	var result: Array[Dictionary] = _chronicle.get_fact_changes_between("player.gold", 0.0, 8.0)
	assert_eq(result.size(), 0, "player.gold only at t=10, outside [0,8)")


# fact_changes_between with key not in timeline returns []
func test_fact_changes_between_nonexistent_key() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)

	var result: Array[Dictionary] = _chronicle.get_fact_changes_between("missing.key", 0.0, 10.0)
	assert_eq(result.size(), 0, "nonexistent key returns []")


# fact_changes_between with dotless key (normalization)
func test_fact_changes_between_dotless_key() -> void:
	set_time(5.0)
	_chronicle.set_fact("flag", true)
	set_time(10.0)
	_chronicle.set_fact("player.hp", 100)

	var result: Array[Dictionary] = _chronicle.get_fact_changes_between("flag", 0.0, 15.0)
	assert_eq(result.size(), 1, "dotless key 'flag' found")
	assert_eq(result[0].key as String, "flag")
	assert_eq(result[0].value, true)


# fact_changes_between NaN validation
func test_fact_changes_between_nan() -> void:
	set_time(5.0)
	_chronicle.set_fact("player.hp", 100)

	var r1: Array[Dictionary] = _chronicle.get_fact_changes_between("player.hp", NAN, 10.0)
	assert_eq(r1.size(), 0, "NaN since returns []")
	var r2: Array[Dictionary] = _chronicle.get_fact_changes_between("player.hp", 0.0, NAN)
	assert_eq(r2.size(), 0, "NaN until returns []")


# fact_changes_between return format matches {key, value, old_value, time, tick}
func test_fact_changes_between_format() -> void:
	set_time(5.0)
	_chronicle.set_fact("quest.done", true)

	var result: Array[Dictionary] = _chronicle.get_fact_changes_between("quest.done", 0.0, 10.0)
	assert_eq(result.size(), 1)
	var entry: Dictionary = result[0]
	assert_has(entry, "key")
	assert_has(entry, "value")
	assert_has(entry, "old_value")
	assert_has(entry, "time")
	assert_eq(entry.size(), 4, "key, value, old_value, time")


# fact_changes_between empty timeline returns []
func test_fact_changes_between_empty_timeline() -> void:
	var result: Array[Dictionary] = _chronicle.get_fact_changes_between("player.hp", 0.0, 10.0)
	assert_eq(result.size(), 0, "empty timeline returns []")


# changes_between works after serialize/deserialize roundtrip
func test_changes_between_after_deserialization() -> void:
	set_time(1.0)
	_chronicle.set_fact("ser.a", 1)
	set_time(5.0)
	_chronicle.set_fact("ser.b", 2)
	set_time(10.0)
	_chronicle.set_fact("ser.c", 3)

	var data: Dictionary = _chronicle.serialize()
	_chronicle.deserialize(data)

	var result: Array[Dictionary] = _chronicle.get_changes_between(0.0, 8.0)
	assert_eq(result.size(), 2, "after deserialize, (0,8] returns 2 entries")
	assert_eq(result[0].key as String, "ser.a")
	assert_eq(result[1].key as String, "ser.b")


# fact_changes_between works after serialize/deserialize roundtrip
func test_fact_changes_between_after_deserialization() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(5.0)
	_chronicle.set_fact("player.gold", 50)
	set_time(10.0)
	_chronicle.set_fact("player.hp", 80)

	var data: Dictionary = _chronicle.serialize()
	_chronicle.deserialize(data)

	var result: Array[Dictionary] = _chronicle.get_fact_changes_between("player.hp", 0.0, 15.0)
	assert_eq(result.size(), 2, "after deserialize, hp has 2 entries")
	assert_eq(result[0].value, 100)
	assert_eq(result[1].value, 80)


# changes_between after rollback returns surviving entries only
func test_changes_between_after_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(5.0)
	_chronicle.set_fact("player.gold", 50)
	set_time(10.0)
	_chronicle.set_fact("player.hp", 80)
	set_time(15.0)
	_chronicle.set_fact("enemy.hp", 30)

	_chronicle.rollback_to(7.0)

	var result: Array[Dictionary] = _chronicle.get_changes_between(0.0, 20.0)
	assert_eq(result.size(), 2, "after rollback to t=7, t=1 and t=5 survive")
	assert_eq(result[0].key as String, "player.hp")
	assert_eq(result[1].key as String, "player.gold")


# fact_changes_between after rollback
func test_fact_changes_between_after_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(5.0)
	_chronicle.set_fact("player.hp", 80)
	set_time(10.0)
	_chronicle.set_fact("player.hp", 60)

	_chronicle.rollback_to(7.0)

	var result: Array[Dictionary] = _chronicle.get_fact_changes_between("player.hp", 0.0, 20.0)
	assert_eq(result.size(), 2, "after rollback to t=7, hp at t=1 and t=5 survive")
	assert_eq(result[0].value, 100)
	assert_eq(result[1].value, 80)


# Transient facts included in changes_between
func test_transient_facts_included() -> void:
	set_time(5.0)
	_chronicle.set_fact("temp.flag", true, true, 0.0)
	set_time(10.0)
	_chronicle.set_fact("player.hp", 100)

	var result: Array[Dictionary] = _chronicle.get_changes_between(0.0, 15.0)
	assert_eq(result.size(), 2, "transient fact included in results")
	assert_eq(result[0].key as String, "temp.flag")
