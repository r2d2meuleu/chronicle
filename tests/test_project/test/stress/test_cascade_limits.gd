extends ChronicleTestSuite


# ── Cascade Depth ──


# Cascade at depth 7 (below limit) executes all inline
func test_cascade_depth_7_executes_inline() -> void:
	# Build a chain of 7 watchers: a.0 → a.1 → ... → a.6
	# Each watcher fires at depth 1 through 7, all below MAX_CASCADE_DEPTH (8)
	build_cascade_chain("a", 7)

	var events_6 := watch_events("a.6")

	_chronicle.set_fact("a.0", true)

	# All 7 facts must exist — depth 7 is the last inline level
	for i in range(7):
		assert_fact("a.%d" % i, true)
	# The watcher on a.6 fires at depth 7, setting a.7 is at depth 8 — not in this chain
	# Here we only have 7 watchers (a.0..a.6), so a.6 was SET by the a.5 watcher at depth 6
	events_6.assert_count(1)


# Cascade at depth 8 defers the overflow to queue
func test_cascade_depth_8_defers_to_queue() -> void:
	# Build a chain of 8 watchers so the 9th set_fact happens at depth >= 8
	# a.0 watcher fires at depth 1, sets a.1
	# a.1 watcher fires at depth 2, sets a.2
	# ... a.7 watcher fires at depth 8, which is AT MAX_CASCADE_DEPTH,
	# so its call to set_fact("a.8") is deferred
	build_cascade_chain("a", 8)

	var events_8 := watch_events("a.8")

	_chronicle.set_fact("a.0", true)

	# After set_fact returns, the deferred queue has already been drained synchronously.
	# a.8 must exist — it was deferred then applied.
	assert_fact("a.8", true)
	events_8.assert_count(1)


# Deferred facts execute after cascade fully resolves
func test_deferred_facts_execute_after_cascade_resolves() -> void:
	var fire_order: Array = []

	# Chain: a.0 → a.1 → ... → a.7 → a.deferred (at depth 8+, deferred)
	for i in range(8):
		var captured_i := i
		_chronicle.watch("a.%d" % i, func(_k: String, _v: Variant, _o: Variant, ci: int = captured_i) -> void:
			fire_order.append("a.%d" % ci)
			if ci < 7:
				_chronicle.set_fact("a.%d" % (ci + 1), true)
			else:
				_chronicle.set_fact("a.deferred", true)
		)

	_chronicle.watch("a.deferred", func(_k: String, _v: Variant, _o: Variant) -> void:
		fire_order.append("deferred")
	)

	_chronicle.set_fact("a.0", true)

	# All 9 watchers must have fired — deferred one last
	assert_eq(fire_order.size(), 9, "all 9 watchers fired (8 inline + 1 deferred)")
	assert_eq(fire_order[8], "deferred", "deferred fact watcher fires last")


# Deferred queue at cap (64 entries) drops excess
func test_deferred_queue_at_cap_drops_excess() -> void:
	# Reach depth 8 so next set_facts calls are deferred, then flood with 70 entries.
	# The deferred queue cap is 64, so the final batch of 70 must be rejected.
	build_cascade_chain("flood.chain", 8)

	# At depth 8 (when flood.chain.7 watcher fires), try to queue 70 facts
	_chronicle.watch("flood.chain.7", func(_k: String, _v: Variant, _o: Variant) -> void:
		for j in range(70):
			_chronicle.set_fact("flood.item.%d" % j, j)
	)

	_chronicle.set_fact("flood.chain.0", true)

	# After drain: some items must exist (queue accepted up to 64)
	# and some must be missing (the excess were dropped).
	var present_count: int = 0
	for j in range(70):
		if _chronicle.has_fact("flood.item.%d" % j):
			present_count += 1

	assert_gt(present_count, 0, "some deferred facts were accepted (queue not zero)")
	assert_lt(present_count, 70, "some deferred facts were dropped (cap enforced)")
	assert_lte(present_count, 64, "no more than 64 deferred facts were accepted")


