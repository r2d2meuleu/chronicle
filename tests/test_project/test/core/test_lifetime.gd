extends ChronicleTestSuite


# Fact set with lifetime is stored and readable
func test_fact_with_lifetime_is_stored() -> void:
	set_time(1.0)
	_chronicle.set_fact("buff.speed", 2.0, false, 5.0)
	assert_fact("buff.speed", 2.0)


# Lifetime implies transient — excluded from serialize facts
func test_lifetime_implies_transient_facts_excluded() -> void:
	_chronicle.set_fact("buff.atk", 5, false, 10.0)
	_chronicle.set_fact("player.gold", 100)
	var data: Dictionary = _chronicle.serialize()
	assert_has(data["facts"], "player.gold", "persistent fact present")
	var has_buff: bool = false
	for k: String in data["facts"]:
		if "buff" in k:
			has_buff = true
	assert_false(has_buff, "lifetime fact excluded from serialize")


# Lifetime implies transient — timeline entries excluded from serialize
func test_lifetime_implies_transient_timeline_excluded() -> void:
	set_time(1.0)
	_chronicle.set_fact("buff.atk", 5, false, 10.0)
	var data: Dictionary = _chronicle.serialize()
	var found: bool = false
	for entry: Dictionary in data["timeline"]:
		if "buff" in entry.get("key", ""):
			found = true
	assert_false(found, "lifetime fact timeline excluded from serialize")


# Re-set with lifetime resets the timer (new expiry from now)
func test_reset_resets_timer() -> void:
	set_time(1.0)
	_chronicle.set_fact("buff.x", 10, false, 3.0)
	set_time(3.0)
	_chronicle.set_fact("buff.x", 20, false, 5.0)
	assert_fact("buff.x", 20)
	assert_eq(_chronicle.get_expiry_remaining("buff.x"), 5.0, "timer was reset to 5s from t=3")


# Re-set WITH lifetime=0 clears existing timer; re-set without lifetime preserves it
func test_reset_without_lifetime_cancels_timer() -> void:
	set_time(1.0)
	_chronicle.set_fact("buff.x", 10, false, 3.0)
	# KEEP_LIFETIME is now the default — re-set without explicit lifetime preserves the expiry
	_chronicle.set_fact("buff.x", 20, false, 0.0)
	assert_eq(_chronicle.get_expiry_remaining("buff.x"), -1.0, "timer cancelled by explicit lifetime=0.0")
	assert_fact("buff.x", 20)


# erase_fact cancels timer (no ghost expiry later)
func test_erase_fact_cancels_timer() -> void:
	set_time(1.0)
	_chronicle.set_fact("buff.x", 10, false, 3.0)
	_chronicle.erase_fact("buff.x")
	assert_eq(_chronicle.get_expiry_remaining("buff.x"), -1.0, "timer cancelled by erase")
	assert_no_fact("buff.x")


# Fact expires after lifetime elapses
func test_fact_expires_after_lifetime() -> void:
	set_time(1.0)
	_chronicle.set_fact("buff.speed", 2.0, false, 5.0)
	advance_time(4.9)
	assert_fact("buff.speed", 2.0)
	advance_time(0.2)
	assert_no_fact("buff.speed")


# Fact present before expiry
func test_fact_present_before_expiry() -> void:
	set_time(0.0)
	_chronicle.set_fact("buff.shield", true, false, 3.0)
	advance_time(2.9)
	assert_fact("buff.shield", true)


# Lifetime uses game clock, not wall clock
func test_lifetime_uses_game_clock() -> void:
	set_time(10.0)
	_chronicle.set_fact("buff.shield", true, false, 5.0)
	assert_fact("buff.shield", true)
	set_time(15.1)
	assert_no_fact("buff.shield")


# fact_expired signal fires on expiry
func test_fact_expired_signal_fires() -> void:
	var events := collect_signal(_chronicle, "fact_expired")
	set_time(0.0)
	_chronicle.set_fact("buff.x", 42, false, 3.0)
	advance_time(3.1)
	events.assert_count(1)


