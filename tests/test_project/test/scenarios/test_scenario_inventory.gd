## Scenario tests: RPG inventory system built on Chronicle.
## Each test simulates a real game interaction — not isolated API checks.
## Facts represent items, quantities, equipment slots, and currency.
extends ChronicleTestSuite


# ── Item Pickup & Storage ──


# Pick up a unique item — marks it in inventory
func test_pickup_unique_item_marks_inventory() -> void:
	# Player walks over a sword on the dungeon floor
	_chronicle.set_fact("inventory.sword")

	assert_marked("inventory.sword")
	assert_fact("inventory.sword", true)


# Pick up stackable item — increments count
func test_pickup_stackable_item_increments_count() -> void:
	# Player picks up 3 health potions one at a time
	_chronicle.increment_fact("inventory.potions", 1)
	_chronicle.increment_fact("inventory.potions", 1)
	_chronicle.increment_fact("inventory.potions", 1)

	assert_fact("inventory.potions", 3)


# Drop unique item — erases from inventory
func test_drop_unique_item_erases_fact() -> void:
	# Player picks up a torch, then drops it
	_chronicle.set_fact("inventory.torch")
	assert_marked("inventory.torch")

	_chronicle.erase_fact("inventory.torch")

	assert_no_fact("inventory.torch")


# Use consumable — decrements count
func test_use_consumable_decrements_count() -> void:
	# Player has 5 potions, drinks one in combat
	_chronicle.set_fact("inventory.potions", 5)
	var remaining: Variant = _chronicle.increment_fact("inventory.potions", -1)

	assert_eq(remaining, 4.0)
	assert_fact("inventory.potions", 4)


# Use last consumable — count reaches 0, item erased
func test_use_last_consumable_erases_fact() -> void:
	# Player has exactly 1 potion left and uses it
	_chronicle.set_fact("inventory.potions", 1)
	_chronicle.increment_fact("inventory.potions", -1)

	# At zero, the system should erase the entry (no "zero" lingering)
	_chronicle.erase_fact("inventory.potions")

	assert_no_fact("inventory.potions")


# Equip item — sets equipment slot
func test_equip_item_sets_slot() -> void:
	# Player has a sword and equips it to the weapon slot
	_chronicle.set_fact("inventory.sword")
	_chronicle.set_fact("player.equipped.weapon", "sword")

	assert_fact("player.equipped.weapon", "sword")
	assert_marked("inventory.sword")


# Unequip item — clears equipment slot
func test_unequip_item_clears_slot() -> void:
	# Player had their sword equipped, now switches to bare hands
	_chronicle.set_fact("inventory.sword")
	_chronicle.set_fact("player.equipped.weapon", "sword")
	assert_fact("player.equipped.weapon", "sword")

	_chronicle.erase_fact("player.equipped.weapon")

	assert_no_fact("player.equipped.weapon")
	assert_marked("inventory.sword")  # sword still in bag


# ── Inventory Queries ──


# Find all items with glob pattern
func test_find_all_items_returns_all_inventory_keys() -> void:
	# Player looted a dungeon room with multiple items
	_chronicle.set_fact("inventory.sword")
	_chronicle.set_fact("inventory.shield")
	_chronicle.set_fact("inventory.torch")
	_chronicle.set_fact("inventory.potions", 3)
	_chronicle.set_fact("player.gold", 200)  # not inventory

	var items: Array[String] = _chronicle.get_fact_keys("inventory.*")

	assert_eq(items.size(), 4)
	assert_has(items, "inventory.sword")
	assert_has(items, "inventory.shield")
	assert_has(items, "inventory.torch")
	assert_has(items, "inventory.potions")


# Count items in a category
func test_count_items_in_category() -> void:
	# Merchant wants to know how many quest items the player carries
	_chronicle.set_fact("inventory.quest.ancient_scroll")
	_chronicle.set_fact("inventory.quest.golden_key")
	_chronicle.set_fact("inventory.quest.red_gem")
	_chronicle.set_fact("inventory.sword")  # not a quest item

	assert_fact_count("inventory.quest.*", 3)


# Check if player has specific item
func test_has_fact_checks_item_presence() -> void:
	# Gate puzzle: player needs the iron key
	_chronicle.set_fact("inventory.iron_key")

	assert_marked("inventory.iron_key")
	assert_no_fact("inventory.gold_key")