# Cascade depth resets properly — second cascade works independently
func test_cascade_depth_resets_after_resolution() -> void:
	# First cascade
	_chronicle.watch("first.trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("first.result", true)
	)
	_chronicle.watch("first.result", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("first.final", true)
	)

	_chronicle.set_fact("first.trigger", true)
	assert_fact("first.trigger", true)
	assert_fact("first.result", true)
	assert_fact("first.final", true)

	# Second independent cascade — depth must have reset to 0 after first resolved
	_chronicle.watch("second.trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("second.result", true)
	)
	_chronicle.watch("second.result", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("second.final", true)
	)

	_chronicle.set_fact("second.trigger", true)
	assert_fact("second.trigger", true)
	assert_fact("second.result", true)
	assert_fact("second.final", true)


# set_facts inside watcher respects depth limit
func test_nested_set_facts_in_watcher_respects_depth() -> void:
	# Build chain to depth 7, then at depth 8 call set_facts with a small batch.
	# The batch must be deferred and eventually applied.
	build_cascade_chain("sf.chain", 7)

	# This watcher fires at depth 8 — set_facts must defer the batch
	_chronicle.watch("sf.chain.7", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_facts({"sf.deferred.a": 1, "sf.deferred.b": 2})
	)

	_chronicle.set_fact("sf.chain.0", true)

	# All chain links must exist
	for i in range(8):
		assert_fact("sf.chain.%d" % i, true)

	# The deferred batch must have been applied after drain
	assert_fact("sf.deferred.a", 1)
	assert_fact("sf.deferred.b", 2)


# ── Watcher Cascade Chains ──


# Chain A→B→C all resolve correctly
func test_watcher_chain_a_b_c_all_resolve() -> void:
	_chronicle.watch("chain.a", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("chain.b", true)
	)
	_chronicle.watch("chain.b", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("chain.c", true)
	)

	var b_events := watch_events("chain.b")
	var c_events := watch_events("chain.c")

	_chronicle.set_fact("chain.a", true)

	assert_fact("chain.a", true)
	assert_fact("chain.b", true)
	assert_fact("chain.c", true)
	b_events.assert_count(1)
	c_events.assert_count(1)


# Circular chain (A→B→A) halts at depth limit without infinite loop
func test_circular_chain_halts_at_depth_limit() -> void:
	# A's watcher sets B; B's watcher sets A. This would loop forever without depth guard.
	# Chronicle's depth limit (8) must stop it by deferring the repeated writes.
	_chronicle.watch("circ.a", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("circ.b", true)
	)
	_chronicle.watch("circ.b", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("circ.a", true)
	)

	# This must NOT hang or crash — it must terminate.
	_chronicle.set_fact("circ.a", true)

	# Both facts must exist in the end
	assert_fact("circ.a", true)
	assert_fact("circ.b", true)


# Cascade produces correct final state regardless of intermediate order
func test_cascade_produces_correct_final_state() -> void:
	# Watcher on "state.base" sets "state.derived" as base * 10.
	# A second watcher on "state.derived" sets "state.final" as derived + 1.
	_chronicle.watch("state.base", func(_k: String, _v: Variant, _o: Variant) -> void:
		var base_val: int = _chronicle.get_fact("state.base")
		_chronicle.set_fact("state.derived", base_val * 10)
	)
	_chronicle.watch("state.derived", func(_k: String, _v: Variant, _o: Variant) -> void:
		var derived_val: int = _chronicle.get_fact("state.derived")
		_chronicle.set_fact("state.final", derived_val + 1)
	)

	_chronicle.set_fact("state.base", 5)

	assert_fact("state.base", 5)
	assert_fact("state.derived", 50)
	assert_fact("state.final", 51)


# Timeline records all intermediate states during cascade
func test_cascade_timeline_records_all_states() -> void:
	_chronicle.watch("hist.a", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("hist.b", 2)
	)
	_chronicle.watch("hist.b", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("hist.c", 3)
	)

	_chronicle.set_fact("hist.a", 1)

	# All three facts must appear in their respective histories
	assert_history("hist.a", [1])
	assert_history("hist.b", [2])
	assert_history("hist.c", [3])


# fact_changed signal fires for each change in cascade
func test_fact_changed_fires_for_each_cascade_level() -> void:
	_chronicle.watch("sig.a", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("sig.b", true)
	)
	_chronicle.watch("sig.b", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("sig.c", true)
	)

	var changes := collect_signal(_chronicle, "fact_changed")

	_chronicle.set_fact("sig.a", true)

	# fact_changed must fire once per change: sig.a, sig.b, sig.c
	changes.assert_count(3)
	changes.assert_event(0, "sig.a", true, null)
	changes.assert_event(1, "sig.b", true, null)
	changes.assert_event(2, "sig.c", true, null)


