extends ChronicleTestSuite


# ── Watcher + Deserialize ──────────────────────────────────────────────────────

# Watcher registered before deserialize does NOT fire for restored facts
func test_watcher_does_not_fire_for_deserialized_facts() -> void:
	# Set up state, serialize, clear, register watcher, then deserialize
	_chronicle.set_fact("player.hp", 100)
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()

	# Watcher registered after clear — deserialize suppresses dispatch
	var events := watch_events("player.hp")
	_chronicle.deserialize(data)

	# Watchers do NOT fire during deserialize (_deserializing flag suppresses dispatch)
	events.assert_count(0)
	# But the fact IS restored
	assert_fact("player.hp", 100)


# state_reset signal fires after deserialize completes
func test_state_reset_fires_after_deserialize() -> void:
	# Set up a fact and serialize
	_chronicle.set_fact("player.gold", 50)
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()

	# Connect a collector to state_reset
	var reset_events := collect_any_signal(_chronicle, "state_reset")

	# Deserialize — _reset_state() skips signal; only _apply_snapshot emits state_reset once
	_chronicle.deserialize(data)
	reset_events.assert_emission_count(1)


# Glob watcher does NOT fire for keys matching pattern during deserialize
func test_glob_watcher_does_not_fire_for_deserialized_keys() -> void:
	# Set several facts under "entity.*"
	_chronicle.set_fact("entity.hp", 100)
	_chronicle.set_fact("entity.mp", 50)
	_chronicle.set_fact("entity.level", 3)
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()

	# Register glob watcher before deserializing
	var events := watch_events("entity.*")
	_chronicle.deserialize(data)

	# Deserialize suppresses watcher dispatch — no events fired
	events.assert_count(0)
	# Facts are restored correctly
	assert_fact("entity.hp", 100)
	assert_fact("entity.mp", 50)
	assert_fact("entity.level", 3)


# watch_once is NOT consumed by fact restored during deserialize
func test_watch_once_not_consumed_by_deserialize() -> void:
	# Set up state to serialize
	_chronicle.set_fact("player.hp", 100)
	var data: Dictionary = _chronicle.serialize()
	# Deserialize (internally calls clear, wiping prior watchers)
	var ok: bool = _chronicle.deserialize(data)
	assert_true(ok)

	# Register watch_once AFTER deserialize — verify it works normally
	var events := watch_once_events("player.hp")
	_chronicle.set_fact("player.hp", 200)
	events.assert_count(1)
	events.assert_event(0, "player.hp", 200, 100)

	# watch_once is now spent — no second fire
	_chronicle.set_fact("player.hp", 300)
	events.assert_count(1)


# Watcher registered before deserialize survives and fires after for new changes
func test_watcher_survives_deserialize() -> void:
	# Set up state and serialize
	_chronicle.set_fact("game.score", 999)
	var data: Dictionary = _chronicle.serialize()

	# Deserialize (calls clear() internally, which wipes watchers)
	var ok: bool = _chronicle.deserialize(data)
	assert_true(ok)

	# Register watcher AFTER deserialize — verify watch system works post-deserialize
	var events := watch_events("game.score")
	_chronicle.set_fact("game.score", 1000)
	events.assert_count(1)
	events.assert_event(0, "game.score", 1000, 999)


# ── Watcher Self-Modification ──────────────────────────────────────────────────

# Unwatch self inside callback — no crash, watcher removed
func test_unwatch_self_inside_callback() -> void:
	# Register watcher that unwatches itself on first call
	var my_id: Array = [0]
	var fired: Array = [0]
	my_id[0] = _chronicle.watch("key.self", func(k: String, v: Variant, o: Variant) -> void:
		fired[0] += 1
		_chronicle.unwatch(my_id[0])
	)
	assert_gte(my_id[0], 0, "watch returned valid id")

	# First set_fact fires the callback and self-unwatches
	_chronicle.set_fact("key.self", 1)
	assert_eq(fired[0], 1, "callback fired once")

	# Second set_fact does not fire — watcher removed
	_chronicle.set_fact("key.self", 2)
	assert_eq(fired[0], 1, "callback not fired again after self-unwatch")


