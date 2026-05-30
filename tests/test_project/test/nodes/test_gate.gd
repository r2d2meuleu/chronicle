extends ChronicleTestSuite


# Gate with HIDE_WHEN_FALSE hides parent when condition is false
func test_hide_when_false_hides_parent() -> void:
	# quest.done does not exist -> condition is false -> parent hidden
	var parent := add_gate("quest.done")

	assert_gate_closed(parent)


# Gate shows parent when condition becomes true
func test_hide_when_false_shows_parent_when_true() -> void:
	var parent := add_gate("quest.done")

	assert_gate_closed(parent)

	# Set the fact -> condition becomes true -> parent shown
	_chronicle.set_fact("quest.done", true)
	assert_gate_open(parent)


# Gate re-evaluates ONLY when a dependency key changes
func test_only_reevaluates_on_dependency_change() -> void:
	var parent := add_gate("quest.done")

	assert_gate_closed(parent)

	# Set an unrelated fact
	_chronicle.set_fact("unrelated.key", true)
	assert_gate_closed(parent)

	# Now set the relevant fact
	_chronicle.set_fact("quest.done", true)
	assert_gate_open(parent)

	# Set unrelated fact again — should not affect gate
	_chronicle.set_fact("another.unrelated", 42)
	assert_gate_open(parent)


# SHOW_WHEN_FALSE inverts behavior
func test_show_when_false_inverts() -> void:
	var parent := add_gate("quest.done", {
		gate_mode = CompanionFactory.GateMode.SHOW_WHEN_FALSE,
	})

	# Condition is false -> SHOW_WHEN_FALSE shows parent
	assert_gate_open(parent)

	# Set fact -> condition becomes true -> parent hidden
	_chronicle.set_fact("quest.done", true)
	assert_gate_closed(parent)


# QUEUE_FREE_WHEN_TRUE removes target when condition is true
func test_queue_free_when_true() -> void:
	var parent := add_gate("should.destroy", {
		gate_mode = CompanionFactory.GateMode.QUEUE_FREE_WHEN_TRUE,
	})

	# Condition false initially — parent still valid
	assert_true(is_instance_valid(parent), "QUEUE_FREE_WHEN_TRUE: parent valid when condition false")

	# Set fact -> condition becomes true -> parent queued for free
	_chronicle.set_fact("should.destroy", true)

	# queue_free happens at end of frame — check that is_queued_for_deletion is true
	assert_true(parent.is_queued_for_deletion(), "QUEUE_FREE_WHEN_TRUE: parent queued for deletion when condition true")


# SIGNAL_ONLY emits signals without modifying parent
func test_signal_only_no_modification() -> void:
	var parent := add_node_2d()
	var gate := CompanionFactory.make_gate({
		condition = "quest.done",
		gate_mode = CompanionFactory.GateMode.SIGNAL_ONLY,
	})
	parent.add_child(gate)

	# SIGNAL_ONLY should NOT modify visibility or process_mode
	assert_true(parent.visible, "SIGNAL_ONLY: parent still visible when condition false")
	assert_eq(parent.process_mode, Node.PROCESS_MODE_INHERIT, "SIGNAL_ONLY: parent still enabled when condition false")

	var opened := collect_any_signal(gate, "gate_opened")
	var closed := collect_any_signal(gate, "gate_closed")

	_chronicle.set_fact("quest.done", true)
	opened.assert_emission_count(1)
	assert_true(parent.visible, "SIGNAL_ONLY: parent still visible after condition true")

	_chronicle.set_fact("quest.done", false)
	closed.assert_emission_count(1)
	assert_true(parent.visible, "SIGNAL_ONLY: parent still visible after condition false")


# Expression with comparison: "player.gold >= 100"
func test_comparison_expression() -> void:
	_chronicle.set_fact("player.gold", 50)

	var parent := add_gate("player.gold >= 100")

	assert_gate_closed(parent)

	_chronicle.set_fact("player.gold", 100)
	assert_gate_open(parent)

	_chronicle.set_fact("player.gold", 200)
	# result didn't change (still true), gate should not re-apply
	assert_gate_open(parent)

	_chronicle.set_fact("player.gold", 50)
	assert_gate_closed(parent)


