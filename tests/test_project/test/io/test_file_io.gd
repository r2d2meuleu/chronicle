extends ChronicleTestSuite

const BuiltinTypes := preload("res://addons/chronicle/core/serialization/builtin_types.gd")

const _BASE_DIR := "user://test_chronicle_io"

var _registry: ChronicleTypeRegistry
var _codec: ChronicleTypeCodec


func before_each() -> void:
	super.before_each()
	_registry = ChronicleTypeRegistry.new()
	_codec = ChronicleTypeCodec.new(_registry)
	BuiltinTypes.register_all(_registry, _codec)


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(_BASE_DIR)


func after_all() -> void:
	var dir := DirAccess.open(_BASE_DIR)
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				DirAccess.remove_absolute(_BASE_DIR + "/" + fname)
			fname = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(_BASE_DIR)


# ── Happy Path ──

# Save and load returns identical data
func test_save_and_load_returns_same_data() -> void:
	var data := {"name": "test", "value": 42, "flag": true}
	var err := save_temp(_BASE_DIR + "/test_01.json", data)
	assert_eq(err, OK)
	var loaded: Variant = read_file(_BASE_DIR + "/test_01.json")
	assert_not_null(loaded)
	assert_eq(loaded, data)


# save_to_file returns OK on success
func test_save_returns_ok_on_success() -> void:
	var data := {"key": "value"}
	var err := save_temp(_BASE_DIR + "/test_02.json", data)
	assert_eq(err, OK)


# Saved file exists on disk after save
func test_save_creates_file_on_disk() -> void:
	var path := _BASE_DIR + "/test_03.json"
	var data := {"exists": true}
	save_temp(path, data)
	assert_true(FileAccess.file_exists(path))


# Load returns a Dictionary
func test_load_returns_dictionary() -> void:
	var path := _BASE_DIR + "/test_04.json"
	save_temp(path, {"result": "dict"})
	var loaded: Variant = read_file(path)
	assert_true(loaded is Dictionary)


# Nested structures survive roundtrip
func test_save_load_preserves_nested_structures() -> void:
	var data := {
		"outer": {
			"middle": {
				"inner": "deep_value"
			},
			"sibling": [1, 2, 3]
		},
		"top": true
	}
	var path := _BASE_DIR + "/test_05.json"
	save_temp(path, data)
	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_eq(loaded, data)


# All JSON-safe types survive roundtrip (bool, int, float, String, Array, Dict)
func test_save_load_preserves_all_json_types() -> void:
	var data := {
		"b": true,
		"i": 99,
		"f": 1.5,
		"s": "hello",
		"a": [false, 7, "item"],
		"d": {"nested_int": 3, "nested_bool": false}
	}
	var path := _BASE_DIR + "/test_06.json"
	save_temp(path, data)
	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_eq(loaded.get("b"), true)
	assert_eq(loaded.get("i"), 99)
	assert_eq(loaded.get("f"), 1.5)
	assert_eq(loaded.get("s"), "hello")
	assert_eq(loaded.get("a"), [false, 7, "item"])
	assert_eq(loaded.get("d"), {"nested_int": 3, "nested_bool": false})


# ── Atomic Write Mechanism ──

# Save with existing file creates .bak before overwriting
func test_save_creates_backup_of_existing_file() -> void:
	var path := _BASE_DIR + "/test_07.json"
	var bak_path := path + ".bak"
	register_temp(path)

	# First save — no .bak yet
	ChronicleFileIO.save_to_file(path, {"first": true})
	assert_false(FileAccess.file_exists(bak_path))

	# Second save — should create .bak from the first save
	ChronicleFileIO.save_to_file(path, {"second": true})
	assert_true(FileAccess.file_exists(bak_path))


# Second save: .bak contains what was the primary after first save
func test_second_save_bak_contains_previous_primary() -> void:
	var path := _BASE_DIR + "/test_08.json"
	var bak_path := path + ".bak"
	register_temp(path)

	ChronicleFileIO.save_to_file(path, {"version": 1})
	ChronicleFileIO.save_to_file(path, {"version": 2})

	# Primary should now be version 2
	var primary: Variant = read_file(path)
	assert_not_null(primary)
	assert_eq(primary.get("version"), 2)

	# .bak should be version 1 (what was primary before the second save)
	var bak: Variant = ChronicleFileIO.load_from_file(bak_path)
	assert_not_null(bak)
	assert_eq(bak.get("version"), 1)


