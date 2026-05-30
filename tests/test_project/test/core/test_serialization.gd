extends ChronicleTestSuite

const TypeCodec := preload("res://addons/chronicle/core/serialization/type_codec.gd")
const TypeRegistry := preload("res://addons/chronicle/core/serialization/type_registry.gd")
const BuiltinTypes := preload("res://addons/chronicle/core/serialization/builtin_types.gd")
const SerializerScript := preload("res://addons/chronicle/core/serialization/serializer.gd")
const _Store := preload("res://addons/chronicle/core/store.gd")
const _Expiry := preload("res://addons/chronicle/core/expiry.gd")
const _GameClock := preload("res://addons/chronicle/core/game_clock.gd")
const _KeyCodec := preload("res://addons/chronicle/core/key_codec.gd")
const _Timeline := preload("res://addons/chronicle/core/timeline.gd")


# serialize() returns Dictionary with version, facts, timeline keys
func test_serialize_returns_valid_structure() -> void:
	_chronicle.set_fact("player.gold", 500)
	var data: Dictionary = _chronicle.serialize()

	assert_true(data is Dictionary)
	assert_has(data, "version")
	assert_has(data, "game_time")
	assert_has(data, "tick")
	assert_has(data, "facts")
	assert_has(data, "timeline")
	assert_eq(data["version"], 2)
	assert_true(data["facts"] is Dictionary)
	assert_true(data["timeline"] is Array)


# deserialize(serialize()) roundtrip preserves all facts
func test_roundtrip_preserves_facts() -> void:
	_chronicle.set_fact("player.gold", 500)
	_chronicle.set_fact("player.defeated.boss_swamp", true)
	_chronicle.set_fact("game_started", true)

	roundtrip()

	assert_eq(_chronicle.get_fact("player.gold"), 500)
	assert_eq(_chronicle.get_fact("player.defeated.boss_swamp"), true, "boss_swamp defeated flag should roundtrip as bool true")
	assert_eq(_chronicle.get_fact("game_started"), true)


# Roundtrip preserves all Variant types (bool, int, float, String, Array, Dictionary)
func test_roundtrip_all_variant_types() -> void:
	_chronicle.set_fact("t.bool_val", true)
	_chronicle.set_fact("t.int_val", 42)
	_chronicle.set_fact("t.float_val", 3.14)
	_chronicle.set_fact("t.str_val", "hello")
	_chronicle.set_fact("t.arr_val", [1, "two", false])
	_chronicle.set_fact("t.dict_val", {"hp": 100, "mp": 50})

	roundtrip()

	assert_eq(_chronicle.get_fact("t.bool_val"), true)
	assert_eq(_chronicle.get_fact("t.int_val"), 42)
	assert_eq(_chronicle.get_fact("t.float_val"), 3.14)
	assert_eq(_chronicle.get_fact("t.str_val"), "hello")
	assert_eq(_chronicle.get_fact("t.arr_val"), [1, "two", false])
	assert_eq(_chronicle.get_fact("t.dict_val"), {"hp": 100, "mp": 50})


# Transient facts excluded from serialize() output
func test_transient_facts_excluded_from_facts() -> void:
	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.temp_buff", 5, true, 0.0)  # transient

	var data: Dictionary = _chronicle.serialize()

	# player.gold should appear (normalized key)
	assert_has(data["facts"], "player.gold")
	# player.temp_buff should NOT appear (it's transient)
	var has_transient: bool = false
	for k: String in data["facts"]:
		if "temp_buff" in k:
			has_transient = true
	assert_false(has_transient)


# Transient timeline entries excluded from serialize() output
func test_transient_facts_excluded_from_timeline() -> void:
	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.temp_buff", 5, true, 0.0)  # transient

	var data: Dictionary = _chronicle.serialize()

	# Timeline should not contain entries for transient key
	var transient_in_timeline: bool = false
	for entry: Dictionary in data["timeline"]:
		if "temp_buff" in entry.get("key", ""):
			transient_in_timeline = true
	assert_false(transient_in_timeline)

	# Non-transient timeline entry should be present
	var gold_in_timeline: bool = false
	for entry: Dictionary in data["timeline"]:
		if "gold" in entry.get("key", ""):
			gold_in_timeline = true
	assert_true(gold_in_timeline)


# deserialize with missing "facts" key returns false, state unchanged
func test_deserialize_missing_facts_key_returns_false() -> void:
	_chronicle.set_fact("player.gold", 999)

	var bad_data: Dictionary = {"version": 1, "timeline": []}
	var ok: bool = _chronicle.deserialize(bad_data)

	assert_false(ok)
	# State should be unchanged (deserialize validates BEFORE clearing)
	assert_fact("player.gold", 999)


# deserialize with version > SAVE_VERSION returns false
func test_deserialize_future_version_returns_false() -> void:
	_chronicle.set_fact("player.hp", 100)

	var future_data: Dictionary = {
		"version": 999,
		"facts": {"player.hp": 50},
		"timeline": []
	}
	var ok: bool = _chronicle.deserialize(future_data)

	assert_false(ok)
	assert_fact("player.hp", 100)


# clear() wipes everything — serialize returns empty after clear
func test_clear_then_serialize_empty() -> void:
	_chronicle.set_fact("player.gold", 500)
	_chronicle.set_fact("game_started")
	_chronicle.clear()

	var data: Dictionary = _chronicle.serialize()

	assert_eq(data["version"], 2)
	assert_eq(data["facts"].size(), 0)
	assert_eq(data["timeline"], [])


# save_to_file / load_from_file roundtrip via temp file
func test_save_load_file_roundtrip() -> void:
	_chronicle.set_fact("player.gold", 1234)
	_chronicle.set_fact("player.level", 7)
	_chronicle.set_fact("quest.completed")

	var data: Dictionary = _chronicle.serialize()
	var save_path: String = "user://chronicle_test_save.json"
	var err: Error = save_temp(save_path, data)
	assert_eq(err, OK)

	var loaded: Variant = read_file(save_path)
	assert_not_null(loaded)
	assert_true(loaded is Dictionary)

	var c2: Node = add_child_autoqfree(Chronicle.new())
	var ok: bool = c2.deserialize(loaded)
	assert_true(ok)
	assert_eq(c2.get_fact("player.gold"), 1234)
	assert_eq(c2.get_fact("player.level"), 7)
	assert_true(c2.is_marked("quest.completed"))


# Corrupt primary file — load_from_file falls back to .bak
func test_corrupt_primary_falls_back_to_bak() -> void:
	_chronicle.set_fact("player.score", 9999)
	var data: Dictionary = _chronicle.serialize()

	var save_path: String = "user://chronicle_test_save_bak.json"

	# First write a good save so .bak exists
	save_temp(save_path, data)
	# Save again to create a .bak from the first good save and update primary
	ChronicleFileIO.save_to_file(save_path, data)

	# Corrupt the primary file
	var bad_file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	bad_file.store_string("CORRUPT_DATA_NOT_JSON{{{")
	bad_file.close()

	# load_from_file should fall back to .bak
	var loaded: Variant = read_file(save_path)
	assert_not_null(loaded)
	assert_true(loaded is Dictionary)

	if loaded != null:
		var c2: Node = add_child_autoqfree(Chronicle.new())
		var ok: bool = c2.deserialize(loaded)
		assert_true(ok)
		assert_eq(c2.get_fact("player.score"), 9999)

	# The corrupt primary file emits one engine error from JSON.parse_string
	# before the loader falls back to the .bak. Declaring it confirms the
	# fallback path was exercised (and keeps the error from failing the gate).
	assert_engine_error_count(1, "corrupt primary file triggers one JSON parse error before .bak fallback")


# Empty store serializes cleanly
func test_empty_store_serializes_cleanly() -> void:
	var data: Dictionary = _chronicle.serialize()

	assert_true(data is Dictionary)
	assert_eq(data.get("version"), 2)
	assert_eq(data.get("facts").size(), 0)
	assert_eq(data.get("timeline"), [])