# fact_expired carries correct key and value
func test_fact_expired_correct_payload() -> void:
	var events := collect_signal(_chronicle, "fact_expired")
	set_time(0.0)
	_chronicle.set_fact("buff.x", 42, false, 3.0)
	advance_time(3.1)
	events.assert_event(0, "buff.x", 42)


# fact_expired fires on expiry; fact_changed fires with null value
func test_expired_signal_fires_on_expiry() -> void:
	var order: Array = []
	_chronicle.fact_expired.connect(func(_k: String, _v: Variant) -> void: order.append("expired"))
	_chronicle.fact_changed.connect(func(k: String, v: Variant, _o: Variant, _s: int = 0) -> void:
		if "buff" in k and v == null:
			order.append("changed_null"))
	set_time(0.0)
	_chronicle.set_fact("buff.x", 42, false, 3.0)
	advance_time(3.1)
	assert_has(order, "expired", "fact_expired must fire on expiry")
	assert_has(order, "changed_null", "fact_changed(null) must fire on expiry")


# fact_changed fires with null on expiry; fact_expired also fires
func test_fact_changed_on_expiry() -> void:
	var changed_null: Array = []
	_chronicle.fact_changed.connect(func(key: String, value: Variant, old_value: Variant, _erase_source: int = 0) -> void:
		if value == null:
			changed_null.append({key = key, old_value = old_value}))
	set_time(0.0)
	_chronicle.set_fact("buff.x", 42, false, 3.0)
	changed_null.clear()
	advance_time(3.1)
	assert_eq(changed_null.size(), 1, "fact_changed(null) should fire on expiry")
	assert_eq(changed_null[0].key, "buff.x")
	assert_eq(changed_null[0].old_value, 42)


# advance_game_time triggers expiry
func test_advance_game_time_triggers_expiry() -> void:
	set_time(0.0)
	_chronicle.set_fact("buff.x", 1, false, 5.0)
	advance_time(5.5)
	assert_no_fact("buff.x")


# set_game_time triggers expiry
func test_set_game_time_triggers_expiry() -> void:
	set_time(0.0)
	_chronicle.set_fact("buff.x", 1, false, 5.0)
	set_time(6.0)
	assert_no_fact("buff.x")


# Zero lifetime means no expiry (fact persists)
func test_zero_lifetime_no_expiry() -> void:
	_chronicle.set_fact("normal", 42, false, 0.0)
	advance_time(100.0)
	assert_fact("normal", 42)


# Watcher fires on expiry with null value
func test_watcher_fires_on_expiry() -> void:
	var events: EventCollector = watch_events("buff.x")
	set_time(0.0)
	_chronicle.set_fact("buff.x", 42, false, 3.0)
	events.clear()
	advance_time(3.1)
	events.assert_count(1)
	events.assert_event(0, "buff.x", null, 42)


# get_expiry_remaining with active timer
func test_remaining_lifetime_active() -> void:
	set_time(10.0)
	_chronicle.set_fact("buff.x", 1, false, 5.0)
	set_time(12.0)
	var remaining: float = _chronicle.get_expiry_remaining("buff.x")
	assert_almost_eq(remaining, 3.0, 0.01, "should have ~3s remaining")


# get_expiry_remaining with no timer
func test_remaining_lifetime_no_timer() -> void:
	_chronicle.set_fact("player.gold", 100)
	assert_eq(_chronicle.get_expiry_remaining("player.gold"), -1.0)


# get_expiry_remaining for nonexistent key
func test_remaining_lifetime_nonexistent() -> void:
	assert_eq(_chronicle.get_expiry_remaining("no.such.key"), -1.0)


# get_expiry_remaining after expiry
func test_remaining_lifetime_after_expiry() -> void:
	set_time(0.0)
	_chronicle.set_fact("buff.x", 1, false, 2.0)
	advance_time(3.0)
	assert_eq(_chronicle.get_expiry_remaining("buff.x"), -1.0)