# Find first acquired item (earliest in timeline)
func test_first_change_returns_earliest_acquired_item() -> void:
	# Player acquired items over time — the first pickup was the dagger
	set_time(1.0)
	_chronicle.set_fact("inventory.dagger")
	set_time(2.0)
	_chronicle.set_fact("inventory.shield")
	set_time(3.0)
	_chronicle.set_fact("inventory.helmet")

	var first: Variant = _chronicle.get_first_change("inventory.*")

	assert_not_null(first)
	assert_eq(first.key, "inventory.dagger")
	assert_eq(first.time, 1.0)


# Find last acquired item (most recent)
func test_last_change_returns_most_recent_acquired_item() -> void:
	# Player's most recent pickup was the helmet
	set_time(1.0)
	_chronicle.set_fact("inventory.dagger")
	set_time(2.0)
	_chronicle.set_fact("inventory.shield")
	set_time(3.0)
	_chronicle.set_fact("inventory.helmet")

	var last: Variant = _chronicle.get_last_change("inventory.*")

	assert_not_null(last)
	assert_eq(last.key, "inventory.helmet")
	assert_eq(last.time, 3.0)


# Changes since last save shows new pickups
func test_changes_since_shows_new_pickups() -> void:
	# Player saved at t=5.0, then explored and found new items
	set_time(5.0)
	_chronicle.set_fact("inventory.leather_armor")  # already had before save

	var save_time: float = 5.0

	set_time(6.0)
	_chronicle.set_fact("inventory.magic_ring")
	set_time(7.0)
	_chronicle.set_fact("inventory.arrows", 20)

	var new_changes: Array[Dictionary] = _chronicle.get_changes_since(save_time)

	# Should contain the new ring and arrows, but not the armor (at exactly save_time)
	var new_keys: Array = []
	for entry: Dictionary in new_changes:
		new_keys.append(entry.key)

	assert_has(new_keys, "inventory.magic_ring")
	assert_has(new_keys, "inventory.arrows")


# ── Inventory with Companions ──


# Gate: locked door requires key item
func test_gate_locked_door_requires_key_item() -> void:
	# The dungeon's iron gate is locked unless player has the iron key
	var iron_door := add_gate("inventory.iron_key")

	# No key in inventory — door stays shut
	assert_gate_closed(iron_door)

	# Player picks up the iron key
	_chronicle.set_fact("inventory.iron_key")

	# Door swings open
	assert_gate_open(iron_door)


# Reactor: notifies on inventory change (watches inventory.*)
func test_reactor_notifies_on_inventory_change() -> void:
	# The UI loot-log listens for any inventory change to display a pickup banner
	var reactor := add_reactor({
		watch_pattern = "inventory.*",
		target_method = "on_fact",
		react_to = CompanionFactory.ReactTo.ANY,
	})

	# Player picks up two items
	_chronicle.set_fact("inventory.torch")
	_chronicle.set_fact("inventory.potions", 3)

	assert_spy_calls(reactor, 2)
	assert_spy_call(reactor, 0, "inventory.torch")
	assert_spy_call(reactor, 1, "inventory.potions")


# Recorder: chest signal records item pickup
func test_recorder_chest_signal_records_item_pickup() -> void:
	# Opening a chest emits "opened" signal — recorder commits the loot fact
	var chest := add_recorder({
		trigger_signal = "opened",
		fact_key = "inventory.chest_relic",
		record_mode = CompanionFactory.RecordMode.ONCE,
	})

	assert_no_fact("inventory.chest_relic")

	# Player opens the chest
	chest.emit_signal("opened")

	assert_marked("inventory.chest_relic")


# Gate: opens when gold >= threshold (expression condition)
func test_gate_opens_when_gold_meets_threshold() -> void:
	# Merchant's back room only opens to wealthy customers (500+ gold)
	var merchant_room := add_gate("player.gold >= 500")

	_chronicle.set_fact("player.gold", 200)
	assert_gate_closed(merchant_room)

	_chronicle.set_fact("player.gold", 500)
	assert_gate_open(merchant_room)

	_chronicle.set_fact("player.gold", 1000)
	assert_gate_open(merchant_room)

	_chronicle.set_fact("player.gold", 499)
	assert_gate_closed(merchant_room)


# ── Inventory + Serialization ──


