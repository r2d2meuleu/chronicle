## Unit tests for ChronicleFactRegistry: scanning, key discovery, signal emission, and testability boundary.
extends GutTest

const InspPlugin = preload("res://addons/chronicle/editor/inspector_plugin.gd")
const FactRegistryScript = preload("res://addons/chronicle/editor/fact_registry.gd")

var _temp_files: Array[String] = []

# Helper .gd file placed outside test/ and addons/ so the registry finds it after the L7 skip.
const _PROBE_GD_PATH := "res://registry_probe.gd"
const _PROBE_GD_CONTENT := """extends Node
func _ready() -> void:
\tget_node("/root/Chronicle").set_fact("player.gold", 100)
\tget_node("/root/Chronicle").set_fact("player.hp", 50)
\tget_node("/root/Chronicle").set_fact("quest.done", true)
"""


func before_each() -> void:
	var f := FileAccess.open(_PROBE_GD_PATH, FileAccess.WRITE)
	if f:
		f.store_string(_PROBE_GD_CONTENT)
		f.close()
	_temp_files.append(_PROBE_GD_PATH)


func after_each() -> void:
	for path in _temp_files:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_temp_files.clear()


# Preload succeeded — can we instantiate ChronicleFactRegistry?
func test_can_instantiate_fact_registry() -> void:
	var reg = FactRegistryScript.new()
	assert_not_null(reg, "ChronicleFactRegistry.new() should return a non-null instance")
	assert_true(reg is RefCounted, "ChronicleFactRegistry should be a RefCounted")


# is_empty() returns true on a fresh instance
func test_is_empty_before_rebuild() -> void:
	var reg = FactRegistryScript.new()
	assert_true(reg.is_empty(), "fresh ChronicleFactRegistry should be empty")


# rebuild() runs without error in headless mode and emits rebuilt signal
func test_rebuild_emits_signal() -> void:
	var reg = FactRegistryScript.new()
	watch_signals(reg)
	reg.rebuild()
	assert_signal_emitted(reg, "rebuilt", "rebuild() should emit 'rebuilt' signal")


# After rebuild, is_empty() returns false (test .gd files contain set_fact/mark calls)
func test_not_empty_after_rebuild() -> void:
	var reg = FactRegistryScript.new()
	reg.rebuild()
	assert_false(reg.is_empty(), "ChronicleFactRegistry should have keys after rebuild (test .gd files contain set_fact calls)")


# is_known() finds specific keys from the test project's .gd files
func test_is_known_finds_gd_keys() -> void:
	var reg = FactRegistryScript.new()
	reg.rebuild()
	# These keys are used in set_fact() calls across the test suite
	assert_true(reg.is_known("player.gold"), "player.gold should be known (used in test_watch_once.gd, etc.)")
	assert_true(reg.is_known("player.hp"), "player.hp should be known (used in test_queries.gd, etc.)")
	assert_true(reg.is_known("quest.done"), "quest.done should be known (used in test_gate.gd, etc.)")


# is_known() returns false for a key that definitely does not exist
func test_is_known_returns_false_for_unknown() -> void:
	var reg = FactRegistryScript.new()
	reg.rebuild()
	assert_false(reg.is_known("zzz.nonexistent.key.12345"), "nonsense key should not be known")


# _scan_cfg() picks up keys from a chronicle_facts.cfg file
func test_scan_cfg() -> void:
	var cfg_path := "res://chronicle_facts.cfg"
	var f := FileAccess.open(cfg_path, FileAccess.WRITE)
	assert_not_null(f, "should be able to create chronicle_facts.cfg")
	f.store_string("# comment line\ntest.cfg.alpha\ntest.cfg.beta\n")
	f.close()
	_temp_files.append(cfg_path)

	var reg = FactRegistryScript.new()
	reg.rebuild()

	assert_true(reg.is_known("test.cfg.alpha"), "key from cfg file should be known")
	assert_true(reg.is_known("test.cfg.beta"), "key from cfg file should be known")


