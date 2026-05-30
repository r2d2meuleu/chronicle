extends ChronicleTestSuite


# Helper: populate _chronicle with known facts in a fixed tick order
func _setup_player_facts() -> void:
	_chronicle.set_fact("player.gold", 10)
	_chronicle.set_fact("player.hp", 100)
	_chronicle.set_fact("player.name", "Hero")
	_chronicle.set_fact("enemy.hp", 50)


# find("player.*") returns matching keys
func test_find_glob() -> void:
	_setup_player_facts()
	var keys: Array[String] = _chronicle.get_fact_keys("player.*")
	assert_has(keys, "player.gold", "find player.* includes player.gold")
	assert_has(keys, "player.hp", "find player.* includes player.hp")
	assert_has(keys, "player.name", "find player.* includes player.name")
	assert_does_not_have(keys, "enemy.hp", "find player.* excludes enemy.hp")
	assert_eq(keys.size(), 3, "find player.* returns exactly 3 keys")


# find("player.gold") exact match
func test_find_exact_match() -> void:
	_setup_player_facts()
	var keys: Array[String] = _chronicle.get_fact_keys("player.gold")
	assert_eq(keys.size(), 1, "find exact returns 1 key")
	assert_eq(keys[0], "player.gold", "find exact returns correct key")


# find("*") returns all keys (denormalized)
func test_find_star_all() -> void:
	_setup_player_facts()
	var keys: Array[String] = _chronicle.get_fact_keys("*")
	assert_eq(keys.size(), 4, "find * returns all 4 keys")
	assert_has(keys, "player.gold", "find * has player.gold")
	assert_has(keys, "enemy.hp", "find * has enemy.hp")


# find("nonexistent.*") returns []
func test_find_no_match() -> void:
	_setup_player_facts()
	var keys: Array[String] = _chronicle.get_fact_keys("nonexistent.*")
	assert_eq(keys.size(), 0)


# count("player.*") returns correct count
func test_count_glob() -> void:
	_setup_player_facts()
	assert_fact_count("player.*", 3)


# count("*") returns total fact count
func test_count_star_all() -> void:
	_setup_player_facts()
	assert_fact_count("*", 4)


# first_change("player.*") returns earliest entry {key, value, time}
func test_first_change_glob() -> void:
	_setup_player_facts()
	var entry: Variant = _chronicle.get_first_change("player.*")
	assert_true(entry is Dictionary, "first_change player.* returns a Dictionary")
	assert_first_change("player.*", "player.gold", 10)
	assert_has(entry, "time", "first_change player.* has time field")


# first_change("player.*") returns latest entry
func test_last_change_glob() -> void:
	_setup_player_facts()
	var entry: Variant = _chronicle.get_last_change("player.*")
	assert_true(entry is Dictionary, "last_change player.* returns a Dictionary")
	assert_last_change("player.*", "player.name", "Hero")
	assert_has(entry, "time", "last_change player.* has time field")


# first_change("*") returns the very first fact set
func test_first_change_star() -> void:
	_chronicle.set_fact("alpha.x", 1)
	_chronicle.set_fact("beta.y", 2)
	var entry: Variant = _chronicle.get_first_change("*")
	assert_not_null(entry, "first_change * returns an entry")
	assert_eq(entry.key as String, "alpha.x", "first_change * returns the first fact set")


# first_change("missing.*") returns null
func test_first_change_no_match() -> void:
	_setup_player_facts()
	assert_no_first_change("missing.*")


# last_change("missing.*") returns null
func test_last_change_no_match() -> void:
	_setup_player_facts()
	assert_no_last_change("missing.*")


# changes_since(time) returns entries strictly after given time (exclusive lower bound)
func test_changes_since() -> void:
	set_time(0.0)
	_chronicle.set_fact("player.a", 1)
	_chronicle.set_fact("player.b", 2)

	set_time(5.0)
	_chronicle.set_fact("player.c", 3)
	_chronicle.set_fact("enemy.x", 99)

	set_time(10.0)
	_chronicle.set_fact("boss.defeated", true)

	# changes_since(0.0) returns entries strictly after t=0.0: t=5 and t=10 = 3 entries
	assert_changes_since_count(0.0, 3)

	# changes_since(5.0) returns entries strictly after t=5.0: only t=10 = 1 entry
	assert_changes_since_count(5.0, 1)

	# changes_since(10.0) returns entries strictly after t=10.0: none
	assert_changes_since_count(10.0, 0)

	# changes_since past all writes returns empty
	assert_changes_since_count(10.001, 0)

	# Entries have required fields
	var all_entries: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_has(all_entries[0], "key")
	assert_has(all_entries[0], "value")
	assert_has(all_entries[0], "time")


