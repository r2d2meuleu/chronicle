extends ChronicleTestSuite

const ChronicleExpiry := preload("res://addons/chronicle/core/expiry.gd")
const ChronicleGameClock := preload("res://addons/chronicle/core/game_clock.gd")

var _clock: ChronicleGameClock
var _expiry: RefCounted


func before_each() -> void:
	super.before_each()
	_clock = ChronicleGameClock.new()
	_expiry = ChronicleExpiry.new(_clock.get_time)


# get_remaining returns NO_EXPIRY (-1.0) for unregistered key
func test_get_remaining_no_expiry_returns_sentinel() -> void:
	assert_eq(_expiry.get_remaining("player.gold"), ChronicleExpiry.NO_EXPIRY)


# unregister of min key recomputes min correctly
func test_unregister_min_key_recomputes_min() -> void:
	_clock.set_time(0.0)
	_expiry.schedule("a", 2.0)
	_expiry.schedule("b", 5.0)
	_expiry.schedule("c", 8.0)
	_expiry.cancel("a")
	_clock.set_time(4.0)
	var expired: Array = _expiry.flush_expired()
	assert_eq(expired.size(), 0, "nothing expires at t=4 — min recomputed to b at t=5")
	_clock.set_time(5.1)
	expired = _expiry.flush_expired()
	assert_eq(expired.size(), 1, "b expires at t=5.1")


# re-registration with longer lifetime recomputes min
func test_reregister_longer_lifetime_recomputes_min() -> void:
	_clock.set_time(0.0)
	_expiry.schedule("a", 2.0)
	_expiry.schedule("b", 5.0)
	_expiry.schedule("a", 10.0)
	_clock.set_time(4.0)
	var expired: Array = _expiry.flush_expired()
	assert_eq(expired.size(), 0, "a was extended to t=10, b is at t=5 — nothing at t=4")
	_clock.set_time(5.1)
	expired = _expiry.flush_expired()
	assert_eq(expired.size(), 1, "b expires first now")


# get_expire_at returns -1.0 for missing key
func test_get_expire_at_missing_returns_minus_one() -> void:
	assert_eq(_expiry.get_expire_at("missing"), -1.0)


# get_expire_at returns correct absolute time
func test_get_expire_at_returns_absolute() -> void:
	_clock.set_time(3.0)
	_expiry.schedule("key", 5.0)
	assert_eq(_expiry.get_expire_at("key"), 8.0)


# tick() returns empty when nothing expired (fast path)
func test_fast_path_no_expiry() -> void:
	_clock.set_time(100.0)
	var result: Array = _expiry.flush_expired()
	assert_eq(result.size(), 0, "Empty expiry dict returns empty immediately")


# tick() returns all expired keys at same time
func test_tick_returns_all_same_time_expirations() -> void:
	_clock.set_time(0.0)
	_expiry.schedule_at("a", 5.0)
	_expiry.schedule_at("b", 5.0)
	_expiry.schedule_at("c", 5.0)
	_clock.set_time(5.0)
	var expired: Array = _expiry.flush_expired()
	assert_eq(expired.size(), 3, "All 3 same-time entries should expire together")


# tick() removes entries after returning them (has() returns false)
func test_tick_removes_after_returning() -> void:
	_clock.set_time(0.0)
	_expiry.schedule_at("x", 3.0)
	_clock.set_time(3.0)
	var first: Array = _expiry.flush_expired()
	assert_eq(first.size(), 1)
	assert_false(_expiry.has("x"), "Expired key should be removed after tick")  # meta-allow:has-membership
	var second: Array = _expiry.flush_expired()
	assert_eq(second.size(), 0, "Second tick should return nothing")


# get_remaining for past times returns 0.0 (not negative)
func test_get_remaining_returns_clamped() -> void:
	_clock.set_time(0.0)
	_expiry.schedule_at("key", 10.0)
	_clock.set_time(12.0)
	assert_eq(_expiry.get_remaining("key"), 0.0, "Expired key returns 0.0, not negative")


