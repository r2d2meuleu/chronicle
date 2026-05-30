extends ChronicleTestSuite

const Timeline := preload("res://addons/chronicle/core/timeline.gd")


func _make_timeline(cap: int = 10) -> RefCounted:
	var tl: RefCounted = Timeline.new(
		ChronicleValueUtils.deep_copy,
		func(_msg: String) -> void: pass,
	)
	tl.set_cap(cap)
	return tl


# truncate nulls freed slots in linear layout
func test_truncate_nulls_freed_slots_linear() -> void:
	var tl: RefCounted = _make_timeline(10)
	_append(tl, "a", 1.0)
	_append(tl, "b", 2.0)
	_append(tl, "c", 3.0)
	_append(tl, "d", 4.0)
	tl.truncate(2)
	assert_eq(tl.size(), 2)
	assert_not_null(tl._buffer[0])
	assert_not_null(tl._buffer[1])
	assert_null(tl._buffer[2])
	assert_null(tl._buffer[3])


# truncate to zero nulls all slots
func test_truncate_to_zero_nulls_all() -> void:
	var tl: RefCounted = _make_timeline(10)
	_append(tl, "x", 1.0)
	_append(tl, "y", 2.0)
	tl.truncate(0)
	assert_eq(tl.size(), 0)
	assert_null(tl._buffer[0])
	assert_null(tl._buffer[1])


# truncate with wrapped head nulls correct slots
func test_truncate_nulls_correct_slots_wrapped() -> void:
	var tl: RefCounted = _make_timeline(4)
	_append(tl, "e0", 1.0)
	_append(tl, "e1", 2.0)
	_append(tl, "e2", 3.0)
	_append(tl, "e3", 4.0)
	_append(tl, "e4", 5.0)
	assert_eq(tl._head, 1)
	tl.truncate(2)
	assert_eq(tl.size(), 2)
	assert_not_null(tl._buffer[1])
	assert_not_null(tl._buffer[2])
	assert_null(tl._buffer[3])
	assert_null(tl._buffer[0])


# set_entries respects cap — keeps newest
func test_set_entries_respects_cap() -> void:
	var tl: RefCounted = _make_timeline(3)
	var entries: Array[Dictionary] = []
	for i in range(5):
		entries.append({key = str(i), value = i, old_value = null, time = float(i), tick = i})
	tl.set_entries(entries)
	assert_eq(tl.size(), 3)
	assert_eq(tl.get_at(0).display_key, "2")
	assert_eq(tl.get_at(1).display_key, "3")
	assert_eq(tl.get_at(2).display_key, "4")


# Append at capacity overwrites oldest entry
func test_append_overflow_drops_oldest() -> void:
	var tl: RefCounted = _make_timeline(3)
	_append(tl, "k1", 1.0)
	_append(tl, "k2", 2.0)
	_append(tl, "k3", 3.0)
	_append(tl, "k4", 4.0)
	assert_eq(tl.size(), 3)
	var first: RefCounted = tl.get_at(0)
	assert_eq(first.display_key, "k2", "Oldest entry (k1) should have been dropped")


# Warning fires when capacity exceeded
func test_cap_warning_fires_on_overflow() -> void:
	var warned: Array = [false]
	var warn_fn: Callable = func(msg: String) -> void:
		if "oldest entries are being dropped" in msg:
			warned[0] = true
	var tl: RefCounted = Timeline.new(
		ChronicleValueUtils.deep_copy,
		warn_fn,
	)
	tl.set_cap(2)
	_append(tl, "k1", 1.0)
	_append(tl, "k2", 2.0)
	_append(tl, "k3", 3.0)
	assert_true(warned[0], "Warning should fire when timeline overflows")


# get_at() preserves order after buffer wraps
func test_get_entries_after_wrap() -> void:
	var tl: RefCounted = _make_timeline(3)
	for i: int in range(7):
		_append(tl, "k%d" % i, float(i))
	assert_eq(tl.size(), 3)
	assert_eq(tl.get_at(0).display_key, "k4")
	assert_eq(tl.get_at(1).display_key, "k5")
	assert_eq(tl.get_at(2).display_key, "k6")


# Append after truncate works correctly
func test_append_after_truncate() -> void:
	var tl: RefCounted = _make_timeline(10)
	_append(tl, "a", 1.0)
	_append(tl, "b", 2.0)
	_append(tl, "c", 3.0)
	tl.truncate(1)
	assert_eq(tl.size(), 1)
	_append(tl, "d", 4.0)
	assert_eq(tl.size(), 2)
	assert_eq(tl.get_at(0).display_key, "a")
	assert_eq(tl.get_at(1).display_key, "d")


# ── Timeline & Rollback: ring buffer, bisect, and rollback edge cases ──


# ── Ring Buffer Capacity ──