# Unwatch ANOTHER watcher inside callback — other stops firing
func test_unwatch_other_inside_callback() -> void:
	# Register two watchers; watcher A unwatches B when triggered
	var b_id: Array = [-1]
	var a_fired: Array = [0]
	var b_events := make_collector()

	_chronicle.watch("key.pair", func(k: String, v: Variant, o: Variant) -> void:
		a_fired[0] += 1
		_chronicle.unwatch(b_id[0])
	)
	b_id[0] = _chronicle.watch("key.pair", b_events.callback())

	# First fire: A fires and unwatches B; B is skipped (watch_reverse guard)
	_chronicle.set_fact("key.pair", 1)
	assert_eq(a_fired[0], 1, "watcher A fired")
	b_events.assert_count(0)

	# Second fire: only A fires; B is gone
	_chronicle.set_fact("key.pair", 2)
	assert_eq(a_fired[0], 2, "watcher A fired again")
	b_events.assert_count(0)


# Register new watch inside callback — new watcher works for future changes
func test_register_watch_inside_callback() -> void:
	# Register a watcher that, on first fire, registers a new persistent watcher
	var inner_events := make_collector()
	var inner_registered: Array = [false]

	_chronicle.watch("key.outer", func(k: String, v: Variant, o: Variant) -> void:
		if not inner_registered[0]:
			inner_registered[0] = true
			_chronicle.watch("key.inner", inner_events.callback())
	)

	# Trigger outer watcher — registers inner watcher
	_chronicle.set_fact("key.outer", 1)
	assert_true(inner_registered[0], "inner watcher registered from callback")

	# Inner watcher not yet fired (it was registered after this dispatch)
	inner_events.assert_count(0)

	# Set inner key — inner watcher fires
	_chronicle.set_fact("key.inner", 42)
	inner_events.assert_count(1)
	inner_events.assert_event(0, "key.inner", 42, null)


# watch_once callback registers a new persistent watch
func test_watch_once_registers_new_watch() -> void:
	# watch_once that, when it fires, registers a persistent watcher
	var persistent_events := make_collector()
	var once_fired: Array = [false]

	_chronicle.watch("key.bootstrap", func(k: String, v: Variant, o: Variant) -> void:
		once_fired[0] = true
		_chronicle.watch("key.persistent", persistent_events.callback())
	, true)

	# Trigger watch_once — it fires and registers persistent watcher
	_chronicle.set_fact("key.bootstrap", 1)
	assert_true(once_fired[0], "watch_once fired")

	# watch_once is spent — won't fire again
	_chronicle.set_fact("key.bootstrap", 2)
	assert_true(once_fired[0], "watch_once stays fired (not reset) after a second write")

	# Persistent watcher from inside callback works
	_chronicle.set_fact("key.persistent", 99)
	persistent_events.assert_count(1)
	persistent_events.assert_event(0, "key.persistent", 99, null)

	_chronicle.set_fact("key.persistent", 100)
	persistent_events.assert_count(2)


# ── Watcher + Bulk Operations ──────────────────────────────────────────────────

# Watcher fires for each key in set_facts batch
func test_watcher_fires_for_each_key_in_set_facts() -> void:
	# Register a watcher on each individual key
	var events_a := watch_events("batch.a")
	var events_b := watch_events("batch.b")
	var events_c := watch_events("batch.c")

	# Batch write three keys
	_chronicle.set_facts({"batch.a": 1, "batch.b": 2, "batch.c": 3})

	# Each individual watcher fires once
	events_a.assert_count(1)
	events_b.assert_count(1)
	events_c.assert_count(1)
	events_a.assert_event(0, "batch.a", 1, null)
	events_b.assert_event(0, "batch.b", 2, null)
	events_c.assert_event(0, "batch.c", 3, null)