# _scan_tres() picks up keys from a .tres file with fact_key = "..."
func test_scan_tres() -> void:
	var tres_path := "res://test_probe.tres"
	var f := FileAccess.open(tres_path, FileAccess.WRITE)
	assert_not_null(f, "should be able to create test .tres")
	f.store_string('[resource]\nfact_key = "probe.tres.key"\n')
	f.close()
	_temp_files.append(tres_path)

	var reg = FactRegistryScript.new()
	reg.rebuild()

	assert_true(reg.is_known("probe.tres.key"), "key from .tres should be known")


# rebuild() clears stale keys that no longer exist in sources
func test_rebuild_clears_stale_keys() -> void:
	var cfg_path := "res://chronicle_facts.cfg"
	var f := FileAccess.open(cfg_path, FileAccess.WRITE)
	assert_not_null(f, "should be able to create chronicle_facts.cfg")
	f.store_string("stale.key.to.remove\n")
	f.close()
	_temp_files.append(cfg_path)

	var reg = FactRegistryScript.new()
	reg.rebuild()
	assert_true(reg.is_known("stale.key.to.remove"), "key should exist after first rebuild")

	# Remove the cfg file and rebuild — key must be gone
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	_temp_files.erase(cfg_path)
	reg.rebuild()
	assert_false(reg.is_known("stale.key.to.remove"), "key should be gone after cfg removed and rebuild")


# rebuilt signal fires after scan is complete (is_known works inside handler)
func test_rebuilt_signal_fires_after_scan_complete() -> void:
	var cfg_path := "res://chronicle_facts.cfg"
	var f := FileAccess.open(cfg_path, FileAccess.WRITE)
	assert_not_null(f, "should be able to create chronicle_facts.cfg")
	f.store_string("signal.timing.key\n")
	f.close()
	_temp_files.append(cfg_path)

	var reg = FactRegistryScript.new()
	var key_was_known_in_handler := [false]
	reg.rebuilt.connect(func() -> void:
		key_was_known_in_handler[0] = reg.is_known("signal.timing.key")
	)
	reg.rebuild()
	assert_true(key_was_known_in_handler[0], "is_known() should return true inside rebuilt handler")


# Multiple rebuild cycles produce consistent results (no accumulation bugs)
func test_multiple_rebuild_cycles() -> void:
	var reg = FactRegistryScript.new()
	reg.rebuild()
	assert_true(reg.is_known("player.gold"), "player.gold should be known after first rebuild")

	reg.rebuild()
	assert_true(reg.is_known("player.gold"), "player.gold should still be known after second rebuild")
	assert_false(reg.is_known("zzz.nonexistent.key.12345"), "nonsense key should not appear after multiple rebuilds")

	reg.rebuild()
	assert_false(reg.is_empty(), "registry should not be empty after third rebuild")


# FactKeyProperty is editor-only — EditorProperty cannot be instantiated in headless mode.
# This is NOT a bug: Godot restricts EditorProperty to the editor process.
# The test documents the testability boundary so future maintainers know this is expected.
func test_fact_key_property_is_editor_only() -> void:
	var prop = InspPlugin._FactKeyProperty.new(InspPlugin._FactKeyProperty._Mode.FACT_KEY)
	assert_null(prop, "FactKeyProperty.new() returns null in headless mode (editor-only class)")
	# Instantiating an EditorProperty outside the editor emits two engine errors:
	# the editor-only restriction, plus a null "owner" follow-on. Declaring them
	# confirms the headless boundary is exercised (and keeps the gate green).
	assert_engine_error_count(2, "EditorProperty is editor-only — instantiation in headless emits two engine errors")


# ── Scanner Edge Cases ──

# Basic key extraction from GDScript source text
func test_extract_key_from_set_fact() -> void:
	var reg := FactRegistryScript.new()
	# Simulate what _extract_keys_multi does internally
	var text := 'chronicle.set_fact("player.health", 100)'
	var needle := 'set_fact("'
	var idx := text.find(needle)
	assert_ne(idx, -1, "needle should be found")
	# Call the internal method to extract the key
	reg._extract_key_at(text, idx + needle.length())
	assert_true(reg.is_known("player.health"),
		"should extract 'player.health' from set_fact call")