# Timeline at cap evicts oldest and preserves newest
func test_ring_buffer_eviction_preserves_newest() -> void:
	_chronicle._timeline.set_cap(3)
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	set_time(3.0)
	_chronicle.set_fact("c", 3)
	# At cap now — next write evicts oldest
	set_time(4.0)
	_chronicle.set_fact("d", 4)
	set_time(5.0)
	_chronicle.set_fact("e", 5)

	var history: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_eq(history.size(), 3, "cap=3 means only 3 entries survive")
	assert_eq(history[0].key, "c")
	assert_eq(history[1].key, "d")
	assert_eq(history[2].key, "e")


# set_cap shrinks correctly — drops oldest, keeps newest
func test_set_cap_shrink() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	set_time(3.0)
	_chronicle.set_fact("c", 3)
	set_time(4.0)
	_chronicle.set_fact("d", 4)

	_chronicle._timeline.set_cap(2)

	var history: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_eq(history.size(), 2, "after shrink to cap=2, only 2 entries remain")
	assert_eq(history[0].key, "c")
	assert_eq(history[1].key, "d")


# set_cap grows — all existing entries preserved
func test_set_cap_grow() -> void:
	_chronicle._timeline.set_cap(3)
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	set_time(3.0)
	_chronicle.set_fact("c", 3)

	_chronicle._timeline.set_cap(100)

	var history: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_eq(history.size(), 3, "grow preserves all entries")
	assert_eq(history[0].key, "a")
	assert_eq(history[2].key, "c")


# set_cap(0) or negative is rejected
func test_set_cap_zero_rejected() -> void:
	_chronicle._timeline.set_cap(100)
	set_time(1.0)
	_chronicle.set_fact("a", 1)

	_chronicle._timeline.set_cap(0)
	_chronicle._timeline.set_cap(-5)

	# Original cap should still be in effect
	assert_eq(_chronicle._timeline.get_cap(), 100)
	var history: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_eq(history.size(), 1)


# Ring buffer wrap-around after eviction — get_at returns correct entries
func test_ring_buffer_wrap_around() -> void:
	_chronicle._timeline.set_cap(4)
	# Fill the buffer
	for i in range(4):
		set_time(float(i + 1))
		_chronicle.set_fact("key%d" % i, i)
	# Overflow — evicts key0, key1
	set_time(5.0)
	_chronicle.set_fact("key4", 4)
	set_time(6.0)
	_chronicle.set_fact("key5", 5)

	# Should have key2, key3, key4, key5
	var history: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_eq(history.size(), 4)
	assert_eq(history[0].key, "key2")
	assert_eq(history[3].key, "key5")


# ── Bisect Edge Cases ──


# bisect_after on empty timeline returns 0
func test_bisect_after_empty() -> void:
	assert_eq(_chronicle._timeline.bisect_after(5.0), 0)


# bisect_at_or_after on empty timeline returns 0
func test_bisect_at_or_after_empty() -> void:
	assert_eq(_chronicle._timeline.bisect_at_or_after(5.0), 0)


# bisect_after with single element — target before
func test_bisect_after_single_before() -> void:
	set_time(5.0)
	_chronicle.set_fact("a", 1)
	# bisect_after(3.0): first entry with time > 3.0 → index 0
	assert_eq(_chronicle._timeline.bisect_after(3.0), 0)


# bisect_after with single element — target equal
func test_bisect_after_single_equal() -> void:
	set_time(5.0)
	_chronicle.set_fact("a", 1)
	# bisect_after(5.0): first entry with time > 5.0 → past end → 1
	assert_eq(_chronicle._timeline.bisect_after(5.0), 1)


# bisect_after with single element — target after
func test_bisect_after_single_after() -> void:
	set_time(5.0)
	_chronicle.set_fact("a", 1)
	# bisect_after(10.0): first entry with time > 10.0 → past end → 1
	assert_eq(_chronicle._timeline.bisect_after(10.0), 1)


# bisect_at_or_after with single element — target equal
func test_bisect_at_or_after_single_equal() -> void:
	set_time(5.0)
	_chronicle.set_fact("a", 1)
	# bisect_at_or_after(5.0): first entry with time >= 5.0 → index 0
	assert_eq(_chronicle._timeline.bisect_at_or_after(5.0), 0)


# bisect with all entries at same time
func test_bisect_all_same_time() -> void:
	set_time(3.0)
	_chronicle.set_fact("a", 1)
	_chronicle.set_fact("b", 2)
	_chronicle.set_fact("c", 3)

	# bisect_after(3.0): all entries at 3.0, first with time > 3.0 = past end
	assert_eq(_chronicle._timeline.bisect_after(3.0), 3)
	# bisect_at_or_after(3.0): first with time >= 3.0 = index 0
	assert_eq(_chronicle._timeline.bisect_at_or_after(3.0), 0)
	# bisect_after(2.0): all entries at 3.0 > 2.0, first = index 0
	assert_eq(_chronicle._timeline.bisect_after(2.0), 0)