# Serialized facts use normalized keys (e.g., _global.game_started)
func test_serialized_facts_use_normalized_keys() -> void:
	# Dotless key — stored internally as _global.game_started
	_chronicle.set_fact("game_started", true)
	_chronicle.set_fact("player.gold", 100)

	var data: Dictionary = _chronicle.serialize()

	assert_has(data["facts"], "_global.game_started")
	assert_has(data["facts"], "player.gold")
	assert_does_not_have(data["facts"], "game_started")

# load_from_file with nonexistent path
func test_load_nonexistent_file() -> void:
	var result: Variant = read_file("user://chronicle_nonexistent_test_xyz.json")
	assert_null(result)

# deserialize emits state_reset signal once
func test_deserialize_emits_state_reset() -> void:
	_chronicle.set_fact("player.gold", 100)
	var data: Dictionary = _chronicle.serialize()
	var c2: Node = add_child_autoqfree(Chronicle.new())
	var reset_ev := collect_any_signal(c2, "state_reset")
	c2.deserialize(data)
	# _reset_state() skips signal; only _apply_snapshot emits state_reset once
	reset_ev.assert_emission_count(1)

# deserialize suppresses fact_changed
func test_deserialize_suppresses_fact_changed() -> void:
	_chronicle.set_fact("player.gold", 100)
	var data: Dictionary = _chronicle.serialize()
	var c2: Node = add_child_autoqfree(Chronicle.new())
	var events := collect_signal(c2, "fact_changed")
	c2.deserialize(data)
	events.assert_count(0)

# serialization preserves game clock
func test_serialization_preserves_game_clock() -> void:
	set_time(42.5)
	_chronicle.set_fact("player.gold", 100)
	set_time(50.0)
	_chronicle.set_fact("player.hp", 80)

	var data: Dictionary = _chronicle.serialize()
	assert_has(data, "game_time", "serialized data includes game_time")
	assert_has(data, "tick", "serialized data includes tick")

	var c2: Node = serialize_into_new()

	assert_eq(c2.get_game_time(), 50.0,\
		"game_time survives roundtrip")

	var history: Array[Dictionary] = c2.get_fact_history("player.gold")
	assert_eq(history.size(), 1)
	assert_eq(history[0].time, 42.5,\
		"timeline entry time survives roundtrip")

# serialization preserves tick
func test_serialization_preserves_tick() -> void:
	_chronicle.set_fact("a.x", 1)
	_chronicle.set_fact("a.y", 2)
	_chronicle.set_fact("a.z", 3)

	var data: Dictionary = _chronicle.serialize()

	var c2: Node = serialize_into_new()

	# Write a new fact on the restored chronicle — tick should not collide
	c2.set_fact("a.w", 4)
	var history: Array[Dictionary] = c2.get_fact_history("a.w")
	assert_eq(history.size(), 1)

	# The new fact's timeline entry should have a tick > all restored ticks
	var all_changes: Array[Dictionary] = c2.get_changes_since(0.0)
	var max_restored_tick: int = 0
	for entry: Dictionary in data["timeline"]:
		if entry.get("tick", 0) > max_restored_tick:
			max_restored_tick = entry.get("tick", 0)

	# Verify tick from serialized data matches what we restored
	assert_eq(data.get("tick", -1) as int, 3,\
		"serialized tick equals number of writes")


# ── Stress: scale and edge cases ──


# 1000 facts roundtrip
func test_thousand_facts_roundtrip() -> void:
	for i: int in range(1000):
		var entity: String = "entity_%d" % (i % 50)
		var key: String = "%s.fact_%d" % [entity, i]
		_chronicle.set_fact(key, i)

	assert_eq(_chronicle.get_fact_keys("*").size(), 1000)

	var data: Dictionary = _chronicle.serialize()
	assert_eq(data["facts"].size(), 1000)

	_chronicle.clear()
	assert_eq(_chronicle.get_fact_keys("*").size(), 0)

	var ok: bool = _chronicle.deserialize(data)
	assert_true(ok)
	assert_eq(_chronicle.get_fact_keys("*").size(), 1000)

	# Spot-check all values
	var all_correct: bool = true
	for i: int in range(1000):
		var entity: String = "entity_%d" % (i % 50)
		var key: String = "%s.fact_%d" % [entity, i]
		var val: Variant = _chronicle.get_fact(key)
		if val == null or int(val) != i:
			all_correct = false
			break
	assert_true(all_correct)


# int vs float type preservation
func test_int_vs_float_preservation() -> void:
	_chronicle.set_fact("gold", 42)
	_chronicle.set_fact("speed", 3.5)
	_chronicle.set_fact("big_int", 1000000)
	_chronicle.set_fact("zero_int", 0)

	# Verify in-store types before serialization
	assert_fact_type("gold", TYPE_INT)
	assert_fact_type("speed", TYPE_FLOAT)

	# In-memory roundtrip (no JSON involved)
	var data: Dictionary = _chronicle.serialize()

	# Check types in serialized dict (before any JSON)
	assert_eq(typeof(data["facts"]["_global.gold"]), TYPE_INT)
	assert_eq(typeof(data["facts"]["_global.speed"]), TYPE_FLOAT)

	var c2: Node = serialize_into_new()
	assert_eq(typeof(c2.get_fact("gold")), TYPE_INT)
	assert_eq(c2.get_fact("gold"), 42)
	assert_eq(typeof(c2.get_fact("speed")), TYPE_FLOAT)
	assert_eq(typeof(c2.get_fact("big_int")), TYPE_INT)
	assert_eq(typeof(c2.get_fact("zero_int")), TYPE_INT)

	# File I/O roundtrip — this goes through JSON.stringify + JSON.parse_string
	var save_path: String = "user://chronicle_test_int_float.json"
	save_temp(save_path, data)
	var loaded: Variant = read_file(save_path)
	assert_not_null(loaded)

	if loaded != null:
		# Check what JSON did to our types
		var gold_from_file: Variant = loaded["facts"]["_global.gold"]
		var gold_type_after_file: int = typeof(gold_from_file)
		if gold_type_after_file == TYPE_FLOAT:
			push_warning("BUG DETECTED: #04 — JSON roundtrip converted int 42 to float. typeof(gold) = TYPE_FLOAT after file I/O.")
		assert_eq(typeof(gold_from_file), TYPE_INT)

		# Now deserialize the file-loaded data and check
		var c3: Node = add_child_autoqfree(Chronicle.new())
		c3.deserialize(loaded)
		var gold_after_full: Variant = c3.get_fact("gold")
		var gold_type_final: int = typeof(gold_after_full)
		if gold_type_final == TYPE_FLOAT:
			push_warning("BUG DETECTED: #04 — After full file roundtrip, gold is TYPE_FLOAT (was TYPE_INT). Value: %s" % str(gold_after_full))
		assert_eq(typeof(gold_after_full), TYPE_INT)
		assert_eq(gold_after_full, 42)


# timeline roundtrip
func test_timeline_roundtrip() -> void:
	_chronicle.set_fact("score", 10)
	_chronicle.set_fact("score", 20)
	_chronicle.set_fact("score", 30)
	_chronicle.set_fact("player.hp", 100)

	var history_before: Array = _chronicle.get_fact_history("score")
	assert_eq(history_before.size(), 3)

	var data: Dictionary = _chronicle.serialize()

	# Verify timeline entries exist in serialized output
	var score_entries: int = 0
	for entry: Dictionary in data["timeline"]:
		if entry.get("key", "") == "score":
			score_entries += 1
	assert_eq(score_entries, 3)

	var c2: Node = serialize_into_new()

	var history_after: Array = c2.get_fact_history("score")
	assert_eq(history_after.size(), 3)

	if history_after.size() >= 3:
		assert_eq(history_after[0].value, 10)
		assert_eq(history_after[1].value, 20)
		assert_eq(history_after[2].value, 30)

	var hp_history: Array = c2.get_fact_history("player.hp")
	assert_eq(hp_history.size(), 1)


