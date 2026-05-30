extends ChronicleTestSuite

# Smoke tests for ChronicleTestSuite helpers. Each sets up the precondition,
# calls the helper, and expects the suite to stay green (helper asserts correctly).

# assert_idle passes when no cascade is running
func test_assert_idle_when_idle() -> void:
	_chronicle.set_fact("a", 1)
	assert_idle()

# assert_has_expiry passes when fact has an expiry
func test_assert_has_expiry() -> void:
	_chronicle.set_fact("buff", true, false, 5.0)
	assert_has_expiry("buff")

# assert_no_expiry passes when fact has no expiry
func test_assert_no_expiry() -> void:
	_chronicle.set_fact("perm", true)
	assert_no_expiry("perm")

# assert_has_fact passes for existence regardless of value
func test_assert_has_fact() -> void:
	_chronicle.set_fact("x", 0)  # falsy, but exists
	assert_has_fact("x")

# assert_transient / assert_not_transient
func test_assert_transient() -> void:
	_chronicle.set_fact("t", 1, true)
	assert_transient("t")
	_chronicle.set_fact("p", 1, false)
	assert_not_transient("p")

# assert_fact_type checks stored value type
func test_assert_fact_type() -> void:
	_chronicle.set_fact("n", 42)
	assert_fact_type("n", TYPE_INT)

# assert_game_time reflects the clock
func test_assert_game_time() -> void:
	set_time(12.0)
	assert_game_time(12.0)

# assert_watcher_count reflects active watchers
func test_assert_watcher_count() -> void:
	assert_watcher_count(0)
	watch_events("a.*")
	assert_watcher_count(1)

# assert_rollback_ok on a successful rollback
func test_assert_rollback_ok() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("a", 2)
	assert_rollback_ok(_chronicle.rollback_to(1.0))
	assert_fact("a", 1)

# assert_rollback_rejected when rollback cannot proceed
func test_assert_rollback_rejected() -> void:
	# Rolling back to a future time with no entries is a no-op/rejected.
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	assert_rollback_rejected(_chronicle.rollback_to(99.0))

# first/last change for a pattern
func test_assert_first_last_change() -> void:
	set_time(1.0)
	_chronicle.set_fact("score", 10)
	set_time(2.0)
	_chronicle.set_fact("score", 20)
	assert_first_change("score", "score", 10)
	assert_last_change("score", "score", 20)

# no first/last change when nothing matches
func test_assert_no_first_last_change() -> void:
	assert_no_first_change("missing.*")
	assert_no_last_change("missing.*")

# changes-since count
func test_assert_changes_since_count() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	assert_changes_since_count(1.5, 1)

# roundtrip preserves non-transient facts through serialize/clear/deserialize
func test_roundtrip_preserves_facts() -> void:
	_chronicle.set_fact("kept", 7)
	_chronicle.set_fact("temp", 9, true)  # transient — excluded from serialization
	roundtrip()
	assert_fact("kept", 7)
	assert_no_fact("temp")

# spy call count + individual call inspection (reactor writes to its SpyNode parent)
func test_assert_spy_calls() -> void:
	var reactor: Node = add_reactor({watch_pattern = "evt.*"})
	_chronicle.set_fact("evt.hit", 3)
	assert_spy_calls(reactor, 1)
	assert_spy_call(reactor, 0, "evt.hit", 3)

# assert_history with old_values
func test_assert_history_old_values() -> void:
	_chronicle.set_fact("hp", 100)
	_chronicle.set_fact("hp", 80)
	assert_history("hp", [100, 80], [], [null, 100])

# high-volume history helpers
func test_assert_history_size_first_last() -> void:
	for i in 50:
		_chronicle.set_fact("v", i)
	assert_history_size("v", 50)
	assert_history_first("v", 0)
	assert_history_last("v", 49)

# unified collect_signal captures real time on a 4-arg signal (fact_changed)
func test_collect_signal_captures_time_4arg() -> void:
	set_time(5.0)
	var c := collect_signal(_chronicle, "fact_changed")
	_chronicle.set_fact("x", 1)
	c.assert_count(1)
	c.assert_event(0, "x", 1, null)
	c.assert_event_time(0, 5.0)

# unified collect_signal works on a 3-arg node signal (reactor fact_matched)
func test_collect_signal_3arg_reactor() -> void:
	var reactor: Node = add_reactor({watch_pattern = "m.*"})
	var c := collect_signal(reactor, "fact_matched")
	_chronicle.set_fact("m.go", 2)
	c.assert_count(1)
	c.assert_event(0, "m.go", 2)

# unified collect_signal works on a 2-arg signal (fact_expired)
func test_collect_signal_2arg_expired() -> void:
	var c := collect_signal(_chronicle, "fact_expired")
	_chronicle.set_fact("e", true, false, 1.0)
	advance_time(2.0)
	_chronicle.flush_expiry()
	c.assert_count(1)
	c.assert_event(0, "e")

# collect_any_signal captures 0-arg and 1-arg user-signal emissions
func test_collect_any_signal_arity() -> void:
	var node0 := add_signaled_node("pinged")
	var c0 := collect_any_signal(node0, "pinged")
	node0.emit_signal("pinged")
	node0.emit_signal("pinged")
	c0.assert_emission_count(2)
	c0.assert_emission_args(0, [])

	var node1 := add_signaled_node("ticked", [{"name": "t", "type": TYPE_FLOAT}])
	var c1 := collect_any_signal(node1, "ticked")
	node1.emit_signal("ticked", 3.5)
	c1.assert_emission_count(1)
	c1.assert_emission_args(0, [3.5])


# serialize_into_new returns an independent loaded instance
func test_serialize_into_new_returns_independent_loaded_instance() -> void:
	_chronicle.set_fact("player.hp", 42)
	_chronicle.set_fact("player.name", "hero")
	var c2: Node = serialize_into_new()
	assert_eq(c2.get_fact("player.hp"), 42, "new instance has deserialized fact")
	assert_eq(c2.get_fact("player.name"), "hero")
	c2.set_fact("player.hp", 99)
	assert_eq(_chronicle.get_fact("player.hp"), 42, "original unaffected by new instance")


# Base after_each restores the timeline cap between tests
func test_timeline_cap_is_restored_between_tests_via_base() -> void:
	var default_cap: int = _chronicle.get_timeline_cap()
	_chronicle.set_timeline_cap(50000)
	assert_eq(_chronicle.get_timeline_cap(), 50000)
	after_each()
	before_each()
	assert_eq(_chronicle.get_timeline_cap(), default_cap,
		"base after_each must restore the timeline cap (clear() does not reset _cap)")