# bisect correctness with wrapped ring buffer
func test_bisect_wrapped_ring_buffer() -> void:
	_chronicle._timeline.set_cap(3)
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	set_time(3.0)
	_chronicle.set_fact("c", 3)
	# Push one more to wrap
	set_time(4.0)
	_chronicle.set_fact("d", 4)

	# Buffer now has [b@2, c@3, d@4] (a evicted)
	# bisect_after(2.5): first with time > 2.5 → c@3 → logical index 1
	assert_eq(_chronicle._timeline.bisect_after(2.5), 1)
	# bisect_at_or_after(3.0): first with time >= 3.0 → c@3 → logical index 1
	assert_eq(_chronicle._timeline.bisect_at_or_after(3.0), 1)
	# bisect_after(4.0): first with time > 4.0 → past end → 3
	assert_eq(_chronicle._timeline.bisect_after(4.0), 3)


# ── Rollback Edge Cases ──


# rollback_to exact entry time keeps that entry
func test_rollback_to_exact_entry_time() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("a", 2)
	set_time(3.0)
	_chronicle.set_fact("a", 3)

	_chronicle.rollback_to(2.0)

	assert_fact("a", 2)
	var history: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	# Entries at t=1.0 and t=2.0 should survive
	assert_eq(history.size(), 2)


# rollback_to with multiple entries at same time — all at target time kept
func test_rollback_same_time_entries_preserved() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	_chronicle.set_fact("b", 2)
	_chronicle.set_fact("c", 3)
	set_time(2.0)
	_chronicle.set_fact("d", 4)

	_chronicle.rollback_to(1.0)

	assert_fact("a", 1)
	assert_fact("b", 2)
	assert_fact("c", 3)
	assert_no_fact("d")


# rollback_steps(1) with multiple same-time entries undoes only the last
func test_rollback_steps_one_same_time() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	_chronicle.set_fact("b", 2)
	_chronicle.set_fact("c", 3)

	_chronicle.rollback_steps(1)

	# Should undo c (the last entry), keep a and b
	assert_fact("a", 1)
	assert_fact("b", 2)
	assert_no_fact("c")


# rollback after timeline cap overflow fails correctly
func test_rollback_after_overflow_succeeds_best_effort() -> void:
	_chronicle._timeline.set_cap(5)
	# Write entries at times 1-10 — only last 5 survive (t=6..10)
	for i in range(10):
		set_time(float(i + 1))
		_chronicle.set_fact("key%d" % i, i)

	# Rollback to t=3.0 — before the earliest surviving entry (t=6).
	# The rollback reverts all surviving entries and reports success.
	# State is restored to what was known at the earliest retained entry.
	var result = _chronicle.rollback_to(3.0)
	assert_true(result.success, "rollback applies all surviving entries — best-effort success")


# rollback_steps with interleaved transient and persistent entries
func test_rollback_steps_interleaved_transient() -> void:
	set_time(1.0)
	_chronicle.set_fact("base", 100)
	set_time(2.0)
	_chronicle.set_fact("temp.a", "x", true, 0.0)
	set_time(3.0)
	_chronicle.set_fact("data", 200)
	set_time(4.0)
	_chronicle.set_fact("temp.b", "y", true, 0.0)
	set_time(5.0)
	_chronicle.set_fact("final", 300)

	# rollback_steps(2): undo 2 non-transient steps (final, data)
	var result = _chronicle.rollback_steps(2)

	assert_rollback_ok(result)
	assert_eq(result.steps_reverted, 2)
	assert_fact("base", 100)
	assert_no_fact("data")
	assert_no_fact("final")
	# Transient facts survive
	assert_fact("temp.a", "x")
	assert_fact("temp.b", "y")


# truncate nulls buffer slots (no stale references)
func test_truncate_clears_slots() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	set_time(3.0)
	_chronicle.set_fact("c", 3)

	_chronicle._timeline.truncate(1)

	# Only entry at index 0 should exist
	assert_not_null(_chronicle._timeline.get_at(0))
	assert_null(_chronicle._timeline.get_at(1))
	assert_null(_chronicle._timeline.get_at(2))
	assert_eq(_chronicle._timeline.size(), 1)


# get_at with negative and out-of-bounds returns null
func test_get_at_bounds() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)

	assert_null(_chronicle._timeline.get_at(-1))
	assert_null(_chronicle._timeline.get_at(1))
	assert_null(_chronicle._timeline.get_at(9999))
	assert_not_null(_chronicle._timeline.get_at(0))


# Multiple rollback_to calls in sequence
func test_sequential_rollbacks() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	set_time(3.0)
	_chronicle.set_fact("c", 3)
	set_time(4.0)
	_chronicle.set_fact("d", 4)

	_chronicle.rollback_to(3.0)
	assert_fact("c", 3)
	assert_no_fact("d")

	# Write something new, then rollback again
	set_time(3.5)
	_chronicle.set_fact("e", 5)
	_chronicle.rollback_to(2.5)

	assert_fact("b", 2)
	assert_no_fact("c")
	assert_no_fact("e")