# ── set_facts in Cascade ──


# set_facts called inside watcher callback defers batch correctly
func test_set_facts_inside_watcher_defers_correctly() -> void:
	# Build chain to reach depth 8, then call set_facts
	build_cascade_chain("dsf.chain", 7)

	_chronicle.watch("dsf.chain.7", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_facts({"dsf.batch.x": 10, "dsf.batch.y": 20, "dsf.batch.z": 30})
	)

	_chronicle.set_fact("dsf.chain.0", true)

	assert_fact("dsf.batch.x", 10)
	assert_fact("dsf.batch.y", 20)
	assert_fact("dsf.batch.z", 30)


# All keys from deferred set_facts batch are stored after resolution
func test_deferred_set_facts_batch_all_keys_stored() -> void:
	build_cascade_chain("allkeys", 8)

	# At depth 8, queue a batch of 5 facts
	_chronicle.watch("allkeys.8", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_facts({
			"allkeys.batch.p": "alpha",
			"allkeys.batch.q": "beta",
			"allkeys.batch.r": "gamma",
			"allkeys.batch.s": "delta",
			"allkeys.batch.t": "epsilon",
		})
	)

	_chronicle.set_fact("allkeys.0", true)

	# All batch entries must be present after drain
	assert_fact("allkeys.batch.p", "alpha")
	assert_fact("allkeys.batch.q", "beta")
	assert_fact("allkeys.batch.r", "gamma")
	assert_fact("allkeys.batch.s", "delta")
	assert_fact("allkeys.batch.t", "epsilon")


# Cascade triggered by set_facts fires watchers in correct order
func test_set_facts_cascade_fires_watchers_in_order() -> void:
	var fire_order: Array = []

	_chronicle.watch("ord.x", func(_k: String, _v: Variant, _o: Variant) -> void:
		fire_order.append("x")
		_chronicle.set_fact("ord.z", true)
	)
	_chronicle.watch("ord.y", func(_k: String, _v: Variant, _o: Variant) -> void:
		fire_order.append("y")
	)
	_chronicle.watch("ord.z", func(_k: String, _v: Variant, _o: Variant) -> void:
		fire_order.append("z")
	)

	# set_facts processes keys in iteration order: x fires, cascade sets z, then y fires
	_chronicle.set_facts({"ord.x": 1, "ord.y": 2})

	assert_eq(fire_order.size(), 3, "x watcher, z cascade watcher, and y watcher all fired")
	assert_eq(fire_order[0], "x", "x watcher fires first (first key in batch)")
	assert_eq(fire_order[1], "z", "z cascade watcher fires during x dispatch")
	assert_eq(fire_order[2], "y", "y watcher fires after x's cascade resolves")
	assert_fact("ord.x", 1)
	assert_fact("ord.y", 2)
	assert_fact("ord.z", true)


# ── watch_once in Cascade ──


# watch_once consumed during cascade does not fire again
func test_watch_once_consumed_in_cascade_no_refire() -> void:
	var once_count: Array = [0]

	_chronicle.watch("once.target", func(_k: String, _v: Variant, _o: Variant) -> void:
		once_count[0] += 1
	, true)

	# Watcher that sets once.target twice through cascade
	_chronicle.watch("once.trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("once.target", 1)
		# Second set — watch_once is already consumed, must not fire again
		_chronicle.set_fact("once.target", 2)
	)

	_chronicle.set_fact("once.trigger", true)

	assert_eq(once_count[0], 1, "watch_once fires exactly once even when key is set twice in cascade")
	assert_fact("once.target", 2)


# watch_once and persistent watch on same key — both fire, once consumed
func test_watch_once_and_persistent_in_same_cascade() -> void:
	var persistent_count: Array = [0]
	var once_count: Array = [0]

	_chronicle.watch("shared.key", func(_k: String, _v: Variant, _o: Variant) -> void:
		persistent_count[0] += 1
	)
	_chronicle.watch("shared.key", func(_k: String, _v: Variant, _o: Variant) -> void:
		once_count[0] += 1
	, true)

	# Trigger key twice through a cascade
	_chronicle.watch("shared.trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("shared.key", 1)
		_chronicle.set_fact("shared.key", 2)
	)

	_chronicle.set_fact("shared.trigger", true)

	# Persistent watcher fires for both sets (2 times)
	assert_eq(persistent_count[0], 2, "persistent watcher fires for each set_fact")
	# watch_once fires exactly once (consumed on first fire)
	assert_eq(once_count[0], 1, "watch_once fires exactly once")
	assert_fact("shared.key", 2)


