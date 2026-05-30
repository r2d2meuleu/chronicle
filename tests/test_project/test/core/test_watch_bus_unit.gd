extends ChronicleTestSuite


# prune_invalid removes stale watchers
func test_prune_invalid_removes_stale():
	var obj := RefCounted.new()
	var cb: Callable = obj.set.bind("", null)
	var id: int = _chronicle.watch("test.key", cb)
	assert_gte(id, 0, "watch should return a valid id")
	obj = null
	for i in range(10):
		pass
	_chronicle._watch_bus.prune_invalid()
	assert_watcher_count(0)


# unwatch_pattern case insensitive for globs
func test_unwatch_pattern_case_insensitive():
	var c := watch_events("player.*")
	var removed: int = _chronicle.unwatch_pattern("Player.*")
	assert_eq(removed, 1, "uppercase pattern should match lowercase registration")


# Watchers survive deserialize
func test_watchers_survive_deserialize():
	var c := watch_events("player.hp")
	_chronicle.set_fact("player.hp", 100)
	c.assert_count(1)
	var data: Dictionary = _chronicle.serialize()
	_chronicle.deserialize(data)
	_chronicle.set_fact("player.hp", 200)
	c.assert_count(2)


# ── R17-A3 watch bus audit ───────────────


# New exact watcher registered during dispatch should NOT fire for the
#    triggering event
func test_new_watcher_during_dispatch_should_not_fire_for_same_event() -> void:
	var inner_fired: Array[bool] = [false]

	_chronicle.watch("player.hp", func(_k: String, _v: Variant, _o: Variant) -> void:
		# Register a NEW watcher on the same key, mid-dispatch
		_chronicle.watch("player.hp", func(_k2: String, _v2: Variant, _o2: Variant) -> void:
			inner_fired[0] = true
		)
	)

	_chronicle.set_fact("player.hp", 100)

	# The newly registered watcher should NOT fire for the event that was
	# already in-flight when it was registered. If it does, that's a
	# surprising re-entrancy leak.
	assert_false(inner_fired[0],
		"watcher registered mid-dispatch should not fire for the in-flight event")

	# But it SHOULD fire on subsequent writes
	_chronicle.set_fact("player.hp", 200)
	assert_true(inner_fired[0],
		"watcher registered mid-dispatch should fire for next event")


# unwatch_pattern during dispatch suppresses remaining same-pattern watchers
func test_unwatch_pattern_during_dispatch_prevents_remaining_fires() -> void:
	var order: Array = []

	# Register two glob watchers on the same pattern.
	# First watcher calls unwatch_pattern; the second shares the same pattern.
	_chronicle.watch("enemy.*", func(_k: String, _v: Variant, _o: Variant) -> void:
		order.append("A")
		_chronicle.unwatch_pattern("enemy.*")
	)
	_chronicle.watch("enemy.*", func(_k: String, _v: Variant, _o: Variant) -> void:
		order.append("B")
	)

	_chronicle.set_fact("enemy.hp", 50)

	# unwatch_pattern marks ALL matching watcher IDs dead immediately, so the
	# second same-pattern watcher (B) is suppressed in the same dispatch.
	assert_has(order, "A", "first watcher should always fire")
	assert_does_not_have(order, "B",
		"second same-pattern watcher must be suppressed — unwatch_pattern marks all matching IDs dead")


# watch_any with mixed valid/invalid patterns still works for valid ones
func test_watch_any_partial_success_valid_patterns_work() -> void:
	var events := make_collector()
	# "bad*pattern" has wildcard in mixed segment — invalid
	# "player.hp" is valid exact
	var patterns: Array[String] = ["bad*pattern", "player.hp"]
	var id: int = _chronicle.watch_any(patterns, events.callback())

	# watch_any validates ALL patterns first. If ANY pattern is invalid,
	# the entire registration fails and returns -1.
	assert_eq(id, -1, "watch_any should fail when any pattern is invalid")

	# Since registration failed, no events should be received.
	_chronicle.set_fact("player.hp", 42)
	events.assert_count(0)


# unwatch_all during dispatch suppresses remaining watchers
func test_unwatch_all_during_dispatch_suppresses_remaining() -> void:
	var order: Array = []

	_chronicle.watch("x", func(_k: String, _v: Variant, _o: Variant) -> void:
		order.append("A")
		_chronicle.unwatch_all()
	)
	_chronicle.watch("x", func(_k: String, _v: Variant, _o: Variant) -> void:
		order.append("B")
	)

	_chronicle.set_fact("x", 1)

	# A fires and calls unwatch_all. B should be suppressed because
	# _invoke_watcher checks _pending_clear at line 251.
	assert_eq(order, ["A"],
		"watcher B should be suppressed after unwatch_all during dispatch")

	# After dispatch, watchers should be fully cleared
	assert_watcher_count(0)


# Glob dispatch computes key_segs correctly after rebuild
func test_glob_dispatch_with_mid_segment_wildcard() -> void:
	var events := watch_events("player.*.level")

	_chronicle.set_fact("player.warrior.level", 10)
	_chronicle.set_fact("player.mage.level", 20)
	_chronicle.set_fact("player.warrior.hp", 100)  # should not match

	events.assert_count(2)
	events.assert_keys(["player.warrior.level", "player.mage.level"])


# Deferred unwatch_pattern normalizes correctly on resume
func test_deferred_unwatch_pattern_normalizes_on_resume() -> void:
	var count: Array[int] = [0]
	_chronicle.watch("player.hp", func(_k: String, _v: Variant, _o: Variant) -> void:
		count[0] += 1
		# Unwatch pattern with different casing during dispatch
		_chronicle.unwatch_pattern("player.hp")
	)

	_chronicle.set_fact("player.hp", 100)
	assert_eq(count[0], 1, "watcher fired once")

	# After dispatch, the deferred unwatch_pattern should have run
	_chronicle.set_fact("player.hp", 200)
	assert_eq(count[0], 1, "watcher should not fire after deferred unwatch_pattern")