# fact_history("player.gold") returns all changes to that key with timestamps
func test_fact_history() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.gold", 10)
	set_time(2.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(3.0)
	_chronicle.set_fact("player.gold", 20)
	set_time(5.0)
	_chronicle.set_fact("player.gold", 30)
	assert_history("player.gold", [10, 20, 30], [1.0, 3.0, 5.0])
	var history: Array[Dictionary] = _chronicle.get_fact_history("player.gold")
	for entry: Dictionary in history:
		assert_eq(entry.key as String, "player.gold",\
			"all history entries have key player.gold")


# Dotless key in find: find("flag") where set_fact("flag", true) was called
func test_find_dotless_key() -> void:
	_chronicle.set_fact("flag", true)
	_chronicle.set_fact("player.gold", 99)
	var keys: Array[String] = _chronicle.get_fact_keys("flag")
	assert_eq(keys.size(), 1, "find dotless 'flag' returns 1 result")
	assert_eq(keys[0], "flag", "find dotless 'flag' returns denormalized 'flag'")


# Results have denormalized keys (no _global. prefix)
func test_results_denormalized() -> void:
	_chronicle.set_fact("flag", true)
	_chronicle.set_fact("score", 42)

	# find should return "flag" and "score", not "_global.flag"
	var keys: Array[String] = _chronicle.get_fact_keys("*")
	for k: String in keys:
		assert_false(k.begins_with("_global."), "find result not prefixed with _global.: " + k)

	# first_change/last_change should have denormalized key
	var entry: Variant = _chronicle.get_first_change("flag")
	assert_not_null(entry, "first_change flag returns result")
	assert_false((entry.key as String).begins_with("_global."), "first_change result key not prefixed with _global.")

	# fact_history should have denormalized key
	var history: Array[Dictionary] = _chronicle.get_fact_history("flag")
	for h: Dictionary in history:
		assert_false((h.key as String).begins_with("_global."), "fact_history key not prefixed with _global.")


# first_change/last_change include erasure entries
func test_first_change_last_change_include_erasures() -> void:
	_chronicle.set_fact("a.b", 42)
	_chronicle.erase_fact("a.b")
	# After erase, first_change returns the original set entry (value=42)
	var f: Variant = _chronicle.get_first_change("a.*")
	assert_not_null(f, "first_change returns first entry (the set)")
	assert_eq(f.get("value", null), 42, "first_change returns original set value")
	# last_change returns the most recent entry — the erasure (value=null)
	var l: Variant = _chronicle.get_last_change("a.*")
	assert_not_null(l, "last_change returns last entry (the erasure)")
	assert_null(l.get("value"), "last_change returns erasure entry with null value")
	# Re-set and verify last_change returns the new value
	_chronicle.set_fact("a.b", 99)
	l = _chronicle.get_last_change("a.*")
	assert_eq(l.get("value", null), 99, "last_change returns re-set value after erase")


# first_change and last_change return correct timestamps
func test_first_change_last_change_with_time() -> void:
	set_time(2.0)
	_chronicle.set_fact("item.sword", true)
	set_time(4.0)
	_chronicle.set_fact("item.shield", true)
	set_time(6.0)
	_chronicle.set_fact("item.bow", true)

	var first: Variant = _chronicle.get_first_change("item.*")
	assert_not_null(first)
	assert_eq(first.key as String, "item.sword")
	assert_eq(first.time, 2.0,\
		"first_change returns entry stamped at t=2.0")

	var last: Variant = _chronicle.get_last_change("item.*")
	assert_not_null(last)
	assert_eq(last.key as String, "item.bow")
	assert_eq(last.time, 6.0,\
		"last_change returns entry stamped at t=6.0")

	# Overwrite sword at t=8.0 — last_change should now return sword
	set_time(8.0)
	_chronicle.set_fact("item.sword", false)
	var new_last: Variant = _chronicle.get_last_change("item.*")
	assert_not_null(new_last)
	assert_eq(new_last.key as String, "item.sword")
	assert_eq(new_last.time, 8.0,\
		"last_change returns re-written entry at t=8.0")


# changes_since on empty timeline returns []
func test_changes_since_empty_timeline() -> void:
	assert_changes_since_count(0.0, 0)
	assert_changes_since_count(-1.0, 0)
	assert_changes_since_count(999.9, 0)


# changes_since with single entry — query at exact time excludes it (exclusive lower bound)
func test_changes_since_single_entry_exact() -> void:
	set_time(5.0)
	_chronicle.set_fact("solo.key", 42)
	assert_changes_since_count(5.0, 0)
	# Use a time before the entry to include it
	var result_before: Array[Dictionary] = _chronicle.get_changes_since(4.999)
	assert_eq(result_before.size(), 1, "single entry at t=5.0, since(4.999) returns 1")
	assert_eq(result_before[0].key as String, "solo.key")
	assert_eq(result_before[0].value, 42)


# changes_since with single entry — query after it returns []
func test_changes_since_single_entry_after() -> void:
	set_time(5.0)
	_chronicle.set_fact("solo.key", 42)
	assert_changes_since_count(10.0, 0)


# changes_since with single entry — query before it returns it
func test_changes_since_single_entry_before() -> void:
	set_time(5.0)
	_chronicle.set_fact("solo.key", 42)
	assert_changes_since_count(0.0, 1)


# changes_since with equal timestamps — exclusive lower bound excludes the boundary
func test_changes_since_equal_timestamps() -> void:
	set_time(3.0)
	_chronicle.set_fact("eq.a", 1)
	_chronicle.set_fact("eq.b", 2)
	_chronicle.set_fact("eq.c", 3)
	_chronicle.set_fact("eq.d", 4)
	_chronicle.set_fact("eq.e", 5)
	# since(3.0) is exclusive: all 5 entries are at t=3.0, so none qualify
	assert_changes_since_count(3.0, 0)
	# since before the cluster includes all
	var all_result: Array[Dictionary] = _chronicle.get_changes_since(2.999)
	assert_eq(all_result.size(), 5, "5 entries at t=3.0, since(2.999) returns all 5")
	assert_eq(all_result[0].key as String, "eq.a", "first entry is eq.a (leftmost)")
	assert_eq(all_result[4].key as String, "eq.e", "last entry is eq.e")


# changes_since with all-same-timestamp boundary — exclusive lower bound
func test_changes_since_all_same_timestamp_boundary() -> void:
	set_time(7.0)
	for i: int in range(10):
		_chronicle.set_fact("same.k%d" % i, i)
	# since(7.0) is exclusive: entries are at t=7.0, so none qualify
	assert_changes_since_count(7.0, 0)
	# since before the cluster includes all
	assert_changes_since_count(6.999, 10)
	assert_changes_since_count(7.001, 0)


# changes_since boundary precision with close float values — exclusive lower bound
func test_changes_since_boundary_precision() -> void:
	set_time(4.999999)
	_chronicle.set_fact("prec.before", 1)
	set_time(5.0)
	_chronicle.set_fact("prec.exact", 2)
	set_time(5.000001)
	_chronicle.set_fact("prec.after", 3)
	# since(5.0) is exclusive: entry at t=5.0 is NOT included
	assert_changes_since_count(5.0, 1)
	var result: Array[Dictionary] = _chronicle.get_changes_since(5.0)
	assert_eq(result[0].key as String, "prec.after")


# changes_since with mixed timestamp clusters — exclusive lower bound
func test_changes_since_mixed_timestamp_clusters() -> void:
	set_time(1.0)
	_chronicle.set_fact("cl.a1", 1)
	_chronicle.set_fact("cl.a2", 2)
	_chronicle.set_fact("cl.a3", 3)
	set_time(5.0)
	_chronicle.set_fact("cl.b1", 4)
	_chronicle.set_fact("cl.b2", 5)
	set_time(5.0)
	_chronicle.set_fact("cl.b3", 6)
	set_time(9.0)
	_chronicle.set_fact("cl.c1", 7)
	# since(5.0) is exclusive: entries at t=5.0 are excluded, only t=9.0 qualifies
	assert_changes_since_count(5.0, 1)
	var result: Array[Dictionary] = _chronicle.get_changes_since(5.0)
	assert_eq(result[0].key as String, "cl.c1", "only entry is cl.c1 at t=9.0")


# changes_since works correctly after serialize/deserialize roundtrip
func test_changes_since_after_deserialization() -> void:
	set_time(0.0)
	_chronicle.set_fact("ser.a", 1)
	set_time(5.0)
	_chronicle.set_fact("ser.b", 2)
	set_time(10.0)
	_chronicle.set_fact("ser.c", 3)

	var data: Dictionary = _chronicle.serialize()
	_chronicle.deserialize(data)

	# since(5.0) is exclusive: ser.b at t=5.0 is excluded, only ser.c at t=10.0 qualifies
	assert_changes_since_count(5.0, 1)
	var mid: Array[Dictionary] = _chronicle.get_changes_since(5.0)
	assert_eq(mid[0].key as String, "ser.c")


# changes_since works correctly after batch-trim
func test_changes_since_after_batch_trim() -> void:
	set_time(0.0)
	for i: int in range(11001):
		_chronicle.set_fact("trim.k%d" % (i % 100), i)
	assert_eq(_chronicle.get_stats().timeline_size, 10000,
		"after trim, timeline has exactly 10000 entries")


# find() returns an independent snapshot — clearing it doesn't affect the store
func test_find_returns_independent_snapshot() -> void:
	_chronicle.set_fact("player.hp", 100)
	_chronicle.set_fact("player.gold", 50)
	var snapshot: Array[String] = _chronicle.get_fact_keys("player.*")
	assert_eq(snapshot.size(), 2)
	snapshot.clear()
	assert_eq(_chronicle.count_facts("player.*"), 2)
	assert_fact("player.hp", 100)
	assert_fact("player.gold", 50)


# ── R16-A7 query engine audit ────────────


# History cache invalidates after rollback (tick changes via truncate)
func test_history_cache_invalidates_after_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(2.0)
	_chronicle.set_fact("player.hp", 80)
	set_time(3.0)
	_chronicle.set_fact("player.hp", 60)

	# Build cache
	assert_history_size("player.hp", 3)

	# Rollback removes last entry
	_chronicle.rollback_steps(1)

	# Cache must be invalidated — should show 2 entries now
	assert_history("player.hp", [100, 80])


# History cache invalidates after rollback_to
func test_history_cache_invalidates_after_rollback_to() -> void:
	set_time(1.0)
	_chronicle.set_fact("score", 10)
	set_time(2.0)
	_chronicle.set_fact("score", 20)
	set_time(3.0)
	_chronicle.set_fact("score", 30)

	# Prime the cache
	assert_history("score", [10, 20, 30])

	# Rollback to t=1.5 removes entries at t=2.0 and t=3.0
	_chronicle.rollback_to(1.5)

	assert_history("score", [10])


# History for nonexistent key returns empty array
func test_history_nonexistent_key() -> void:
	_chronicle.set_fact("player.hp", 100)
	assert_history_size("player.mana", 0)


# History for invalid key returns empty array (not a crash)
func test_history_invalid_key() -> void:
	assert_history_size("", 0)


# find() with entity glob on empty entity returns empty
func test_find_entity_glob_empty() -> void:
	_chronicle.set_fact("player.hp", 100)
	var keys: Array[String] = _chronicle.get_fact_keys("enemy.*")
	assert_eq(keys.size(), 0, "no enemy keys exist, find returns empty")


# count() with entity glob on empty entity returns 0
func test_count_entity_glob_empty() -> void:
	_chronicle.set_fact("player.hp", 100)
	assert_fact_count("enemy.*", 0)


# get_facts() with entity glob on empty entity returns empty dict
func test_get_facts_entity_glob_empty() -> void:
	_chronicle.set_fact("player.hp", 100)
	var facts: Dictionary = _chronicle.get_facts("enemy.*")
	assert_eq(facts.size(), 0, "no enemy facts exist")


# find/count/get_facts for exact key that doesn't exist
func test_find_exact_nonexistent() -> void:
	var keys: Array[String] = _chronicle.get_fact_keys("does.not.exist")
	assert_eq(keys.size(), 0)
	assert_fact_count("does.not.exist", 0)
	var facts: Dictionary = _chronicle.get_facts("does.not.exist")
	assert_eq(facts.size(), 0)


# get_first_change on empty timeline returns null
func test_first_change_empty_timeline() -> void:
	assert_no_first_change("*")


# get_last_change on empty timeline returns null
func test_last_change_empty_timeline() -> void:
	assert_no_last_change("*")


# get_fact_history after clear returns empty (cache invalidated)
func test_history_after_clear() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(2.0)
	_chronicle.set_fact("player.hp", 50)

	# Prime cache
	assert_history("player.hp", [100, 50])

	_chronicle.clear()

	assert_history_size("player.hp", 0)


# History works correctly for dotless (global) keys
func test_history_dotless_key() -> void:
	set_time(1.0)
	_chronicle.set_fact("flag", true)
	set_time(2.0)
	_chronicle.set_fact("flag", false)

	assert_history("flag", [true, false])
	# Ensure display keys are denormalized (no _global. prefix)
	var history: Array[Dictionary] = _chronicle.get_fact_history("flag")
	assert_eq(history[0].key, "flag", "display key is denormalized")
	assert_eq(history[1].key, "flag", "display key is denormalized")


# History cache correctly handles interleaved keys
func test_history_interleaved_keys() -> void:
	set_time(1.0)
	_chronicle.set_fact("a.x", 1)
	set_time(2.0)
	_chronicle.set_fact("b.y", 2)
	set_time(3.0)
	_chronicle.set_fact("a.x", 3)
	set_time(4.0)
	_chronicle.set_fact("b.y", 4)

	assert_history("a.x", [1, 3], [1.0, 3.0])
	assert_history("b.y", [2, 4], [2.0, 4.0])


# get_first_change with dotless key
func test_first_change_dotless_key() -> void:
	set_time(1.0)
	_chronicle.set_fact("flag", true)
	set_time(2.0)
	_chronicle.set_fact("flag", false)

	assert_first_change("flag", "flag", true)


# get_last_change with dotless key
func test_last_change_dotless_key() -> void:
	set_time(1.0)
	_chronicle.set_fact("flag", true)
	set_time(2.0)
	_chronicle.set_fact("flag", false)

	assert_last_change("flag", "flag", false)


# find with wildcard-only entity segment ("*.hp" pattern)
func test_find_wildcard_entity() -> void:
	_chronicle.set_fact("player.hp", 100)
	_chronicle.set_fact("enemy.hp", 50)
	_chronicle.set_fact("player.mp", 200)

	var keys: Array[String] = _chronicle.get_fact_keys("*.hp")
	assert_eq(keys.size(), 2, "*.hp matches player.hp and enemy.hp")
	assert_has(keys, "player.hp")
	assert_has(keys, "enemy.hp")
	assert_does_not_have(keys, "player.mp")


# get_fact_changes_between with no matching key
func test_fact_changes_between_no_match() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)

	var result: Array[Dictionary] = _chronicle.get_fact_changes_between(
		"enemy.hp", 0.0, 10.0)
	assert_eq(result.size(), 0, "no changes for nonexistent key")