# clear cancels all lifetime timers
func test_clear_cancels_all_timers() -> void:
	var events := collect_signal(_chronicle, "fact_expired")
	_chronicle.set_fact("a.x", 1, false, 5.0)
	_chronicle.set_fact("b.x", 2, false, 10.0)
	_chronicle.clear()
	set_time(0.0)
	advance_time(15.0)
	events.assert_count(0)
	assert_no_fact("a.x")
	assert_no_fact("b.x")


# Multiple facts expire in correct order
func test_multiple_expire_in_order() -> void:
	var events := collect_signal(_chronicle, "fact_expired")
	set_time(0.0)
	_chronicle.set_fact("short", 1, false, 2.0)
	_chronicle.set_fact("medium", 2, false, 5.0)
	_chronicle.set_fact("long", 3, false, 10.0)
	advance_time(11.0)
	events.assert_count(3)
	events.assert_keys(["short", "medium", "long"])


# set_facts bulk with lifetime
func test_set_facts_bulk_with_lifetime() -> void:
	set_time(0.0)
	_chronicle.set_facts({"buff.a": 1, "buff.b": 2}, false, 5.0)
	assert_fact("buff.a", 1)
	assert_fact("buff.b", 2)
	advance_time(5.5)
	assert_no_fact("buff.a")
	assert_no_fact("buff.b")


# set_facts bulk — lifetime implies transient
func test_set_facts_bulk_excluded_from_serialize() -> void:
	_chronicle.set_facts({"buff.a": 1, "buff.b": 2}, false, 5.0)
	var data: Dictionary = _chronicle.serialize()
	var has_buff: bool = false
	for k: String in data["facts"]:
		if "buff" in k:
			has_buff = true
	assert_false(has_buff, "bulk lifetime facts excluded from serialize")


# mark with lifetime
func test_mark_with_lifetime() -> void:
	set_time(0.0)
	_chronicle.set_fact("temp.flag", true, false, 3.0)
	assert_marked("temp.flag")
	advance_time(3.5)
	assert_not_marked("temp.flag")
	assert_no_fact("temp.flag")


# Sub-frame lifetime expires on next tick
func test_sub_frame_lifetime_expires() -> void:
	set_time(0.0)
	_chronicle.set_fact("flash", true, false, 0.001)
	advance_time(0.016)
	assert_no_fact("flash")


# Rollback preserves lifetime facts and their timers
func test_rollback_preserves_lifetime() -> void:
	set_time(1.0)
	_chronicle.set_fact("persist.a", 100)
	_chronicle.set_fact("buff.x", 10, false, 8.0)
	set_time(2.0)
	_chronicle.set_fact("persist.a", 200)
	_chronicle.rollback_to(1.5)
	assert_fact("buff.x", 10)
	assert_gt(_chronicle.get_expiry_remaining("buff.x"), 0.0, "timer still active after rollback")
	set_time(9.5)
	assert_no_fact("buff.x")


