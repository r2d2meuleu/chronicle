extends ChronicleTestSuite

const TEMP_PATH := "user://test_r6_save_load.json"


func before_each() -> void:
	super.before_each()
	# save_file writes TEMP_PATH (and a .bak on the second save). Register it so the
	# base after_each removes both — no bespoke cleanup override needed.
	register_temp(TEMP_PATH)


# Save and load roundtrip preserves facts
func test_save_and_load_roundtrip() -> void:
	_chronicle.set_fact("player.name", "hero")
	_chronicle.set_fact("player.hp", 100)
	var err: Error = _chronicle.save_file(TEMP_PATH)
	assert_eq(err, OK)
	_chronicle.clear()
	assert_no_fact("player.name")
	err = _chronicle.load_file(TEMP_PATH)
	assert_eq(err, OK)
	assert_fact("player.name", "hero")
	assert_fact("player.hp", 100)


# Load nonexistent file returns a read error
func test_load_nonexistent_returns_error() -> void:
	# The default load_fn returns null for a missing file, which load_file maps to
	# ERR_FILE_CANT_READ.
	var err: Error = _chronicle.load_file("user://nonexistent_r6_test.json")
	assert_eq(err, ERR_FILE_CANT_READ)


# Save excludes transient facts
func test_save_excludes_transient() -> void:
	_chronicle.set_fact("temp", true, true, 0.0)
	_chronicle.set_fact("perm", true)
	var err: Error = _chronicle.save_file(TEMP_PATH)
	assert_eq(err, OK)
	_chronicle.clear()
	_chronicle.load_file(TEMP_PATH)
	assert_no_fact("temp")
	assert_fact("perm", true)


# Custom save_fn is invoked instead of default
func test_custom_save_fn_invoked() -> void:
	var saved_data: Array = []
	_chronicle.set_save_fn(func(path: String, data: Dictionary) -> Error: saved_data.append(data); return OK)
	_chronicle.set_fact("x", 1)
	_chronicle.save_file("ignored_path")
	assert_eq(saved_data.size(), 1)
	assert_true(saved_data[0] is Dictionary)


# Custom load_fn is invoked instead of default, and its data is deserialized
func test_custom_load_fn_invoked() -> void:
	_chronicle.set_fact("seed", 42)
	var snapshot: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	var load_paths: Array = []
	_chronicle.set_load_fn(func(path: String) -> Variant: load_paths.append(path); return snapshot)
	var err: int = _chronicle.load_file("ignored_path")
	assert_eq(err, OK, "load_file should succeed via the custom load_fn")
	assert_eq(load_paths.size(), 1, "custom load_fn should be invoked exactly once")
	assert_fact("seed", 42)