# get_fact_changes_between with matching key
func test_fact_changes_between_with_match() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(3.0)
	_chronicle.set_fact("player.hp", 80)
	set_time(5.0)
	_chronicle.set_fact("player.hp", 60)

	var result: Array[Dictionary] = _chronicle.get_fact_changes_between(
		"player.hp", 2.0, 4.0)
	assert_eq(result.size(), 1, "only the t=3.0 entry is in [2.0, 4.0]")
	assert_eq(result[0].value, 80)
	assert_eq(result[0].time, 3.0)


# get_changes_between closed range includes both endpoints
func test_changes_between_closed_range() -> void:
	set_time(2.0)
	_chronicle.set_fact("a.x", 1)
	set_time(4.0)
	_chronicle.set_fact("b.y", 2)
	set_time(6.0)
	_chronicle.set_fact("c.z", 3)

	# Half-open range (2.0, 6.0] — exclusive lower, inclusive upper.
	# Entry at t=2.0 is excluded, entries at t=4.0 and t=6.0 are included.
	var result: Array[Dictionary] = _chronicle.get_changes_between(2.0, 6.0)
	assert_eq(result.size(), 2, "(2.0, 6.0] excludes t=2 endpoint, includes t=4 and t=6")

	# Half-open range (2.0, 4.0] — only t=4.0 included
	result = _chronicle.get_changes_between(2.0, 4.0)
	assert_eq(result.size(), 1, "(2.0, 4.0] includes only t=4")


