extends ChronicleTestSuite


# watch("player.gold", callback) fires on set_fact("player.gold", 100)
func test_exact_watch_fires() -> void:
	var events := watch_events("player.gold")
	events.assert_valid_id()
	_chronicle.set_fact("player.gold", 100)
	events.assert_count(1)


# Watcher does NOT fire for non-matching key
func test_no_fire_for_non_matching_key() -> void:
	var events := watch_events("player.gold")
	_chronicle.set_fact("player.hp", 50)
	events.assert_count(0)


# watch(["key1", "key2"], callback) fires for either key
func test_multi_key_watch() -> void:
	var events := watch_events(["player.gold", "player.hp"])

	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.hp", 50)
	_chronicle.set_fact("player.name", "Hero")  # should not fire
	events.assert_count(2)
	events.assert_keys(["player.gold", "player.hp"])


# watch("player.*", callback) fires for any player.* fact
func test_glob_watch_fires() -> void:
	var events := watch_events("player.*")

	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.hp", 50)
	events.assert_count(2)


# Glob watcher does NOT fire for non-matching prefix
func test_glob_no_fire_for_non_matching_prefix() -> void:
	var events := watch_events("player.*")
	_chronicle.set_fact("enemy.hp", 100)
	events.assert_count(0)


# unwatch(id) stops delivery
func test_unwatch_stops_delivery() -> void:
	var events := watch_events("player.gold")

	_chronicle.set_fact("player.gold", 100)
	events.assert_count(1)

	_chronicle.unwatch(events.watch_id)
	_chronicle.set_fact("player.gold", 200)
	events.assert_count(1)

	# Also test glob unwatch
	var glob_events := watch_events("player.*")

	_chronicle.set_fact("player.hp", 50)
	glob_events.assert_count(1)

	_chronicle.unwatch(glob_events.watch_id)
	_chronicle.set_fact("player.hp", 75)
	glob_events.assert_count(1)


# Callback receives correct (key, value, old_value) args
func test_callback_receives_correct_args() -> void:
	var events := watch_events("player.gold")

	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.gold", 250)
	events.assert_count(2)
	events.assert_event(0, "player.gold", 100, null)
	events.assert_event(1, "player.gold", 250, 100)


# Watcher fires with denormalized key (user sees "flag" not "_global.flag")
func test_denormalized_key_in_callback() -> void:
	var events := watch_events("flag")
	_chronicle.set_fact("flag", true)
	events.assert_count(1)
	events.assert_event(0, "flag")


# Multiple watchers on same key all fire
func test_multiple_watchers_same_key() -> void:
	var events_a := watch_events("player.gold")
	var events_b := watch_events("player.gold")

	_chronicle.set_fact("player.gold", 100)
	events_a.assert_count(1)
	events_b.assert_count(1)


# Re-entrancy: callback that calls set_fact works (depth < 8)
func test_reentrant_callback() -> void:
	# Re-entrant callbacks need custom lambdas — EventCollector handles the
	# simple capture; we layer the side-effect on top.
	var fired: Array = []

	_chronicle.watch("player.gold", func(key: String, value: Variant, old_value: Variant) -> void:
		fired.append(key)
		# Re-entrant set_fact on a different key
		if not _chronicle.has_fact("player.bonus"):
			_chronicle.set_fact("player.bonus", 10)
	)

	var bonus_events := watch_events("player.bonus")

	_chronicle.set_fact("player.gold", 100)
	assert_eq(fired.size(), 1)
	assert_fact("player.bonus", 10)
	bonus_events.assert_count(1)