# rollback_steps partial — fewer non-transient entries than requested
func test_rollback_steps_partial() -> void:
	set_time(1.0)
	_chronicle.set_fact("only", 42)

	var result = _chronicle.rollback_steps(5)

	assert_rollback_rejected(result)
	assert_true(result.partial, "fewer entries than requested → partial rollback")
	assert_eq(result.steps_reverted, 1)
	assert_no_fact("only")


# set_entries with mixed Entry and Dictionary types
func test_set_entries_from_serialized_data() -> void:
	set_time(1.0)
	_chronicle.set_fact("x", 10)
	set_time(2.0)
	_chronicle.set_fact("y", 20)

	# Serialize and deserialize — exercises set_entries
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	_chronicle.deserialize(data)

	assert_fact("x", 10)
	assert_fact("y", 20)
	var history: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_eq(history.size(), 2)


# clear() resets all ring buffer state
func test_clear_resets_ring_buffer() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)

	_chronicle.clear()

	assert_eq(_chronicle._timeline.size(), 0)
	assert_true(_chronicle._timeline.is_empty(), "timeline should be empty after clear()")
	assert_eq(_chronicle._timeline.get_tick(), 0)
	assert_null(_chronicle._timeline.get_at(0))


# rollback_to at timeline boundary — target_time == first entry time
func test_rollback_to_first_entry_time() -> void:
	set_time(5.0)
	_chronicle.set_fact("a", 1)
	set_time(10.0)
	_chronicle.set_fact("b", 2)

	var result = _chronicle.rollback_to(5.0)
	assert_rollback_ok(result)
	assert_fact("a", 1)
	assert_no_fact("b")
	assert_eq(_chronicle.get_game_time(), 5.0)


# rollback_to just before first entry time — now succeeds (R22)
func test_rollback_before_first_entry_fails() -> void:
	set_time(5.0)
	_chronicle.set_fact("a", 1)
	set_time(10.0)
	_chronicle.set_fact("b", 2)

	var result = _chronicle.rollback_to(4.9)
	assert_true(result.success, "R22: rollback before first entry now succeeds")
	# All entries after 4.9 are undone
	assert_no_fact("a")
	assert_no_fact("b")


# rollback_steps exactly matching entry count — full success
func test_rollback_steps_exact_count() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)

	var result = _chronicle.rollback_steps(2)

	# Exact match: 2 requested, 2 available — SUCCESS not PARTIAL
	assert_rollback_ok(result)
	assert_false(result.partial, "exact-count rollback is not partial")
	assert_eq(result.steps_reverted, 2)
	assert_eq(_chronicle.get_game_time(), 0.0)
	assert_no_fact("a")
	assert_no_fact("b")


# set_cap during wrapped ring buffer preserves data
func test_set_cap_while_wrapped() -> void:
	_chronicle._timeline.set_cap(4)
	for i in range(6):
		set_time(float(i + 1))
		_chronicle.set_fact("k%d" % i, i)
	# Buffer wrapped: has k2,k3,k4,k5 (head != 0)

	# Grow cap — should linearize and preserve all 4 entries
	_chronicle._timeline.set_cap(10)

	var history: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_eq(history.size(), 4)
	assert_eq(history[0].key, "k2")
	assert_eq(history[3].key, "k5")


# rollback_steps(1) on single entry — full success
func test_rollback_steps_single_entry() -> void:
	set_time(1.0)
	_chronicle.set_fact("solo", 99)

	var result = _chronicle.rollback_steps(1)

	# Exact match: 1 requested, 1 available — SUCCESS
	assert_rollback_ok(result)
	assert_false(result.partial, "exact-count rollback is not partial")
	assert_eq(result.steps_reverted, 1)
	assert_no_fact("solo")


# bisect with entries at boundaries (t=0.0)
func test_bisect_at_time_zero() -> void:
	_chronicle.set_fact("anchor", 0)  # at t=0.0
	set_time(1.0)
	_chronicle.set_fact("a", 1)

	# bisect_after(0.0): first entry with time > 0.0 → index 1 (entry "a")
	assert_eq(_chronicle._timeline.bisect_after(0.0), 1)
	# bisect_at_or_after(0.0): first entry with time >= 0.0 → index 0 (anchor)
	assert_eq(_chronicle._timeline.bisect_at_or_after(0.0), 0)


# ── Timeline ring-buffer & rollback: set_cap, truncate, bisect, set_entries, deep-copy, tick ──


func _append(tl: RefCounted, key: String, time: float, value: Variant = 1) -> void:
	tl.append(key, key, value, null, time)