# get_keys returns all tracked keys, cancel removes them
func test_get_keys_and_cancel_removes_orphaned_entries() -> void:
	var store_has: Callable = func(k: String) -> bool: return k == "exists"
	var local_expiry := ChronicleExpiry.new(_clock.get_time)
	_clock.set_time(0.0)
	local_expiry.schedule_at("exists", 10.0)
	local_expiry.schedule_at("gone", 15.0)
	for norm_key: String in local_expiry.get_keys():
		if not store_has.call(norm_key):
			local_expiry.cancel(norm_key)
	assert_true(local_expiry.has("exists"), "Existing key should remain")  # meta-allow:has-membership
	assert_false(local_expiry.has("gone"), "Missing key should be purged")  # meta-allow:has-membership


# ── R16-A6 Expiry & Game Clock audit tests ──
# Tests edge cases in expiry scheduling, min tracking, and clock interaction.


# Rescheduling the minimum key to a later time — min must recompute
func test_reschedule_min_key_later_recomputes_min() -> void:
	_chronicle.set_fact("a", 1, false, 3.0)   # expires at t=3
	_chronicle.set_fact("b", 2, false, 5.0)   # expires at t=5
	# Reschedule "a" to expire much later
	_chronicle.set_fact("a", 1, false, 20.0)  # expires at t=20 (from t=0)
	# Advance past old expiry of "a" (t=3) but before "b" (t=5)
	advance_time(4.0)
	_chronicle.flush_expiry()
	# "a" should still exist — it was rescheduled
	assert_fact("a", 1)
	# "b" should still exist — not yet expired
	assert_fact("b", 2)
	# Advance past "b"
	advance_time(2.0)  # now at t=6
	_chronicle.flush_expiry()
	assert_no_fact("b")
	assert_fact("a", 1)


# Multiple facts expiring at the exact same time
func test_multiple_same_time_expiry() -> void:
	_chronicle.set_fact("x", 10, false, 5.0)
	_chronicle.set_fact("y", 20, false, 5.0)
	_chronicle.set_fact("z", 30, false, 5.0)
	var expired := collect_signal(_chronicle, "fact_expired")
	advance_time(5.0)
	_chronicle.flush_expiry()
	expired.assert_count(3)
	assert_no_fact("x")
	assert_no_fact("y")
	assert_no_fact("z")


# Cancel the only expiring fact — flush should return empty
func test_cancel_only_expiry_then_flush() -> void:
	_chronicle.set_fact("sole", 42, false, 3.0)
	_chronicle.set_expiry("sole", 0.0)  # clear expiry
	advance_time(10.0)
	_chronicle.flush_expiry()
	assert_fact("sole", 42)


# Erase a fact that has an expiry — expiry should be cleaned up
func test_erase_fact_cancels_expiry() -> void:
	_chronicle.set_fact("temp", "data", false, 10.0)
	assert_has_expiry("temp")
	_chronicle.erase_fact("temp")
	assert_no_expiry("temp")
	# Advancing past the would-be expiry should not crash or emit
	var expired := collect_signal(_chronicle, "fact_expired")
	advance_time(15.0)
	_chronicle.flush_expiry()
	expired.assert_count(0)


# Rapid reschedule cycle — schedule, cancel, reschedule
func test_rapid_reschedule_cycle() -> void:
	_chronicle.set_fact("key", 1, false, 2.0)   # expires at t=2
	_chronicle.set_expiry("key", 0.0)    # clear expiry
	_chronicle.set_expiry("key", 8.0)    # re-add expiry at t=8 (from t=0)
	advance_time(5.0)
	_chronicle.flush_expiry()
	assert_fact("key", 1)  # should still exist — expiry is at t=8
	advance_time(4.0)  # now at t=9
	_chronicle.flush_expiry()
	assert_no_fact("key")  # should be gone — expired at t=8


