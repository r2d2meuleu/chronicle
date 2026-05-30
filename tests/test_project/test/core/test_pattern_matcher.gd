extends GutTest

const PM := preload("res://addons/chronicle/core/util/pattern_matcher.gd")


var _validate_accepts_valid_params = ParameterFactory.named_parameters(
	["pattern"],
	[
		["player.gold"],
		["player.*"],
		["*"],
		["player.*.boss"],
		["*.killed"],
		["*.*.hp"],
	]
)

func test_validate_accepts_valid(p = use_parameters(_validate_accepts_valid_params)) -> void:
	assert_eq(PM.validate(p.pattern), "", "pattern '%s' should validate (empty error string)" % p.pattern)


var _validate_rejects_invalid_params = ParameterFactory.named_parameters(
	["pattern"],
	[
		[""],
		["player*"],
		["gua*rd.hp"],
	]
)

func test_validate_rejects_invalid(p = use_parameters(_validate_rejects_invalid_params)) -> void:
	assert_gt(PM.validate(p.pattern).length(), 0, "invalid pattern must return a non-empty error")


var _matches_positive_params = ParameterFactory.named_parameters(
	["pattern", "key"],
	[
		["player.gold", "player.gold"],
		["player.*", "player.gold"],
		["player.*", "player.defeated.boss"],
		["player.defeated.*", "player.defeated.boss_swamp"],
		["*", "player.gold"],
		["*", "a"],
		["entity.*", "entity.health"],
	]
)

func test_matches_positive(p = use_parameters(_matches_positive_params)) -> void:
	assert_true(PM.matches(p.pattern, p.key))


var _matches_negative_params = ParameterFactory.named_parameters(
	["pattern", "key"],
	[
		["player.gold", "player.hp"],
		["player.*", "npc.gold"],
		["player.defeated.*", "player.gold"],
		["player.*", "player"],
		["*", ""],
		["player.*", "player."],
		["entity*", "entity_health"],
	]
)

func test_matches_negative(p = use_parameters(_matches_negative_params)) -> void:
	assert_false(PM.matches(p.pattern, p.key))


func test_validate_mid_segment_wildcard() -> void:
	assert_eq(PM.validate("guard.*.alert_level"), "", "mid-segment wildcard should be valid")

func test_validate_leading_wildcard() -> void:
	assert_eq(PM.validate("*.hp"), "", "leading wildcard should be valid")

func test_validate_multi_wildcard() -> void:
	assert_eq(PM.validate("*.*.hp"), "", "multi-wildcard should be valid")

func test_validate_mixed_wildcard_chars_rejected() -> void:
	assert_ne(PM.validate("gua*rd.hp"), "", "mixed wildcard chars in segment should be rejected")

func test_matches_mid_segment() -> void:
	assert_true(PM.matches("guard.*.alert_level", "guard.1.alert_level"))
	assert_true(PM.matches("guard.*.alert_level", "guard.2.alert_level"))
	assert_false(PM.matches("guard.*.alert_level", "guard.1.patrol_route"))
	assert_false(PM.matches("guard.*.alert_level", "player.1.alert_level"))
	assert_false(PM.matches("guard.*.alert_level", "guard.1.sub.alert_level"), "mid-segment * must not cross dot boundary")

func test_matches_leading_wildcard() -> void:
	assert_true(PM.matches("*.hp", "player.hp"))
	assert_true(PM.matches("*.hp", "enemy.hp"))
	assert_false(PM.matches("*.hp", "player.mp"))
	assert_false(PM.matches("*.hp", "player.sub.hp"), "leading * must not cross dot boundary")


func test_validate_rejects_uppercase_in_pattern() -> void:
	assert_ne(PM.validate("Player.*"), "")

func test_validate_rejects_special_chars() -> void:
	assert_ne(PM.validate("player!.*"), "")

func test_validate_accepts_valid_lowercase_pattern() -> void:
	assert_eq(PM.validate("player.stats.*"), "")
	assert_eq(PM.validate("a.*.c"), "")
	assert_eq(PM.validate("*"), "")


# ── Pattern matcher audit (R16-A12) ──