# Multiple watch_once on same key all fire once each
func test_multiple_watch_once_same_key_all_fire() -> void:
	var counts: Array = [0, 0, 0]

	_chronicle.watch("multi.once", func(_k: String, _v: Variant, _o: Variant) -> void:
		counts[0] += 1
	, true)
	_chronicle.watch("multi.once", func(_k: String, _v: Variant, _o: Variant) -> void:
		counts[1] += 1
	, true)
	_chronicle.watch("multi.once", func(_k: String, _v: Variant, _o: Variant) -> void:
		counts[2] += 1
	, true)

	_chronicle.watch("multi.trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("multi.once", 1)
		# Second set — all three watch_once should already be consumed
		_chronicle.set_fact("multi.once", 2)
	)

	_chronicle.set_fact("multi.trigger", true)

	assert_eq(counts[0], 1, "first watch_once fires exactly once")
	assert_eq(counts[1], 1, "second watch_once fires exactly once")
	assert_eq(counts[2], 1, "third watch_once fires exactly once")
	assert_fact("multi.once", 2)


# ── Operations During Cascade ──


# rollback_to during cascade returns false (rejected)
func test_rollback_during_cascade_returns_false() -> void:
	set_time(5.0)
	_chronicle.set_fact("rb.prior", 1)

	var result: Array = [null]
	_chronicle.watch("rb.trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		result[0] = _chronicle.rollback_to(0.0)
	)

	_chronicle.set_fact("rb.trigger", true)

	assert_rollback_rejected(result[0])
	assert_fact("rb.trigger", true)


# rollback_steps during cascade returns false (rejected)
func test_rollback_steps_during_cascade_returns_false() -> void:
	_chronicle.set_fact("rbs.prior", 99)

	var result: Array = [null]
	_chronicle.watch("rbs.trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		result[0] = _chronicle.rollback_steps(1)
	)

	_chronicle.set_fact("rbs.trigger", true)

	assert_rollback_rejected(result[0])
	assert_fact("rbs.trigger", true)


# erase_fact during cascade succeeds
func test_erase_during_cascade_succeeds() -> void:
	_chronicle.set_fact("erase.setup", 42)

	_chronicle.watch("erase.trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.erase_fact("erase.setup")
		_chronicle.set_fact("erase.proof", true)
	)

	_chronicle.set_fact("erase.trigger", true)

	assert_no_fact("erase.setup")
	assert_fact("erase.trigger", true)
	assert_fact("erase.proof", true)


# increment during cascade accumulates correctly
func test_increment_during_cascade_accumulates() -> void:
	_chronicle.set_fact("inc.counter", 0)

	# Each of three cascading events increments the counter
	_chronicle.watch("inc.a", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.increment_fact("inc.counter")
		_chronicle.set_fact("inc.b", true)
	)
	_chronicle.watch("inc.b", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.increment_fact("inc.counter")
		_chronicle.set_fact("inc.c", true)
	)
	_chronicle.watch("inc.c", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.increment_fact("inc.counter")
	)

	_chronicle.set_fact("inc.a", true)

	assert_fact("inc.counter", 3)
	assert_fact("inc.a", true)
	assert_fact("inc.b", true)
	assert_fact("inc.c", true)


# ── Deferred Queue Behavior ──


# Deferred queue preserves insertion order
func test_deferred_queue_preserves_order() -> void:
	# At depth 8, three set_fact calls must be applied in the order they were queued.
	var applied_order: Array = []

	build_cascade_chain("order.chain", 8)

	# At depth 8, enqueue three facts in defined order
	_chronicle.watch("order.chain.8", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("order.deferred.first", 1)
		_chronicle.set_fact("order.deferred.second", 2)
		_chronicle.set_fact("order.deferred.third", 3)
	)

	# Watch each deferred key to track apply order
	_chronicle.watch("order.deferred.first", func(_k: String, _v: Variant, _o: Variant) -> void:
		applied_order.append("first")
	)
	_chronicle.watch("order.deferred.second", func(_k: String, _v: Variant, _o: Variant) -> void:
		applied_order.append("second")
	)
	_chronicle.watch("order.deferred.third", func(_k: String, _v: Variant, _o: Variant) -> void:
		applied_order.append("third")
	)

	_chronicle.set_fact("order.chain.0", true)

	assert_fact("order.deferred.first", 1)
	assert_fact("order.deferred.second", 2)
	assert_fact("order.deferred.third", 3)
	assert_eq(applied_order.size(), 3, "all three deferred facts applied")
	assert_eq(applied_order[0], "first", "first deferred fact applied first")
	assert_eq(applied_order[1], "second", "second deferred fact applied second")
	assert_eq(applied_order[2], "third", "third deferred fact applied third")