# unwatch during iteration doesn't crash (snapshot)
func test_unwatch_during_iteration() -> void:
	var fired: Array = []
	# Use an array to hold the watch id so the lambda can read the updated value
	# (GDScript lambdas capture primitives by value at creation time)
	var id_holder: Array = [-1]

	# This watcher unwatches itself when called
	id_holder[0] = _chronicle.watch("player.gold", func(key: String, value: Variant, old_value: Variant) -> void:
		fired.append(true)
		_chronicle.unwatch(id_holder[0])
	)

	# Should not crash — snapshot iteration protects against mutation
	_chronicle.set_fact("player.gold", 100)
	assert_eq(fired.size(), 1)

	# Should not fire again since unwatched
	_chronicle.set_fact("player.gold", 200)
	assert_eq(fired.size(), 1)


# clear() removes all watchers
func test_clear_removes_watchers() -> void:
	var events_exact := watch_events("player.gold")
	var events_glob := watch_events("player.*")

	_chronicle.set_fact("player.gold", 100)
	events_exact.assert_count(1)
	events_glob.assert_count(1)

	_chronicle.clear()
	_chronicle.set_fact("player.gold", 200)
	events_exact.assert_count(1)
	events_glob.assert_count(1)


func test_watch_empty_array_pattern() -> void:
	var events := make_collector()
	var empty_patterns: Array[String] = []
	var id: int = _chronicle.watch_any(empty_patterns, events.callback())
	assert_eq(id, -1)


func test_watch_any_fires_for_multiple_patterns() -> void:
	var events := make_collector()
	var patterns: Array[String] = ["player.gold"]
	var id: int = _chronicle.watch_any(patterns, events.callback())
	assert_gte(id, 0, "watch_any should return a valid id")
	_chronicle.set_fact("player.gold", 100)
	events.assert_count(1)


func test_unwatch_nonexistent_id() -> void:
	assert_false(_chronicle.unwatch(99999), "unwatch of a nonexistent id returns false")


# ── Stress: scale and edge cases ──────────

# 100 exact watchers on same key
func test_many_exact_watchers_same_key() -> void:
	var collectors: Array = []

	for i in range(100):
		var events := watch_events("player.gold")
		events.assert_valid_id()
		collectors.append(events)

	_chronicle.set_fact("player.gold", 1)
	for c: EventCollector in collectors:
		c.assert_count(1)


# Watcher calls set_fact (cascade depth 1)
func test_cascade_depth_1() -> void:
	# Watcher on "a" has a side-effect (sets fact "b"), so it needs a custom lambda
	# that both collects events and triggers the cascade.
	var fired_a := make_collector()

	_chronicle.watch("a", func(key: String, value: Variant, old_value: Variant) -> void:
		fired_a.events.append({key = key, value = value, old_value = old_value})
		# Cascade: watcher on "a" sets fact "b"
		if not _chronicle.has_fact("b"):
			_chronicle.set_fact("b", 1)
	)

	var fired_b := watch_events("b")

	_chronicle.set_fact("a", 42)

	fired_a.assert_count(1)
	fired_b.assert_count(1)
	assert_fact("a", 42)
	assert_fact("b", 1)

	# Verify order: 'a' watcher fires before 'b' watcher
	fired_a.assert_event(0, "a")
	fired_b.assert_event(0, "b")


# Cascade depth 8
# Chronicle's internal _drain_deferred_queue() runs within the same set_fact()
# call stack, so all levels resolve synchronously here.
func test_cascade_depth_8() -> void:
	var fire_log: Array = []

	# Build chain: watcher on "level.N" sets "level.(N+1)"
	for i in range(1, 9):
		var current_level: int = i
		var next_key: String = "level.%d" % (current_level + 1)
		_chronicle.watch("level.%d" % current_level, func(key: String, value: Variant, old_value: Variant) -> void:
			fire_log.append(key)
			_chronicle.set_fact(next_key, current_level + 1)
		)

	# Also watch level.9 to see if the deferred write fires it
	var level9 := watch_events("level.9")

	# Trigger the chain
	_chronicle.set_fact("level.1", 1)

	# Levels 1-8 should be set immediately (during the cascade)
	for i in range(1, 9):
		assert_has_fact("level.%d" % i)

	# Level 9 is deferred during cascade, then drained when _apply_depth returns to 0
	assert_fact("level.9", 9)
	level9.assert_count(1)


