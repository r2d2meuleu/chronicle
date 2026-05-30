extends ChronicleTestSuite


# watch_once fires exactly once on exact key match
func test_fires_once_on_exact_key() -> void:
	var events := watch_once_events("player.gold")
	events.assert_valid_id()
	_chronicle.set_fact("player.gold", 100)
	events.assert_count(1)


# watch_once does NOT fire a second time
func test_does_not_fire_second_time() -> void:
	var events := watch_once_events("player.gold")

	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.gold", 200)
	_chronicle.set_fact("player.gold", 300)
	events.assert_count(1)


# watch_once with glob pattern fires once
func test_glob_fires_once() -> void:
	var events := watch_once_events("player.*")

	_chronicle.set_fact("player.gold", 100)
	events.assert_count(1)
	events.assert_event(0, "player.gold")


# watch_once with glob pattern does NOT fire again
func test_glob_does_not_fire_again() -> void:
	var events := watch_once_events("player.*")

	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.hp", 50)
	_chronicle.set_fact("player.name", "Hero")
	events.assert_count(1)


# Array pattern fires once, unwatches all patterns in the group
func test_array_pattern_fires_once_unwatches_all() -> void:
	var events := watch_once_events(["player.gold", "player.hp"])

	_chronicle.set_fact("player.gold", 100)
	events.assert_count(1)
	events.assert_event(0, "player.gold")

	# Second key should NOT fire — the entire watch_once group is spent
	_chronicle.set_fact("player.hp", 50)
	events.assert_count(1)


# Cancel before fire — unwatch before any set_fact
func test_cancel_before_fire() -> void:
	var events := watch_once_events("player.gold")
	_chronicle.unwatch(events.watch_id)
	_chronicle.set_fact("player.gold", 100)
	events.assert_count(0)


# Callback receives correct (key, value, old_value) args
func test_correct_callback_args() -> void:
	_chronicle.set_fact("player.gold", 50)

	var events := watch_once_events("player.gold")

	_chronicle.set_fact("player.gold", 100)
	events.assert_count(1)
	events.assert_event(0, "player.gold", 100, 50)


# Dotless key is denormalized in callback (user sees "flag" not "_global.flag")
func test_dotless_key_denormalized_in_callback() -> void:
	var events := watch_once_events("flag")
	_chronicle.set_fact("flag", true)
	events.assert_count(1)
	events.assert_event(0, "flag")


# Re-entrant callback: callback calls set_fact on a different key
func test_reentrant_callback_different_key() -> void:
	# Re-entrant side-effects need a hand-written lambda.
	var gold_fired: Array = []
	_chronicle.watch("player.gold", func(key: String, value: Variant, old_value: Variant) -> void:
		gold_fired.append(true)
		_chronicle.set_fact("player.bonus", 10)
	, true)

	var bonus_events := watch_once_events("player.bonus")

	_chronicle.set_fact("player.gold", 100)
	assert_eq(gold_fired.size(), 1)
	assert_fact("player.bonus", 10)
	bonus_events.assert_count(1)


# Re-entrant same-key: callback calls set_fact on the SAME key matching the pattern
func test_reentrant_callback_same_key() -> void:
	var fired: Array = []
	_chronicle.watch("player.gold", func(key: String, value: Variant, old_value: Variant) -> void:
		fired.append(value)
		# Re-entrant set_fact on the same key — the once-watch is already spent
		_chronicle.set_fact("player.gold", 999)
	, true)

	_chronicle.set_fact("player.gold", 100)
	assert_eq(fired.size(), 1)
	assert_eq(fired[0], 100)
	assert_fact("player.gold", 999)


# Calling unwatch after auto-unwatch is a no-op (no crash)
func test_unwatch_after_auto_unwatch_is_noop() -> void:
	var events := watch_once_events("player.gold")

	_chronicle.set_fact("player.gold", 100)
	events.assert_count(1)

	# This should not crash — the watch was already auto-removed
	_chronicle.unwatch(events.watch_id)

	# Verify no side effects
	_chronicle.set_fact("player.gold", 200)
	events.assert_count(1)


# watch_once returns valid unique IDs
func test_returns_valid_unique_ids() -> void:
	var e1 := watch_once_events("player.gold")
	var e2 := watch_once_events("player.hp")
	var e3 := watch_once_events("player.name")

	e1.assert_valid_id()
	e2.assert_valid_id()
	e3.assert_valid_id()
	assert_ne(e1.watch_id, e2.watch_id, "watch ids must be unique")
	assert_ne(e1.watch_id, e3.watch_id, "watch ids must be unique")
	assert_ne(e2.watch_id, e3.watch_id, "watch ids must be unique")