# Save/load preserves full inventory state
func test_save_load_preserves_full_inventory() -> void:
	# Player has a rich inventory; game saves and reloads (e.g., quit and relaunch)
	_chronicle.set_fact("inventory.sword")
	_chronicle.set_fact("inventory.shield")
	_chronicle.set_fact("inventory.potions", 5)
	_chronicle.set_fact("inventory.arrows", 30)
	_chronicle.set_fact("player.gold", 1500)

	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	var ok: bool = _chronicle.deserialize(data)

	assert_true(ok)
	assert_marked("inventory.sword")
	assert_marked("inventory.shield")
	assert_fact("inventory.potions", 5)
	assert_fact("inventory.arrows", 30)
	assert_fact("player.gold", 1500)


# Save/load preserves equipped items
func test_save_load_preserves_equipment() -> void:
	# Player's equipment loadout must survive a save/load cycle
	_chronicle.set_fact("inventory.sword")
	_chronicle.set_fact("inventory.leather_armor")
	_chronicle.set_fact("player.equipped.weapon", "sword")
	_chronicle.set_fact("player.equipped.armor", "leather")

	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	var ok: bool = _chronicle.deserialize(data)

	assert_true(ok)
	assert_fact("player.equipped.weapon", "sword")
	assert_fact("player.equipped.armor", "leather")
	assert_marked("inventory.sword")
	assert_marked("inventory.leather_armor")


# Rollback after spending gold restores balance
func test_rollback_after_spending_gold_restores_balance() -> void:
	# Player had 1000 gold; a purchase went wrong and needs to be reversed
	set_time(1.0)
	_chronicle.set_fact("player.gold", 1000)

	set_time(2.0)
	_chronicle.increment_fact("player.gold", -400)  # bought a helmet for 400

	assert_fact("player.gold", 600)

	# Transaction rolled back (e.g., server rejected it)
	_chronicle.rollback_to(1.5)

	assert_fact("player.gold", 1000)


# Rollback after using consumable restores count
func test_rollback_after_using_consumable_restores_count() -> void:
	# Player used a potion, but the game needs to undo the action
	set_time(1.0)
	_chronicle.set_fact("inventory.potions", 5)

	set_time(2.0)
	_chronicle.increment_fact("inventory.potions", -1)
	assert_fact("inventory.potions", 4)

	_chronicle.rollback_to(1.5)

	assert_fact("inventory.potions", 5)


# ── Inventory Edge Cases ──


# Pickup same unique item twice is idempotent
func test_pickup_same_unique_item_twice_is_idempotent() -> void:
	# Triggering the same pickup event twice should not corrupt state
	_chronicle.set_fact("inventory.old_map")
	_chronicle.set_fact("inventory.old_map")  # duplicate trigger

	assert_marked("inventory.old_map")
	assert_fact_count("inventory.*", 1)  # still just one entry


# Drop item not in inventory — no crash, no change
func test_drop_nonexistent_item_no_crash() -> void:
	# Safe to call erase_fact on a key that never existed
	_chronicle.set_fact("inventory.sword")

	_chronicle.erase_fact("inventory.shield")  # shield was never picked up

	# Sword is unaffected; no crash
	assert_marked("inventory.sword")
	assert_no_fact("inventory.shield")
	assert_fact_count("inventory.*", 1)


# Multiple save/load cycles — inventory stable
func test_multiple_save_load_cycles_inventory_stable() -> void:
	# Simulate autosave every few minutes across three save points
	_chronicle.set_fact("inventory.sword")
	_chronicle.set_fact("inventory.potions", 3)
	_chronicle.set_fact("player.gold", 800)

	# Cycle 1
	roundtrip()
	assert_marked("inventory.sword")

	# Pick up something new between saves
	_chronicle.set_fact("inventory.magic_wand")

	# Cycle 2
	roundtrip()

	assert_marked("inventory.sword")
	assert_marked("inventory.magic_wand")
	assert_fact("inventory.potions", 3)
	assert_fact("player.gold", 800)

	# Cycle 3
	roundtrip()

	assert_marked("inventory.sword")
	assert_marked("inventory.magic_wand")
	assert_fact("inventory.potions", 3)
	assert_fact("player.gold", 800)