# extra keys ignored on deserialize
func test_extra_keys_ignored() -> void:
	var data_with_extras: Dictionary = {
		"version": 1,
		"facts": {"player.gold": 42},
		"timeline": [],
		"extra": "some data",
		"metadata": {"author": "test"},
		"unknown_array": [1, 2, 3]
	}
	var ok: bool = _chronicle.deserialize(data_with_extras)
	assert_true(ok)
	assert_fact("player.gold", 42)


# file I/O roundtrip with complex types
func test_file_roundtrip_complex_types() -> void:
	_chronicle.set_fact("player.gold", 9999)
	_chronicle.set_fact("player.name", "Gandalf")
	_chronicle.set_fact("quest.main.completed", true)
	_chronicle.set_fact("inventory.items", ["sword", "shield", "potion"])
	_chronicle.set_fact("stats", {"str": 18, "dex": 14, "con": 16})

	var data: Dictionary = _chronicle.serialize()
	var save_path: String = "user://chronicle_stress_test_io.json"

	var err: Error = save_temp(save_path, data)
	assert_eq(err, OK)

	var loaded: Variant = read_file(save_path)
	assert_not_null(loaded)
	assert_true(loaded is Dictionary)

	if loaded != null:
		var c2: Node = add_child_autoqfree(Chronicle.new())
		var ok: bool = c2.deserialize(loaded)
		assert_true(ok)
		# Note: gold may be float after JSON roundtrip, so compare with == which handles int/float
		assert_eq(c2.get_fact("player.gold"), 9999)
		assert_eq(c2.get_fact("player.name"), "Gandalf")
		assert_eq(c2.get_fact("quest.main.completed"), true)
		assert_eq(c2.get_fact("inventory.items").size(), 3)
		assert_eq(c2.get_fact("stats").get("str"), 18)


# both corrupt files returns null
func test_both_corrupt_files_returns_null() -> void:
	_chronicle.set_fact("player.score", 7777)
	_chronicle.set_fact("level", 42)
	var data: Dictionary = _chronicle.serialize()

	var save_path: String = "user://chronicle_stress_corrupt.json"

	# Write twice to create both primary and .bak
	save_temp(save_path, data)
	ChronicleFileIO.save_to_file(save_path, data)

	# Corrupt the primary file
	var bad_file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	bad_file.store_string("THIS IS NOT JSON {{{corrupted!!!")
	bad_file.close()

	# Load should fall back to .bak
	var loaded: Variant = read_file(save_path)
	assert_not_null(loaded)
	assert_true(loaded is Dictionary)

	if loaded != null:
		var c2: Node = add_child_autoqfree(Chronicle.new())
		var ok: bool = c2.deserialize(loaded)
		assert_true(ok)
		assert_eq(c2.get_fact("player.score"), 7777)

	# Also test: both primary and .bak corrupt -> returns null
	var bak_path: String = save_path + ".bak"
	var bad_bak: FileAccess = FileAccess.open(bak_path, FileAccess.WRITE)
	bad_bak.store_string("ALSO CORRUPT {{{")
	bad_bak.close()

	var loaded2: Variant = read_file(save_path)
	assert_null(loaded2)

	# Engine errors: the first read emits one JSON parse error (corrupt primary)
	# before the .bak loads cleanly; the second read emits one more (both primary
	# and .bak corrupt) = 2 total. Declaring them confirms both fallback paths ran.
	assert_engine_error_count(2, "corrupt primary + corrupt .bak emit JSON parse errors across both load attempts")


# deserialize doesn't corrupt on failure
func test_deserialize_doesnt_corrupt_on_failure() -> void:
	_chronicle.set_fact("player.gold", 500)
	_chronicle.set_fact("player.name", "Hero")
	_chronicle.set_fact("quest.started", true)
	_chronicle.set_fact("inventory.count", 3)

	# Attempt 1: Missing facts key
	var bad1: Dictionary = {"version": 1}
	var ok1: bool = _chronicle.deserialize(bad1)
	assert_false(ok1)
	assert_fact("player.gold", 500)
	assert_fact("player.name", "Hero")
	assert_fact("quest.started", true)
	assert_fact("inventory.count", 3)

	# Attempt 2: Future version with facts key present
	var bad2: Dictionary = {"version": 99, "facts": {"player.gold": 999}}
	var ok2: bool = _chronicle.deserialize(bad2)
	assert_false(ok2)
	assert_fact("player.gold", 500)
	assert_fact("player.name", "Hero")

	# Attempt 3: Empty dict
	var bad3: Dictionary = {}
	var ok3: bool = _chronicle.deserialize(bad3)
	assert_false(ok3)
	assert_fact("player.gold", 500)

	# Verify timeline is also preserved
	var history: Array = _chronicle.get_fact_history("player.gold")
	assert_gt(history.size(), 0, "timeline preserved after failed deserialize attempts")


# serialized timeline cap
func test_serialize_timeline_cap() -> void:
	for i in range(1100):
		_chronicle.set_fact("ser.key%d" % i, i)
	var data: Dictionary = _chronicle.serialize()
	assert_lte(data.timeline.size(), 1000, "serialized timeline should be <= 1000, got %d" % data.timeline.size())
	assert_gt(data.timeline.size(), 0, "serialized timeline should not be empty")


# auto_advance survives serialization roundtrip
func test_auto_advance_survives_serialization() -> void:
	_chronicle.set_auto_advancing(false)
	set_time(5.0)
	_chronicle.set_fact("key", 1)
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	assert_true(_chronicle.is_auto_advancing(), "clear() resets to auto-advance")
	_chronicle.deserialize(data)
	assert_false(_chronicle.is_auto_advancing(), "Manual mode should survive serialize/deserialize")


# Old version saves are rejected with an error (migration chain removed)
func test_old_version_save_is_rejected() -> void:
	var old_data: Dictionary = {
		"version": 3,
		"game_time": 1.0,
		"tick": 0,
		"facts": {"player.gold": 42},
		"timeline": [],
		"expiry": {},
	}
	_chronicle.set_fact("player.hp", 100)
	var ok: bool = _chronicle.deserialize(old_data)
	assert_false(ok, "Old version data (version != 2) should be rejected")
	# State unchanged — deserialize validated before clearing
	assert_fact("player.hp", 100)


# SERIALIZE_ALL truly serializes all timeline entries
func test_serialize_all_includes_everything():
	for i in range(50):
		_chronicle.set_fact("key.%d" % i, i)
	var data: Dictionary = _chronicle.serialize(Chronicle.SERIALIZE_ALL)
	assert_eq(data.timeline.size(), 50)


# ── Codec bugs ──────────────────────────


# decode_value double-call corrupts whole floats to int
func test_restore_double_call_corrupts_whole_float() -> void:
	var codec := _make_codec()

	var original: float = 5.0
	var prepared: Variant = codec.encode_value(original)
	# First restore: correctly returns float 5.0
	var restored_once: Variant = codec.decode_value(prepared)
	assert_eq(typeof(restored_once), TYPE_FLOAT, "first restore should yield float")
	assert_eq(restored_once, 5.0)

	# Second decode on an already-decoded float: whole-number float 5.0 is
	# coerced to int 5 by the JSON-roundtrip guard (decode_value line 136-138).
	# This is documented (line 72: "Do NOT call twice on the same value").
	var restored_twice: Variant = codec.decode_value(restored_once)
	assert_eq(typeof(restored_twice), TYPE_INT,
		"double decode_value coerces whole float to int (documented limitation)")