# Cascade depth 9+
func test_cascade_depth_9_plus() -> void:
	for i in range(1, 12):
		var current_level: int = i
		var next_key: String = "level.%d" % (current_level + 1)
		_chronicle.watch("level.%d" % current_level, func(_k: String, _v: Variant, _o: Variant) -> void:
			_chronicle.set_fact(next_key, current_level + 1)
		)

	var level12_events := watch_events("level.12")

	_chronicle.set_fact("level.1", 1)

	for i in range(1, 12):
		assert_fact("level.%d" % i, i)
	level12_events.assert_count(1)


# Unwatch during dispatch — unwatched watcher must not fire
func test_unwatch_during_dispatch_snapshot_safety() -> void:
	var fired_a: Array = []
	var b_events := make_collector()
	var b_id_holder: Array = [-1]

	# Watcher A: unwatches B during dispatch
	_chronicle.watch("key", func(key: String, value: Variant, old_value: Variant) -> void:
		fired_a.append(value)
		_chronicle.unwatch(b_id_holder[0])
	)

	# Watcher B: should NOT fire because A unwatches it before iteration reaches B
	b_id_holder[0] = _chronicle.watch("key", b_events.callback())
	b_events.watch_id = b_id_holder[0]

	# First write: only A should fire (B was unwatched mid-dispatch)
	_chronicle.set_fact("key", 1)
	assert_eq(fired_a.size(), 1)
	b_events.assert_count(0)

	# Second write: only A should fire (B was unwatched)
	_chronicle.set_fact("key", 2)
	assert_eq(fired_a.size(), 2)
	b_events.assert_count(0)


# Erase dispatches to watchers
func test_erase_dispatches_to_watchers() -> void:
	_chronicle.set_fact("a.b", 42)

	var events := watch_events("a.b")
	_chronicle.erase_fact("a.b")

	events.assert_count(1)
	events.assert_event(0, "a.b", null, 42)


# Invalid glob rejected
func test_invalid_glob_rejected() -> void:
	# Mixed wildcard in segment (e.g. "some*thing.foo") should be rejected
	# Use EventCollector.watch directly — watch_events() asserts valid id by design
	var events := EventCollector.watch(self, _chronicle, "some*thing.foo")
	events.assert_invalid_id()

	# Set some facts to verify no watcher fires
	_chronicle.set_fact("something.foo", 1)
	_chronicle.set_fact("other.foo", 2)
	events.assert_count(0)
	# assert_invalid_id() above is the behavioral proof that nothing was registered.


func test_deferred_queue_cap_drops_excess() -> void:
	for i in range(1, 9):
		var current_level: int = i
		var next_key: String = "chain.%d" % (current_level + 1)
		_chronicle.watch("chain.%d" % current_level, func(_k: String, _v: Variant, _o: Variant) -> void:
			_chronicle.set_fact(next_key, current_level + 1)
		)

	_chronicle.watch("chain.8", func(_k: String, _v: Variant, _o: Variant) -> void:
		for j in range(70):
			_chronicle.set_fact("flood.%d" % j, j)
	)

	_chronicle.set_fact("chain.1", 1)

	var found: int = 0
	for j in range(70):
		if _chronicle.has_fact("flood.%d" % j):
			found += 1
	# Exact count is cap-dependent (queue cap drops the overflow), so assert the
	# range: some were dropped (< 70) and some were processed (> 0).
	assert_lt(found, 70, "some deferred facts dropped at cap")
	assert_gt(found, 0, "some deferred facts were processed")