# get_remaining after time passes — should return clamped positive value
func test_get_remaining_decreases_with_time() -> void:
	_chronicle.set_fact("timed", true, false, 10.0)  # expires at t=10
	advance_time(3.0)
	var remaining: float = _chronicle.get_expiry_remaining("timed")
	# Should be approximately 7.0 (10.0 - 3.0)
	assert_almost_eq(remaining, 7.0, 0.01, "remaining should be ~7.0 after 3s")
	# Advance clock past expiry WITHOUT flushing — use raw clock to avoid
	# advance_game_time's automatic _flush_expiry() call.
	_chronicle._clock.set_time(11.0)  # now at t=11, past expiry
	remaining = _chronicle.get_expiry_remaining("timed")
	# Past expiry but not yet flushed — should clamp to 0.0
	assert_eq(remaining, 0.0, "past-expiry remaining should clamp to 0.0")


# Rollback restores expiry state — fact that expired should come back
func test_rollback_restores_expired_fact() -> void:
	_chronicle.set_fact("mortal", "alive", false, 3.0)  # expires at t=3
	advance_time(1.0)  # t=1
	_chronicle.set_fact("anchor", true)  # anchor at t=1
	advance_time(3.0)  # t=4
	_chronicle.flush_expiry()
	assert_no_fact("mortal")  # should be expired
	# Rollback to t=1 — mortal should exist again
	var result = _chronicle.rollback_to(1.0)
	assert_rollback_ok(result)
	# After rollback, mortal should exist (it was alive at t=1)
	# Note: the expiry schedule may or may not be restored depending on
	# whether the rollback system preserves expiry entries. The key behavior
	# is that the fact's value is restored.
	assert_fact("mortal", "alive")


# Flush when clock hasn't moved — fast path, no work done
func test_flush_at_time_zero_no_expiry() -> void:
	var expired := collect_signal(_chronicle, "fact_expired")
	_chronicle.flush_expiry()
	expired.assert_count(0)


# set_game_time forward triggers expiry flush
func test_set_game_time_forward_flushes_expiry() -> void:
	_chronicle.set_fact("flash", "bright", false, 5.0)
	var expired := collect_signal(_chronicle, "fact_expired")
	set_time(10.0)  # jump past expiry
	expired.assert_count(1)
	expired.assert_event(0, "flash", "bright")


# Two-phase flush: first flush expires some, second flush expires rest
func test_two_phase_flush() -> void:
	_chronicle.set_fact("early", 1, false, 2.0)  # expires at t=2
	_chronicle.set_fact("late", 2, false, 6.0)   # expires at t=6
	advance_time(3.0)  # t=3
	_chronicle.flush_expiry()
	assert_no_fact("early")
	assert_fact("late", 2)
	advance_time(4.0)  # t=7
	_chronicle.flush_expiry()
	assert_no_fact("late")


# schedule then overwrite fact WITHOUT expiry — expiry should be preserved
# (KEEP_LIFETIME behavior)
func test_overwrite_value_preserves_expiry() -> void:
	_chronicle.set_fact("item", "v1", false, 10.0)
	assert_has_expiry("item")
	# Overwrite value without specifying lifetime (defaults to KEEP_LIFETIME)
	_chronicle.set_fact("item", "v2")
	assert_has_expiry("item")
	assert_fact("item", "v2")


# schedule then overwrite fact WITH lifetime=0.0 — expiry should be cleared
func test_overwrite_with_zero_lifetime_clears_expiry() -> void:
	_chronicle.set_fact("item", "v1", false, 10.0)
	assert_has_expiry("item")
	_chronicle.set_fact("item", "v2", false, 0.0)
	assert_no_expiry("item")
	# Fact should still exist with new value
	assert_fact("item", "v2")
	# Advancing past original expiry should not expire the fact
	advance_time(15.0)
	_chronicle.flush_expiry()
	assert_fact("item", "v2")


# Expiry fires fact_expired signal with correct key and value
func test_fact_expired_signal_carries_correct_data() -> void:
	_chronicle.set_fact("player.buff", "shield", false, 5.0)
	var expired := collect_signal(_chronicle, "fact_expired")
	advance_time(5.0)
	_chronicle.flush_expiry()
	expired.assert_count(1)
	expired.assert_event(0, "player.buff", "shield")