# ── A5-1  set_cap: tick must NOT increment on a no-op (cap == _cap) ──


# set_cap with identical value must not change the tick
func test_set_cap_noop_does_not_increment_tick() -> void:
	# _init sets _cap = 10000; the _make_tl helper calls set_cap(cap) once.
	# We snapshot the tick AFTER that first set_cap to establish a baseline, then
	# call set_cap again with the same value and confirm tick is unchanged.
	var tl: RefCounted = _make_timeline(5)
	var tick_before: int = tl.get_tick()
	tl.set_cap(5)  # no-op call — same cap
	assert_eq(tl.get_tick(), tick_before,
		"set_cap with the same cap value must not increment _tick")


# set_cap with a DIFFERENT value must increment tick (control test)
func test_set_cap_different_value_increments_tick() -> void:
	var tl: RefCounted = _make_timeline(5)
	var tick_before: int = tl.get_tick()
	tl.set_cap(10)
	assert_gt(tl.get_tick(), tick_before,
		"set_cap with a different cap value must increment _tick")


# ── A5-2  set_cap: ring-buffer arithmetic — shrink path preserves newest entries ──


# Shrinking cap keeps only the newest entries in correct order
func test_set_cap_shrink_keeps_newest() -> void:
	var tl: RefCounted = _make_timeline(6)
	for i: int in range(1, 6):
		_append(tl, "k%d" % i, float(i))
	# size==5, now shrink to 3 — should keep k3, k4, k5
	tl.set_cap(3)
	assert_eq(tl.size(), 3)
	assert_eq(tl.get_at(0).display_key, "k3")
	assert_eq(tl.get_at(1).display_key, "k4")
	assert_eq(tl.get_at(2).display_key, "k5")


# Shrinking from a fully-wrapped ring-buffer keeps correct entries
func test_set_cap_shrink_wrapped_ring() -> void:
	var tl: RefCounted = _make_timeline(4)
	# Fill to cap then add 2 more to wrap the buffer
	for i: int in range(1, 7):
		_append(tl, "k%d" % i, float(i))
	# Buffer contains k3, k4, k5, k6 (k1 and k2 dropped by overflow)
	assert_eq(tl.size(), 4)
	# Shrink to 2 — should keep k5 and k6
	tl.set_cap(2)
	assert_eq(tl.size(), 2)
	assert_eq(tl.get_at(0).display_key, "k5")
	assert_eq(tl.get_at(1).display_key, "k6")


# Expanding cap preserves all existing entries
func test_set_cap_expand_preserves_entries() -> void:
	var tl: RefCounted = _make_timeline(3)
	for i: int in range(1, 4):
		_append(tl, "e%d" % i, float(i))
	tl.set_cap(10)
	assert_eq(tl.size(), 3)
	assert_eq(tl.get_at(0).display_key, "e1")
	assert_eq(tl.get_at(1).display_key, "e2")
	assert_eq(tl.get_at(2).display_key, "e3")


# set_cap to 1 retains only the single newest entry
func test_set_cap_to_one_keeps_newest() -> void:
	var tl: RefCounted = _make_timeline(5)
	for i: int in range(1, 5):
		_append(tl, "x%d" % i, float(i))
	tl.set_cap(1)
	assert_eq(tl.size(), 1)
	assert_eq(tl.get_at(0).display_key, "x4")


# Appending after set_cap uses the new capacity boundary
func test_append_after_set_cap_uses_new_cap() -> void:
	var tl: RefCounted = _make_timeline(10)
	for i: int in range(5):
		_append(tl, "pre%d" % i, float(i))
	tl.set_cap(3)
	# add 4 more — should overflow into the new cap-3 ring
	for i: int in range(4):
		_append(tl, "post%d" % i, float(10 + i))
	assert_eq(tl.size(), 3)
	assert_eq(tl.get_at(0).display_key, "post1")
	assert_eq(tl.get_at(1).display_key, "post2")
	assert_eq(tl.get_at(2).display_key, "post3")


# ── A5-3  truncate: null slots and size update ──


# truncate(n) where n < size nulls the freed physical slots
func test_truncate_nulls_freed_slots() -> void:
	var tl: RefCounted = _make_timeline(6)
	for i: int in range(5):
		_append(tl, "t%d" % i, float(i))
	tl.truncate(2)
	assert_eq(tl.size(), 2)
	# logical 0 and 1 must still be present
	assert_not_null(tl.get_at(0))
	assert_not_null(tl.get_at(1))
	# physical slots 2..4 must be null
	for i: int in range(2, 5):
		assert_null(tl._buffer[i],
			"physical slot %d should be null after truncate(2)" % i)


# truncate increments tick
func test_truncate_increments_tick() -> void:
	var tl: RefCounted = _make_timeline(5)
	_append(tl, "a", 1.0)
	_append(tl, "b", 2.0)
	var tick_before: int = tl.get_tick()
	tl.truncate(1)
	assert_gt(tl.get_tick(), tick_before,
		"truncate must increment _tick")