# Unwatch during exact dispatch — unwatched watcher must not fire
func test_unwatch_during_exact_dispatch_does_not_fire_removed() -> void:
	var order: Array = []
	var id_b_holder: Array = [-1]
	var id_a: int = _chronicle.watch("safe.key", func(_k: String, _v: Variant, _o: Variant) -> void:
		order.append("A")
		_chronicle.unwatch(id_b_holder[0])
	)
	id_b_holder[0] = _chronicle.watch("safe.key", func(_k: String, _v: Variant, _o: Variant) -> void:
		order.append("B")
	)
	_chronicle.set_fact("safe.key", 1)
	assert_eq(order, ["A"], "B should not fire after being unwatched by A's callback")


# ── unwatch_pattern tests ────────────────────────────────────────────────────


# unwatch_pattern removes exact matches and returns correct count
func test_unwatch_pattern_removes_exact_matches() -> void:
	var events_a := watch_events("health")
	var events_b := watch_events("health")
	var removed: int = _chronicle.unwatch_pattern("health")
	assert_eq(removed, 2, "Should remove 2 exact watchers")
	_chronicle.set_fact("health", 100)
	events_a.assert_count(0)
	events_b.assert_count(0)


# unwatch_pattern doesn't remove glob watchers with different patterns
func test_unwatch_pattern_does_not_remove_globs() -> void:
	var events := watch_events("player.*")
	var removed: int = _chronicle.unwatch_pattern("player.health")
	assert_eq(removed, 0, "Exact unwatch_pattern should not remove glob watchers")
	_chronicle.set_fact("player.health", 100)
	events.assert_count(1)


# unwatch_pattern returns 0 for nonexistent pattern
func test_unwatch_pattern_returns_zero_for_nonexistent() -> void:
	var removed: int = _chronicle.unwatch_pattern("nonexistent.pattern")
	assert_eq(removed, 0)


# unwatch_pattern with an empty string matches no watchers and returns 0 (no error)
func test_unwatch_pattern_empty_string_returns_zero() -> void:
	watch_events("enemy.*")
	var removed: int = _chronicle.unwatch_pattern("")
	assert_eq(removed, 0, "unwatch_pattern('') should match no watchers and return 0")
	assert_watcher_count(1)


# unwatch_pattern with glob pattern removes matching globs
func test_unwatch_pattern_removes_glob() -> void:
	var events := watch_events("enemy.*")
	var removed: int = _chronicle.unwatch_pattern("enemy.*")
	assert_eq(removed, 1, "Should remove 1 glob watcher")
	_chronicle.set_fact("enemy.health", 50)
	events.assert_count(0)


# ── Snapshot dispatch safety ─────────────────────────────────────────────────


# Self-unwatch during exact dispatch must not skip the next watcher
func test_self_unwatch_during_dispatch_does_not_skip_next_watcher() -> void:
	var results: Array = []
	var id_holder: Array = [-1]
	id_holder[0] = _chronicle.watch("player.gold", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.unwatch(id_holder[0])
		results.append("a")
	)
	_chronicle.watch("player.gold", func(_k: String, _v: Variant, _o: Variant) -> void:
		results.append("b")
	)
	_chronicle.set_fact("player.gold", 100)
	assert_eq(results, ["a", "b"], "Both watchers should fire even when A self-unwatches")


# unwatch_all during dispatch defers clear until dispatch completes
func test_unwatch_all_during_dispatch_defers_clear() -> void:
	var fired: Array = [false]
	_chronicle.watch("x", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.unwatch_all()
		fired[0] = true
	)
	_chronicle.set_fact("x", 1)
	assert_true(fired[0], "Callback should have fired")
	assert_watcher_count(0)