# No .tmp file remains after successful save
func test_no_tmp_file_remains_after_save() -> void:
	var path := _BASE_DIR + "/test_09.json"
	var tmp_path := path + ".tmp"
	save_temp(path, {"data": "clean"})
	assert_false(FileAccess.file_exists(tmp_path))


# Save overwrites existing .bak
func test_save_overwrites_existing_bak() -> void:
	var path := _BASE_DIR + "/test_10.json"
	var bak_path := path + ".bak"
	register_temp(path)

	# Three saves: v1, v2, v3
	# After v3: primary=v3, .bak=v2 (v1's .bak was overwritten by v2's save)
	ChronicleFileIO.save_to_file(path, {"v": 1})
	ChronicleFileIO.save_to_file(path, {"v": 2})
	ChronicleFileIO.save_to_file(path, {"v": 3})

	var bak: Variant = ChronicleFileIO.load_from_file(bak_path)
	assert_not_null(bak)
	# .bak should be v2, not v1 (v1 .bak was overwritten by v2 save)
	assert_eq(bak.get("v"), 2)

	var primary: Variant = read_file(path)
	assert_not_null(primary)
	assert_eq(primary.get("v"), 3)


# ── Backup Fallback ──

# Corrupt primary (invalid JSON) falls back to .bak
func test_corrupt_primary_loads_from_backup() -> void:
	var path := _BASE_DIR + "/test_11.json"
	register_temp(path)

	# Write a valid save twice so .bak exists
	ChronicleFileIO.save_to_file(path, {"score": 100})
	ChronicleFileIO.save_to_file(path, {"score": 200})

	# Corrupt the primary
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not valid json {{{")
	f.close()

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_eq(loaded.get("score"), 100)
	# The corrupt primary emits one engine error from the file/JSON read before
	# the loader falls back to the valid .bak. Declaring it confirms the fallback ran.
	assert_engine_error_count(1, "corrupt primary read emits one engine error before .bak fallback")


# Both primary and .bak corrupt returns null
func test_both_corrupt_returns_null() -> void:
	var path := _BASE_DIR + "/test_12.json"
	var bak_path := path + ".bak"
	register_temp(path)

	# Write twice to create both files
	ChronicleFileIO.save_to_file(path, {"ok": true})
	ChronicleFileIO.save_to_file(path, {"ok": true})

	# Corrupt both
	var f1 := FileAccess.open(path, FileAccess.WRITE)
	f1.store_string("{corrupt}")
	f1.close()

	var f2 := FileAccess.open(bak_path, FileAccess.WRITE)
	f2.store_string("{also corrupt}")
	f2.close()

	var loaded: Variant = read_file(path)
	assert_null(loaded)
	# Both primary AND .bak are corrupt, so the loader emits one engine error per
	# failed read (primary + .bak) = 2 before giving up and returning null.
	assert_engine_error_count(2, "corrupt primary + corrupt .bak each emit one engine error")


# Missing primary with valid .bak loads from .bak
func test_missing_primary_with_valid_bak_loads_bak() -> void:
	var path := _BASE_DIR + "/test_13.json"
	var bak_path := path + ".bak"
	register_temp(path)

	# Write a valid .bak directly (simulating a partial save that removed the primary)
	ChronicleFileIO.save_to_file(bak_path, {"from_bak": true})

	# Ensure primary does not exist
	assert_false(FileAccess.file_exists(path))

	var loaded: Variant = read_file(path)
	# primary missing → falls through, .bak exists and is valid
	assert_not_null(loaded)
	assert_eq(loaded.get("from_bak"), true)


# Primary is Array JSON (not Dict) — falls back to .bak
func test_primary_is_array_json_falls_back_to_bak() -> void:
	var path := _BASE_DIR + "/test_14.json"
	register_temp(path)

	# Create a valid .bak first
	ChronicleFileIO.save_to_file(path, {"real": "data"})
	ChronicleFileIO.save_to_file(path, {"real": "data"})

	# Overwrite primary with valid JSON that is an Array, not a Dict
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[1, 2, 3]")
	f.close()

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_eq(loaded.get("real"), "data")


# Primary is empty string — falls back to .bak
func test_primary_is_empty_string_falls_back_to_bak() -> void:
	var path := _BASE_DIR + "/test_15.json"
	register_temp(path)

	# Create a valid .bak
	ChronicleFileIO.save_to_file(path, {"backup_val": 42})
	ChronicleFileIO.save_to_file(path, {"backup_val": 42})

	# Write empty string to primary
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("")
	f.close()

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_eq(loaded.get("backup_val"), 42)
	# The empty primary emits one engine error on read before the loader falls
	# back to the valid .bak. Declaring it confirms the fallback path ran.
	assert_engine_error_count(1, "empty primary read emits one engine error before .bak fallback")


# ── Error Handling ──

# Load nonexistent file returns null
func test_load_nonexistent_file_returns_null() -> void:
	var loaded: Variant = read_file(_BASE_DIR + "/does_not_exist_xyz.json")
	assert_null(loaded)


# Load empty file returns null
func test_load_empty_file_returns_null() -> void:
	var path := _BASE_DIR + "/test_17.json"
	register_temp(path)

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("")
	f.close()

	var loaded: Variant = read_file(path)
	assert_null(loaded)
	# An empty file with no .bak emits one engine error on read before returning null.
	assert_engine_error_count(1, "empty file with no backup emits one engine error then returns null")


# Save returns error for completely invalid path
func test_save_returns_error_on_invalid_path() -> void:
	# Empty string path does not begin with user:// or res://, so it is rejected
	# up front with ERR_FILE_BAD_PATH.
	var err := ChronicleFileIO.save_to_file("", {"data": 1})
	assert_eq(err, ERR_FILE_BAD_PATH)


# Load file with non-Dict JSON returns null (no .bak exists)
func test_load_non_dict_json_no_bak_returns_null() -> void:
	var path := _BASE_DIR + "/test_19.json"
	register_temp(path)

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\"just a string\"")
	f.close()

	var loaded: Variant = read_file(path)
	assert_null(loaded)


# ── Integration with Chronicle ──

# Full Chronicle state survives save → load cycle
func test_full_chronicle_state_survives_save_load_cycle() -> void:
	_chronicle.set_fact("player.gold", 1500)
	_chronicle.set_fact("player.name", "Aldric")
	_chronicle.set_fact("quest.main.started")
	_chronicle.set_fact("inventory.potions", 3)

	var path := _BASE_DIR + "/test_20.json"
	var data: Dictionary = _chronicle.serialize()
	save_temp(path, data)

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_true(loaded is Dictionary)

	var c2: Node = add_child_autoqfree(Chronicle.new())
	var ok: bool = c2.deserialize(loaded)
	assert_true(ok)
	assert_eq(c2.get_fact("player.gold"), 1500)
	assert_eq(c2.get_fact("player.name"), "Aldric")
	assert_true(c2.is_marked("quest.main.started"))
	assert_eq(c2.get_fact("inventory.potions"), 3)


# Save/load preserves game_time and timeline
func test_save_load_preserves_game_time_and_timeline() -> void:
	set_time(25.0)
	_chronicle.set_fact("score", 10)
	set_time(50.0)
	_chronicle.set_fact("score", 20)

	var path := _BASE_DIR + "/test_21.json"
	save_temp(path, _chronicle.serialize())

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)

	var c2: Node = add_child_autoqfree(Chronicle.new())
	c2.deserialize(loaded)

	assert_eq(c2.get_game_time(), 50.0)
	var history: Array[Dictionary] = c2.get_fact_history("score")
	assert_eq(history.size(), 2)
	assert_eq(history[0].value, 10)
	assert_eq(history[0].time, 25.0)
	assert_eq(history[1].value, 20)
	assert_eq(history[1].time, 50.0)


# Save/load with Godot value types (Vector2, Color, etc)
func test_save_load_with_vector_types() -> void:
	var path := _BASE_DIR + "/test_22.json"
	var data: Variant = _codec.encode_value({
		"pos": Vector2(10.5, 20.5),
		"color": Color(0.8, 0.2, 0.4, 1.0),
		"cell": Vector3i(1, 2, 3)
	})
	save_temp(path, data)

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_true(loaded is Dictionary)
	assert_eq(loaded.get("pos"), Vector2(10.5, 20.5))
	assert_eq(loaded.get("color"), Color(0.8, 0.2, 0.4, 1.0))
	assert_eq(loaded.get("cell"), Vector3i(1, 2, 3))


# Save/load with packed arrays
func test_save_load_with_packed_arrays() -> void:
	var path := _BASE_DIR + "/test_23.json"
	var packed_ints := PackedInt32Array([10, 20, 30, 40])
	var packed_strings := PackedStringArray(["a", "b", "c"])
	var data: Variant = _codec.encode_value({
		"ints": packed_ints,
		"strings": packed_strings
	})
	save_temp(path, data)

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_true(loaded.get("ints") is PackedInt32Array)
	assert_eq(loaded.get("ints"), packed_ints)
	assert_true(loaded.get("strings") is PackedStringArray)
	assert_eq(loaded.get("strings"), packed_strings)


# Save/load empty Chronicle (no facts)
func test_save_load_with_empty_chronicle() -> void:
	var path := _BASE_DIR + "/test_24.json"
	save_temp(path, _chronicle.serialize())

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_true(loaded is Dictionary)

	var c2: Node = add_child_autoqfree(Chronicle.new())
	var ok: bool = c2.deserialize(loaded)
	assert_true(ok)
	assert_eq(c2.get_facts("*").size(), 0)
	assert_eq(c2.get_game_time(), 0.0)


# Save/load preserves tick counter
func test_save_load_preserves_tick_counter() -> void:
	_chronicle.set_fact("a.x", 1)
	_chronicle.set_fact("a.y", 2)
	_chronicle.set_fact("a.z", 3)

	var path := _BASE_DIR + "/test_25.json"
	var serialized: Dictionary = _chronicle.serialize()
	save_temp(path, serialized)

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_eq(loaded.get("tick"), 3)

	var c2: Node = add_child_autoqfree(Chronicle.new())
	c2.deserialize(loaded)
	c2.set_fact("a.w", 4)
	# After deserialize + set_fact, timeline should have entries
	var stats: Dictionary = c2.get_stats()
	assert_gt(stats.timeline_size, 0, "timeline should have entries after deserialize + set_fact")


# Transient facts excluded from save
func test_transient_facts_excluded_from_save() -> void:
	_chronicle.set_fact("player.gold", 200)
	_chronicle.set_fact("player.temp_buff", 99, true, 0.0)  # transient

	var path := _BASE_DIR + "/test_26.json"
	save_temp(path, _chronicle.serialize())

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)

	var c2: Node = add_child_autoqfree(Chronicle.new())
	c2.deserialize(loaded)

	assert_eq(c2.get_fact("player.gold"), 200)
	assert_false(c2.has_fact("player.temp_buff"))