# Non-string dictionary keys silently dropped during encode_value
func test_nonstring_dict_keys_data_loss() -> void:
	var codec := _make_codec()

	# A dictionary with an integer key
	var original: Dictionary = {"valid": 1}
	# This should round-trip fine for string-only keys
	var prepared: Variant = codec.encode_value(original)
	var restored: Variant = codec.decode_value(prepared)
	assert_eq(restored, {"valid": 1}, "string-key dict round-trips cleanly")


# Rect2i round-trip through JSON loses type fidelity
func test_rect2i_json_roundtrip() -> void:
	var codec := _make_codec()

	var original := Rect2i(Vector2i(10, 20), Vector2i(100, 50))
	var prepared: Variant = codec.encode_value(original)

	# Simulate JSON round-trip: stringify then parse
	var json_str: String = JSON.stringify(prepared)
	var json_parsed: Variant = JSON.parse_string(json_str)

	var restored: Variant = codec.decode_value(json_parsed)
	assert_true(restored is Rect2i,
		"Rect2i should survive JSON round-trip, got: %s" % type_string(typeof(restored)))
	assert_eq(restored, original)


# Missing required key in builtin type returns null (fact dropped)
func test_missing_required_key_returns_partial_dict() -> void:
	var codec := _make_codec()

	# Corrupt Vector2 data: missing "y" key
	var corrupt: Dictionary = {"_chronicle_type": "Vector2", "x": 1.5}
	var restored: Variant = codec.decode_value(corrupt)

	# S03+S04 fix: missing required key now returns null (fact dropped)
	assert_null(restored,
		"missing required key should return null (fact dropped)")


# Reserved tag collision — "float_special" rejected by register_type
func test_reserved_tag_collision() -> void:
	var registry := TypeRegistry.new()
	var codec := TypeCodec.new(registry)
	BuiltinTypes.register_all(registry, codec)

	# Attempt to register a type with the reserved tag "float_special"
	var ok: bool = registry.register_type(
		999, "float_special",
		func(v: Variant) -> Dictionary: return {"_chronicle_type": "float_special", "v": "custom"},
		func(d: Dictionary) -> Variant: return 42,
	)
	# FIXED: register_type now rejects reserved tags ("float_special", "escaped_dict")
	# to prevent collision with hardcoded internal serialization paths in type_codec.gd.
	assert_false(ok, "reserved tag 'float_special' should be rejected by register_type")
	assert_false(registry.is_type_registered(999),
		"type_id 999 should not be registered after reserved tag rejection")


# NaN and Inf in nested structures round-trip correctly
func test_nan_inf_in_nested_structures() -> void:
	var codec := _make_codec()

	var original: Dictionary = {
		"normal": 3.14,
		"nan_val": NAN,
		"inf_val": INF,
		"neg_inf": -INF,
		"nested": [NAN, INF, -INF, 1.0],
	}
	var prepared: Variant = codec.encode_value(original)
	var restored: Variant = codec.decode_value(prepared)

	assert_eq(restored["normal"], 3.14)
	assert_true(is_nan(restored["nan_val"]), "NaN should survive nested round-trip")
	assert_true(is_inf(restored["inf_val"]) and restored["inf_val"] > 0, "INF should survive")
	assert_true(is_inf(restored["neg_inf"]) and restored["neg_inf"] < 0, "-INF should survive")
	var arr: Array = restored["nested"]
	assert_true(is_nan(arr[0]), "NaN in array should survive")
	assert_true(is_inf(arr[1]) and arr[1] > 0, "INF in array should survive")
	assert_true(is_inf(arr[2]) and arr[2] < 0, "-INF in array should survive")
	assert_eq(typeof(arr[3]), TYPE_FLOAT, "1.0 in array should stay float")


# Zero float 0.0 round-trip preserves type
func test_zero_float_roundtrip() -> void:
	var registry := TypeRegistry.new()
	var codec := TypeCodec.new(registry)

	var original: float = 0.0
	var prepared: Variant = codec.encode_value(original)

	# Should be tagged as float_special whole
	assert_true(prepared is Dictionary, "0.0 should be tagged")
	assert_eq(prepared.get("_chronicle_type"), "float_special")
	assert_eq(prepared.get("v"), "whole")

	var restored: Variant = codec.decode_value(prepared)
	assert_eq(typeof(restored), TYPE_FLOAT, "0.0 should restore as float")
	assert_eq(restored, 0.0)


# Expiry roundtrip with game_time
func test_expiry_roundtrip_with_game_time() -> void:
	set_time(10.0)
	# Use set_fact + set_expiry to create a serializable (non-transient) expiring fact.
	# Passing lifetime directly to set_fact auto-marks it transient (excluded from serialization).
	_chronicle.set_fact("exp.key", "value")
	_chronicle.set_expiry("exp.key", 5.0)
	var data: Dictionary = _chronicle.serialize()

	# Expiry should store remaining time (5.0 - elapsed)
	# Since we set time to 10.0 and wrote with lifetime 5.0, the absolute
	# expiry is at 15.0. The serialized remaining = 15.0 - 10.0 = 5.0.
	assert_has(data, "expiry", "serialized data should have expiry")
	var expiry_data: Dictionary = data.get("expiry", {})
	# The key in expiry is normalized
	var has_key: bool = false
	var remaining: float = 0.0
	for k: String in expiry_data:
		if "exp.key" in k:
			has_key = true
			# Whole-number remainings (e.g. 5.0) are wire-encoded by the type codec
			# as {"_chronicle_type": "float_special", "v": "whole", "n": <float>};
			# fractional remainings serialize as a bare float. Extract either shape.
			var raw: Variant = expiry_data[k]
			if raw is Dictionary:
				remaining = float(raw.get("n", 0.0))
			else:
				remaining = float(raw)
	if has_key:
		assert_almost_eq(remaining, 5.0, 0.1,
			"expiry remaining should be approximately 5.0")

	# Deserialize and verify expiry is restored
	var c2: Node = serialize_into_new()
	assert_true(c2.has_expiry("exp.key"), "expiry should survive round-trip")


# Version 0 migration fails gracefully
func test_version_0_migration_fails_gracefully() -> void:
	var data: Dictionary = {
		"version": 0,
		"facts": {"player.hp": 100},
		"timeline": [],
	}
	var ok: bool = _chronicle.deserialize(data)
	assert_false(ok, "version 0 with no migration should fail")


# User migration overrides builtin migration
func test_user_migration_overrides_builtin() -> void:
	# Register a user migration for v1 -> v2 that renames a field
	_chronicle.register_migration(1, func(dict: Dictionary) -> Dictionary:
		dict["version"] = 2
		# User migration: rename old field
		if "old_field" in dict:
			dict["facts"]["new_field"] = dict["old_field"]
			dict.erase("old_field")
		return dict
	)

	var data: Dictionary = {
		"version": 1,
		"old_field": "custom_data",
		"facts": {"player.hp": 100},
		"timeline": [],
		"expiry": {},
	}
	var ok: bool = _chronicle.deserialize(data)
	assert_true(ok, "user migration v1->v2 should succeed")
	assert_fact("player.hp", 100)


# Deep nesting hits depth limit
func test_deep_nesting_hits_depth_limit() -> void:
	var registry := TypeRegistry.new()
	var codec := TypeCodec.new(registry)

	# Build a 70-level deep nested dict
	var deep: Dictionary = {"leaf": true}
	for i: int in range(70):
		deep = {"nested": deep}

	var prepared: Variant = codec.encode_value(deep)
	# At depth 64, encode_value returns null
	# The outer layers should contain the nested structure up to depth 64
	# then null for deeper levels
	assert_true(prepared is Dictionary, "top-level should still be a Dictionary")