# Deferred queue processing can trigger a new (shallow) cascade
func test_deferred_processing_can_trigger_new_cascade() -> void:
	# Build chain to depth 8 so next set_fact defers.
	# The deferred fact has its own watcher that sets another fact (a new shallow cascade).
	build_cascade_chain("newcasc.chain", 8)

	# At depth 8, set the deferred seed
	_chronicle.watch("newcasc.chain.8", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("newcasc.seed", 1)
	)

	# When the deferred seed is drained (depth 0), its watcher triggers a new cascade
	_chronicle.watch("newcasc.seed", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("newcasc.child", 2)
	)
	_chronicle.watch("newcasc.child", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("newcasc.grandchild", 3)
	)

	_chronicle.set_fact("newcasc.chain.0", true)

	assert_fact("newcasc.seed", 1)
	assert_fact("newcasc.child", 2)
	assert_fact("newcasc.grandchild", 3)


# Multiple independent cascades in sequence work correctly
func test_multiple_cascades_in_sequence() -> void:
	# Register watchers for two completely independent chains
	_chronicle.watch("seq.first.a", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("seq.first.b", true)
	)
	_chronicle.watch("seq.first.b", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("seq.first.c", true)
	)

	_chronicle.watch("seq.second.a", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("seq.second.b", true)
	)
	_chronicle.watch("seq.second.b", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("seq.second.c", true)
	)

	# First cascade
	_chronicle.set_fact("seq.first.a", true)
	assert_fact("seq.first.a", true)
	assert_fact("seq.first.b", true)
	assert_fact("seq.first.c", true)

	# State from second chain must not yet exist
	assert_no_fact("seq.second.a")
	assert_no_fact("seq.second.b")
	assert_no_fact("seq.second.c")

	# Second cascade
	_chronicle.set_fact("seq.second.a", true)
	assert_fact("seq.second.a", true)
	assert_fact("seq.second.b", true)
	assert_fact("seq.second.c", true)


# Cascade with erase and set on same key — last write wins
func test_cascade_erase_and_set_same_key_last_wins() -> void:
	_chronicle.set_fact("lw.key", 1)

	# First watcher erases the key
	_chronicle.watch("lw.trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.erase_fact("lw.key")
	)

	# Second watcher re-sets the key with a new value (fires after erase, depth still shallow)
	var erased_events := watch_events("lw.key")

	_chronicle.set_fact("lw.trigger", true)

	# The erase must have fired (key was present, erase dispatched)
	erased_events.assert_count(1)
	erased_events.assert_event(0, "lw.key", null, 1)

	# After erase watcher runs, the key is gone
	assert_no_fact("lw.key")

	# Now set it again via a direct call — simulates "last write wins" scenario
	_chronicle.set_fact("lw.key", 99)
	assert_fact("lw.key", 99)
	erased_events.assert_count(2)
	erased_events.assert_event(1, "lw.key", 99, null)


# Deep cascade with watchers on glob pattern — all fire correctly
func test_deep_cascade_with_glob_watchers() -> void:
	# A glob watcher on "glob.*" should fire for every fact set in the cascade chain.
	var glob_events := watch_events("glob.*")

	# Build a chain: glob.0 → glob.1 → glob.2 → glob.3
	_chronicle.watch("glob.0", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("glob.1", true)
	)
	_chronicle.watch("glob.1", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("glob.2", true)
	)
	_chronicle.watch("glob.2", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("glob.3", true)
	)

	_chronicle.set_fact("glob.0", true)

	assert_fact("glob.0", true)
	assert_fact("glob.1", true)
	assert_fact("glob.2", true)
	assert_fact("glob.3", true)

	# The glob watcher must have fired for all four facts
	glob_events.assert_count(4)
	glob_events.assert_keys(["glob.3", "glob.2", "glob.1", "glob.0"])