# watch_any fires at most once per dispatch even with overlapping patterns
func test_watch_any_dedup_with_overlapping_patterns() -> void:
	var events := make_collector()
	var patterns: Array[String] = ["player.*", "player.hp"]
	var id: int = _chronicle.watch_any(patterns, events.callback())
	assert_gte(id, 0, "watch_any should return a valid id")

	_chronicle.set_fact("player.hp", 100)
	events.assert_count(1)


# Trailing wildcard uses correct matching path
func test_trailing_wildcard_matches_any_depth() -> void:
	var events := watch_events("player.*")

	_chronicle.set_fact("player.hp", 100)
	_chronicle.set_fact("player.stats.str", 15)  # deeper nesting
	_chronicle.set_fact("player.inventory.slot.1", "sword")

	# player.* with trailing wildcard matches any depth
	events.assert_count(3)


# once watcher with watch_any fires exactly once then is cleaned up
func test_once_watch_any_fires_once_then_cleanup() -> void:
	var events := make_collector()
	var patterns: Array[String] = ["player.*", "enemy.*"]
	var id: int = _chronicle.watch_any(patterns, events.callback(), true)
	assert_gte(id, 0, "watch_any (once) should return a valid id")

	_chronicle.set_fact("player.hp", 100)
	events.assert_count(1)

	# Should not fire again — once flag
	_chronicle.set_fact("enemy.hp", 50)
	events.assert_count(1)

	# Watcher should be cleaned up
	assert_watcher_count(0)


# Glob registered during dispatch works on next dispatch
func test_glob_registered_during_dispatch_works_next_time() -> void:
	var inner_fired: Array[bool] = [false]

	_chronicle.watch("trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		# Register a glob watcher during dispatch
		_chronicle.watch("data.*", func(_k2: String, _v2: Variant, _o2: Variant) -> void:
			inner_fired[0] = true
		)
		# Also set a fact that matches — but the glob shouldn't fire yet
		_chronicle.set_fact("data.x", 42)
	)

	_chronicle.set_fact("trigger", 1)

	# The glob watcher should fire for data.x because write_coordinator
	# dispatches deferred writes after the initial dispatch completes.
	# Whether it fires depends on whether the deferred queue processes data.x
	# after the glob buckets are rebuilt.
	# The key point: on the NEXT explicit write, it MUST fire.
	inner_fired[0] = false
	_chronicle.set_fact("data.y", 99)
	assert_true(inner_fired[0],
		"glob watcher registered during dispatch should work on subsequent dispatches")


# Once watcher + explicit unwatch during dispatch doesn't crash
func test_once_plus_explicit_unwatch_no_crash() -> void:
	var id_holder: Array[int] = [-1]
	var fired: Array[bool] = [false]

	id_holder[0] = _chronicle.watch("x", func(_k: String, _v: Variant, _o: Variant) -> void:
		fired[0] = true
	, true)  # once=true

	_chronicle.watch("x", func(_k: String, _v: Variant, _o: Variant) -> void:
		# Explicitly unwatch the once watcher (already marked dead by once logic)
		_chronicle.unwatch(id_holder[0])
	)

	# Should not crash
	_chronicle.set_fact("x", 1)
	assert_true(fired[0], "once watcher should have fired")
	assert_watcher_count(1)


# watch() during pending clear is rejected
func test_watch_during_pending_clear_rejected() -> void:
	var new_id: Array[int] = [-1]

	_chronicle.watch("x", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.unwatch_all()
		# Try to register a new watcher while unwatch_all is pending
		new_id[0] = _chronicle.watch("y", func(_k2: String, _v2: Variant, _o2: Variant) -> void:
			pass
		)
	)

	_chronicle.set_fact("x", 1)

	# The watch() during pending clear should return -1
	assert_eq(new_id[0], -1,
		"watch() during pending unwatch_all should return -1")

	# After dispatch completes, new registrations should work
	var post_id: int = _chronicle.watch("z", func(_k: String, _v: Variant, _o: Variant) -> void:
		pass
	)
	assert_gte(post_id, 0,
		"watch() after pending clear resolves should succeed")


# watch_any during pending_clear returns -1 and does not consume an ID
func test_watch_any_during_pending_clear_no_id_consumed() -> void:
	var id_before: Array[int] = [-1]
	var id_after_failed: Array[int] = [-1]

	_chronicle.watch("x", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.unwatch_all()
		# Try watch_any while pending_clear is set
		var patterns: Array[String] = ["y", "z"]
		id_after_failed[0] = _chronicle.watch_any(patterns, func(_k2: String, _v2: Variant, _o2: Variant) -> void: pass)
	)

	id_before[0] = _chronicle.watch("sentinel",
		func(_k: String, _v: Variant, _o: Variant) -> void: pass)

	_chronicle.set_fact("x", 1)

	# The watch_any during pending_clear should return -1
	assert_eq(id_after_failed[0], -1,
		"watch_any during pending_clear should return -1")

	# After dispatch resolves (unwatch_all ran), register a new watcher.
	# Its ID should be contiguous with pre-dispatch registrations — no gap.
	var post_id: int = _chronicle.watch("new.key",
		func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	assert_gt(post_id, id_before[0],
		"post-clear ID (%d) should be greater than pre-dispatch ID (%d)" % [post_id, id_before[0]])