# Empty condition -> configuration warning
func test_empty_condition_warning() -> void:
	var gate: Node = autofree(CompanionFactory.make_gate({condition = ""}))
	assert_has_warning(gate, "condition")


# gate_opened / gate_closed signals emitted correctly
func test_signals_emitted() -> void:
	var parent := add_node_2d()
	var gate := CompanionFactory.make_gate({condition = "flag"})
	parent.add_child(gate)

	# Connect after _ready so we don't count the initial evaluation
	var opened := collect_any_signal(gate, "gate_opened")
	var closed := collect_any_signal(gate, "gate_closed")

	# Set flag -> opens gate
	_chronicle.set_fact("flag", true)
	opened.assert_emission_count(1)
	closed.assert_emission_count(0)

	# Unset flag -> closes gate
	_chronicle.set_fact("flag", false)
	opened.assert_emission_count(1)
	closed.assert_emission_count(1)

	# Re-open
	_chronicle.set_fact("flag", true)
	opened.assert_emission_count(2)


# gate_opened fires only on transition, not on every evaluation: a dependency value
# change that keeps the boolean result true must NOT re-emit gate_opened.
func test_gate_opened_not_reemitted_on_redundant_evaluation() -> void:
	_chronicle.set_fact("player.gold", 50)
	var parent := add_node_2d()
	var gate := CompanionFactory.make_gate({condition = "player.gold >= 100"})
	parent.add_child(gate)

	# Connect after _ready so we don't count the initial evaluation.
	var opened := collect_any_signal(gate, "gate_opened")

	# false -> true: opens once.
	_chronicle.set_fact("player.gold", 150)
	opened.assert_emission_count(1)

	# Value CHANGES (forces re-evaluation) but the boolean result stays true:
	# no transition, so gate_opened must NOT fire again.
	_chronicle.set_fact("player.gold", 200)
	opened.assert_emission_count(1)


# Gate with target_path targets a specific node instead of parent
func test_target_path() -> void:
	var parent := add_node_2d()
	var target: Node2D = autoqfree(Node2D.new())
	target.name = "TargetNode"
	target.visible = true
	parent.add_child(target)
	var gate := CompanionFactory.make_gate({
		condition = "quest.done",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
		target_path = NodePath("../TargetNode"),
	})
	parent.add_child(gate)

	# Condition false -> target hidden, parent should remain visible
	assert_false(target.visible, "target_path: target hidden when condition false")
	assert_true(parent.visible, "target_path: parent still visible (not the target)")

	# Set fact -> condition true -> target shown
	_chronicle.set_fact("quest.done", true)
	assert_true(target.visible, "target_path: target visible when condition true")
	assert_true(parent.visible, "target_path: parent still visible")


# Gate _exit_tree unwatches from Chronicle
func test_exit_tree_unwatches() -> void:
	var parent := add_node_2d()
	var gate := CompanionFactory.make_gate({condition = "quest.done"})
	parent.add_child(gate)

	_chronicle.set_fact("quest.done", true)
	assert_gate_open(parent)

	parent.remove_child(gate)
	gate.queue_free()

	_chronicle.set_fact("quest.done", false)
	assert_true(parent.visible, "parent stays visible after gate removed")


# Gate re-evaluates condition on state_reset (deserialize)
func test_state_reset_reevaluates() -> void:
	_chronicle.set_fact("quest.done", true)

	var parent := add_gate("quest.done")
	assert_gate_open(parent)

	var data: Dictionary = _chronicle.serialize()
	data["facts"]["quest.done"] = false
	_chronicle.deserialize(data)

	assert_gate_closed(parent)


# Gate with non-CanvasItem parent does not crash
func test_non_canvas_item_parent_no_crash() -> void:
	var parent := add_node()
	var gate := CompanionFactory.make_gate({condition = "quest.done"})
	parent.add_child(gate)

	_chronicle.set_fact("quest.done", true)
	assert_true(is_instance_valid(parent), "gate on non-CanvasItem parent doesn't crash")