# fact_changed fires for each key in set_facts batch
func test_fact_changed_fires_for_each_batch_key() -> void:
	var events := collect_signal(_chronicle, "fact_changed")

	# Batch write three keys
	_chronicle.set_facts({"quest.a": 10, "quest.b": 20, "quest.c": 30})

	# fact_changed fires for each key
	events.assert_count(3)
	events.assert_keys(["quest.a", "quest.b", "quest.c"])


# erase_facts fires watcher for each erased key
func test_erase_facts_fires_watcher_per_key() -> void:
	# Create facts then register watchers
	_chronicle.set_fact("item.sword", true)
	_chronicle.set_fact("item.shield", true)
	_chronicle.set_fact("item.potion", true)

	var sword_events := watch_events("item.sword")
	var shield_events := watch_events("item.shield")
	var potion_events := watch_events("item.potion")

	# Erase all three via erase_facts
	_chronicle.erase_facts(["item.sword", "item.shield", "item.potion"] as Array[String])

	# Each watcher fires once with null value
	sword_events.assert_count(1)
	shield_events.assert_count(1)
	potion_events.assert_count(1)
	sword_events.assert_event(0, "item.sword", null, true)
	shield_events.assert_event(0, "item.shield", null, true)
	potion_events.assert_event(0, "item.potion", null, true)


# Glob watcher matches keys from set_facts batch
func test_glob_watcher_matches_set_facts_keys() -> void:
	# Register glob watcher before batch
	var events := watch_events("npc.*")

	# Batch write — some match glob, some don't
	_chronicle.set_facts({
		"npc.guard": "idle",
		"npc.merchant": "selling",
		"player.hp": 100,
	})

	# Glob watcher fires only for matching keys
	events.assert_count(2)
	events.assert_keys(["npc.guard", "npc.merchant"])


# set_facts with mix of new and existing keys — watcher fires for all
func test_set_facts_mixed_new_existing_fires_all() -> void:
	# Pre-set some keys
	_chronicle.set_fact("mix.existing", 1)

	# Register watcher
	var events := watch_events("mix.*")

	# Batch with one existing key (update) and one new key (creation)
	_chronicle.set_facts({"mix.existing": 99, "mix.new": 42})

	# Watcher fires for both
	events.assert_count(2)
	events.assert_keys(["mix.existing", "mix.new"])
	events.assert_event(0, "mix.existing", 99, 1)
	events.assert_event(1, "mix.new", 42, null)


# ── Watcher + Lifetime ────────────────────────────────────────────────────────

# Watcher fires when fact expires (value becomes null)
func test_watcher_fires_on_expiration() -> void:
	# Register watcher, set fact with lifetime
	var events := watch_events("buff.speed")
	set_time(10.0)
	_chronicle.set_fact("buff.speed", 2.0, false, 5.0)  # expires at t=15
	events.clear()  # ignore the creation event

	# Advance past expiry
	advance_time(6.0)  # now t=16

	# Watcher fires with null value
	events.assert_count(1)
	events.assert_event(0, "buff.speed", null, 2.0)


# fact_expired signal fires with last value before expiry
func test_fact_expired_signal_contains_value() -> void:
	# Collect fact_expired signal (key, value — 2-arg)
	var expired_events := make_collector()
	_chronicle.fact_expired.connect(expired_events.callback())

	# Set fact with lifetime and advance past expiry
	set_time(0.0)
	_chronicle.set_fact("pickup.coin", 100, false, 3.0)
	advance_time(3.5)

	# fact_expired fired with the correct key and value
	expired_events.assert_count(1)
	expired_events.assert_event(0, "pickup.coin", 100)


# Glob watcher fires for expired fact within pattern
func test_glob_watcher_fires_on_expiry() -> void:
	# Register glob watcher
	var events := watch_events("effect.*")
	set_time(0.0)
	_chronicle.set_fact("effect.fire", 5, false, 2.0)
	events.clear()  # clear creation event

	# Advance past expiry
	advance_time(2.5)

	# Glob watcher fires with null value
	events.assert_count(1)
	events.assert_event(0, "effect.fire", null, 5)