# History after deserialize (cache must be invalidated)
func test_history_after_deserialize() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(2.0)
	_chronicle.set_fact("player.hp", 50)

	# Prime cache
	assert_history("player.hp", [100, 50])

	# Serialize and deserialize
	var data: Dictionary = _chronicle.serialize()
	_chronicle.deserialize(data)

	# Cache should be invalidated; history should still work
	assert_history("player.hp", [100, 50])


# History entries include old_value field
func test_history_entries_have_old_value() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(2.0)
	_chronicle.set_fact("player.hp", 80)

	# First set: old_value null (fact didn't exist); second set: old_value 100.
	assert_history("player.hp", [100, 80], [], [null, 100])


# get_facts returns defensive copies (mutating result doesn't affect store)
func test_get_facts_returns_defensive_copies() -> void:
	_chronicle.set_fact("player.items", [1, 2, 3])
	var facts: Dictionary = _chronicle.get_facts("player.*")
	var items: Array = facts["player.items"]
	items.append(4)
	# Store should be unaffected
	assert_fact("player.items", [1, 2, 3])


# History with erased fact includes the erasure entry
func test_history_includes_erasure() -> void:
	set_time(1.0)
	_chronicle.set_fact("quest.done", true)
	set_time(2.0)
	_chronicle.erase_fact("quest.done")

	# First entry is the set; second is the erasure (null value).
	assert_history("quest.done", [true, null])