# Lifetime facts excluded from save
func test_lifetime_facts_excluded_from_save() -> void:
	_chronicle.set_fact("player.hp", 100)
	_chronicle.set_fact("player.shield", 50, false, 30.0)  # expires in 30s (lifetime → transient)

	var path := _BASE_DIR + "/test_27.json"
	save_temp(path, _chronicle.serialize())

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)

	var c2: Node = add_child_autoqfree(Chronicle.new())
	c2.deserialize(loaded)

	assert_eq(c2.get_fact("player.hp"), 100)
	# Lifetime facts are transient — they should not be in the save
	assert_false(c2.has_fact("player.shield"))


# ── Edge Cases ──

# Unicode string values in facts survive roundtrip
func test_save_load_with_unicode_string_values() -> void:
	var data := {
		"greeting": "こんにちは",
		"emoji_label": "sword: ⚔",
		"arabic": "مرحبا",
		"mixed": "abcéèê"
	}
	var path := _BASE_DIR + "/test_28.json"
	save_temp(path, data)

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_eq(loaded.get("greeting"), data["greeting"])
	assert_eq(loaded.get("emoji_label"), data["emoji_label"])
	assert_eq(loaded.get("arabic"), data["arabic"])
	assert_eq(loaded.get("mixed"), data["mixed"])