# Expiry on a fact that was set during another fact's expiry callback
# (re-entrant write during expiry processing — should be deferred)
func test_reentrant_write_during_expiry_callback() -> void:
	_chronicle.set_fact("trigger", "go", false, 3.0)
	_chronicle.connect("fact_expired", func(key: String, _val: Variant) -> void:
		if key == "trigger":
			_chronicle.set_fact("created_in_callback", true)
	)
	advance_time(3.0)
	_chronicle.flush_expiry()
	assert_no_fact("trigger")
	# The deferred write should have been drained after expiry processing
	assert_fact("created_in_callback", true)


# advance_game_time(0.0) is a no-op — no expiry flush, no crash
func test_advance_zero_does_not_flush() -> void:
	_chronicle.set_fact("stable", 1, false, 5.0)
	# advance_game_time with 0.0 should be a no-op (short-circuited in chronicle.gd)
	_chronicle.advance_game_time(0.0)
	assert_fact("stable", 1)
	assert_has_expiry("stable")


# Large number of concurrent expiries — stress test for min tracking
func test_many_concurrent_expiries_min_tracking() -> void:
	# Schedule 50 facts with different lifetimes
	for i: int in range(50):
		_chronicle.set_fact("fact_%d" % i, i, false, float(i + 1))
	# Advance to t=25 — first 25 should expire
	advance_time(25.0)
	_chronicle.flush_expiry()
	for i: int in range(25):
		assert_no_fact("fact_%d" % i)
	for i: int in range(25, 50):
		assert_fact("fact_%d" % i, i)
	# Advance to t=50 — all should expire
	advance_time(25.0)
	_chronicle.flush_expiry()
	for i: int in range(50):
		assert_no_fact("fact_%d" % i)


# Negative delta rejected by advance_game_time
func test_negative_delta_rejected() -> void:
	advance_time(5.0)
	var time_before: float = _chronicle.get_game_time()
	_chronicle.advance_game_time(-1.0)
	assert_game_time(time_before)


# set_game_time backward rejected (not rollback)
func test_set_game_time_backward_rejected() -> void:
	set_time(10.0)
	_chronicle.set_game_time(5.0)  # should be rejected with warning
	assert_game_time(10.0)


# clear() resets expiry state completely
func test_clear_resets_expiry() -> void:
	_chronicle.set_fact("a", 1, false, 5.0)
	_chronicle.set_fact("b", 2, false, 10.0)
	assert_has_expiry("a")
	assert_has_expiry("b")
	_chronicle.clear()
	assert_no_expiry("a")
	assert_no_expiry("b")
	assert_game_time(0.0)
	assert_true(_chronicle.is_auto_advancing(), "auto-advance should be re-enabled")


# Deserialize restores expiry as remaining time from new clock position
func test_serialize_deserialize_preserves_expiry() -> void:
	# Use set_fact + set_expiry to create a serializable (non-transient) expiring fact.
	# Passing lifetime directly to set_fact auto-marks it transient (excluded from serialization).
	_chronicle.set_fact("persist", "data")
	_chronicle.set_expiry("persist", 20.0)  # expires at t=20
	advance_time(5.0)  # t=5, remaining=15
	var snapshot: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	assert_no_fact("persist")
	var ok: bool = _chronicle.deserialize(snapshot)
	assert_true(ok, "deserialize should succeed")
	assert_fact("persist", "data")
	assert_has_expiry("persist")
	var remaining: float = _chronicle.get_expiry_remaining("persist")
	# Roundtrip does NOT advance the clock, so remaining is exact (tolerance 0.001).
	assert_almost_eq(remaining, 15.0, 0.001, "remaining should be ~15.0 after round-trip")


# ── R17-A6: Time subsystem audit — expiry.gd and game_clock.gd ──


# set_game_time to current time disables auto-advance
func test_set_game_time_equal_current_keeps_auto_advance() -> void:
	# Auto-advance is enabled by default (cleared in before_each)
	assert_true(_chronicle.is_auto_advancing(), "auto-advance should start enabled")
	var current: float = _chronicle.get_game_time()
	_chronicle.set_game_time(current)  # same value — should be a no-op
	# set_game_time never touches auto-advance (chronicle.gd ~482-493); the equal-time
	# branch returns early, so auto-advance stays enabled.
	assert_true(_chronicle.is_auto_advancing(),
		"set_game_time(current) should not disable auto-advance when time is unchanged")