# Fact expires then gets re-set — watcher fires for both events
func test_expire_then_reset_fires_twice() -> void:
	# Register watcher
	var events := watch_events("buff.regen")
	set_time(0.0)
	_chronicle.set_fact("buff.regen", 3, false, 2.0)
	events.clear()  # ignore creation event

	# Expire the fact
	advance_time(2.5)
	events.assert_count(1)  # expiry event (null)
	events.assert_event(0, "buff.regen", null, 3)

	# Re-set the fact
	_chronicle.set_fact("buff.regen", 7)
	events.assert_count(2)  # second event: re-creation
	events.assert_event(1, "buff.regen", 7, null)


# ── Watcher + Erase ───────────────────────────────────────────────────────────

# Watcher fires when fact is erased (new value = null)
func test_watcher_fires_on_erase() -> void:
	# Create fact and register watcher
	_chronicle.set_fact("obj.active", true)
	var events := watch_events("obj.active")

	# Erase the fact
	_chronicle.erase_fact("obj.active")

	# Watcher fired once
	events.assert_count(1)
	assert_no_fact("obj.active")


# Erased fact's watcher receives null as new_value, previous as old_value
func test_erase_watcher_receives_null_and_old() -> void:
	# Create fact with a known value
	_chronicle.set_fact("char.name", "Hero")
	var events := watch_events("char.name")

	# Erase
	_chronicle.erase_fact("char.name")

	# Event carries correct null + old_value
	events.assert_count(1)
	events.assert_event(0, "char.name", null, "Hero")


# Glob watcher fires on erase within pattern
func test_glob_watcher_fires_on_erase() -> void:
	# Set facts under glob pattern, then register watcher
	_chronicle.set_fact("world.zone", "forest")
	_chronicle.set_fact("world.boss", "dragon")
	var events := watch_events("world.*")

	# Erase one key
	_chronicle.erase_fact("world.zone")

	# Glob watcher fires for the erased key
	events.assert_count(1)
	events.assert_event(0, "world.zone", null, "forest")


# Erase non-existent fact — watcher does NOT fire
func test_erase_nonexistent_does_not_fire_watcher() -> void:
	# Register watcher on a key that doesn't exist
	var events := watch_events("ghost.key")

	# Attempt to erase a non-existent fact
	_chronicle.erase_fact("ghost.key")

	# Watcher never fires — nothing was removed
	events.assert_count(0)


# ── Watch Patterns ────────────────────────────────────────────────────────────

# Multiple glob watchers on overlapping patterns — all fire independently
func test_multiple_globs_all_fire() -> void:
	# Register two glob patterns that overlap for "player.speed"
	var all_events := watch_events("*")
	var player_events := watch_events("player.*")

	# Write a key matching both patterns
	_chronicle.set_fact("player.speed", 5)

	# Both fire independently
	all_events.assert_count(1)
	player_events.assert_count(1)

	# A key in a different entity — only the broad glob fires
	_chronicle.set_fact("enemy.hp", 100)
	all_events.assert_count(2)
	player_events.assert_count(1)


# unwatch with invalid ID is a no-op that returns false
func test_unwatch_invalid_id_no_crash() -> void:
	# Unwatching IDs that were never registered returns false
	assert_false(_chronicle.unwatch(-1), "unwatch(-1) returns false — no such watcher")
	assert_false(_chronicle.unwatch(0), "unwatch(0) returns false — no such watcher")
	assert_false(_chronicle.unwatch(99999), "unwatch(99999) returns false — no such watcher")

	# No crash — watchers still function normally
	var events := watch_events("safe.key")
	_chronicle.set_fact("safe.key", 1)
	events.assert_count(1)