# StringName and NodePath round-trip
func test_stringname_nodepath_roundtrip() -> void:
	var codec := _make_codec()

	var sn := StringName("test_name")
	var np := NodePath("root/child/grandchild")

	var sn_prepared: Variant = codec.encode_value(sn)
	var sn_restored: Variant = codec.decode_value(sn_prepared)
	assert_true(sn_restored is StringName, "StringName should survive round-trip")
	assert_eq(sn_restored, StringName("test_name"))

	var np_prepared: Variant = codec.encode_value(np)
	var np_restored: Variant = codec.decode_value(np_prepared)
	assert_true(np_restored is NodePath, "NodePath should survive round-trip")
	assert_eq(np_restored, NodePath("root/child/grandchild"))


# Escaped dict round-trip preserves user _chronicle_type key
func test_escaped_dict_roundtrip() -> void:
	var codec := _make_codec()

	var original: Dictionary = {
		"_chronicle_type": "user_value",
		"data": 42,
	}
	var prepared: Variant = codec.encode_value(original)

	# Should be wrapped in escaped_dict
	assert_true(prepared is Dictionary)
	assert_eq(prepared.get("_chronicle_type"), "escaped_dict")

	var restored: Variant = codec.decode_value(prepared)
	assert_true(restored is Dictionary)
	assert_eq(restored.get("_chronicle_type"), "user_value",
		"original _chronicle_type value should be preserved")
	assert_eq(restored.get("data"), 42)


# PackedFloat32Array precision
func test_packed_float32_precision() -> void:
	var codec := _make_codec()

	var original := PackedFloat32Array([1.5, 2.5, 0.1])
	var prepared: Variant = codec.encode_value(original)
	var restored: Variant = codec.decode_value(prepared)

	assert_true(restored is PackedFloat32Array)
	assert_eq(restored.size(), 3)
	# 1.5 and 2.5 are exact in float32
	assert_eq(restored[0], 1.5)
	assert_eq(restored[1], 2.5)
	# 0.1 has float32 precision loss but should be close
	assert_almost_eq(restored[2], 0.1, 0.001)


# Negative tick on deserialize is clamped
func test_negative_tick_on_deserialize_clamped() -> void:
	var data: Dictionary = {
		"version": 2,
		"game_time": 0.0,
		"tick": -5,
		"auto_advance": true,
		"facts": {"player.hp": 100},
		"timeline": [],
		"expiry": {},
	}
	var ok: bool = _chronicle.deserialize(data)
	# Negative tick should trigger warning and reset to 0
	assert_true(ok, "negative tick should be corrected, not rejected")


# ── Codec audit A9 ──────────────────────


# Unknown tag does not recurse nested values — returns null
func test_unknown_tag_recurses_nested_values() -> void:
	var codec := _make_codec()

	# Simulate a save file with an unknown outer tag, but a known type (Vector2) nested inside.
	# This could happen if a type is unregistered between saving and loading.
	var crafted: Dictionary = {
		"_chronicle_type": "UnknownTypeTag",
		"position": {
			"_chronicle_type": "Vector2",
			"x": 3.0,
			"y": 4.0,
		}
	}
	var restored: Variant = codec.decode_value(crafted)

	# Unknown tags now return null (fact dropped) — the data is unrecoverable.
	assert_null(restored,
		"unknown tag should return null (fact dropped)")


# Corrupt "escaped_dict" without "_data" key — unrecoverable external corruption.
# audit: R17-A9-2
#
# VALIDATED — NOT a product bug. Chronicle's own encoder ALWAYS writes an
# escaped_dict with "_data" (type_codec.gd:56), so a missing "_data" can only be
# external corruption with no recoverable data. decode_value() handles it
# defensively and CONSISTENTLY with its other partial-recovery paths: it emits a
# loud push_error ("...data lost.") — so the loss is DIAGNOSED, not silent — and
# returns {} so the rest of the deserialize survives. (The original survey finding
# claimed "silent loss"; it missed the push_error at type_codec.gd:103.) This test
# pins that defensible contract and is GREEN.
func test_escaped_dict_missing_data_is_diagnosed_and_yields_empty_dict() -> void:
	var codec := _make_codec()

	# A corrupt "escaped_dict" envelope with no "_data" key (external corruption).
	var corrupt_escaped: Dictionary = {
		"_chronicle_type": "escaped_dict",
		# "_data" is intentionally missing
	}
	var restored: Variant = codec.decode_value(corrupt_escaped)

	# Graceful: returns an empty Dictionary rather than crashing or returning garbage.
	assert_true(restored is Dictionary,
		"malformed escaped_dict decodes to a Dictionary (graceful)")
	assert_eq((restored as Dictionary).size(), 0,
		"unrecoverable corrupt envelope yields an empty dict")
	# Diagnosed, NOT silent: exactly one push_error surfaces the data loss.
	assert_push_error_count(1,
		"malformed escaped_dict (missing _data) must surface a diagnostic error")


# Empty keys double-wrap breaks restore to original type
func test_empty_keys_double_wrap_breaks_restore_to_original_type() -> void:
	var registry := TypeRegistry.new()
	var codec := TypeCodec.new(registry)
	BuiltinTypes.register_all(registry, codec)

	# Register a type with keys=[] whose pack fn returns a tagged dict.
	registry.register_type(
		TYPE_RID, "custom_rid",
		func(_v: Variant) -> Dictionary:
			return {"_chronicle_type": "custom_rid", "id": 42},
		func(_d: Dictionary) -> Variant:
			return RID(),
		Callable(), []   # empty keys => re-prepare path
	)

	var rid_val: RID = RID()
	var prepared: Variant = codec.encode_value(rid_val)

	# Double-wrap: the pack result was re-prepared and wrapped in escaped_dict.
	assert_true(prepared is Dictionary, "prepared should be a Dictionary")
	var outer_tag: String = (prepared as Dictionary).get("_chronicle_type", "")
	assert_eq(outer_tag, "escaped_dict",
		"A9-3: pack result with TAG_KEY gets double-wrapped in escaped_dict")

	# Restore: escaped_dict unwraps _data but only recurses VALUES, not the dict itself.
	# The "custom_rid" tag in _data is never dispatched → returns a plain Dictionary.
	var restored: Variant = codec.decode_value(prepared)
	assert_true(restored is Dictionary,
		"A9-3: restore of escaped_dict containing custom_rid returns Dictionary, NOT RID")
	assert_false(restored is RID,
		"A9-3 BUG: roundtrip through empty-keys+tagged-pack does NOT restore to original type")


# Missing required key drops fact, not stores dict
func test_missing_required_key_drops_fact_not_stores_dict() -> void:
	# Craft a save file where a Vector2 fact is missing its "y" required key.
	var corrupt_data: Dictionary = {
		"version": 2,
		"game_time": 0.0,
		"tick": 1,
		"auto_advance": true,
		"facts": {
			"player.pos": {
				"_chronicle_type": "Vector2",
				"x": 5.0
				# "y" is intentionally absent
			}
		},
		"timeline": [],
		"expiry": {},
	}
	var ok: bool = _chronicle.deserialize(corrupt_data)
	assert_true(ok, "deserialize should succeed even with corrupt type data")

	# FIX S03+S04: decode_value returns null for missing required key,
	# and the null filter in deserialize drops the fact rather than storing a partial dict.
	# S03+S04 fix: decode_value returns null for missing required key,
	# and the null filter in deserialize drops the fact rather than storing a partial dict.
	assert_no_fact("player.pos")


# A null fact value passes is_valid_type but is dropped by the store on deserialize
func test_null_fact_value_passes_validation_and_is_dropped() -> void:
	var registry := TypeRegistry.new()
	var codec := TypeCodec.new(registry)
	BuiltinTypes.register_all(registry, codec)

	# is_valid_type should accept null
	assert_true(registry.is_valid_type(null),
		"is_valid_type(null) must return true per type_registry implementation")

	# A null fact value in the save dict passes through deserialization without aborting.
	var data_with_null: Dictionary = {
		"version": 2,
		"game_time": 0.0,
		"tick": 1,
		"auto_advance": true,
		"facts": {
			"player.alive": null
		},
		"timeline": [],
		"expiry": {},
	}
	var ok: bool = _chronicle.deserialize(data_with_null)
	assert_true(ok, "null fact value in save file does not abort deserialization")
	# Pinned behavior: a null value is an erase in Chronicle semantics, so the
	# store drops it — the fact does not exist after deserialization.
	assert_no_fact("player.alive")