# ── Expression Extensions — Gate Integration ──

# Gate with IN condition
func test_gate_in_condition() -> void:
	var parent := add_gate('quest.status IN ["done", "completed"]', {
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	assert_gate_closed(parent)
	_chronicle.set_fact("quest.status", "done")
	assert_gate_open(parent)
	_chronicle.set_fact("quest.status", "active")
	assert_gate_closed(parent)


# Gate with BETWEEN condition
func test_gate_between_condition() -> void:
	var parent := add_gate("player.level BETWEEN 5 AND 15", {
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	assert_gate_closed(parent)
	_chronicle.set_fact("player.level", 10)
	assert_gate_open(parent)
	_chronicle.set_fact("player.level", 20)
	assert_gate_closed(parent)


# Gate with IN key RHS — re-evaluates when RHS key changes
func test_gate_in_key_rhs_reacts_to_change() -> void:
	_chronicle.set_fact("allowed", ["warrior", "paladin"])
	_chronicle.set_fact("player.class", "warrior")
	var parent := add_gate("player.class IN allowed", {
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	assert_gate_open(parent)
	_chronicle.set_fact("allowed", ["mage", "sorcerer"])
	assert_gate_closed(parent)


# Gate with BETWEEN key bounds — re-evaluates when bound changes
func test_gate_between_key_bounds_reacts() -> void:
	_chronicle.set_fact("player.level", 10)
	_chronicle.set_fact("zone.min", 5)
	_chronicle.set_fact("zone.max", 15)
	var parent := add_gate("player.level BETWEEN zone.min AND zone.max", {
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	assert_gate_open(parent)
	_chronicle.set_fact("zone.min", 12)
	assert_gate_closed(parent)


# Gate with MATCHES condition — opens when string matches pattern
func test_gate_matches_condition() -> void:
	var parent := add_gate('npc.state MATCHES "idle|patrol"', {
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	assert_gate_closed(parent)
	_chronicle.set_fact("npc.state", "idle")
	assert_gate_open(parent)
	_chronicle.set_fact("npc.state", "chase")
	assert_gate_closed(parent)


# Gate with NOT MATCHES condition
func test_gate_not_matches_condition() -> void:
	_chronicle.set_fact("enemy.type", "miniboss")
	var parent := add_gate('enemy.type NOT MATCHES "boss"', {
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	assert_gate_open(parent)
	_chronicle.set_fact("enemy.type", "boss")
	assert_gate_closed(parent)


# Gate re-evaluates MATCHES when subject key changes
func test_gate_matches_reacts_to_subject_change() -> void:
	_chronicle.set_fact("quest.id", "main_quest_1")
	var parent := add_gate('quest.id MATCHES "main_.*"', {
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	assert_gate_open(parent)
	_chronicle.set_fact("quest.id", "side_quest_1")
	assert_gate_closed(parent)
	_chronicle.set_fact("quest.id", "main_quest_2")
	assert_gate_open(parent)


# Gate preserves original process_mode when showing target
func test_gate_preserves_original_process_mode() -> void:
	var target := add_node_2d("PMTarget")
	target.process_mode = Node.PROCESS_MODE_ALWAYS
	var gate := CompanionFactory.make_gate({condition = "pm.flag"})
	target.add_child(gate)

	# Condition false -> target hidden + process_mode DISABLED
	assert_false(target.visible, "target hidden when condition false")
	assert_eq(target.process_mode, Node.PROCESS_MODE_DISABLED, "process_mode DISABLED when gate closed")

	# Set fact -> condition true -> target shown, original ALWAYS restored
	_chronicle.set_fact("pm.flag", true)
	assert_true(target.visible, "target visible when condition true")
	assert_eq(target.process_mode, Node.PROCESS_MODE_ALWAYS, "Should restore original ALWAYS mode")


# Gate survives clear() — re-registers its watch so it can react again
func test_gate_survives_clear() -> void:
	_chronicle.set_fact("flag", true)
	var target := add_gate("flag", {target_path = ""})
	await get_tree().process_frame
	assert_gate_open(target)
	_chronicle.clear()
	_chronicle.set_fact("flag", true)
	assert_gate_open(target)


# Gate survives deserialize() — re-registers its watch so it can react again.
# clear() emits state_reset before destroying state (signal-before-destroy), so
# the gate re-evaluates while facts still exist. After _reset_state() the gate
# holds stale state until the next signal. deserialize() fires state_reset again,
# restoring the gate to the correct state.
func test_gate_survives_deserialize() -> void:
	_chronicle.set_fact("flag", true)
	var data: Dictionary = _chronicle.serialize()
	var target := add_gate("flag", {target_path = ""})
	await get_tree().process_frame
	assert_gate_open(target)
	_chronicle.clear()
	# After clear(), gate re-evaluated during state_reset while facts existed,
	# then _reset_state() destroyed facts. Gate holds stale open state.
	_chronicle.deserialize(data)
	assert_gate_open(target)


# QUEUE_FREE_WHEN_TRUE shows configuration warning
func test_queue_free_mode_shows_warning() -> void:
	var gate: ChronicleGate = autoqfree(ChronicleGate.new())
	gate.condition = "test.key"
	gate.gate_mode = CompanionFactory.GateMode.QUEUE_FREE_WHEN_TRUE
	assert_has_warning(gate, "QUEUE_FREE_WHEN_TRUE")


# ── Merged from test/audit/test_r16_a10_nodes.gd — Gate bug regression tests ──

# Gate captures original process_mode from target resolved via target_path
func test_gate_captures_original_process_mode_from_target() -> void:
	var parent := add_node_2d("parent")
	var target := Node2D.new()
	target.name = "target"
	target.visible = true
	target.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(target)

	var gate := CompanionFactory.make_gate({
		condition = "flag",
		target_path = NodePath("../target"),
	})
	parent.add_child(gate)

	# Gate should have captured PROCESS_MODE_ALWAYS
	assert_false(target.visible, "target hidden when condition false")
	assert_eq(target.process_mode, Node.PROCESS_MODE_DISABLED, "target disabled when gate closed")

	_chronicle.set_fact("flag", true)
	assert_true(target.visible, "target visible when condition true")
	assert_eq(target.process_mode, Node.PROCESS_MODE_ALWAYS,
		"Should restore original PROCESS_MODE_ALWAYS, not default INHERIT")

	# Cleanup
	target.queue_free()


# SHOW_WHEN_FALSE full open/close cycle preserves original process_mode
func test_show_when_false_full_cycle_preserves_process_mode() -> void:
	# Start with condition TRUE → SHOW_WHEN_FALSE hides target
	_chronicle.set_fact("quest.done", true)
	var parent := add_node_2d("swf_target")
	parent.process_mode = Node.PROCESS_MODE_ALWAYS
	var gate := CompanionFactory.make_gate({
		condition = "quest.done",
		gate_mode = CompanionFactory.GateMode.SHOW_WHEN_FALSE,
	})
	parent.add_child(gate)

	# Condition is true → SHOW_WHEN_FALSE hides
	assert_gate_closed(parent)

	# Set condition false → SHOW_WHEN_FALSE shows
	_chronicle.set_fact("quest.done", false)
	assert_true(parent.visible, "SHOW_WHEN_FALSE: visible when condition false")
	assert_eq(parent.process_mode, Node.PROCESS_MODE_ALWAYS,
		"SHOW_WHEN_FALSE: should restore original PROCESS_MODE_ALWAYS")


# custom_apply_fn with SHOW_WHEN_FALSE receives is_open (inverted), not raw result
func test_custom_apply_show_when_false_receives_is_open() -> void:
	var applied_results: Array = []

	var parent := add_node_2d("custom_gate_target")
	var gate: ChronicleGate = CompanionFactory.make_gate({
		condition = "flag",
		gate_mode = CompanionFactory.GateMode.SHOW_WHEN_FALSE,
	})
	gate.set_custom_apply(func(result: bool, _target: Node) -> void:
		applied_results.append(result)
	)
	parent.add_child(gate)

	# Initial: condition false → SHOW_WHEN_FALSE inverts: is_open = NOT result = true
	# _apply_gate passes is_open (inverted) to custom_apply_fn, not the raw result.
	assert_eq(applied_results.size(), 1, "custom_apply called on initial eval")
	assert_eq(applied_results[0], true, "custom_apply receives is_open (true — SHOW_WHEN_FALSE inverts false)")
	assert_true(gate.is_open(), "is_open should be true (SHOW_WHEN_FALSE inverts)")

	# Set condition true → is_open = NOT true = false
	_chronicle.set_fact("flag", true)
	assert_eq(applied_results.size(), 2)
	assert_eq(applied_results[1], false, "custom_apply receives is_open (false — SHOW_WHEN_FALSE inverts true)")
	assert_false(gate.is_open(), "is_open should be false (SHOW_WHEN_FALSE inverts)")


# SIGNAL_ONLY passes raw condition result (no SHOW_WHEN_FALSE inversion)
func test_signal_only_passes_raw_condition_result() -> void:
	var parent := add_node_2d("signal_only_target")
	var gate: ChronicleGate = CompanionFactory.make_gate({
		condition = "flag",
		gate_mode = CompanionFactory.GateMode.SIGNAL_ONLY,
	})
	parent.add_child(gate)

	# Initial: condition false → gate closed
	assert_false(gate.is_open(), "SIGNAL_ONLY: closed when condition false")

	_chronicle.set_fact("flag", true)
	assert_true(gate.is_open(), "SIGNAL_ONLY: open when condition true")

	# Parent should NOT be modified
	assert_true(parent.visible, "SIGNAL_ONLY: parent visibility unchanged")
	assert_eq(parent.process_mode, Node.PROCESS_MODE_INHERIT,
		"SIGNAL_ONLY: parent process_mode unchanged")


# Repeated _hide_target calls are idempotent — guard prevents overwriting _original_process_mode
func test_hide_target_idempotent_preserves_original_process_mode() -> void:
	var parent := add_node_2d("idempotent_target")
	parent.process_mode = Node.PROCESS_MODE_ALWAYS
	var gate := CompanionFactory.make_gate({condition = "flag"})
	parent.add_child(gate)

	# Initial: condition false → hidden
	assert_eq(parent.process_mode, Node.PROCESS_MODE_DISABLED, "initially disabled")

	# Set fact to false again (same result) → _apply_gate called again
	# Due to _transition_to guard, signals won't re-emit, but _hide_target is still called
	_chronicle.set_fact("flag", false)
	assert_eq(parent.process_mode, Node.PROCESS_MODE_DISABLED, "still disabled after redundant false")

	# Now open the gate
	_chronicle.set_fact("flag", true)
	assert_eq(parent.process_mode, Node.PROCESS_MODE_ALWAYS,
		"Should restore ALWAYS, not DISABLED (guard at line 246 prevents overwrite)")


# ── Merged from test/audit/test_r17_a10_nodes.gd — Gate audit tests ──

# Gate watch_id is valid (>= 0) after setup for single-key condition
func test_gate_watch_id_valid_after_setup() -> void:
	var target := add_node_2d()
	var gate: ChronicleGate = CompanionFactory.make_gate({condition = "quest.done"})
	target.add_child(gate)

	# After setup, gate should have a valid watch_id (>= 0) for single-key condition
	assert_gte(gate._watch_id, 0,
		"Gate should have a valid watch_id after setup for a single-key condition")


# Gate watch_id is valid for multi-key condition (watch_any)
func test_gate_watch_id_valid_for_multi_key_condition() -> void:
	var target := add_node_2d()
	var gate: ChronicleGate = CompanionFactory.make_gate({
		condition = "quest.started AND NOT quest.done"
	})
	target.add_child(gate)

	# Two keys → watch_any → watch_id >= 0
	assert_gte(gate._watch_id, 0,
		"Gate should have a valid watch_id for a multi-key condition")


# Gate with constant condition has NO_WATCH (-1) — no keys to watch
func test_gate_static_condition_no_watch() -> void:
	var target := add_node_2d()
	var gate: ChronicleGate = CompanionFactory.make_gate({condition = "TRUE"})
	target.add_child(gate)

	# Constant expression → zero keys → watch_id stays NO_WATCH (-1)
	assert_eq(gate._watch_id, -1,
		"Gate with constant condition should have NO_WATCH (-1) — no keys to watch")


# Gate preserves original process_mode across multiple open/close cycles
func test_gate_preserves_original_process_mode_across_cycles() -> void:
	var target := add_node_2d()
	target.process_mode = Node.PROCESS_MODE_ALWAYS
	var gate: ChronicleGate = CompanionFactory.make_gate({condition = "flag"})
	target.add_child(gate)

	# Initial: condition false -> gate hidden
	assert_false(target.visible, "gate should hide target initially")
	assert_eq(target.process_mode, Node.PROCESS_MODE_DISABLED,
		"gate should disable target initially")

	# Cycle 1: open -> close
	_chronicle.set_fact("flag", true)
	assert_true(target.visible, "target visible on open (cycle 1)")
	assert_eq(target.process_mode, Node.PROCESS_MODE_ALWAYS,
		"Gate should restore PROCESS_MODE_ALWAYS on open (cycle 1)")
	_chronicle.set_fact("flag", false)
	assert_eq(target.process_mode, Node.PROCESS_MODE_DISABLED,
		"Gate should disable target on close (cycle 1)")

	# Cycle 2: open -> close
	_chronicle.set_fact("flag", true)
	assert_eq(target.process_mode, Node.PROCESS_MODE_ALWAYS,
		"Gate should restore PROCESS_MODE_ALWAYS on open (cycle 2)")
	_chronicle.set_fact("flag", false)
	assert_eq(target.process_mode, Node.PROCESS_MODE_DISABLED,
		"Gate should disable target on close (cycle 2)")

	# Cycle 3: confirm _original_process_mode not degraded to DISABLED
	_chronicle.set_fact("flag", true)
	assert_eq(target.process_mode, Node.PROCESS_MODE_ALWAYS,
		"Gate should not degrade _original_process_mode after multiple cycles")


# QUEUE_FREE_WHEN_TRUE cleans up watches — no dangling refs after free
func test_queue_free_when_true_no_dangling_refs() -> void:
	var target := add_gate("destroy.me", {
		gate_mode = CompanionFactory.GateMode.QUEUE_FREE_WHEN_TRUE,
	})

	# Should not crash; target and gate get queue_freed
	_chronicle.set_fact("destroy.me", true)
	assert_true(target.is_queued_for_deletion(),
		"target should be queued for deletion")

	# Gate removes its watch before queue_free, so further writes should not
	# crash even though gate and target are queued (watch is already gone).
	var watcher_count_before: int = _chronicle.get_stats().watcher_count
	_chronicle.set_fact("destroy.me", false)
	_chronicle.set_fact("destroy.me", true)
	# Watcher count should not increase (gate unregistered its watch)
	assert_eq(_chronicle.get_stats().watcher_count, watcher_count_before,
		"Gate should unregister its watch before queue_free — no orphaned watchers")


# _ready_done is true when Chronicle autoload is present
func test_ready_done_true_when_chronicle_resolves() -> void:
	var target := add_node_2d()
	var gate: ChronicleGate = CompanionFactory.make_gate({condition = "quest.done"})
	target.add_child(gate)

	assert_true(gate._ready_done,
		"_ready_done should be true when Chronicle autoload is present")


# Gate _warn_unresolved_keys deduplicates — same missing key warns exactly once
func test_gate_warn_dedup_on_repeated_missing_key() -> void:
	var target := add_node_2d()
	var gate: ChronicleGate = CompanionFactory.make_gate({condition = "never.set"})
	target.add_child(gate)

	# Force MULTIPLE re-evaluations of the SAME watched key while it stays
	# missing at eval time: a falsy value (condition still false → warn path),
	# then erase (key absent again → warn path) — repeated. _warn_unresolved_keys
	# runs each time but _key_warn_dedup must keep exactly one entry for the key.
	for _i: int in 3:
		_chronicle.set_fact("never.set", false)
		_chronicle.erase_fact("never.set")
	assert_eq(gate._key_warn_dedup.size(), 1,
		"dedup keeps exactly one entry across repeated missing-key evals")


# SIGNAL_ONLY is_open reflects raw condition result (no inversion)
func test_signal_only_is_open_reflects_raw_result() -> void:
	var target := add_node_2d()
	var gate: ChronicleGate = CompanionFactory.make_gate({
		condition = "flag",
		gate_mode = CompanionFactory.GateMode.SIGNAL_ONLY,
	})
	target.add_child(gate)

	assert_false(gate.is_open(), "SIGNAL_ONLY: closed when condition false")
	assert_true(target.visible, "SIGNAL_ONLY: target visibility unchanged")
	assert_eq(target.process_mode, Node.PROCESS_MODE_INHERIT,
		"SIGNAL_ONLY: target process_mode unchanged")

	_chronicle.set_fact("flag", true)
	assert_true(gate.is_open(), "SIGNAL_ONLY: open when condition true")
	assert_true(target.visible, "SIGNAL_ONLY: target visibility still unchanged")


# ── R14/R15 bug regression ──


# Opening a gate on a target that started DISABLED activates it (INHERIT).
# audit: R17 — investigated, NOT a bug. gate.gd deliberately guards
# `if process_mode != DISABLED` at all three _original_process_mode capture
# sites (ready L114, reconnect L135, _hide_target L268) so DISABLED is NEVER
# recorded as a restorable original — this makes hide idempotent and enforces
# the gate's contract: "open ⇒ target active". A target that was DISABLED before
# the gate managed it is therefore activated (INHERIT + visible) when opened; the
# gate owns the target's enabled-state and cannot infer a pre-disabled target
# "wants" to stay disabled when the condition says open.
func test_gate_open_activates_target_that_started_disabled() -> void:
	var target := add_node_2d("target")
	target.process_mode = Node.PROCESS_MODE_DISABLED

	var gate := CompanionFactory.make_gate({
		condition = "unlock",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	target.add_child(gate)

	# Condition false → target stays disabled (already was). Now open the gate.
	_chronicle.set_fact("unlock", true)

	# Intentional contract: open activates the target (INHERIT) and makes it visible.
	assert_eq(target.process_mode, Node.PROCESS_MODE_INHERIT,
		"opening a gate activates a pre-disabled target (gate owns enabled-state)")
	assert_true(target.visible,
		"opening a gate makes the target visible")


# Gate custom_apply_fn + SHOW_WHEN_FALSE — signals should invert correctly
func test_gate_custom_apply_show_when_false_signals_invert() -> void:
	# Pre-set fact so expression is false initially, then true after
	var target := add_node_2d("target")
	var gate := CompanionFactory.make_gate({
		condition = "flag",
		gate_mode = CompanionFactory.GateMode.SHOW_WHEN_FALSE,
	})

	# Set custom apply BEFORE adding to tree so it's active from first eval
	gate.set_custom_apply(func(_result: bool, _t: Node) -> void:
		pass
	)

	target.add_child(gate)

	# Initial state: flag not set → expression false → SHOW_WHEN_FALSE = gate OPEN
	# Now set flag=true → expression true → SHOW_WHEN_FALSE = gate should be CLOSED
	var opened_events := collect_any_signal(gate, "gate_opened")
	var closed_events := collect_any_signal(gate, "gate_closed")

	_chronicle.set_fact("flag", true)

	# CORRECT: expression=true + SHOW_WHEN_FALSE → gate should CLOSE → gate_closed fires
	closed_events.assert_emission_count(1)
	opened_events.assert_emission_count(0)