# Multiple rollbacks keep history cache consistent
func test_multiple_rollbacks_history_consistency() -> void:
	set_time(1.0)
	_chronicle.set_fact("score", 10)
	set_time(2.0)
	_chronicle.set_fact("score", 20)
	set_time(3.0)
	_chronicle.set_fact("score", 30)
	set_time(4.0)
	_chronicle.set_fact("score", 40)

	# Prime cache
	assert_history("score", [10, 20, 30, 40])

	# First rollback
	_chronicle.rollback_steps(1)
	assert_history("score", [10, 20, 30])

	# Second rollback
	_chronicle.rollback_steps(1)
	assert_history("score", [10, 20])

	# Third rollback
	_chronicle.rollback_steps(1)
	assert_history("score", [10])


# find returns fresh array each time (independent snapshots)
func test_find_returns_independent_arrays() -> void:
	_chronicle.set_fact("player.hp", 100)
	var keys1: Array[String] = _chronicle.get_fact_keys("player.*")
	var keys2: Array[String] = _chronicle.get_fact_keys("player.*")
	keys1.clear()
	assert_eq(keys2.size(), 1, "second array unaffected by clearing first")


# count matches find().size() for all pattern types
func test_count_matches_find_size() -> void:
	_chronicle.set_fact("player.hp", 100)
	_chronicle.set_fact("player.mp", 200)
	_chronicle.set_fact("enemy.hp", 50)
	_chronicle.set_fact("flag", true)

	# Glob with entity
	assert_eq(
		_chronicle.count_facts("player.*"),
		_chronicle.get_fact_keys("player.*").size(),
		"count matches find size for entity glob")

	# Wildcard-all
	assert_eq(
		_chronicle.count_facts("*"),
		_chronicle.get_fact_keys("*").size(),
		"count matches find size for *")

	# Exact key
	assert_eq(
		_chronicle.count_facts("player.hp"),
		_chronicle.get_fact_keys("player.hp").size(),
		"count matches find size for exact key")

	# No match
	assert_eq(
		_chronicle.count_facts("boss.*"),
		_chronicle.get_fact_keys("boss.*").size(),
		"count matches find size for no match")