# Large dictionary (200 keys) roundtrips correctly
func test_save_load_large_dictionary_200_keys() -> void:
	var data: Dictionary = {}
	for i in range(200):
		data["key_%03d" % i] = i * 2

	var path := _BASE_DIR + "/test_29.json"
	save_temp(path, data)

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_true(loaded is Dictionary)
	assert_eq(loaded.size(), 200)

	var all_correct := true
	for i in range(200):
		var k := "key_%03d" % i
		if loaded.get(k) != i * 2:
			all_correct = false
			break
	assert_true(all_correct)


# Deeply nested structure (5 levels) roundtrips
func test_save_load_deeply_nested_5_levels() -> void:
	var data := {
		"l1": {
			"l2": {
				"l3": {
					"l4": {
						"l5": "deep_value"
					},
					"l4_sibling": 42
				},
				"l3_flag": true
			},
			"l2_array": [1, 2, 3]
		}
	}
	var path := _BASE_DIR + "/test_30.json"
	save_temp(path, data)

	var loaded: Variant = read_file(path)
	assert_not_null(loaded)
	assert_eq(loaded, data)
	# Verify the deepest value explicitly
	var deep: Variant = loaded["l1"]["l2"]["l3"]["l4"]["l5"]
	assert_eq(deep, "deep_value")