# truncate(current_size) is a no-op (tick must not change)
func test_truncate_same_size_is_noop() -> void:
	var tl: RefCounted = _make_timeline(5)
	_append(tl, "a", 1.0)
	var tick_before: int = tl.get_tick()
	tl.truncate(1)  # no-op: size is already 1
	assert_eq(tl.get_tick(), tick_before,
		"truncate(size) must not increment _tick")


# truncate on a wrapped buffer nulls correct physical slots
func test_truncate_wrapped_ring_nulls_correct_slots() -> void:
	var tl: RefCounted = _make_timeline(4)
	for i: int in range(6):
		_append(tl, "w%d" % i, float(i))
	# ring has wrapped: size=4, head is at physical 2
	assert_eq(tl._head, 2)
	tl.truncate(2)
	assert_eq(tl.size(), 2)
	# Logical 0 → physical 2, logical 1 → physical 3 must be non-null
	assert_not_null(tl._buffer[2])
	assert_not_null(tl._buffer[3])
	# Logical 2 → physical 0, logical 3 → physical 1 must be null
	assert_null(tl._buffer[0])
	assert_null(tl._buffer[1])


# ── A5-4  bisect correctness ──


# bisect_at_or_after returns index of first entry >= target
func test_bisect_at_or_after_exact_hit() -> void:
	var tl: RefCounted = _make_timeline(10)
	for i: int in range(1, 6):
		_append(tl, "b%d" % i, float(i))
	# target exactly matches entry at logical index 2 (time=3.0)
	var idx: int = tl.bisect_at_or_after(3.0)
	assert_eq(idx, 2, "bisect_at_or_after(3.0) should return index 2")


# bisect_after returns index of first entry strictly after target
func test_bisect_after_exact_hit() -> void:
	var tl: RefCounted = _make_timeline(10)
	for i: int in range(1, 6):
		_append(tl, "b%d" % i, float(i))
	# target=3.0: entry at index 2 is 3.0 (not strictly after), so result should be 3
	var idx: int = tl.bisect_after(3.0)
	assert_eq(idx, 3, "bisect_after(3.0) should return index 3 (first entry with time > 3.0)")


# bisect_after returns size when all entries are at or before target
func test_bisect_after_all_at_or_before() -> void:
	var tl: RefCounted = _make_timeline(5)
	_append(tl, "a", 1.0)
	_append(tl, "b", 2.0)
	var idx: int = tl.bisect_after(5.0)
	assert_eq(idx, tl.size(),
		"bisect_after(5.0) should return size when all entries are <= 5.0")


# bisect_at_or_after returns 0 when all entries are after target
func test_bisect_at_or_after_all_after() -> void:
	var tl: RefCounted = _make_timeline(5)
	_append(tl, "a", 3.0)
	_append(tl, "b", 5.0)
	var idx: int = tl.bisect_at_or_after(1.0)
	assert_eq(idx, 0,
		"bisect_at_or_after(1.0) should return 0 when all entries are >= 1.0")


# bisect on empty timeline returns 0
func test_bisect_empty_timeline() -> void:
	var tl: RefCounted = _make_timeline(5)
	assert_eq(tl.bisect_after(1.0), 0)
	assert_eq(tl.bisect_at_or_after(1.0), 0)


# bisect is correct after buffer has wrapped (non-contiguous physical layout)
func test_bisect_after_wrap() -> void:
	var tl: RefCounted = _make_timeline(4)
	for i: int in range(6):
		_append(tl, "k%d" % i, float(i + 1))
	# ring now holds logical [k2@3, k3@4, k4@5, k5@6] at physical [0,1,2,3] with head=2
	var idx: int = tl.bisect_after(4.0)
	# first entry strictly after 4.0 is k4@5 at logical index 2
	assert_eq(idx, 2)


# ── A5-5  set_entries: Dictionary and Entry paths ──


# set_entries from Dictionaries populates the timeline correctly
func test_set_entries_from_dict() -> void:
	var tl: RefCounted = _make_timeline(10)
	var entries: Array[Variant] = []
	entries.append({key = "foo.a", value = 10, old_value = null, time = 1.0, tick = 1,
		expire_at = -1.0, old_expire_at = -1.0, old_transient = false})
	entries.append({key = "foo.b", value = 20, old_value = null, time = 2.0, tick = 2,
		expire_at = -1.0, old_expire_at = -1.0, old_transient = false})
	tl.set_entries(entries)
	assert_eq(tl.size(), 2)
	assert_eq(tl.get_at(0).display_key, "foo.a")
	assert_eq(tl.get_at(0).value, 10)
	assert_eq(tl.get_at(1).display_key, "foo.b")