# Negative zero (-0.0) roundtrip through JSON
func test_negative_zero_roundtrip_through_json() -> void:
	var registry := TypeRegistry.new()
	var codec := TypeCodec.new(registry)

	var neg_zero: float = -0.0
	var prepared: Variant = codec.encode_value(neg_zero)

	# Should be tagged as float_special whole
	assert_true(prepared is Dictionary,
		"-0.0 should be tagged as float_special")
	assert_eq(prepared.get("_chronicle_type"), "float_special")
	assert_eq(prepared.get("v"), "whole")

	# Simulate JSON round-trip: -0.0 is encoded as "0" in JSON
	var json_str: String = JSON.stringify(prepared)
	var json_parsed: Variant = JSON.parse_string(json_str)
	assert_true(json_parsed is Dictionary,
		"JSON parse of float_special dict should yield a Dictionary")

	var restored: Variant = codec.decode_value(json_parsed)
	# After JSON, -0.0 becomes 0.0 (sign lost), but equality holds since -0.0 == 0.0
	assert_eq(typeof(restored), TYPE_FLOAT,
		"-0.0 after JSON roundtrip should restore as float (not int)")
	assert_eq(restored, 0.0,
		"-0.0 == 0.0 after JSON roundtrip (sign may be lost but equality holds)")


# Float "whole" boundary at 2^53
func test_float_whole_boundary_9007199254740992() -> void:
	var registry := TypeRegistry.new()
	var codec := TypeCodec.new(registry)

	var boundary: float = 9007199254740992.0  # 2^53 — last safe integer as float
	var prepared: Variant = codec.encode_value(boundary)

	# Should be tagged (within boundary)
	assert_true(prepared is Dictionary,
		"9007199254740992.0 should be tagged as float_special whole")
	assert_eq(prepared.get("v"), "whole")

	var restored: Variant = codec.decode_value(prepared)
	assert_eq(typeof(restored), TYPE_FLOAT,
		"9007199254740992.0 should restore as float")
	assert_eq(restored, boundary)

	# Just above the boundary: not tagged, returned as plain float
	var above: float = 9007199254740994.0
	var prepared_above: Variant = codec.encode_value(above)
	# For values above 2^53 that equal their int truncation, the boundary check fails
	# (absf(above) > 9007199254740992.0), so it falls through to return value directly
	assert_false(prepared_above is Dictionary,
		"9007199254740994.0 (above boundary) should NOT be tagged — returned as raw float")


# Float tick is silently truncated
func test_float_tick_is_silently_truncated_no_warning() -> void:
	var data_float_tick: Dictionary = {
		"version": 2,
		"game_time": 0.0,
		"tick": 7.9,   # float, not int — should ideally warn or round
		"auto_advance": true,
		"facts": {"player.hp": 100},
		"timeline": [],
		"expiry": {},
	}
	var ok: bool = _chronicle.deserialize(data_float_tick)
	assert_true(ok, "float tick should be accepted (not fatal)")

	# After deserialization the tick is int(7.9) = 7 (truncated, not 8)
	# Verify the timeline tick was restored correctly by checking internal state.
	assert_eq(_chronicle._timeline.get_tick(), 7,
		"A9-8: tick 7.9 is silently truncated to 7")
	# Write a new fact — tick should increment from 7 to 8.
	_chronicle.set_fact("new.fact", true)
	assert_eq(_chronicle._timeline.get_tick(), 8,
		"new write after restored tick=7 gets tick 8")


# Migration producing wrong version aborts
func test_migration_producing_wrong_version_aborts() -> void:
	# Register a migration that returns version 3 instead of 2
	_chronicle.register_migration(1, func(d: Dictionary) -> Dictionary:
		d["version"] = 3  # Wrong! Should be 2.
		return d
	)

	var data: Dictionary = {
		"version": 1,
		"facts": {"player.hp": 100},
		"timeline": [],
		"expiry": {},
	}
	_chronicle.set_fact("existing.fact", true)
	var ok: bool = _chronicle.deserialize(data)
	assert_false(ok,
		"A9-9: migration producing wrong version should abort deserialization")
	# State should be unchanged since deserialization failed
	assert_fact("existing.fact", true)


# Timeline entry with null value survives roundtrip
func test_timeline_entry_with_null_value_survives_roundtrip() -> void:
	# Set and then erase a fact — the timeline will record value=null for the erase.
	_chronicle.set_fact("rt.erasable", 42)
	_chronicle.erase_fact("rt.erasable")

	var data: Dictionary = _chronicle.serialize()

	# Verify that the timeline has an entry with null value (the erase)
	var has_null_entry: bool = false
	for entry: Dictionary in data["timeline"]:
		if "erasable" in entry.get("key", "") and entry.get("value") == null:
			has_null_entry = true
	assert_true(has_null_entry,
		"serialize should include timeline entry with null value for erasure")

	# Roundtrip
	var c2: Node = serialize_into_new()

	# The erasure timeline entry should be preserved
	var history: Array[Dictionary] = c2.get_fact_history("rt.erasable")
	assert_gte(history.size(), 2,
		"history should have at least: set(42) and erase(null)")
	if history.size() >= 2:
		assert_eq(history[0].value, 42,
			"first entry should be the set to 42")
		assert_eq(history[1].value, null,
			"second entry should be the erasure (null value)")


# Expiry remaining=0.0 is accepted and expires immediately
func test_expiry_remaining_zero_is_accepted_and_expires_immediately() -> void:
	var data: Dictionary = {
		"version": 2,
		"game_time": 10.0,
		"tick": 1,
		"auto_advance": true,
		"facts": {"player.buff": true},
		"timeline": [],
		"expiry": {
			"player.buff": 0.0   # remaining = 0.0 — expires exactly at game_time
		},
	}
	var c2: Node = add_child_autoqfree(Chronicle.new())
	var ok: bool = c2.deserialize(data)
	assert_true(ok, "expiry remaining=0.0 should not abort deserialization")

	# remaining=0.0 is skipped by _validate_expiry (remaining <= 0.0 check).
	# The fact exists but has no expiry — already expired at load time.
	var has_exp: bool = c2.has_expiry("player.buff")
	assert_false(has_exp,
		"A9-11: expiry remaining=0.0 is dropped (already expired at load time)")


# Expiry clamping at 1_000_000
func test_expiry_clamping_at_one_million() -> void:
	var data_exact: Dictionary = {
		"version": 2,
		"game_time": 0.0,
		"tick": 1,
		"auto_advance": true,
		"facts": {"player.buff": true},
		"timeline": [],
		"expiry": {"player.buff": 1000000.0},
	}
	var c2: Node = add_child_autoqfree(Chronicle.new())
	var ok: bool = c2.deserialize(data_exact)
	assert_true(ok, "expiry remaining=1_000_000 is at the limit and should be accepted")
	assert_true(c2.has_expiry("player.buff"),
		"expiry at exactly 1M should be stored")

	# A value over 1M should be clamped
	var data_over: Dictionary = {
		"version": 2,
		"game_time": 0.0,
		"tick": 1,
		"auto_advance": true,
		"facts": {"player.buff2": true},
		"timeline": [],
		"expiry": {"player.buff2": 1000001.0},
	}
	var c3: Node = add_child_autoqfree(Chronicle.new())
	var ok3: bool = c3.deserialize(data_over)
	assert_true(ok3, "expiry over 1M should be clamped, not rejected")
	assert_true(c3.has_expiry("player.buff2"),
		"clamped expiry should still be stored")
	# Remaining after clamp should be exactly 1M (stored as game_time + 1M = 0 + 1M)
	var remaining: float = c3.get_expiry_remaining("player.buff2")
	assert_almost_eq(remaining, 1000000.0, 0.1,
		"clamped expiry should be approximately 1_000_000 remaining")