# Gate closes when lifetime fact expires
func test_gate_closes_on_expiry() -> void:
	var parent := add_node_2d("GateTarget")
	var gate := CompanionFactory.make_gate({
		condition = "buff.visible",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	parent.add_child(gate)
	assert_gate_closed(parent)
	set_time(0.0)
	_chronicle.set_fact("buff.visible", true, false, 3.0)
	assert_gate_open(parent)
	advance_time(3.1)
	assert_gate_closed(parent)


# Reactor fires when lifetime fact expires
func test_reactor_fires_on_expiry() -> void:
	var reactor: Node = add_reactor({watch_pattern = "buff.*"})
	set_time(0.0)
	_chronicle.set_fact("buff.speed", 2.0, false, 3.0)
	assert_spy_calls(reactor, 1)
	advance_time(3.1)
	assert_spy_calls(reactor, 2)
	assert_spy_call(reactor, 1, EventCollector.SKIP, null)


# Lifetime with Vector2 value type
func test_lifetime_with_vector2() -> void:
	set_time(0.0)
	_chronicle.set_fact("player.knockback", Vector2(10, 5), false, 2.0)
	assert_fact("player.knockback", Vector2(10, 5))
	advance_time(2.5)
	assert_no_fact("player.knockback")


# Lifetime with Dictionary value — deep copy isolation
func test_lifetime_with_dictionary() -> void:
	var d: Dictionary = {"power": 3}
	_chronicle.set_fact("buff.data", d, false, 5.0)
	d["power"] = 999
	assert_fact("buff.data", {"power": 3})


# Re-entrant: watcher on expiry sets a NEW key with lifetime
func test_reentrant_new_key_on_expiry() -> void:
	_chronicle.watch("buff.x", func(key: String, value: Variant, _old: Variant) -> void:
		if value == null:
			_chronicle.set_fact("buff.y", 99, false, 5.0))
	set_time(0.0)
	_chronicle.set_fact("buff.x", 1, false, 2.0)
	advance_time(2.5)
	assert_no_fact("buff.x")
	assert_fact("buff.y", 99)
	advance_time(5.5)
	assert_no_fact("buff.y")


# Re-entrant: watcher renews the SAME key on first expiry only
func test_reentrant_renew_same_key() -> void:
	var renew_count: Array = [0]
	_chronicle.watch("buff.x", func(_key: String, value: Variant, _old: Variant) -> void:
		if value == null and renew_count[0] == 0:
			renew_count[0] += 1
			_chronicle.set_fact("buff.x", 1, false, 2.0))
	set_time(0.0)
	_chronicle.set_fact("buff.x", 1, false, 2.0)
	advance_time(2.5)
	assert_fact("buff.x", 1)
	advance_time(2.5)
	assert_no_fact("buff.x")


# increment preserves existing lifetime timer
func test_increment_preserves_timer() -> void:
	set_time(0.0)
	_chronicle.set_fact("player.combo", 0, false, 5.0)
	set_time(2.0)
	_chronicle.increment_fact("player.combo")
	assert_fact("player.combo", 1)
	assert_gt(_chronicle.get_expiry_remaining("player.combo"), 0.0, "timer preserved by increment")
	advance_time(4.0)
	assert_no_fact("player.combo")


# decrement preserves existing lifetime timer
func test_decrement_preserves_timer() -> void:
	set_time(0.0)
	_chronicle.set_fact("player.charges", 5, false, 10.0)
	_chronicle.increment_fact("player.charges", -1.0)
	assert_fact("player.charges", 4)
	assert_gt(_chronicle.get_expiry_remaining("player.charges"), 0.0, "timer preserved by decrement")


# Deep copy isolation for lifetime fact
func test_deep_copy_isolation() -> void:
	var arr: Array = [1, 2, 3]
	_chronicle.set_fact("temp.list", arr, false, 10.0)
	arr.append(4)
	assert_fact("temp.list", [1, 2, 3])


# Negative lifetime writes fact without expiry (value is preserved, only expiry is dropped)
func test_negative_lifetime_writes_without_expiry() -> void:
	_chronicle.set_fact("buff.x", 1, false, -5.0)
	assert_fact("buff.x", 1)
	assert_no_expiry("buff.x")


# INF lifetime writes fact without expiry (value is preserved, only expiry is dropped)
func test_inf_lifetime_writes_without_expiry() -> void:
	_chronicle.set_fact("buff.x", 1, false, INF)
	assert_fact("buff.x", 1)
	assert_no_expiry("buff.x")


# NAN lifetime writes fact without expiry (value is preserved, only expiry is dropped)
func test_nan_lifetime_writes_without_expiry() -> void:
	_chronicle.set_fact("buff.x", 1, false, NAN)
	assert_fact("buff.x", 1)
	assert_no_expiry("buff.x")