# set_entries from Entry objects deep-copies values
func test_set_entries_from_entry_deep_copies() -> void:
	var tl: RefCounted = _make_timeline(10)
	var original_val: Array = [1, 2, 3]
	tl.append("arr.key", "arr.key", original_val, null, 1.0)
	var entry0: RefCounted = tl.get_at(0)

	# Build a second timeline and populate it from the first timeline's entry
	var entries: Array[Variant] = [entry0]
	var tl2: RefCounted = _make_timeline(10)
	tl2.set_entries(entries)

	# Mutating the original entry's value must not affect tl2's copy
	entry0.value.append(99)
	assert_eq(tl2.get_at(0).value.size(), 3,
		"set_entries must deep-copy Entry values — mutation of source must not affect the copy")


# set_entries skips entries that are neither Entry nor Dictionary
func test_set_entries_skips_invalid_types() -> void:
	var tl: RefCounted = _make_timeline(10)
	var entries: Array[Variant] = []
	entries.append("not_an_entry")
	entries.append(42)
	entries.append({key = "valid.key", value = 7, old_value = null, time = 1.0, tick = 1,
		expire_at = -1.0, old_expire_at = -1.0, old_transient = false})
	tl.set_entries(entries)
	assert_eq(tl.size(), 1, "Only the valid Dictionary entry should be stored")
	assert_eq(tl.get_at(0).display_key, "valid.key")


# set_entries respects cap and discards oldest when count > cap
func test_set_entries_truncates_to_cap() -> void:
	var tl: RefCounted = _make_timeline(3)
	var entries: Array[Variant] = []
	for i: int in range(5):
		entries.append({key = "k%d" % i, value = i, old_value = null,
			time = float(i), tick = i,
			expire_at = -1.0, old_expire_at = -1.0, old_transient = false})
	tl.set_entries(entries)
	assert_eq(tl.size(), 3)
	# Keeps newest 3: k2, k3, k4
	assert_eq(tl.get_at(0).display_key, "k2")
	assert_eq(tl.get_at(2).display_key, "k4")


# set_entries resets head to 0 and lays entries out linearly
func test_set_entries_linear_layout() -> void:
	# Pre-wrap the ring then set_entries — the new layout must start at slot 0
	var tl: RefCounted = _make_timeline(3)
	for i: int in range(5):
		_append(tl, "pre%d" % i, float(i))
	assert_ne(tl._head, 0, "Head should have wrapped before set_entries")
	tl.set_entries([
		{key = "a.k", value = 1, old_value = null, time = 1.0, tick = 1,
			expire_at = -1.0, old_expire_at = -1.0, old_transient = false},
	] as Array[Variant])
	assert_eq(tl._head, 0, "set_entries must reset _head to 0")
	assert_not_null(tl._buffer[0])
	assert_null(tl._buffer[1])


# ── A5-6  Rollback: value AND expiry restoration via Chronicle API ──


# Rollback restores old_value correctly (basic round-trip)
func test_rollback_restores_old_value() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.gold", 100)
	set_time(2.0)
	_chronicle.set_fact("player.gold", 999)
	_chronicle.rollback_to(1.5)
	assert_fact("player.gold", 100)


# Rollback restores old_expire_at via write_coordinator
func test_rollback_restores_expiry() -> void:
	set_time(0.0)
	_chronicle.set_fact("buff.speed", 5, false, 10.0)  # expires at t=10
	advance_time(1.0)
	_chronicle.set_fact("buff.speed", 99, false, 0.0)  # overwrite; explicit 0 clears expiry
	assert_false(_chronicle.has_expiry("buff.speed"),
		"Overwrite with lifetime=0 should clear expiry")
	_chronicle.rollback_to(0.5)
	assert_fact("buff.speed", 5)
	assert_true(_chronicle.has_expiry("buff.speed"),
		"Rollback should restore the original expiry")


# Rollback to before oldest entry succeeds and restores all old_values
func test_rollback_before_oldest_entry_succeeds() -> void:
	set_time(5.0)
	_chronicle.set_fact("anchor", 1)
	set_time(10.0)
	_chronicle.set_fact("b", 2)
	# Rolling back before the oldest entry restores from old_value of all entries
	var result = _chronicle.rollback_to(3.0)
	assert_true(result.success,
		"rollback_to time before oldest timeline entry must succeed")
	assert_no_fact("anchor")
	assert_no_fact("b")
	assert_eq(_chronicle.get_game_time(), 3.0)


# rollback_to exactly the oldest entry's time succeeds
func test_rollback_to_exact_oldest_entry_time_succeeds() -> void:
	set_time(5.0)
	_chronicle.set_fact("anchor", 1)
	set_time(10.0)
	_chronicle.set_fact("b", 2)
	# Roll back to exactly the oldest entry time (t=5.0)
	var result = _chronicle.rollback_to(5.0)
	assert_true(result.success,
		"rollback_to(oldest_entry_time) must succeed — the anchor entry is at that time")
	assert_fact("anchor", 1)
	assert_no_fact("b")
	assert_eq(_chronicle.get_game_time(), 5.0)


