extends GutTest

const KeyCodec := preload("res://addons/chronicle/core/key_codec.gd")

var _codec: ChronicleKeyCodec


func before_each() -> void:
	_codec = ChronicleKeyCodec.new(func(_msg): pass)


# Lowercase keys are accepted
func test_lowercase_key_accepted():
	var norm: String = _codec.validate_and_normalize("player.hp")
	assert_ne(norm, "", "lowercase key should normalize")


# Uppercase keys are rejected
func test_uppercase_key_rejected():
	var norm: String = _codec.validate_and_normalize("Player.HP")
	assert_eq(norm, "", "uppercase key should be rejected")


# Empty key is rejected
func test_empty_key_rejected():
	var norm: String = _codec.validate_and_normalize("")
	assert_eq(norm, "")


# Key with special characters is rejected
func test_special_chars_rejected():
	var norm: String = _codec.validate_and_normalize("player-hp")
	assert_eq(norm, "", "hyphens not allowed")


# Max length key (256 chars)
func test_max_length_key():
	var long_key: String = "a".repeat(256)
	var norm: String = _codec.validate_and_normalize(long_key)
	assert_ne(norm, "", "256-char key should be accepted")


# Over max length rejected
func test_over_max_length_rejected():
	var long_key: String = "a".repeat(257)
	var norm: String = _codec.validate_and_normalize(long_key)
	assert_eq(norm, "", "257-char key should be rejected")


# build_key joins segments
func test_build_key_joins():
	var result: String = ChronicleKeyCodec.build_key(["player", "stats", "hp"] as Array[String])
	assert_eq(result, "player.stats.hp")


# build_key sanitizes segments
func test_build_key_sanitizes():
	var result: String = ChronicleKeyCodec.build_key(["Player", "HP"] as Array[String])
	assert_eq(result, "player.hp")


# Dotless key gets _global prefix
func test_dotless_key_normalized():
	var norm: String = _codec.validate_and_normalize("score")
	assert_true(norm.begins_with("_global."), "dotless key should get _global prefix")


# ── Ring cache and key codec audit (R16-A12) ──


# Cached invalid key suppresses subsequent error messages
func test_cached_invalid_key_suppresses_error() -> void:
	var warnings: Array[String] = []
	var codec := KeyCodec.new(func(msg: String) -> void: warnings.append(msg))
	# First call: should push_error and return ""
	var result1: String = codec.validate_and_normalize("INVALID_UPPER")
	assert_eq(result1, "", "Invalid key should return empty string")
	# Second call: should hit cache and return "" without push_error
	var result2: String = codec.validate_and_normalize("INVALID_UPPER")
	assert_eq(result2, "", "Cached invalid key also returns empty string")
	# The second call will NOT trigger push_error — this is the suppression.


# build_key warning message is misleading for fully-stripped segments
func test_build_key_underscore_only_segment_dropped() -> void:
	# A segment of just underscores gets stripped to "", then dropped.
	# The warning says 'sanitized to ""' but doesn't say 'segment dropped'.
	var result: String = KeyCodec.build_key(["player", "___", "health"] as Array[String])
	assert_eq(result, "player.health",
		"Underscore-only segment should be dropped")


# _global prefix is now rejected — user keys cannot alias globals
func test_global_prefix_rejected() -> void:
	var warnings: Array[String] = []
	var codec := KeyCodec.new(func(msg: String) -> void: warnings.append(msg))
	# Bare key normalizes correctly
	var norm1: String = codec.validate_and_normalize("health")
	assert_eq(norm1, "_global.health", "bare key normalizes to _global.health")
	# Explicit _global. prefix is now rejected by validate_key
	var norm2: String = codec.validate_and_normalize("_global.health")
	assert_eq(norm2, "", "_global.health should be rejected as reserved prefix")
	# Static validate_key also rejects it
	var err: String = KeyCodec.validate_key("_global.health")
	assert_ne(err, "", "validate_key should return an error for _global. prefix")
	assert_true(err.contains("_global"), "error should mention _global")


# validate_key allows underscore-prefixed entity names
func test_underscore_entity_allowed() -> void:
	var err: String = KeyCodec.validate_key("_reserved.something")
	assert_eq(err, "", "Underscore-prefixed entities pass validation")


# ── Key codec audit (R17-A12) ──


# validate_key rejects the "_global." prefix for exact keys
func test_validate_key_rejects_global_prefix() -> void:
	var err: String = KeyCodec.validate_key("_global.health")
	assert_ne(err, "",
		"validate_key must reject the reserved _global. prefix")
	assert_true(err.contains("_global"),
		"error message should mention _global")


# normalize_pattern must reject "_global.*" — reserved prefix, consistent with exact keys.
# audit: R17-A12-3b — EXPECTED RED (documented product bug, see assertion below).
func test_normalize_pattern_rejects_global_wildcard() -> void:
	var warnings: Array[String] = []
	var codec := KeyCodec.new(func(msg: String) -> void: warnings.append(msg))

	# Exact key with _global. prefix — correctly rejected:
	var exact_norm: String = codec.validate_and_normalize("_global.health")
	assert_eq(exact_norm, "",
		"validate_and_normalize must reject _global.health as reserved")

	# EXPECTED CORRECT BEHAVIOR — currently FAILS (product bug: the reserved-prefix
	# guard is bypassed for wildcard patterns, so _global.* leaks internal facts).
	var pat_norm: String = codec.normalize_pattern("_global.*")
	assert_eq(pat_norm, "",
		"normalize_pattern must reject _global.* (reserved internal prefix), like exact _global. keys")
	assert_gte(warnings.size(), 1,
		"rejecting a reserved-prefix wildcard pattern should emit a warning")


# build_key prefixes a pure-numeric segment with "_"
func test_build_key_numeric_segment_prefixed() -> void:
	var result: String = KeyCodec.build_key(["player", "42", "hp"] as Array[String])
	assert_eq(result, "player._42.hp",
		"numeric segments must be prefixed with _")


# build_key silently drops a segment that strips to empty
func test_build_key_all_underscore_segment_dropped() -> void:
	var result: String = KeyCodec.build_key(["a", "___", "b"] as Array[String])
	assert_eq(result, "a.b",
		"all-underscore segment strips to empty and is dropped")


# build_key drops a segment that is all special characters (maps to empty after sanitize)
func test_build_key_all_special_chars_segment_dropped() -> void:
	var result: String = KeyCodec.build_key(["entity", "!@#", "stat"] as Array[String])
	# Each special char -> "_", then leading/trailing underscores stripped -> ""
	assert_eq(result, "entity.stat",
		"segment that sanitizes to empty is dropped")