# matches_presplit_segs vs matches disagreement on trailing wildcard
func test_presplit_trailing_wildcard_disagrees_with_matches() -> void:
	var full_result: bool = PM.matches("entity.*", "entity.a.b")
	var presplit_result: bool = PM.matches_presplit_segs(
		PackedStringArray(["entity", "*"]),
		PackedStringArray(["entity", "a", "b"]))
	# BUG: full matches returns true (multi-level), presplit returns false.
	# watch_bus works around this, but the API is inconsistent.
	assert_true(full_result, "matches() treats trailing * as multi-level")
	assert_false(presplit_result, "presplit treats * as single-segment only")
	assert_ne(full_result, presplit_result,
		"The two match functions disagree — API inconsistency")


# PatternMatcher.validate correctly rejects uppercase patterns
func test_pattern_matcher_validate_rejects_uppercase() -> void:
	var err: String = PM.validate("Player.*")
	# CORRECT: Uppercase "P" fails the (c >= "a" and c <= "z") check because
	# GDScript string comparison uses unicode values and "P" (80) < "a" (97).
	assert_ne(err, "",
		"validate() should reject uppercase characters in patterns")


# ── Pattern matcher audit (R17-A12) ──


# matches() trailing wildcard: key equal to the prefix string is rejected
func test_pattern_matches_trailing_wildcard_boundary() -> void:
	# "a.*" prefix = "a.", key "a." length equals prefix length — returns false.
	assert_false(PM.matches("a.*", "a."),
		"key ending with dot should not match trailing wildcard")
	# "a.*" matches any key that starts with "a." and is strictly longer:
	assert_true(PM.matches("a.*", "a.b"),
		"a.b starts with a. and is longer — should match")
	assert_true(PM.matches("a.*", "a.b.c"),
		"multi-level key under a. should match trailing wildcard")
	# "entity.*" must not match "entity" (no dot at all):
	assert_false(PM.matches("entity.*", "entity"),
		"bare entity without segment must not match entity.*")


# ── R23-BUG-3 pattern matcher tests ─────────


# matches() handles trailing wildcard correctly (the full function works)
func test_matches_handles_trailing_wildcard() -> void:
	assert_true(
		PM.matches("player.*", "player.stats.hp"),
		"matches() correctly handles multi-level trailing wildcard")
	assert_true(
		PM.matches("game.*", "game.a.b.c"),
		"matches() handles deep trailing wildcard")
	assert_true(
		PM.matches("game.*", "game.a"),
		"matches() handles single-depth trailing wildcard")


# presplit rejects multi-level trailing wildcard (known limitation)
func test_presplit_rejects_multilevel_trailing_wildcard() -> void:
	var pat_segs: PackedStringArray = "player.*".split(".")
	var key_segs: PackedStringArray = "player.stats.hp".split(".")

	# Known limitation: presplit compares segment counts, so 2 != 3 -> false
	assert_false(
		PM.matches_presplit_segs(pat_segs, key_segs),
		"presplit rejects multi-level trailing wildcard (known limitation, mitigated by WatchBus)")


# presplit works for same-depth trailing wildcard
func test_presplit_same_depth_works() -> void:
	var pat_segs: PackedStringArray = "game.*".split(".")
	var segs_2: PackedStringArray = "game.a".split(".")
	assert_true(
		PM.matches_presplit_segs(pat_segs, segs_2),
		"presplit matches same-depth key (game.a)")


# presplit and matches() disagree on multi-level trailing wildcard
func test_matches_and_presplit_disagree_on_trailing_wildcard() -> void:
	var pattern := "entity.*"
	var key := "entity.component.health"

	var full_result: bool = PM.matches(pattern, key)
	var pat_segs: PackedStringArray = pattern.split(".")
	var key_segs: PackedStringArray = key.split(".")
	var presplit_result: bool = PM.matches_presplit_segs(pat_segs, key_segs)

	# matches() returns true, presplit returns false — this IS the known limitation
	assert_true(full_result, "matches() returns true for trailing wildcard")
	assert_false(presplit_result,
		"presplit returns false for multi-level trailing wildcard (known limitation)")


# Sanity: mid-position wildcard correctly requires same segment count
func test_presplit_mid_wildcard_correct() -> void:
	# "a.*.c" should only match "a.X.c" (exactly one segment for *)
	var pat_segs: PackedStringArray = "a.*.c".split(".")
	var match_segs: PackedStringArray = "a.b.c".split(".")
	var no_match_segs: PackedStringArray = "a.b.d.c".split(".")

	assert_true(
		PM.matches_presplit_segs(pat_segs, match_segs),
		"mid-wildcard a.*.c should match a.b.c")
	assert_false(
		PM.matches_presplit_segs(pat_segs, no_match_segs),
		"mid-wildcard a.*.c should NOT match a.b.d.c (different depth)")