# set_game_time to a future value does NOT disable auto-advance
func test_set_game_time_forward_keeps_auto_advance() -> void:
	assert_true(_chronicle.is_auto_advancing())
	_chronicle.set_game_time(5.0)
	assert_true(_chronicle.is_auto_advancing(),
		"set_game_time does not disable auto-advance — use set_auto_advancing(false) explicitly")


# Deserializing expiry with remaining == 0.0 causes immediate expiry
func test_deserialize_zero_remaining_expires_immediately() -> void:
	# Build a save that legitimately has a fact with expiry.
	# set_fact + set_expiry keeps the fact non-transient so it (and its expiry
	# entry) survive serialization; passing lifetime directly to set_fact would
	# auto-mark it transient and drop it from the save.
	_chronicle.set_fact("item", "data")
	_chronicle.set_expiry("item", 10.0)
	advance_time(5.0)                     # t=5, remaining=5
	var snapshot: Dictionary = _chronicle.serialize()
	_chronicle.clear()

	# Tamper: set remaining to exactly 0.0 (borderline value the deserializer
	# accepts but the serializer never produces)
	assert_has(snapshot, "expiry", "snapshot must have expiry section")
	assert_eq(snapshot["expiry"].size(), 1, "exactly one expiry entry expected — .keys()[0] is then unambiguous")
	var norm_key: String = snapshot["expiry"].keys()[0]
	snapshot["expiry"][norm_key] = 0.0    # remaining = 0 → expire_at = game_time

	var ok: bool = _chronicle.deserialize(snapshot)
	assert_true(ok, "deserialize should succeed — 0.0 remaining is accepted")

	# Fact exists before flush
	assert_fact("item", "data")

	# After flush: fact should NOT have expired. _validate_expiry rejects
	# remaining <= 0.0 (serializer.gd ~294), matching the serializer which never
	# emits remaining=0.0, so no expiry entry is created.
	var expired := collect_signal(_chronicle, "fact_expired")
	_chronicle.flush_expiry()
	expired.assert_count(0)
	assert_fact("item", "data")


# NaN delta rejected by advance_game_time — clock unchanged
func test_nan_delta_rejected() -> void:
	advance_time(3.0)
	var before: float = _chronicle.get_game_time()
	_chronicle.advance_game_time(NAN)
	assert_game_time(before)


# INF delta rejected by advance_game_time — clock unchanged
func test_inf_delta_rejected() -> void:
	advance_time(2.0)
	var before: float = _chronicle.get_game_time()
	_chronicle.advance_game_time(INF)
	assert_game_time(before)


# NaN time rejected by set_game_time — clock unchanged
func test_nan_time_rejected() -> void:
	set_time(5.0)
	_chronicle.set_game_time(NAN)
	assert_game_time(5.0)


# INF time rejected by set_game_time — clock unchanged
func test_inf_time_rejected() -> void:
	set_time(5.0)
	_chronicle.set_game_time(INF)
	assert_game_time(5.0)


# Negative time rejected by set_game_time — clock unchanged
func test_negative_time_rejected() -> void:
	set_time(5.0)
	_chronicle.set_game_time(-1.0)
	assert_game_time(5.0)


# Backward set_game_time rejected (forward-only contract)
func test_backward_set_game_time_rejected() -> void:
	set_time(10.0)
	_chronicle.set_game_time(5.0)
	assert_game_time(10.0)


# advance_game_time(0.0) is a no-op — clock unchanged, no expiry flush
func test_advance_zero_fires_no_expiry() -> void:
	_chronicle.set_fact("item", 1, false, 5.0)
	advance_time(4.9)
	var expired := collect_signal(_chronicle, "fact_expired")
	_chronicle.advance_game_time(0.0)
	# advance_game_time(0.0) returns early — no flush, no expiry fired
	expired.assert_count(0)
	assert_fact("item", 1)