# ── A5-7  Rollback boundary: oldest-entry edge cases ──


# rollback_to(t) where t < time of ALL timeline entries succeeds and restores old_values
func test_rollback_before_all_entries_succeeds() -> void:
	set_time(10.0)
	_chronicle.set_fact("late", 1)
	var result = _chronicle.rollback_to(1.0)
	assert_rollback_ok(result)
	assert_no_fact("late")
	assert_eq(_chronicle.get_game_time(), 1.0)


# rollback_to succeeds when anchor fact at t=0 exists
func test_rollback_to_zero_with_anchor() -> void:
	_chronicle.set_fact("anchor", true)
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	var result = _chronicle.rollback_to(0.0)
	assert_rollback_ok(result)
	assert_no_fact("a")
	assert_fact("anchor", true)
	assert_eq(_chronicle.get_game_time(), 0.0)


# ── A5-8  Deep copy: timeline entries are independent of the store ──


# Mutating the Array value returned by get_fact does not corrupt the timeline
func test_deep_copy_value_independent_of_timeline() -> void:
	var original: Array = [10, 20, 30]
	set_time(1.0)
	_chronicle.set_fact("arr.key", original)
	set_time(2.0)
	_chronicle.set_fact("arr.key", [99, 99])

	# Roll back to get the original value restored
	_chronicle.rollback_to(1.5)

	var val: Variant = _chronicle.get_fact("arr.key")
	assert_eq((val as Array).size(), 3)
	# Mutating the returned copy must not alter get_fact history
	(val as Array).append(999)
	var val2: Variant = _chronicle.get_fact("arr.key")
	assert_eq((val2 as Array).size(), 3,
		"Returned fact value must be a copy — external mutation must not affect the store")


# Mutating the Dictionary value returned after rollback does not corrupt history
func test_deep_copy_dict_independent_after_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("config", {"hp": 100, "speed": 5})
	set_time(2.0)
	_chronicle.set_fact("config", {"hp": 1, "speed": 1})
	_chronicle.rollback_to(1.5)

	var v: Variant = _chronicle.get_fact("config")
	(v as Dictionary)["hp"] = 9999
	var v2: Variant = _chronicle.get_fact("config")
	assert_eq((v2 as Dictionary)["hp"], 100,
		"Mutating the returned Dictionary must not affect the stored value")


# ── A5-9  Tick management across all mutation paths ──


# append increments tick with each write
func test_append_increments_tick() -> void:
	var tl: RefCounted = _make_timeline(10)
	var tick0: int = tl.get_tick()
	_append(tl, "a", 1.0)
	var tick1: int = tl.get_tick()
	_append(tl, "b", 2.0)
	var tick2: int = tl.get_tick()
	assert_gt(tick1, tick0, "tick must increase after first append")
	assert_gt(tick2, tick1, "tick must increase after second append")


# clear resets tick to 0
func test_clear_resets_tick() -> void:
	var tl: RefCounted = _make_timeline(10)
	_append(tl, "a", 1.0)
	_append(tl, "b", 2.0)
	assert_gt(tl.get_tick(), 0, "tick should be non-zero after appends")
	tl.clear()
	assert_eq(tl.get_tick(), 0, "clear() must reset _tick to 0")


# Entry tick field is stamped from the timeline tick counter at write time
func test_entry_tick_stamped_at_write_time() -> void:
	var tl: RefCounted = _make_timeline(10)
	_append(tl, "first", 1.0)
	var tick_a: int = tl.get_at(0).tick
	_append(tl, "second", 2.0)
	var tick_b: int = tl.get_at(1).tick
	assert_gt(tick_b, tick_a,
		"Entry tick must be stamped after incrementing — second entry must have higher tick")


# Rollback does not produce new timeline entries (no append during rollback)
func test_rollback_does_not_add_timeline_entries() -> void:
	set_time(1.0)
	_chronicle.set_fact("x", 1)
	set_time(2.0)
	_chronicle.set_fact("x", 2)
	var size_before: int = _chronicle.get_stats().timeline_size
	_chronicle.rollback_to(1.5)
	# Timeline size must be strictly smaller than before (entries removed, none added)
	assert_lt(_chronicle.get_stats().timeline_size, size_before,
		"rollback_to must reduce timeline size, not add entries")


# rollback_steps(1) tick continues forward after rollback
func test_tick_continues_after_rollback_steps() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	_chronicle.rollback_steps(1)
	# After rollback, writing a new fact should produce a new timeline entry
	set_time(3.0)
	_chronicle.set_fact("c", 3)
	var history: Array[Dictionary] = _chronicle.get_fact_history("c")
	assert_eq(history.size(), 1,
		"New write after rollback_steps must produce a timeline entry")