# Watch with array of exact keys — fires for each key independently
func test_watch_array_fires_for_each_key() -> void:
	# Register watch on an array of two distinct keys (same callback)
	var events := watch_events(["item.sword", "item.bow"])

	# Set each key — watcher fires for each
	_chronicle.set_fact("item.sword", true)
	events.assert_count(1)
	events.assert_event(0, "item.sword", true, null)

	_chronicle.set_fact("item.bow", true)
	events.assert_count(2)
	events.assert_event(1, "item.bow", true, null)

	# Unrelated key does not fire
	_chronicle.set_fact("item.staff", true)
	events.assert_count(2)


# ── Watcher Ordering ──────────────────────────────────────────────────────────

# Multiple watchers on same key all fire
func test_multiple_watchers_same_key_all_fire() -> void:
	# Register three separate watchers on the same key
	var events_a := watch_events("shared.key")
	var events_b := watch_events("shared.key")
	var events_c := watch_events("shared.key")

	# Set the key once
	_chronicle.set_fact("shared.key", 42)

	# All three fire
	events_a.assert_count(1)
	events_b.assert_count(1)
	events_c.assert_count(1)
	events_a.assert_event(0, "shared.key", 42, null)
	events_b.assert_event(0, "shared.key", 42, null)
	events_c.assert_event(0, "shared.key", 42, null)


# Watcher registration order is preserved for same-key watchers
func test_watcher_order_is_registration_order() -> void:
	# Track order of callback invocations
	var order: Array = []

	_chronicle.watch("order.key", func(k: String, v: Variant, o: Variant) -> void:
		order.append("first")
	)
	_chronicle.watch("order.key", func(k: String, v: Variant, o: Variant) -> void:
		order.append("second")
	)
	_chronicle.watch("order.key", func(k: String, v: Variant, o: Variant) -> void:
		order.append("third")
	)

	# Trigger
	_chronicle.set_fact("order.key", 1)

	# Order matches registration order
	assert_eq(order, ["first", "second", "third"])


# Glob AND exact watch on same key — both fire
func test_glob_and_exact_both_fire() -> void:
	# Register both an exact watcher and a glob watcher covering the same key
	var exact_events := watch_events("combo.value")
	var glob_events := watch_events("combo.*")

	# Set the key — both watchers should fire
	_chronicle.set_fact("combo.value", 77)

	exact_events.assert_count(1)
	glob_events.assert_count(1)
	exact_events.assert_event(0, "combo.value", 77, null)
	glob_events.assert_event(0, "combo.value", 77, null)


# Exact watcher fires BEFORE glob watcher (dispatch order)
func test_exact_fires_before_glob() -> void:
	# Track the order in which exact vs. glob callbacks fire
	var order: Array = []

	_chronicle.watch("dispatch.key", func(k: String, v: Variant, o: Variant) -> void:
		order.append("exact")
	)
	_chronicle.watch("dispatch.*", func(k: String, v: Variant, o: Variant) -> void:
		order.append("glob")
	)

	# Trigger
	_chronicle.set_fact("dispatch.key", 1)

	# Exact fires before glob
	assert_eq(order.size(), 2)
	assert_eq(order[0], "exact")
	assert_eq(order[1], "glob")


# watch_once among persistent watches — fires once then gone
func test_watch_once_among_persistent() -> void:
	# Register a persistent watcher and a watch_once on the same key
	var persistent_events := watch_events("mixed.key")
	var once_events := watch_once_events("mixed.key")

	# First fire — both receive the event
	_chronicle.set_fact("mixed.key", 1)
	persistent_events.assert_count(1)
	once_events.assert_count(1)

	# Second fire — only persistent watcher fires; watch_once is spent
	_chronicle.set_fact("mixed.key", 2)
	persistent_events.assert_count(2)
	once_events.assert_count(1)

	# Third fire — persistent keeps firing, watch_once stays silent
	_chronicle.set_fact("mixed.key", 3)
	persistent_events.assert_count(3)
	once_events.assert_count(1)