# Reentrant dispatch: fired_ids ordering is correct — outer watchers C still fire after inner cascade
func test_reentrant_dispatch_fired_ids_ordering() -> void:
	var order: Array = []
	_chronicle.watch("re.a", func(_k: String, _v: Variant, _o: Variant) -> void:
		order.append("A")
		if not _chronicle.has_fact("re.b"):
			_chronicle.set_fact("re.b", 1)
	)
	_chronicle.watch("re.b", func(_k: String, _v: Variant, _o: Variant) -> void:
		order.append("B")
	)
	_chronicle.watch("re.a", func(_k: String, _v: Variant, _o: Variant) -> void:
		order.append("C")
	)
	_chronicle.set_fact("re.a", 99)
	assert_eq(order.size(), 3, "exactly 3 callbacks must fire — got %s" % str(order))
	assert_eq(order[0], "A")
	assert_eq(order[1], "B")
	assert_eq(order[2], "C")
	assert_fact("re.a", 99)
	assert_fact("re.b", 1)


# Watch IDs are monotonically increasing and do not reset after clear()
func test_watch_ids_monotonic_across_clear() -> void:
	var id_a: int = _chronicle.watch("mono.a", func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	var id_b: int = _chronicle.watch("mono.b", func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	var id_c: int = _chronicle.watch("mono.*", func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	assert_gt(id_b, id_a, "IDs must be strictly increasing before clear")
	assert_gt(id_c, id_b, "IDs must be strictly increasing before clear")
	var max_pre_clear: int = id_c
	_chronicle.clear()
	var id_d: int = _chronicle.watch("mono.d", func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	var id_e: int = _chronicle.watch("mono.e", func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	assert_gt(id_d, max_pre_clear, "post-clear id_d (%d) must exceed max pre-clear ID (%d)" % [id_d, max_pre_clear])
	assert_gt(id_e, id_d, "post-clear IDs must still be strictly increasing")


# ── R16-A3 watch audit ───────────────────


# _seg_cache accumulates entries with each unique dispatched key
func test_seg_cache_grows_per_unique_key() -> void:
	# Register at least one glob watcher so glob dispatch code path runs and
	# key_segs / _seg_cache are actually exercised (the early-exit at line 215
	# skips the cache when both glob buckets are empty).
	# Must hold a reference to the EventCollector to keep the watcher alive —
	# EventCollector is RefCounted, and an unassigned result gets freed immediately.
	var _keep := watch_events("player.*")

	var unique_keys: int = 50
	for i: int in range(unique_keys):
		_chronicle.set_fact("player.key_%d" % i, i)

	# Access the raw watch bus to inspect cache size.
	var cache_size: int = _chronicle._watch_bus._seg_cache.size()
	assert_gte(cache_size, unique_keys,
		"_seg_cache should hold at least %d entries, got %d" % [unique_keys, cache_size])


# unwatch_all() is the only mechanism that resets _seg_cache
func test_seg_cache_cleared_only_by_unwatch_all() -> void:
	var _keep := watch_events("player.*")

	for i: int in range(20):
		_chronicle.set_fact("player.item_%d" % i, i)

	var size_before: int = _chronicle._watch_bus._seg_cache.size()
	assert_gt(size_before, 0, "cache should be non-empty before clear")

	_chronicle.unwatch_all()

	var size_after: int = _chronicle._watch_bus._seg_cache.size()
	assert_eq(size_after, 0, "_seg_cache should be empty after unwatch_all()")


# _seg_cache persists across unwatch/re-watch without unwatch_all — confirms
#     no automatic eviction path
func test_seg_cache_not_cleared_by_individual_unwatch() -> void:
	var events := watch_events("data.*")
	_chronicle.set_fact("data.alpha", 1)

	var id: int = events.watch_id
	_chronicle.unwatch(id)

	# Cache should still hold the entry from the dispatch above.
	var cache_size: int = _chronicle._watch_bus._seg_cache.size()
	assert_gt(cache_size, 0,
		"_seg_cache should not be cleared by individual unwatch(), got size=%d" % cache_size)


# unwatch_pattern during dispatch defers correctly — watcher does not fire
#     after the first event that triggered the unwatch
func test_unwatch_pattern_during_dispatch_defers_but_suppresses_further_fires() -> void:
	var count: Array[int] = [0]

	_chronicle.watch("target.x", func(_k: String, _v: Variant, _o: Variant) -> void:
		count[0] += 1
		_chronicle.unwatch_pattern("target.x")
	)

	_chronicle.set_fact("target.x", 1)
	assert_eq(count[0], 1, "watcher should fire once on the first dispatch")

	# After dispatch, the deferred unwatch_pattern should have cleaned up via
	# the _dead_ids → unwatch() path. A second set_fact must not fire.
	_chronicle.set_fact("target.x", 2)
	assert_eq(count[0], 1, "watcher should not fire after deferred unwatch_pattern resolved")


# After deferred unwatch_pattern resolves, calling unwatch_pattern on the
#     same exact pattern returns 0 — confirming the watcher is already gone
func test_unwatch_pattern_after_deferred_cleanup_returns_zero() -> void:
	_chronicle.watch("zone.a", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.unwatch_pattern("zone.a")
	)

	_chronicle.set_fact("zone.a", 99)

	# Both cleanup paths ran: _dead_ids unwatch + pending_unwatch_patterns unwatch_pattern.
	# A third manual call must find nothing.
	var removed: int = _chronicle.unwatch_pattern("zone.a")
	assert_eq(removed, 0,
		"unwatch_pattern after deferred cleanup should return 0 — entry already gone")


# Deferred glob unwatch_pattern also suppresses further fires
func test_glob_unwatch_pattern_during_dispatch_defers() -> void:
	var count: Array[int] = [0]

	_chronicle.watch("npc.*", func(_k: String, _v: Variant, _o: Variant) -> void:
		count[0] += 1
		_chronicle.unwatch_pattern("npc.*")
	)

	_chronicle.set_fact("npc.name", "Grok")
	assert_eq(count[0], 1, "watcher should fire once")

	_chronicle.set_fact("npc.hp", 100)
	assert_eq(count[0], 1, "watcher should not fire after deferred unwatch_pattern resolved")


# set_matcher() called from a watch callback mid-dispatch causes remaining
#     glob watchers in the same dispatch to switch to the new matcher path
func test_set_matcher_mid_dispatch_switches_remaining_watchers() -> void:
	var fired_a: Array[bool] = [false]
	var fired_b: Array[bool] = [false]

	# Watcher A (exact) fires first and calls set_matcher to replace with a
	# never-match function.
	_chronicle.watch("trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		fired_a[0] = true
		# Replace matcher with one that always returns false (never matches)
		_chronicle._watch_bus.set_matcher(
			func(_pat: String, _key: String) -> bool: return false,
			func(_pat: String) -> String: return ""
		)
	)

	# Watcher B (glob "*") lives in _glob_any_entity and is iterated AFTER the
	# exact dispatch. When set_matcher fires mid-dispatch, _custom_matcher_active
	# becomes true and pat_segs is erased from all entries. The elif branch at
	# _dispatch_glob_list line 263 calls _matches_fn (now never-match) for B.
	_chronicle.watch("*", func(_k: String, _v: Variant, _o: Variant) -> void:
		fired_b[0] = true
	)

	_chronicle.set_fact("trigger", 1)
	assert_true(fired_a[0], "watcher A (exact) should always fire")
	# Because the new matcher always returns false, watcher B (glob "*") should
	# NOT fire during the same dispatch — the split-matcher effect.
	assert_false(fired_b[0],
		"watcher B ('*') should be suppressed by the never-match fn set mid-dispatch")

	# Confirm B does fire when the new matcher is not changed back and a fresh
	# dispatch runs — proving the bug is in the MID-dispatch switch, not B itself
	# being permanently broken. (B stays broken because matcher was replaced.)
	_chronicle.set_fact("trigger", 2)
	assert_false(fired_b[0], "watcher B should also not fire on subsequent dispatch with never-match fn")


# "a.b.*" multi-segment prefix pattern is bucketed by the first segment (entity)
func test_multi_segment_prefix_pattern_lands_in_glob_any_entity() -> void:
	var _keep := watch_events("player.stats.*")

	# Trigger bucket rebuild by dispatching a matching key.
	_chronicle.set_fact("player.stats.str", 10)

	var any_entity: Array = _chronicle._watch_bus._glob_any_entity
	var by_entity: Dictionary = _chronicle._watch_bus._glob_by_entity

	# norm_prefix extracts the first segment ("player"), so the entry is
	# in _glob_by_entity["player"], NOT _glob_any_entity.
	var found_in_player_bucket: bool = false
	if "player" in by_entity:
		for e: Variant in by_entity["player"]:
			if e.pattern == "player.stats.*":
				found_in_player_bucket = true
				break
	assert_true(found_in_player_bucket,
		"'player.stats.*' should be in _glob_by_entity['player'] (entity-bucketed by first segment)")

	# It should NOT be in _glob_any_entity.
	var found_in_any: bool = false
	for entry: Variant in any_entity:
		if entry.pattern == "player.stats.*":
			found_in_any = true
			break
	assert_false(found_in_any,
		"'player.stats.*' should NOT be in _glob_any_entity (entity was extracted)")


# Single-segment prefix pattern IS entity-bucketed
func test_single_segment_prefix_pattern_is_entity_bucketed() -> void:
	var _keep := watch_events("player.*")

	_chronicle.set_fact("player.hp", 100)  # trigger rebuild

	var by_entity: Dictionary = _chronicle._watch_bus._glob_by_entity
	assert_has(by_entity, "player",
		"'player.*' should create a 'player' bucket in _glob_by_entity")

	var found: bool = false
	for entry: ChronicleWatchBus.WatchEntry in by_entity.get("player", []):
		if entry.pattern == "player.*":
			found = true
			break
	assert_true(found, "'player.*' entry should be in _glob_by_entity['player']")


# Multi-segment prefix pattern still matches correctly despite wrong bucket
func test_multi_segment_prefix_pattern_matches_correctly() -> void:
	var events := watch_events("player.stats.*")

	_chronicle.set_fact("player.stats.str", 10)
	_chronicle.set_fact("player.stats.dex", 8)
	_chronicle.set_fact("player.hp", 100)       # should NOT match
	_chronicle.set_fact("enemy.stats.str", 5)   # should NOT match

	events.assert_count(2)
	events.assert_keys(["player.stats.str", "player.stats.dex"])


# Glob watcher registered mid-dispatch does NOT appear in the current dispatch
func test_new_glob_during_dispatch_not_seen_in_same_dispatch() -> void:
	var inner_count: Array[int] = [0]

	_chronicle.watch("trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		# Register a new glob watcher during dispatch.
		_chronicle.watch("data.*", func(_k2: String, _v2: Variant, _o2: Variant) -> void:
			inner_count[0] += 1
		)
		# This write happens at _apply_depth=2 — the "data.*" buckets are not yet
		# rebuilt (_glob_watches_dirty is true but rebuild requires depth==0).
		# The new watcher DOES NOT fire for this write.
		_chronicle.set_fact("data.x", 1)
	)

	_chronicle.set_fact("trigger", 1)

	# data.x write was processed mid-dispatch (depth=2) before buckets rebuilt.
	# The new glob watcher was not in the buckets yet — it should NOT have fired.
	assert_eq(inner_count[0], 0,
		"newly registered glob should NOT fire for writes made before buckets are rebuilt")

	# A new write AFTER the top-level dispatch rebuilds buckets — the watcher fires.
	_chronicle.set_fact("data.y", 2)
	assert_eq(inner_count[0], 1,
		"newly registered glob should fire for writes after buckets are rebuilt")


# Watcher self-unwatching during glob dispatch does not corrupt iteration
func test_glob_self_unwatch_does_not_corrupt_iteration() -> void:
	var id_holder: Array[int] = [-1]
	var count_a: Array[int] = [0]
	var count_b: Array[int] = [0]

	id_holder[0] = _chronicle.watch("item.*", func(_k: String, _v: Variant, _o: Variant) -> void:
		count_a[0] += 1
		_chronicle.unwatch(id_holder[0])  # self-unwatch during glob dispatch
	)

	_chronicle.watch("item.*", func(_k: String, _v: Variant, _o: Variant) -> void:
		count_b[0] += 1
	)

	_chronicle.set_fact("item.sword", true)
	assert_eq(count_a[0], 1, "watcher A should fire once before self-unwatch")
	assert_eq(count_b[0], 1, "watcher B should still fire despite A's self-unwatch")

	# Second dispatch — A is gone, only B fires
	_chronicle.set_fact("item.shield", true)
	assert_eq(count_a[0], 1, "watcher A should not fire again after self-unwatch")
	assert_eq(count_b[0], 2, "watcher B should fire for second dispatch")


# ── R14/R15 bug regression ──


# unwatch_pattern destroys sibling patterns of watch_any groups
func test_unwatch_pattern_destroys_watch_any_siblings() -> void:
	var events: Array[Dictionary] = []
	var cb: Callable = func(key: String, value: Variant, _old: Variant) -> void:
		events.append({key = key, value = value})

	var id: int = _chronicle.watch_any(["player.*", "enemy.*"] as Array[String], cb)
	assert_gte(id, 0, "watch_any should succeed")

	# Unwatch only the player pattern — but for watch_any, this removes the
	# ENTIRE watcher (all patterns), not just the matching one.
	_chronicle.unwatch_pattern("player.*")

	# Write to enemy — the entire watch_any group was removed, so nothing fires
	_chronicle.set_fact("enemy.hp", 50)

	# Documented behavior: unwatch_pattern removes the entire watch_any group
	assert_eq(events.size(), 0,
		"entire watch_any group removed — enemy.* does not survive")


# unwatch_pattern during dispatch suppresses the second same-pattern glob watcher
func test_unwatch_pattern_during_dispatch_suppresses_second_glob() -> void:
	_chronicle.set_fact("player.hp", 100)
	var second_fired: Array[bool] = [false]

	_chronicle.watch("player.*", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.unwatch_pattern("player.*")
	)
	_chronicle.watch("player.*", func(_k: String, _v: Variant, _o: Variant) -> void:
		second_fired[0] = true
	)

	_chronicle.set_fact("player.hp", 200)

	# unwatch_pattern during dispatch marks ALL matching watcher IDs as dead
	# immediately (via _dead_ids). The second watcher shares the same pattern,
	# so it is also marked dead and suppressed in the same dispatch.
	assert_false(second_fired[0],
		"second glob watcher should be suppressed — unwatch_pattern marks all matching IDs dead")


# A _global.* watch must be REJECTED — the reserved internal prefix must not be
# watchable by user patterns (consistent with exact _global. key rejection).
# audit: R-A12-3c (EXPECTED-RED — product bug: reserved-prefix guard bypassed for wildcards)
func test_global_wildcard_watcher_is_rejected() -> void:
	# Set a bare (global) fact — stored internally as _global.score
	_chronicle.set_fact("score", 42)

	# EXPECTED CORRECT BEHAVIOR — currently FAILS (product bug: the reserved-prefix
	# guard is bypassed for wildcard patterns, so a _global.* watcher is accepted and
	# leaks Chronicle's internal global facts to user callbacks).
	var wid: int = _chronicle.watch("_global.*",
		func(_key: String, _v: Variant, _o: Variant) -> void: pass)
	assert_eq(wid, -1,
		"_global.* watcher must be rejected (reserved internal prefix)")