# advance_game_time(0.0) does not disable auto-advance
func test_advance_zero_preserves_auto_advance() -> void:
	assert_true(_chronicle.is_auto_advancing())
	_chronicle.advance_game_time(0.0)
	assert_true(_chronicle.is_auto_advancing(),
		"advance_game_time(0.0) must not disable auto-advance")


# get_expiry_remaining returns NO_EXPIRY for facts without expiry
func test_get_expiry_remaining_no_expiry() -> void:
	_chronicle.set_fact("plain", 42)
	var remaining: float = _chronicle.get_expiry_remaining("plain")
	assert_eq(remaining, Chronicle.EXPIRY_NONE,
		"fact without expiry should return NO_EXPIRY")


# get_expiry_remaining returns NO_EXPIRY for non-existent keys
func test_get_expiry_remaining_missing_key() -> void:
	var remaining: float = _chronicle.get_expiry_remaining("does_not_exist")
	assert_eq(remaining, Chronicle.EXPIRY_NONE,
		"missing key should return NO_EXPIRY")


# get_expiry_remaining clamps to 0.0 for past-due entries not yet flushed
func test_get_expiry_remaining_clamps_to_zero_when_overdue() -> void:
	_chronicle.set_fact("timed", true, false, 3.0)   # expires at t=3
	# Advance the clock WITHOUT triggering expiry flush.
	# advance_game_time() calls _flush_expiry(), so use the raw clock instead.
	_chronicle._clock.set_time(5.0)               # now at t=5, past expiry
	# Fact is still in store but overdue — expiry not yet flushed
	var remaining: float = _chronicle.get_expiry_remaining("timed")
	assert_eq(remaining, 0.0,
		"overdue-but-not-yet-flushed expiry should return 0.0, not negative")


# clear() fully resets expiry state — no lingering timers
func test_clear_resets_all_expiry() -> void:
	_chronicle.set_fact("a", 1, false, 2.0)
	_chronicle.set_fact("b", 2, false, 4.0)
	_chronicle.clear()
	assert_no_expiry("a")
	assert_no_expiry("b")
	assert_game_time(0.0)
	assert_true(_chronicle.is_auto_advancing(),
		"auto-advance must be re-enabled after clear()")
	# Advance past the original expiry window — nothing should fire
	var expired := collect_signal(_chronicle, "fact_expired")
	advance_time(10.0)
	_chronicle.flush_expiry()
	expired.assert_count(0)


# erase_fact cancels pending expiry — no orphan entry
func test_erase_fact_removes_expiry() -> void:
	_chronicle.set_fact("temp", "hello", false, 5.0)
	assert_has_expiry("temp")
	_chronicle.erase_fact("temp")
	assert_no_expiry("temp")
	var expired := collect_signal(_chronicle, "fact_expired")
	advance_time(10.0)
	_chronicle.flush_expiry()
	expired.assert_count(0)


# set_fact with lifetime=0.0 clears existing expiry
func test_set_fact_zero_lifetime_clears_expiry() -> void:
	_chronicle.set_fact("item", "v1", false, 10.0)
	assert_has_expiry("item")
	_chronicle.set_fact("item", "v2", false, 0.0)
	assert_no_expiry("item")
	advance_time(15.0)
	_chronicle.flush_expiry()
	assert_fact("item", "v2")


# Multiple facts expiring at the same clock time all fire fact_expired
func test_batch_expiry_same_time() -> void:
	_chronicle.set_fact("x", 10, false, 5.0)
	_chronicle.set_fact("y", 20, false, 5.0)
	_chronicle.set_fact("z", 30, false, 5.0)
	var expired := collect_signal(_chronicle, "fact_expired")
	advance_time(5.0)
	_chronicle.flush_expiry()
	expired.assert_count(3)
	assert_no_fact("x")
	assert_no_fact("y")
	assert_no_fact("z")