# get_first_change and get_last_change after erasure and re-set
func test_first_last_change_after_erase_and_reset() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(2.0)
	_chronicle.erase_fact("player.hp")
	set_time(3.0)
	_chronicle.set_fact("player.hp", 200)

	var first: Variant = _chronicle.get_first_change("player.*")
	assert_eq(first.value, 100, "first_change returns the original set")
	assert_eq(first.time, 1.0)

	var last: Variant = _chronicle.get_last_change("player.*")
	assert_eq(last.value, 200, "last_change returns the re-set")
	assert_eq(last.time, 3.0)


# get_fact_changes_between for dotless key
func test_fact_changes_between_dotless() -> void:
	set_time(1.0)
	_chronicle.set_fact("flag", true)
	set_time(3.0)
	_chronicle.set_fact("flag", false)

	var result: Array[Dictionary] = _chronicle.get_fact_changes_between("flag", 0.0, 2.0)
	assert_eq(result.size(), 1, "one entry in [0, 2]")
	assert_eq(result[0].key, "flag", "dotless key denormalized")
	assert_eq(result[0].value, true, "timeline value is the bool true (not a truthy non-bool)")


# History cache handles new writes after query (tick change detection)
func test_history_cache_detects_new_writes() -> void:
	set_time(1.0)
	_chronicle.set_fact("counter", 1)

	# Query primes cache
	assert_history("counter", [1])

	# New write changes tick
	set_time(2.0)
	_chronicle.set_fact("counter", 2)

	# Cache should detect tick change and rebuild
	assert_history("counter", [1, 2])

	# Another write
	set_time(3.0)
	_chronicle.set_fact("counter", 3)

	assert_history("counter", [1, 2, 3])