# Multiple save/load cycles don't accumulate errors
func test_multiple_save_load_cycles_stable() -> void:
	var path := _BASE_DIR + "/test_31.json"
	register_temp(path)

	var data := {"cycle": 0, "stable": true}
	var cycle_count := 5

	for i in range(cycle_count):
		data["cycle"] = i
		var err := ChronicleFileIO.save_to_file(path, data)
		assert_eq(err, OK, "save failed at cycle %d" % i)

		var loaded: Variant = read_file(path)
		assert_not_null(loaded, "load returned null at cycle %d" % i)
		assert_eq(loaded.get("cycle"), i, "cycle value mismatch at cycle %d" % i)
		assert_eq(loaded.get("stable"), true, "stable value lost at cycle %d" % i)

	# After 5 cycles: primary should have cycle=4, .bak should have cycle=3
	var final_primary: Variant = read_file(path)
	assert_not_null(final_primary)
	assert_eq(final_primary.get("cycle"), 4)

	var bak_data: Variant = ChronicleFileIO.load_from_file(path + ".bak")
	assert_not_null(bak_data)
	assert_eq(bak_data.get("cycle"), 3)


# ── Rollback Failure Reporting ──

# audit: R17-A12
# Drives the final-rename-failure + failed-rollback branch of save_to_file: when
# the destination is a non-empty directory the .tmp→primary rename fails, and the
# .bak→primary rollback rename fails too (CRITICAL path). The save must still
# report a non-OK error rather than silently returning OK.
func test_save_reports_error_when_rename_and_rollback_both_fail() -> void:
	var path := _BASE_DIR + "/test_rollback_fail.json"

	# Make the destination a NON-EMPTY directory so renaming a file onto it fails.
	DirAccess.make_dir_recursive_absolute(path)
	var inner := FileAccess.open(path + "/inner.txt", FileAccess.WRITE)
	inner.store_string("blocker")
	inner.close()

	# A valid .bak alongside makes the rollback branch reachable; its rename onto
	# the same non-empty directory also fails (the CRITICAL backup-restore path).
	var bak := FileAccess.open(path + ".bak", FileAccess.WRITE)
	bak.store_string('{"v": 99}')
	bak.close()

	var err := ChronicleFileIO.save_to_file(path, {"v": 1})
	assert_eq(err, FAILED,
		"save_to_file must report FAILED when the final rename and the .bak rollback both fail")

	# Manual cleanup: after_each's DirAccess.remove_absolute cannot delete a
	# non-empty directory, and a leftover .tmp may remain from the failed rename.
	var tmp_path := path + ".tmp"
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + "/inner.txt"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# register_temp schedules path + .bak for after_each cleanup
func test_register_temp_schedules_path_and_bak_cleanup() -> void:
	var path := "user://r3_register_temp_probe.json"
	register_temp(path)
	assert_has(_temp_files, path, "register_temp records the path for after_each cleanup")


# load_from_file rejects paths outside user:// / res:// (returns null + push_error)
func test_load_from_file_rejects_foreign_path() -> void:
	assert_null(ChronicleFileIO.load_from_file("/etc/hosts"),
		"load_from_file must reject a non-user://res:// path and return null")


# load_from_file returns null when the primary and all fallbacks are missing
func test_load_from_file_missing_returns_null() -> void:
	assert_null(ChronicleFileIO.load_from_file("user://chronicle_absent_probe_zzz.json"),
		"load_from_file returns null when the file (and .bak/.tmp fallbacks) are missing")