# Empty key (start == end) should not be registered
func test_empty_key_not_registered() -> void:
	var reg := FactRegistryScript.new()
	# Text where the closing quote immediately follows the opening quote
	var text := 'set_fact("")'
	var needle := 'set_fact("'
	var idx := text.find(needle)
	reg._extract_key_at(text, idx + needle.length())
	assert_true(reg.is_empty(),
		"empty string between quotes should not register a key")


# Key with newline should be rejected
func test_key_with_newline_rejected() -> void:
	var reg := FactRegistryScript.new()
	# Simulates a malformed match spanning lines
	var text := "set_fact(\"player\nhealth\")"
	var needle := "set_fact(\""
	var idx := text.find(needle)
	reg._extract_key_at(text, idx + needle.length())
	assert_true(reg.is_empty(),
		"key containing newline should be rejected")


# Multiple needles in one file are all extracted
func test_multi_needle_extraction() -> void:
	var reg := FactRegistryScript.new()
	var text := """
func foo():
	chronicle.set_fact("quest.started", true)
	chronicle.set_fact("quest.marked")
	chronicle.toggle_fact("quest.toggled")
	chronicle.erase_fact("quest.erased")
	chronicle.increment_fact("quest.counter", 1)
	chronicle.increment_fact("quest.dec", -1)
	chronicle.clamp_fact("quest.clamped", 0, 10)
"""
	for needle: String in FactRegistryScript._SCAN_NEEDLES:
		var idx := text.find(needle)
		while idx != -1:
			reg._extract_key_at(text, idx + needle.length())
			idx = text.find(needle, idx + 1)

	assert_true(reg.is_known("quest.started"), "set_fact key should be found")
	assert_true(reg.is_known("quest.marked"), "set_fact(marked) key should be found")
	assert_true(reg.is_known("quest.toggled"), "toggle_fact key should be found")
	assert_true(reg.is_known("quest.erased"), "erase_fact key should be found")
	assert_true(reg.is_known("quest.counter"), "increment_fact key should be found")
	assert_true(reg.is_known("quest.dec"), "increment_fact(dec) key should be found")
	assert_true(reg.is_known("quest.clamped"), "clamp_fact key should be found")


# Scanner only finds double-quote calls (single-quote not scanned — by design)
func test_single_quote_not_scanned() -> void:
	var reg := FactRegistryScript.new()
	# GDScript allows single-quote strings: set_fact('key')
	var text := "chronicle.set_fact('player.hp')"
	for needle: String in FactRegistryScript._SCAN_NEEDLES:
		var idx := text.find(needle)
		while idx != -1:
			reg._extract_key_at(text, idx + needle.length())
			idx = text.find(needle, idx + 1)
	# Single-quote variant is NOT matched by the double-quote needles
	assert_false(reg.is_known("player.hp"),
		"single-quote fact calls are not detected by the scanner (by design)")


# _extract_key_at with no closing quote should not crash
func test_no_closing_quote_safe() -> void:
	var reg := FactRegistryScript.new()
	var text := 'set_fact("player.health'
	var needle := 'set_fact("'
	var idx := text.find(needle)
	# Should not crash — just skip gracefully
	reg._extract_key_at(text, idx + needle.length())
	# The key extends to end of text with no closing quote, so end < 0 path
	# Actually: find returns -1 when not found, so the guard on line 122 fires
	assert_true(reg.is_empty(),
		"missing closing quote should result in no key registered")


# Scene resource needle extracts fact_key from .tscn-like text
func test_scene_resource_fact_key_extraction() -> void:
	var reg := FactRegistryScript.new()
	# Simulates a .tscn serialized property
	var text := '[node name="Recorder" type="Node"]\nfact_key = "quest.item_collected"\n'
	var needle := 'fact_key = "'
	var idx := text.find(needle)
	assert_ne(idx, -1, "needle should be found in tscn text")
	reg._extract_key_at(text, idx + needle.length())
	assert_true(reg.is_known("quest.item_collected"),
		"fact_key from scene resource should be extracted")