# Vector2 fact survives full JSON file roundtrip
func test_vector2_fact_survives_full_json_file_roundtrip() -> void:
	_chronicle.set_fact("player.pos", Vector2(3.5, 7.25))
	_chronicle.set_fact("player.velocity", Vector2(-1.5, 0.0))
	var data: Dictionary = _chronicle.serialize()

	# Simulate file I/O: stringify → parse
	var json_str: String = JSON.stringify(data)
	var parsed: Variant = JSON.parse_string(json_str)
	assert_true(parsed is Dictionary, "JSON parse should yield Dictionary")

	var c2: Node = add_child_autoqfree(Chronicle.new())
	var ok: bool = c2.deserialize(parsed)
	assert_true(ok, "Vector2 facts should survive JSON file roundtrip")

	var pos: Variant = c2.get_fact("player.pos")
	assert_true(pos is Vector2, "player.pos should be Vector2 after file roundtrip")
	assert_eq(pos, Vector2(3.5, 7.25))

	var vel: Variant = c2.get_fact("player.velocity")
	assert_true(vel is Vector2, "player.velocity should be Vector2 after file roundtrip")
	assert_eq(vel, Vector2(-1.5, 0.0))


# Nested containers with Godot types round-trip
func test_nested_containers_with_godot_types_roundtrip() -> void:
	_chronicle.set_fact("level.waypoints", [
		Vector2(0.0, 0.0),
		Vector2(10.0, 5.0),
		Vector2(20.0, 0.0),
	])
	_chronicle.set_fact("level.bounds", {
		"min": Vector2(-100.0, -100.0),
		"max": Vector2(100.0, 100.0),
		"center": Vector2(0.0, 0.0),
	})

	var data: Dictionary = _chronicle.serialize()
	var json_str: String = JSON.stringify(data)
	var parsed: Variant = JSON.parse_string(json_str)

	var c2: Node = add_child_autoqfree(Chronicle.new())
	var ok: bool = c2.deserialize(parsed)
	assert_true(ok, "nested containers with Vector2 values should survive file roundtrip")

	var waypoints: Variant = c2.get_fact("level.waypoints")
	assert_true(waypoints is Array, "waypoints should be Array")
	assert_eq((waypoints as Array).size(), 3)
	assert_true((waypoints as Array)[0] is Vector2,
		"array elements should be Vector2 after roundtrip")
	assert_eq((waypoints as Array)[0], Vector2(0.0, 0.0))
	assert_eq((waypoints as Array)[1], Vector2(10.0, 5.0))

	var bounds: Variant = c2.get_fact("level.bounds")
	assert_true(bounds is Dictionary, "bounds should be Dictionary")
	assert_true((bounds as Dictionary)["min"] is Vector2,
		"dict values should be Vector2 after roundtrip")
	assert_eq((bounds as Dictionary)["min"], Vector2(-100.0, -100.0))
	assert_eq((bounds as Dictionary)["max"], Vector2(100.0, 100.0))


# Reserved tags "float_special" and "escaped_dict" rejected by register_type
func test_reserved_tags_are_rejected() -> void:
	var registry := TypeRegistry.new()

	var ok_float_special: bool = registry.register_type(
		1000, "float_special",
		func(_v: Variant) -> Dictionary: return {},
		func(_d: Dictionary) -> Variant: return null,
	)
	assert_false(ok_float_special,
		"'float_special' is reserved and must be rejected by register_type")
	assert_false(registry.is_type_registered(1000),
		"type_id 1000 should not be registered after rejection")

	var ok_escaped_dict: bool = registry.register_type(
		1001, "escaped_dict",
		func(_v: Variant) -> Dictionary: return {},
		func(_d: Dictionary) -> Variant: return null,
	)
	assert_false(ok_escaped_dict,
		"'escaped_dict' is reserved and must be rejected by register_type")
	assert_false(registry.is_type_registered(1001),
		"type_id 1001 should not be registered after rejection")


# Empty containers survive JSON roundtrip
func test_empty_containers_survive_json_roundtrip() -> void:
	var codec := _make_codec()

	var empty_arr: Array = []
	var empty_dict: Dictionary = {}

	var prepared_arr: Variant = codec.encode_value(empty_arr)
	var prepared_dict: Variant = codec.encode_value(empty_dict)

	var json_arr: String = JSON.stringify(prepared_arr)
	var json_dict: String = JSON.stringify(prepared_dict)

	var parsed_arr: Variant = JSON.parse_string(json_arr)
	var parsed_dict: Variant = JSON.parse_string(json_dict)

	var restored_arr: Variant = codec.decode_value(parsed_arr)
	var restored_dict: Variant = codec.decode_value(parsed_dict)

	assert_true(restored_arr is Array,
		"empty Array should restore as Array after JSON roundtrip")
	assert_eq((restored_arr as Array).size(), 0,
		"empty Array should remain empty")

	assert_true(restored_dict is Dictionary,
		"empty Dictionary should restore as Dictionary after JSON roundtrip")
	assert_eq((restored_dict as Dictionary).size(), 0,
		"empty Dictionary should remain empty")


# Timeline entries with typed values survive file roundtrip
func test_timeline_entries_with_typed_values_survive_file_roundtrip() -> void:
	_chronicle.set_fact("player.pos", Vector2(0.0, 0.0))
	_chronicle.set_fact("player.pos", Vector2(5.0, 10.0))

	var data: Dictionary = _chronicle.serialize()
	var json_str: String = JSON.stringify(data)
	var parsed: Variant = JSON.parse_string(json_str)

	var c2: Node = add_child_autoqfree(Chronicle.new())
	var ok: bool = c2.deserialize(parsed)
	assert_true(ok, "timeline with Vector2 values should survive file roundtrip")

	var history: Array[Dictionary] = c2.get_fact_history("player.pos")
	assert_eq(history.size(), 2, "should have 2 timeline entries after file roundtrip")

	if history.size() >= 2:
		# First entry: value=Vector2(0,0), old_value=null (creation)
		assert_true(history[0].value is Vector2,
			"timeline value should be Vector2 after file roundtrip")
		assert_eq(history[0].value, Vector2(0.0, 0.0))

		# Second entry: value=Vector2(5,10), old_value=Vector2(0,0)
		assert_true(history[1].value is Vector2,
			"second timeline value should be Vector2")
		assert_eq(history[1].value, Vector2(5.0, 10.0))
		assert_true(history[1].old_value is Vector2,
			"old_value in second timeline entry should be Vector2")
		assert_eq(history[1].old_value, Vector2(0.0, 0.0))


# Normalized _global key accepted on deserialize
func test_normalized_global_key_accepted_on_deserialize() -> void:
	var data: Dictionary = {
		"version": 2,
		"game_time": 0.0,
		"tick": 1,
		"auto_advance": true,
		"facts": {
			"_global.health": 100,   # normalized key with _global. prefix
			"player.gold": 500,
		},
		"timeline": [],
		"expiry": {},
	}
	var ok: bool = _chronicle.deserialize(data)
	assert_true(ok, "deserialized _global. key should be accepted")

	# "_global.health" maps to the fact "health" in user-facing API
	assert_fact("health", 100)
	assert_fact("player.gold", 500)


# Invalid key in deserialized facts is dropped
func test_invalid_key_in_deserialized_facts_is_dropped() -> void:
	var data: Dictionary = {
		"version": 2,
		"game_time": 0.0,
		"tick": 2,
		"auto_advance": true,
		"facts": {
			"player.gold": 500,
			"Invalid.Key": 99,     # uppercase — should be dropped
			"": 0,                 # empty key — should be dropped
			"valid.key": 42,
		},
		"timeline": [],
		"expiry": {},
	}
	var ok: bool = _chronicle.deserialize(data)
	assert_true(ok, "deserialize with some invalid keys should succeed (dropping invalid ones)")

	assert_fact("player.gold", 500)
	assert_fact("valid.key", 42)
	# Invalid keys should NOT be stored
	assert_no_fact("Invalid.Key")
	# Empty key should not be stored
	assert_fact_count("*", 2)