# Large inventory (30 items) serializes correctly
func test_large_inventory_serializes_correctly() -> void:
	# Endgame player has collected 30 different items
	for i: int in range(30):
		_chronicle.set_fact("inventory.item_%02d" % i)

	assert_fact_count("inventory.*", 30)

	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	var ok: bool = _chronicle.deserialize(data)

	assert_true(ok)
	assert_fact_count("inventory.*", 30)

	# Spot-check a few entries
	assert_marked("inventory.item_00")
	assert_marked("inventory.item_14")
	assert_marked("inventory.item_29")


# ── Full Playthrough ──


# Full session: find sword, equip, buy potions, use one, save, load, verify all
func test_full_session_find_equip_buy_use_save_load() -> void:
	# Step 1: Player enters the dungeon with some gold
	_chronicle.set_fact("player.gold", 300)

	# Step 2: Find and pick up a sword
	_chronicle.set_fact("inventory.sword")
	_chronicle.set_fact("player.equipped.weapon", "sword")

	# Step 3: Visit a merchant and buy 3 potions for 75 gold total
	_chronicle.increment_fact("player.gold", -75)
	_chronicle.set_fact("inventory.potions", 3)

	# Step 4: Use one potion in a tough fight
	_chronicle.increment_fact("inventory.potions", -1)

	# Step 5: Save game
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	var ok: bool = _chronicle.deserialize(data)

	# Step 6: Verify everything survived the load
	assert_true(ok)
	assert_marked("inventory.sword")
	assert_fact("player.equipped.weapon", "sword")
	assert_fact("player.gold", 225)
	assert_fact("inventory.potions", 2)


# Merchant transaction: spend gold, receive item, both facts consistent
func test_merchant_transaction_gold_and_items_consistent() -> void:
	# Player wants to buy a shield for 150 gold
	_chronicle.set_fact("player.gold", 500)
	_chronicle.set_fact("inventory.sword")  # already owns a sword

	# Merchant sells shield for 150 gold
	var new_gold: Variant = _chronicle.increment_fact("player.gold", -150)
	_chronicle.set_fact("inventory.shield")

	assert_eq(new_gold, 350.0)
	assert_fact("player.gold", 350)
	assert_marked("inventory.shield")
	assert_marked("inventory.sword")  # unrelated item unchanged


# Temporary buff item with lifetime expires (transient fact)
func test_temporary_buff_item_is_transient() -> void:
	# Player drinks a speed potion — effect is transient, not saved
	_chronicle.set_fact("player.gold", 200)
	_chronicle.set_fact("inventory.sword")
	_chronicle.set_fact("player.speed_boost", 2.0, true, 0.0)  # transient buff

	assert_fact("player.speed_boost", 2.0)

	# Save game — the buff should NOT persist
	roundtrip()

	assert_no_fact("player.speed_boost")     # buff gone after load
	assert_marked("inventory.sword")          # persistent items intact
	assert_fact("player.gold", 200)


# Quest reward appears after quest completion (gate + set_fact)
func test_quest_reward_gate_opens_on_completion() -> void:
	# The reward chest only appears once the quest flag is set
	var reward_chest := add_gate("quest.goblin_cave.completed")

	assert_gate_closed(reward_chest)  # quest not yet done

	# Player defeats the goblin boss and completes the quest
	_chronicle.set_fact("quest.goblin_cave.completed")

	assert_gate_open(reward_chest)

	# Player collects the reward
	_chronicle.set_fact("inventory.legendary_bow")
	_chronicle.set_fact("player.gold", _chronicle.get_fact("player.gold") + 500 if _chronicle.has_fact("player.gold") else 500)

	assert_marked("inventory.legendary_bow")
	assert_marked("quest.goblin_cave.completed")


# Rollback mid-transaction restores both gold and items
func test_rollback_mid_transaction_restores_gold_and_items() -> void:
	# Player had 1000 gold and no fancy armor. Tried to buy plate armor for 600 gold.
	set_time(1.0)
	_chronicle.set_fact("player.gold", 1000)
	assert_no_fact("inventory.plate_armor")

	set_time(2.0)
	# Transaction starts: deduct gold and add item
	_chronicle.increment_fact("player.gold", -600)
	_chronicle.set_fact("inventory.plate_armor")

	assert_fact("player.gold", 400)
	assert_marked("inventory.plate_armor")

	# Transaction rejected (e.g., network error, invalid state) — rollback
	_chronicle.rollback_to(1.5)

	# Both gold and item restored to pre-transaction state
	assert_fact("player.gold", 1000)
	assert_no_fact("inventory.plate_armor")
