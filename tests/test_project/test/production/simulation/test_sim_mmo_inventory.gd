extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")


func _setup_inventory() -> void:
	for i in 2000:
		_chronicle.set_facts({
			"slot_%d.item_id" % i: "item_%d" % (i % 100),
			"slot_%d.quantity" % i: (i % 10) + 1,
			"slot_%d.enchantment" % i: "none",
		})
	for i in 100:
		_chronicle.set_fact("currency.type_%d" % i, 1000)
	for i in 50:
		_chronicle.set_facts({
			"stash_%d.name" % i: "Tab %d" % i,
			"stash_%d.size" % i: 40,
		})


# A burst of 500 loot writes lands all items in the store.
func test_loot_burst() -> void:
	_setup_inventory()
	for i in 500:
		_chronicle.set_fact("loot.item_%d" % i, "drop_%d" % i)
	assert_fact_count("loot.*", 500)
	assert_fact("loot.item_0", "drop_0")
	assert_fact("loot.item_499", "drop_499")


# Bulk-rewriting 2000 slot item ids applies to all slots.
func test_inventory_sort() -> void:
	_setup_inventory()
	var sorted_items := {}
	for i in 2000:
		sorted_items["slot_%d.item_id" % i] = "sorted_%d" % i
	_chronicle.set_facts(sorted_items)
	assert_fact("slot_0.item_id", "sorted_0")
	assert_fact("slot_1999.item_id", "sorted_1999")


# A trade batch erases sold slots, adds bought slots, and adjusts currency.
func test_trade_transaction() -> void:
	_setup_inventory()
	var trade := {}
	for i in 20:
		trade["slot_%d.item_id" % i] = null
		trade["slot_%d.quantity" % i] = null
	for i in range(2000, 2020):
		trade["slot_%d.item_id" % i] = "traded_%d" % i
		trade["slot_%d.quantity" % i] = 1
	trade["currency.type_0"] = 500
	_chronicle.set_facts(trade)
	for i in 20:
		assert_no_fact("slot_%d.item_id" % i)
	for i in range(2000, 2020):
		assert_fact("slot_%d.item_id" % i, "traded_%d" % i)
	assert_fact("currency.type_0", 500)


# 1000 ticks of currency increments reach the expected totals.
func test_currency_tick() -> void:
	_setup_inventory()
	for frame in 1000:
		for c in 100:
			_chronicle.increment_fact("currency.type_%d" % c)
	for c in 100:
		assert_fact("currency.type_%d" % c, 2000)


# Serializing a large 6.2k-fact inventory produces a non-empty snapshot.
func test_stash_serialize_size() -> void:
	_setup_inventory()
	var out := [{}]
	var elapsed_ms := ScaleHelper.time_callable(func() -> void:
		out[0] = _chronicle.serialize()
	) / 1000.0
	var data: Dictionary = out[0]
	gut.p("Serialize 6.2k facts: %.1f ms, timeline entries: %d" % [elapsed_ms, data.timeline.size()])
	# 2000 slots * 3 keys + 100 currencies + 50 stash * 2 keys = 6200 facts.
	# No transient facts in _setup_inventory(), so all 6200 are serialized.
	assert_eq(data.facts.size(), 6200, "serialized inventory must contain every fact")


# Rapid save/load cycles preserve the latest currency value each cycle.
func test_rapid_save_load() -> void:
	_setup_inventory()
	for cycle in 20:
		_chronicle.set_fact("currency.type_0", 1000 + cycle)
		roundtrip()
		assert_fact("currency.type_0", 1000 + cycle)