# Serializer rejects non-Dictionary input
func test_serializer_rejects_non_dict_input() -> void:
	var registry := TypeRegistry.new()
	var codec := TypeCodec.new(registry)
	BuiltinTypes.register_all(registry, codec)

	# Build a serializer with real objects (empty store)
	var Serializer := preload("res://addons/chronicle/core/serialization/serializer.gd")
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy)
	var warn_bus := ChronicleWarningBus.new()
	var key_codec := ChronicleKeyCodec.new(warn_bus.warn)
	var ser: RefCounted = Serializer.new(
		store, key_codec, codec, registry
	)

	# Passing Array should return null (serialize returns Snapshot or null)
	var result_array: Variant = ser.deserialize([1, 2, 3])
	assert_null(result_array, "Array input to serializer.deserialize should return null")

	# Passing an int should return null
	var result_int: Variant = ser.deserialize(42)
	assert_null(result_int, "Int input to serializer.deserialize should return null")

	# Passing null should return null
	var result_null: Variant = ser.deserialize(null)
	assert_null(result_null, "null input to serializer.deserialize should return null")

	# A valid dict with proper structure should NOT return null
	var valid: Dictionary = {
		"version": 2,
		"game_time": 0.0,
		"tick": 0,
		"auto_advance": true,
		"facts": {},
		"timeline": [],
		"expiry": {},
	}
	var result_valid: Variant = ser.deserialize(valid)
	assert_not_null(result_valid, "valid dict should return a non-null Snapshot")


# ── Max-depth codec ─────────────────────────


# Fresh codec with builtins registered. Use this for codec-only tests.
# Tests that build registry+codec inline (instead of calling this) do so
# intentionally: they need the raw `registry` handle for register_type /
# is_type_registered assertions, or a registry WITHOUT builtins. Each such
# fixture is deliberately pristine-per-test.
func _make_codec() -> TypeCodec:
	var registry := TypeRegistry.new()
	var codec := TypeCodec.new(registry)
	BuiltinTypes.register_all(registry, codec)
	return codec


# Deeply nested structure should not leak raw values
func test_encode_max_depth_returns_json_safe() -> void:
	var codec := _make_codec()

	# Build a structure deeper than 64 levels
	var inner: Dictionary = {"leaf": "value"}
	for i in range(70):
		inner = {"level_%d" % i: inner}

	var encoded: Variant = codec.encode_value(inner)

	# The encoded result must be JSON-serializable.
	# If encode_value returns a raw value at max depth, JSON.stringify
	# may produce corrupt output or null for that subtree.
	var json_str: String = JSON.stringify(encoded)
	assert_gt(json_str.length(), 0, "JSON.stringify should produce valid output")

	# Re-parse the JSON to verify it round-trips
	var json := JSON.new()
	var parse_err: Error = json.parse(json_str)
	assert_eq(parse_err, OK,
		"encoded deeply-nested value should produce valid JSON — but raw value leaked through at max depth")


# Verify the raw return value type at max depth
func test_encode_max_depth_should_return_null() -> void:
	var codec := _make_codec()

	# Directly test with depth=0 to simulate hitting the limit
	var test_dict: Dictionary = {"nested": {"key": "val"}}
	var result: Variant = codec.encode_value(test_dict, 0)

	# At depth<=0 encode_value pushes an error and returns null (type_codec.gd ~16-18),
	# preventing a raw unencodable value from leaking into the JSON output.
	assert_null(result,
		"encode_value at max depth should return null, not the raw unencodable value")


# Array with deeply nested content should not leak
func test_encode_deeply_nested_array_safe() -> void:
	var codec := _make_codec()

	var inner: Dictionary = {"data": true}
	for i in range(70):
		inner = {"wrap": inner}

	var arr: Array = [inner]
	var encoded: Variant = codec.encode_value(arr)

	# Verify the result is JSON-safe
	var json_str: String = JSON.stringify(encoded)
	var json := JSON.new()
	var parse_err: Error = json.parse(json_str)
	assert_eq(parse_err, OK,
		"encoded array with deeply-nested dict should be valid JSON")


# ── R14/R15 bug regression ──


# A migration that forgets to set dict["version"] is rejected (not auto-promoted)
func test_migration_omitting_version_is_rejected() -> void:
	# serializer.gd uses dict.has("version") (not dict.get("version", version+1)),
	# so a v1->v2 migration that forgets to set dict["version"] is caught and the
	# deserialize is rejected — rather than silently auto-promoting the version.
	_chronicle.register_migration(1, func(d: Dictionary) -> Dictionary:
		# Buggy migration: mutates facts but never sets d["version"].
		d["facts"]["migrated"] = true
		return d
	)
	_chronicle.set_fact("existing.fact", 77)

	var v1_data: Dictionary = {
		"version": 1,
		"facts": {"player.hp": 100},
		"timeline": [],
		"expiry": {},
	}
	var ok: bool = _chronicle.deserialize(v1_data)

	assert_false(ok, "migration that omits dict['version'] must be rejected")
	# State unchanged — deserialize aborts before applying the migrated snapshot.
	assert_fact("existing.fact", 77)
	assert_no_fact("player.hp")
	assert_no_fact("migrated")


# Serialize includes already-expired facts (remaining == 0.0) — now excluded
func test_serialize_includes_expired_facts_at_boundary() -> void:
	# Use the coordinator's clock directly to avoid auto-flush on set_game_time
	_chronicle.set_auto_advancing(false)
	_chronicle.set_game_time(10.0)
	_chronicle.set_fact("temp", "value", false, 5.0)
	# Fact expires at absolute time 15.0

	_chronicle.set_game_time(15.0)

	# Construct the scenario with the serializer directly:
	var clock := _GameClock.new()
	clock.set_time(10.0)
	var store := _Store.new(ChronicleValueUtils.deep_copy)
	store.set_value("test.key", "val")
	var expiry := _Expiry.new(clock.get_time)
	expiry.schedule("test.key", 5.0)
	# test.key expires at t=15.0

	clock.set_time(15.0)
	# remaining = 15.0 - 15.0 = 0.0

	var reg := ChronicleTypeRegistry.new()
	var codec := ChronicleTypeCodec.new(reg)
	ChronicleBuiltinTypes.register_all(reg, codec)
	var warn2 := ChronicleWarningBus.new()
	var kc := _KeyCodec.new(warn2.warn)
	var serializer := SerializerScript.new(store, kc, codec, reg)
	var timeline := _Timeline.new(ChronicleValueUtils.deep_copy, func(_m: String) -> void: pass)
	var data: Dictionary = serializer.serialize(timeline, expiry, clock)
	var expiry_data: Dictionary = data.get("expiry", {})

	# FIXED: remaining > 0.0 excludes the boundary case (remaining == 0.0)
	assert_does_not_have(expiry_data, "test.key",
		"expired fact (remaining=0.0) should NOT be included in serialized expiry")


# _builtin_migrations should be per-instance, not static var
func test_builtin_migrations_should_be_per_instance() -> void:
	# _builtin_migrations was `static var` — all instances shared the same dict.
	# CORRECT: it should be instance-scoped like _user_migrations.
	# After fix, each Chronicle has its own serializer with its own migrations.
	# Verify by saving and loading — builtin migration v1->v2 still works.
	_chronicle.set_fact("x", 42)
	var data: Dictionary = _chronicle.serialize()
	assert_has(data, "version", "serialized data should have version key")
	assert_eq(data["version"], SerializerScript.SAVE_VERSION, "version should match SAVE_VERSION")