# watch_once coexists with regular watch — regular watch keeps firing
func test_coexists_with_regular_watch() -> void:
	var once_events := watch_once_events("player.gold")
	var regular_events := watch_events("player.gold")

	_chronicle.set_fact("player.gold", 100)
	once_events.assert_count(1)
	regular_events.assert_count(1)

	_chronicle.set_fact("player.gold", 200)
	once_events.assert_count(1)
	regular_events.assert_count(2)

	_chronicle.set_fact("player.gold", 300)
	once_events.assert_count(1)
	regular_events.assert_count(3)


# Multiple watch_once on same key fire independently
func test_multiple_watch_once_same_key_fire_independently() -> void:
	var events_a := watch_once_events("player.gold")
	var events_b := watch_once_events("player.gold")

	_chronicle.set_fact("player.gold", 100)
	events_a.assert_count(1)
	events_b.assert_count(1)
	events_a.assert_event(0, EventCollector.SKIP, 100)
	events_b.assert_event(0, EventCollector.SKIP, 100)

	# Neither should fire again
	_chronicle.set_fact("player.gold", 200)
	events_a.assert_count(1)
	events_b.assert_count(1)


# Invalid pattern returns -1
func test_invalid_pattern_returns_negative_one() -> void:
	# Use EventCollector.watch_once directly — watch_once_events() asserts valid id by design
	var e_int := EventCollector.watch_once(self, _chronicle, 42)
	e_int.assert_invalid_id()

	var e_mixed := EventCollector.watch_once(self, _chronicle, "play*er.gold")
	e_mixed.assert_invalid_id()

	var e_mid := EventCollector.watch_once(self, _chronicle, "player*gold")
	e_mid.assert_invalid_id()


# Re-entrant same-key: once-watch must not double-fire when callback sets the same key
func test_once_reentrant_same_key_no_double_fire() -> void:
	var fired: Array = []
	_chronicle.watch("player.gold", func(key: String, value: Variant, _old_value: Variant) -> void:
		fired.append(value)
		_chronicle.set_fact("player.gold", 999)
	, true)
	_chronicle.set_fact("player.gold", 100)
	assert_eq(fired.size(), 1)
	assert_eq(fired[0], 100)
	assert_fact("player.gold", 999)


# Re-entrant glob same-key: once-watch glob must not double-fire when callback sets a matching key
func test_once_glob_reentrant_same_key_no_double_fire() -> void:
	var fired: Array = []
	_chronicle.watch("player.*", func(key: String, _value: Variant, _old_value: Variant) -> void:
		fired.append(key)
		_chronicle.set_fact("player.hp", 50)
	, true)
	_chronicle.set_fact("player.gold", 100)
	assert_eq(fired.size(), 1)
	assert_eq(fired[0], "player.gold")
	assert_fact("player.hp", 50)


# watch_any_once fires once then auto-unwatches
func test_watch_any_once() -> void:
	var c := make_collector()
	var patterns: Array[String] = ["a", "b"]
	var id: int = _chronicle.watch_any_once(patterns, c.callback())
	assert_gte(id, 0, "watch_any_once should return a valid id")
	_chronicle.set_fact("a", 1)
	_chronicle.set_fact("b", 2)
	c.assert_count(1)
	assert_watcher_count(0)


# ── Error paths: invalid callback / empty patterns return -1 ──

func test_watch_once_invalid_callback_returns_negative() -> void:
	assert_eq(_chronicle.watch_once("player.hp", Callable()), -1,
		"watch_once with an invalid callback should return -1")
	assert_watcher_count(0)


func test_watch_any_once_invalid_callback_returns_negative() -> void:
	assert_eq(_chronicle.watch_any_once(["player.hp"] as Array[String], Callable()), -1,
		"watch_any_once with an invalid callback should return -1")
	assert_watcher_count(0)


func test_watch_any_once_empty_patterns_returns_negative() -> void:
	assert_eq(_chronicle.watch_any_once([] as Array[String], func(_k, _v, _o) -> void: pass), -1,
		"watch_any_once with an empty patterns array should return -1")
	assert_watcher_count(0)