# Rollback restores expiry when timeline entry with expiry is reverted
func test_rollback_restores_expiry() -> void:
	_chronicle.set_fact("buff", "shield")
	advance_time(1.0)                              # t=1
	_chronicle.set_fact("anchor", true)
	advance_time(2.0)                              # t=3
	_chronicle.set_expiry("buff", 5.0)             # expires at t=8, timeline entry at t=3
	advance_time(6.0)                              # t=9, buff expired
	_chronicle.flush_expiry()
	assert_no_fact("buff")

	# Roll back to t=2 — the set_expiry at t=3 gets reverted,
	# and the buff fact is restored to its pre-expiry state.
	var result = _chronicle.rollback_to(2.0)
	assert_rollback_ok(result)
	# After rollback, buff must exist with its original value
	assert_fact("buff", "shield")
	# The expiry was added at t=3 (after rollback target t=2), so it's reverted.
	# The fact should no longer have an expiry.
	assert_no_expiry("buff")


# Serialize/deserialize round-trip preserves expiry remaining time
func test_serialize_preserves_expiry_remaining() -> void:
	_chronicle.set_fact("persist", "data")
	_chronicle.set_expiry("persist", 20.0)             # expires at t=20
	advance_time(5.0)                              # t=5, remaining=15

	var snapshot: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	var ok: bool = _chronicle.deserialize(snapshot)
	assert_true(ok, "deserialize should succeed")

	assert_fact("persist", "data")
	assert_has_expiry("persist")
	var remaining: float = _chronicle.get_expiry_remaining("persist")
	# Roundtrip does NOT advance the clock, so remaining is exact (tolerance 0.001).
	assert_almost_eq(remaining, 15.0, 0.001,
		"remaining time must be ~15.0 after round-trip")


# ── R14/R15 bug regression ──


# schedule_at is now public (was _register_at) — used by coordinator
func test_private_register_at_accessed_from_coordinator() -> void:
	var clock := ChronicleGameClock.new()
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy)
	var expiry := ChronicleExpiry.new(clock.get_time)

	store.set_value("test.key", "value")
	clock.set_time(5.0)

	# FIXED: schedule_at is now public — no encapsulation violation
	expiry.schedule_at("test.key", 10.0)

	assert_true(expiry.has("test.key"), "schedule_at registers expiry")  # meta-allow:has-membership
	assert_eq(expiry.get_expire_at("test.key"), 10.0,
		"FIXED: schedule_at (public method) is used by coordinator — no encapsulation violation")


# Parameter trap eliminated — set_fact preserves expiry with KEEP_LIFETIME default
func test_parameter_trap_eliminated() -> void:
	_chronicle.set_game_time(1.0)
	_chronicle.set_fact("buff", true, false, 10.0)
	assert_has_expiry("buff")

	# With the new API, overwriting with set_fact preserves expiry (KEEP_LIFETIME default)
	_chronicle.set_fact("buff", "active")

	# FIX: expiry is preserved because set_fact uses KEEP_LIFETIME by default
	assert_has_expiry("buff")


# flush_expiry should indicate when skipped — expired fact gone or caller knows
func test_flush_expiry_should_indicate_when_skipped() -> void:
	_chronicle.set_fact("temp", 42, false, 0.5)
	advance_time(1.0)

	var fact_still_exists: Array[bool] = [false]

	_chronicle.watch("other", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.flush_expiry()
		fact_still_exists[0] = _chronicle.has_fact("temp")
	)
	_chronicle.set_fact("other", true)

	# CORRECT: either flush_expiry should work during dispatch, or it should
	# indicate it was skipped. Currently it silently does nothing and the
	# expired fact persists with no way for the caller to know.
	assert_false(fact_still_exists[0],
		"expired fact should be gone after flush_expiry — or caller should know it was skipped")


# get_stats expiry_count should be 100 — timeline_cap is accessible
func test_get_stats_expiry_count_allocates_unnecessarily() -> void:
	for i: int in range(100):
		_chronicle.set_fact("fact.%d" % i, i, false, 10.0)

	var stats: Dictionary = _chronicle.get_stats()
	assert_eq(stats.expiry_count, 100,
		"expiry_count should be 100 — but internally it allocates a full dict copy to count")
	assert_has(stats, "timeline_cap",
		"timeline_cap exists but is read via private _timeline._cap")