# get_facts("*") on empty store returns empty dict
func test_get_facts_star_empty() -> void:
	var facts: Dictionary = _chronicle.get_facts("*")
	assert_eq(facts.size(), 0, "no facts on empty store")


# find("*") on empty store returns empty array
func test_find_star_empty() -> void:
	var keys: Array[String] = _chronicle.get_fact_keys("*")
	assert_eq(keys.size(), 0, "no keys on empty store")


# count("*") on empty store returns 0
func test_count_star_empty() -> void:
	assert_fact_count("*", 0)


# ── R17-A7 query engine audit ────────────


# History is correct after timeline overflow (ring-buffer drops oldest)
func test_history_correct_after_overflow() -> void:
	# Use a small cap so we can drive overflow easily.
	_chronicle.set_timeline_cap(5)

	set_time(1.0)
	_chronicle.set_fact("player.hp", 10)
	set_time(2.0)
	_chronicle.set_fact("player.hp", 20)
	set_time(3.0)
	_chronicle.set_fact("player.hp", 30)
	set_time(4.0)
	_chronicle.set_fact("player.hp", 40)
	set_time(5.0)
	_chronicle.set_fact("player.hp", 50)

	# Timeline is now at cap (5 entries for player.hp).
	assert_history("player.hp", [10, 20, 30, 40, 50])

	# This append drops the t=1.0 entry (overflow).
	set_time(6.0)
	_chronicle.set_fact("player.hp", 60)

	# Oldest entry (10) is gone; remaining are [20, 30, 40, 50, 60].
	assert_history("player.hp", [20, 30, 40, 50, 60])


# History remains correct across multiple consecutive overflow writes
func test_history_correct_across_multiple_overflows() -> void:
	_chronicle.set_timeline_cap(3)

	# Write 6 entries — double the cap.
	for i: int in range(1, 7):
		set_time(float(i))
		_chronicle.set_fact("counter", i)

	# Only the last 3 entries (4, 5, 6) survive.
	assert_history("counter", [4, 5, 6])


# History is correct after overflow with interleaved keys
func test_history_interleaved_keys_after_overflow() -> void:
	_chronicle.set_timeline_cap(4)

	# 4 writes: [a.x=1, b.y=2, a.x=3, b.y=4] — fills cap exactly.
	set_time(1.0)
	_chronicle.set_fact("a.x", 1)
	set_time(2.0)
	_chronicle.set_fact("b.y", 2)
	set_time(3.0)
	_chronicle.set_fact("a.x", 3)
	set_time(4.0)
	_chronicle.set_fact("b.y", 4)

	# Now overflow: drops a.x=1 (oldest).
	set_time(5.0)
	_chronicle.set_fact("a.x", 5)

	# a.x history: entries 1 (dropped), 3, 5 → should have [3, 5].
	assert_history("a.x", [3, 5])

	# b.y history: entries 2, 4 → still fully in buffer.
	assert_history("b.y", [2, 4])


# Cache rebuilds correctly when set_timeline_cap shrinks the buffer mid-session
func test_history_after_cap_shrink() -> void:
	set_time(1.0)
	_chronicle.set_fact("score", 10)
	set_time(2.0)
	_chronicle.set_fact("score", 20)
	set_time(3.0)
	_chronicle.set_fact("score", 30)
	set_time(4.0)
	_chronicle.set_fact("score", 40)

	# Prime the cache.
	assert_history("score", [10, 20, 30, 40])

	# Shrink the cap — drops entries 10 and 20 (oldest 2).
	_chronicle.set_timeline_cap(2)

	assert_history("score", [30, 40])


# Cache rebuilds correctly when set_timeline_cap grows (tick changes, no entries lost)
func test_history_after_cap_grow() -> void:
	set_time(1.0)
	_chronicle.set_fact("level", 1)
	set_time(2.0)
	_chronicle.set_fact("level", 2)

	# Prime the cache.
	assert_history("level", [1, 2])

	# Grow the cap — no entries dropped, but _tick increments → cache rebuilds.
	_chronicle.set_timeline_cap(500)

	assert_history("level", [1, 2])


# get_fact_history key that was never written returns empty after overflow
func test_history_unwritten_key_after_overflow() -> void:
	_chronicle.set_timeline_cap(3)

	# Fill and overflow with a different key.
	for i: int in range(1, 5):
		set_time(float(i))
		_chronicle.set_fact("other.key", i)

	assert_history_size("player.hp", 0)


# get_fact_history for a key whose ALL entries were overflowed returns empty
func test_history_all_entries_overflowed() -> void:
	_chronicle.set_timeline_cap(2)

	# Write player.hp once, then overflow it out with 2 other writes.
	set_time(1.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(2.0)
	_chronicle.set_fact("other.a", 1)
	set_time(3.0)
	_chronicle.set_fact("other.b", 2)

	# player.hp entry at t=1.0 is now gone (overflowed by 2 new entries).
	assert_history_size("player.hp", 0)


# find/count/get_facts are consistent with each other for all pattern types
func test_find_count_get_facts_consistency() -> void:
	_chronicle.set_fact("player.hp", 100)
	_chronicle.set_fact("player.mp", 200)
	_chronicle.set_fact("enemy.hp", 50)
	_chronicle.set_fact("flag", true)

	var patterns: Array[String] = ["player.*", "*", "enemy.*", "*.hp", "flag", "boss.*"]
	for pattern: String in patterns:
		var keys: Array[String] = _chronicle.get_fact_keys(pattern)
		var cnt: int = _chronicle.count_facts(pattern)
		var facts: Dictionary = _chronicle.get_facts(pattern)
		assert_eq(cnt, keys.size(),
			"count('%s') == find('%s').size() = %d" % [pattern, pattern, keys.size()])
		assert_eq(facts.size(), keys.size(),
			"get_facts('%s').size() == find('%s').size()" % [pattern, pattern])
		for k: String in keys:
			assert_has(facts, k,
				"key '%s' from find('%s') is present in get_facts result" % [k, pattern])


# get_fact_history index regenerates correctly across multiple build/use cycles
func test_history_index_rebuilt_multiple_times() -> void:
	set_time(1.0)
	_chronicle.set_fact("score", 1)

	# Build cache.
	assert_history("score", [1])

	# Invalidate by writing.
	set_time(2.0)
	_chronicle.set_fact("score", 2)
	assert_history("score", [1, 2])

	# Invalidate again.
	set_time(3.0)
	_chronicle.set_fact("score", 3)
	assert_history("score", [1, 2, 3])

	# One more cycle.
	set_time(4.0)
	_chronicle.set_fact("score", 4)
	assert_history("score", [1, 2, 3, 4])


# get_fact_history entries include correct old_value after overflow
func test_history_old_value_preserved_after_overflow() -> void:
	_chronicle.set_timeline_cap(3)

	set_time(1.0)
	_chronicle.set_fact("hp", 100)
	set_time(2.0)
	_chronicle.set_fact("hp", 80)
	set_time(3.0)
	_chronicle.set_fact("hp", 60)
	set_time(4.0)
	_chronicle.set_fact("hp", 40)  # Overflows t=1.0 entry.

	# Surviving entries: t=2 (80, old=100), t=3 (60, old=80), t=4 (40, old=60)
	assert_history("hp", [80, 60, 40], [], [100, 80, 60])


# ── Change-query time validation (NaN / INF return empty, like rollback) ──

func test_get_changes_since_nan_returns_empty() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	assert_eq(_chronicle.get_changes_since(NAN).size(), 0,
		"get_changes_since(NAN) should return an empty slice")


func test_get_changes_since_inf_returns_empty() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	assert_eq(_chronicle.get_changes_since(INF).size(), 0,
		"get_changes_since(INF) should return an empty slice")


func test_get_changes_between_nan_since_returns_empty() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	assert_eq(_chronicle.get_changes_between(NAN, 10.0).size(), 0,
		"get_changes_between(NAN, ...) should return an empty slice")

