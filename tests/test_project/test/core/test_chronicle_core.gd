extends ChronicleTestSuite

const ChronicleGameClock := preload("res://addons/chronicle/core/game_clock.gd")
const ChronicleTimeline := preload("res://addons/chronicle/core/timeline.gd")
const ChronicleStore := preload("res://addons/chronicle/core/store.gd")
const BuiltinTypes := preload("res://addons/chronicle/core/serialization/builtin_types.gd")

var _registry: ChronicleTypeRegistry
var _codec: ChronicleTypeCodec
var _null_engine: ChronicleExpressionEngine


func before_each() -> void:
	super.before_each()
	_registry = ChronicleTypeRegistry.new()
	_codec = ChronicleTypeCodec.new(_registry)
	BuiltinTypes.register_all(_registry, _codec)
	_null_engine = ChronicleExpressionEngine.new()


# set_fact + get_fact roundtrip for each supported type
func test_set_get_roundtrip() -> void:
	_chronicle.set_fact("player.alive", true)
	assert_fact("player.alive", true)
	_chronicle.set_fact("player.gold", 42)
	assert_fact("player.gold", 42)
	_chronicle.set_fact("player.speed", 3.14)
	assert_fact("player.speed", 3.14)
	_chronicle.set_fact("player.name", "Hero")
	assert_fact("player.name", "Hero")


# has_fact returns true/false correctly
func test_has_fact() -> void:
	assert_no_fact("player.gold")
	_chronicle.set_fact("player.gold", 100)
	assert_has_fact("player.gold")


# get_fact with default value when key missing
func test_get_fact_default() -> void:
	assert_null(_chronicle.get_fact("missing.key"), "get_fact returns null by default")
	assert_eq(_chronicle.get_fact("missing.key", 999), 999, "get_fact returns custom default")


# erase_fact removes key, has_fact returns false after
func test_erase_fact() -> void:
	_chronicle.set_fact("player.gold", 100)
	assert_fact("player.gold", 100)
	_chronicle.erase_fact("player.gold")
	assert_no_fact("player.gold")


# mark("flag") -> is_marked("flag") returns true
func test_mark_is_marked() -> void:
	_chronicle.set_fact("player.defeated.boss")
	assert_marked("player.defeated.boss")


# erase_fact("flag") -> is_marked("flag") returns false
func test_erase_after_mark() -> void:
	_chronicle.set_fact("player.flag")
	assert_marked("player.flag")
	_chronicle.erase_fact("player.flag")
	assert_not_marked("player.flag")


# increment from zero (key doesn't exist -> initializes to 0 + amount)
func test_increment_from_zero() -> void:
	var result: Variant = _chronicle.increment_fact("player.kills")
	assert_eq(result, 1.0, "increment from zero returns 1")
	assert_fact("player.kills", 1)


# increment from existing int value
func test_increment_existing() -> void:
	_chronicle.set_fact("player.gold", 10)
	var result: Variant = _chronicle.increment_fact("player.gold", 5.0)
	assert_eq(result, 15.0, "increment existing returns 15")
	assert_fact("player.gold", 15)


# increment with float amount (int -> float promotion)
func test_increment_float_promotion() -> void:
	_chronicle.set_fact("player.xp", 10)
	var result: Variant = _chronicle.increment_fact("player.xp", 0.5)
	assert_eq(result, 10.5, "increment float promotion returns 10.5")
	assert_true(_chronicle.get_fact("player.xp") is float, "increment float promotion stores float")


# decrement works correctly
func test_decrement() -> void:
	_chronicle.set_fact("player.hp", 100)
	var result: Variant = _chronicle.increment_fact("player.hp", -25.0)
	assert_eq(result, 75.0, "decrement returns 75")
	assert_fact("player.hp", 75)
	var result2: Variant = _chronicle.increment_fact("player.mana", -1.0)
	assert_eq(result2, -1.0, "decrement from zero returns -1")


# increment on non-numeric value warns and returns null
func test_increment_non_numeric() -> void:
	_chronicle.set_fact("player.name", "Hero")
	var result: Variant = _chronicle.increment_fact("player.name")
	assert_eq(result, null, "increment non-numeric returns null")
	assert_fact("player.name", "Hero")


# Empty key rejected
func test_empty_key_rejected() -> void:
	_chronicle.set_fact("", 42)
	assert_no_fact("")


# Key with * rejected
func test_wildcard_in_key_rejected() -> void:
	_chronicle.set_fact("player.*", true)
	assert_no_fact("player.*")


# Parameterized: invalid key characters rejected
var _invalid_key_rejected_params = ParameterFactory.named_parameters(
	["key"],
	[["player gold"], ["player@gold"], ["player#gold"], ["player$gold"], ["player-gold"]]
)
func test_invalid_key_rejected(p = use_parameters(_invalid_key_rejected_params)) -> void:
	_chronicle.set_fact(p.key, 10)
	assert_no_fact(p.key)


# Valid key characters still accepted
func test_valid_key_characters_accepted() -> void:
	_chronicle.set_fact("player.gold_99", 10)
	assert_has_fact("player.gold_99")


# Invalid Variant type rejected with push_warning
func test_invalid_variant_type() -> void:
	_chronicle.set_fact("player.pos", autofree(Node.new()))
	assert_no_fact("player.pos")


# Dotless key normalization
func test_dotless_key_normalization() -> void:
	_chronicle.set_fact("flag", true)
	assert_fact("flag", true)


# Dotless key: _global. prefix is reserved and rejected by validation.
# Users must use the bare key form (e.g. "game_started" not "_global.game_started").
func test_dotless_key_rejects_global_prefix() -> void:
	_chronicle.set_fact("game_started", true)
	assert_fact("game_started", true)
	# _global. prefix is now rejected — set_fact and get_fact will not resolve it.
	assert_no_fact("_global.game_started")


# build_key() sanitizer — parameterized
var _build_key_params = ParameterFactory.named_parameters(
	["segments", "expected"],
	[
		[["player", "gold"], "player.gold"],
		[["player", "killed", "Dr.Evil"], "player.killed.dr_evil"],
		[["player", "has item"], "player.has_item"],
		[["Player", "GOLD"], "player.gold"],
		[["zone", "42"], "zone._42"],
		[["player", "__speed__"], "player.speed"],
		[["player", "", "gold"], "player.gold"],
		[["flag"], "flag"],
		[[], ""],
	]
)
func test_build_key(p = use_parameters(_build_key_params)) -> void:
	var segs: Array[String] = []
	for s: Variant in p.segments:
		segs.append(str(s))
	assert_eq(Chronicle.build_key(segs), p.expected)


# clear() wipes everything
func test_clear() -> void:
	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.hp", 50)
	_chronicle.set_fact("game_started")
	assert_fact("player.gold", 100)
	_chronicle.clear()
	assert_no_fact("player.gold")
	assert_no_fact("player.hp")
	assert_not_marked("game_started")


# set_game_time and game_time roundtrip
func test_set_game_time_basic() -> void:
	assert_game_time(0.0)
	set_time(5.0)
	assert_game_time(5.0)
	set_time(10.0)
	assert_game_time(10.0)


# advance_game_time adds to current clock
func test_advance_game_time_basic() -> void:
	advance_time(3.0)
	assert_game_time(3.0)
	advance_time(2.5)
	assert_game_time(5.5)


# set_game_time rejects backward time (monotonic constraint)
func test_set_game_time_rejects_backward() -> void:
	set_time(10.0)
	set_time(5.0)
	assert_game_time(10.0)


# set_game_time rejects negative values
func test_set_game_time_rejects_negative() -> void:
	set_time(-1.0)
	assert_game_time(0.0)


# advance_game_time rejects negative delta
func test_advance_game_time_rejects_negative() -> void:
	set_time(5.0)
	advance_time(-1.0)
	assert_game_time(5.0)


# set_game_time rejects NaN and INF
func test_set_game_time_rejects_nan_inf() -> void:
	set_time(5.0)
	_chronicle.set_game_time(NAN)
	assert_game_time(5.0)
	_chronicle.set_game_time(INF)
	assert_game_time(5.0)


# advance_game_time zero delta is silent no-op
func test_advance_game_time_zero_noop() -> void:
	set_time(5.0)
	advance_time(0.0)
	assert_game_time(5.0)


# set_game_time stamps timeline entries correctly
func test_set_game_time_stamps_timeline() -> void:
	set_time(3.0)
	_chronicle.set_fact("player.gold", 10)
	set_time(7.0)
	_chronicle.set_fact("player.gold", 20)
	assert_history("player.gold", [10, 20], [3.0, 7.0])


# clear() resets game clock to 0.0
func test_clear_resets_game_time() -> void:
	set_time(100.0)
	assert_game_time(100.0)
	_chronicle.clear()
	assert_game_time(0.0)


# Transient flag: set_fact("temp", 1, true) marks it transient
func test_transient_flag() -> void:
	_chronicle.set_fact("player.temp", 1, true, 0.0)
	assert_fact("player.temp", 1)
	var data: Dictionary = _chronicle.serialize()
	assert_does_not_have(data["facts"], "player.temp", "transient key excluded from serialize")


# Timeline grows with each set_fact
func test_timeline_grows() -> void:
	var initial_size: int = _chronicle.get_stats().timeline_size
	_chronicle.set_fact("player.gold", 10)
	_chronicle.set_fact("player.gold", 20)
	_chronicle.set_fact("player.hp", 100)
	var final_size: int = _chronicle.get_stats().timeline_size
	assert_eq(final_size, initial_size + 3, "timeline grows by 3 after 3 set_fact calls")

	var last: Variant = _chronicle.get_last_change("*")
	assert_not_null(last)
	assert_has(last, "key", "timeline entry has key")
	assert_has(last, "value", "timeline entry has value")
	assert_has(last, "time", "timeline entry has time")


# Array and Dictionary values accepted
func test_array_dict_values() -> void:
	_chronicle.set_fact("player.inventory", [1, 2, 3])
	assert_fact("player.inventory", [1, 2, 3])
	_chronicle.set_fact("player.stats", {"hp": 100, "mp": 50})
	assert_fact("player.stats", {"hp": 100, "mp": 50})

# get_stats on empty chronicle
func test_get_stats_empty() -> void:
	var stats: Dictionary = _chronicle.get_stats()
	assert_eq(stats.fact_count, 0)
	assert_eq(stats.watcher_count, 0)

# get_stats with facts and watchers
func test_get_stats_with_facts_and_watchers() -> void:
	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.hp", 50)
	_chronicle.set_fact("flag", true)
	_chronicle.watch("player.gold", func(_k, _v, _o): pass)
	_chronicle.watch("player.*", func(_k, _v, _o): pass)
	_chronicle.get_fact_keys("player.*")
	_chronicle.count_facts("*")

	var stats: Dictionary = _chronicle.get_stats()
	assert_eq(stats.fact_count, 3)
	assert_eq(stats.watcher_count, 2)
	assert_does_not_have(stats, "facts", "get_stats should not include facts dictionary")

# get_stats() convenience — fact_count and watcher_count
func test_get_fact_count_and_watcher_count() -> void:
	_chronicle.set_fact("a", 1)
	_chronicle.set_fact("b", 2)
	_chronicle.watch("a", func(_k, _v, _o): pass)
	assert_eq(_chronicle.get_stats().fact_count, 2)
	assert_watcher_count(1)

# is_marked returns true only for literal boolean true
func test_is_marked_strict() -> void:
	_chronicle.set_fact("zero_int", 0)
	assert_not_marked("zero_int")
	_chronicle.set_fact("zero_float", 0.0)
	assert_not_marked("zero_float")
	_chronicle.set_fact("empty_string", "")
	assert_not_marked("empty_string")
	_chronicle.set_fact("bool_false", false)
	assert_not_marked("bool_false")
	_chronicle.set_fact("truthy_int", 1)
	assert_marked("truthy_int")
	_chronicle.set_fact("truthy_string", "hello")
	assert_marked("truthy_string")
	_chronicle.set_fact("bool_true")
	assert_marked("bool_true")

# fact_changed signal emitted on set_fact
func test_fact_changed_signal() -> void:
	var events := collect_signal(_chronicle, "fact_changed")
	_chronicle.set_fact("player.gold", 100)
	events.assert_count(1)
	events.assert_event(0, "player.gold", 100, null)

# erase nonexistent key is no-op
func test_erase_nonexistent_key_is_noop() -> void:
	var changes_before: int = _chronicle.get_changes_since(0.0).size()
	_chronicle.erase_fact("never.existed")
	assert_no_fact("never.existed")
	assert_eq(_chronicle.get_changes_since(0.0).size(), changes_before)

# increment on existing float value
func test_increment_on_existing_float() -> void:
	_chronicle.set_fact("player.speed", 2.5)
	var result: Variant = _chronicle.increment_fact("player.speed", 1.0)
	assert_eq(result, 3.5)
	assert_fact("player.speed", 3.5)
	assert_true(_chronicle.get_fact("player.speed") is float)

# advance_game_time rejects NaN and INF
func test_advance_game_time_rejects_nan_inf() -> void:
	set_time(5.0)
	advance_time(NAN)
	assert_game_time(5.0)
	advance_time(INF)
	assert_game_time(5.0)

# set_game_time does not disable auto-advance
func test_set_game_time_preserves_auto_advance() -> void:
	assert_true(_chronicle.is_auto_advancing())
	_chronicle.set_game_time(5.0)
	assert_true(_chronicle.is_auto_advancing(), "set_game_time should not disable auto-advance")
	assert_game_time(5.0)

# advance_game_time does not disable auto-advance
func test_advance_game_time_preserves_auto_advance() -> void:
	assert_true(_chronicle.is_auto_advancing())
	_chronicle.advance_game_time(3.0)
	assert_true(_chronicle.is_auto_advancing(), "advance_game_time should not disable auto-advance")
	assert_game_time(3.0)

# clear resets auto-advance to enabled
func test_clear_resets_auto_advance() -> void:
	_chronicle.set_auto_advancing(false)
	assert_false(_chronicle.is_auto_advancing())
	_chronicle.clear()
	assert_true(_chronicle.is_auto_advancing())

# re-enable auto-advance after manual disable
func test_re_enable_auto_advance() -> void:
	_chronicle.set_auto_advancing(false)
	assert_false(_chronicle.is_auto_advancing())
	_chronicle.set_auto_advancing(true)
	assert_true(_chronicle.is_auto_advancing())

# ChronicleGameClock.advance is a simple addition — validation is caller's responsibility
func test_clock_advance_is_simple_addition() -> void:
	var clock := ChronicleGameClock.new()
	clock.advance(5.0)
	clock.advance(3.0)
	assert_eq(clock.get_time(), 8.0, "advance() adds delta directly")

# advance_game_time (facade) still rejects negative delta — guard lives in the facade
func test_facade_advance_rejects_negative_delta() -> void:
	_chronicle.set_auto_advancing(false)
	_chronicle.set_game_time(5.0)
	_chronicle.advance_game_time(-1.0)
	assert_game_time(5.0)

# advance_game_time (facade) still rejects NaN/INF delta
func test_facade_advance_rejects_nan_inf() -> void:
	_chronicle.set_auto_advancing(false)
	_chronicle.set_game_time(5.0)
	_chronicle.advance_game_time(NAN)
	assert_game_time(5.0)
	_chronicle.advance_game_time(INF)
	assert_game_time(5.0)

# fact_changed fires on erase_fact with null value and correct old_value
func test_fact_changed_signal_on_erase() -> void:
	_chronicle.set_fact("player.gold", 100)
	var col := collect_signal(_chronicle, "fact_changed")
	_chronicle.erase_fact("player.gold")
	col.assert_count(1)
	col.assert_event(0, "player.gold", null, 100)

# set_game_time(current_value) is a no-op — does not change clock or auto-advance
func test_set_game_time_same_value_is_noop() -> void:
	assert_game_time(0.0)
	assert_true(_chronicle.is_auto_advancing())
	_chronicle.set_game_time(0.0)
	assert_true(_chronicle.is_auto_advancing(), "set_game_time with current value should not change auto-advance")
	assert_game_time(0.0)


# KEEP_LIFETIME preserves existing expiry when overwriting a fact
func test_set_fact_with_keep_lifetime_preserves_expiry() -> void:
	_chronicle.set_fact("temp", 1, false, 5.0)
	assert_has_expiry("temp")
	_chronicle.set_fact("temp", 2, false, _chronicle.KEEP_LIFETIME)
	assert_has_expiry("temp")
	assert_fact("temp", 2)


# KEEP_LIFETIME on a non-expiring fact does not add an expiry
func test_set_fact_with_keep_lifetime_no_expiry_stays_none() -> void:
	_chronicle.set_fact("perm", 1)
	assert_no_expiry("perm")
	_chronicle.set_fact("perm", 2, false, _chronicle.KEEP_LIFETIME)
	assert_no_expiry("perm")
	assert_fact("perm", 2)


# register_type rejects invalid pack/unpack Callables
func test_register_type_rejects_invalid_callables() -> void:
	var result: bool = _chronicle.register_type(9999, "bad_type", Callable(), Callable())
	assert_false(result, "register_type should reject invalid pack/unpack Callables")
	_chronicle.unregister_type(9999)


# Key length limit: keys over 256 chars are rejected
func test_key_length_limit_rejects_long_keys() -> void:
	var long_key: String = "a".repeat(257)
	_chronicle.set_fact(long_key, 1)
	assert_no_fact(long_key)


# Key length limit: keys of exactly 256 chars are accepted
func test_key_length_limit_accepts_max_length() -> void:
	var key: String = "a".repeat(256)
	_chronicle.set_fact(key, 1)
	assert_fact(key, 1)


func test_clamp_fact_preserves_expiry() -> void:
	_chronicle.set_fact("hp", 150.0, false, 3.0)
	assert_has_expiry("hp")
	_chronicle.clamp_fact("hp", 0.0, 100.0)
	assert_fact("hp", 100.0)
	assert_has_expiry("hp")


func test_clamp_fact_rejects_inverted_range() -> void:
	_chronicle.set_fact("hp", 50.0)
	_chronicle.clamp_fact("hp", 100.0, 0.0)
	assert_fact("hp", 50.0)


func test_fact_changed_fires_on_erase() -> void:
	_chronicle.set_fact("x", 1)
	var col := collect_signal(_chronicle, "fact_changed")
	_chronicle.erase_fact("x")
	col.assert_count(1)
	col.assert_event(0, "x", null, 1)


func test_fact_changed_null_fires_on_expiry() -> void:
	_chronicle.set_fact("temp", 1, false, 0.5)
	var expired_fired: Array = [false]
	_chronicle.fact_expired.connect(func(_k: String, _v: Variant) -> void: expired_fired[0] = true)
	set_time(0.0)
	advance_time(1.0)
	assert_no_fact("temp")
	assert_true(expired_fired[0], "fact_expired fires on expiry")


# toggle_fact marks when absent
func test_toggle_fact_marks_when_absent() -> void:
	var result: Variant = _chronicle.toggle_fact("toggle.flag")
	assert_true(result)
	assert_marked("toggle.flag")


# toggle_fact sets false when present (fact persists as false, not erased)
func test_toggle_fact_sets_false_when_present() -> void:
	_chronicle.set_fact("toggle.flag")
	var result: Variant = _chronicle.toggle_fact("toggle.flag")
	assert_false(result)
	assert_not_marked("toggle.flag")
	assert_has_fact("toggle.flag")
	assert_fact("toggle.flag", false)


# Sentinel string is storable as a fact value (no collision with erase sentinel)
func test_sentinel_string_is_storable_as_value() -> void:
	_chronicle.set_fact("test.key", "__chronicle_erased__")
	assert_fact("test.key", "__chronicle_erased__")


# is_truthy — null is false
func test_is_truthy_null_false() -> void:
	assert_false(ChronicleValueUtils.is_truthy(null))


# is_truthy — bool passes through
func test_is_truthy_bool() -> void:
	assert_true(ChronicleValueUtils.is_truthy(true))
	assert_false(ChronicleValueUtils.is_truthy(false))


# is_truthy — zero is false, non-zero is true
func test_is_truthy_numbers() -> void:
	assert_true(ChronicleValueUtils.is_truthy(1))
	assert_true(ChronicleValueUtils.is_truthy(0.5))
	assert_false(ChronicleValueUtils.is_truthy(0))
	assert_false(ChronicleValueUtils.is_truthy(0.0))
	assert_false(ChronicleValueUtils.is_truthy(NAN), "NaN should be falsy")


# is_truthy — empty string is false
func test_is_truthy_string() -> void:
	assert_true(ChronicleValueUtils.is_truthy("hello"))
	assert_false(ChronicleValueUtils.is_truthy(""))


# Mid-segment wildcard: get_fact_keys returns matching keys
func test_mid_segment_wildcard_get_fact_keys() -> void:
	_chronicle.set_fact("guard.1.alert_level", 0.5)
	_chronicle.set_fact("guard.2.alert_level", 0.8)
	_chronicle.set_fact("guard.1.patrol_route", "north")
	var keys: Array[String] = _chronicle.get_fact_keys("guard.*.alert_level")
	assert_eq(keys.size(), 2, "should find 2 alert_level keys")
	assert_has(keys, "guard.1.alert_level")
	assert_has(keys, "guard.2.alert_level")


# Mid-segment wildcard: watch fires only on matching keys
func test_mid_segment_wildcard_watch() -> void:
	var events := watch_events("npc.*.relationship")
	_chronicle.set_fact("npc.alice.relationship", 5)
	_chronicle.set_fact("npc.alice.dialogue", "hello")
	_chronicle.set_fact("npc.bob.relationship", 3)
	events.assert_count(2)
	events.assert_keys(["npc.alice.relationship", "npc.bob.relationship"])


# evaluate() returns bool for valid expression
func test_evaluate_returns_bool():
	_chronicle.set_fact("flag", true)
	var result: bool = _chronicle.evaluate("flag")
	assert_true(result)


# evaluate() returns null on parse error
func test_evaluate_returns_null_on_error():
	var result: Variant = _chronicle.evaluate("AND OR NOT")
	assert_null(result)


# set_expiry adds expiry to existing fact
func test_set_expiry_standalone():
	_chronicle.set_fact("buff", true)
	assert_no_expiry("buff")
	_chronicle.set_expiry("buff", 5.0)
	assert_has_expiry("buff")


# is_transient returns correct state
func test_is_transient():
	_chronicle.set_fact("temp", true, true, 0.0)
	assert_transient("temp")
	_chronicle.set_fact("perm", true)
	assert_not_transient("perm")


# get_facts returns matching facts
func test_get_facts_pattern():
	_chronicle.set_fact("player.hp", 100)
	_chronicle.set_fact("player.mp", 50)
	_chronicle.set_fact("enemy.hp", 80)
	var result: Dictionary = _chronicle.get_facts("player.*")
	assert_eq(result.size(), 2)
	assert_eq(result["player.hp"], 100)
	assert_eq(result["player.mp"], 50)


# fact_changed signal carries erase_source
func test_fact_changed_erase_source():
	var sources: Array = []
	_chronicle.fact_changed.connect(func(_k, _v, _o, s): sources.append(s))
	_chronicle.set_fact("a", 1)
	assert_eq(sources[0], Chronicle.EraseSource.USER)
	_chronicle.erase_fact("a")
	assert_eq(sources[1], Chronicle.EraseSource.USER)


# toggle_fact sets false instead of erasing
func test_toggle_sets_false():
	_chronicle.set_fact("flag")
	_chronicle.toggle_fact("flag")
	assert_fact("flag", false)


# erase_fact returns true when fact existed
func test_erase_fact_returns_true_when_existed() -> void:
	_chronicle.set_fact("x", 1)
	assert_true(_chronicle.erase_fact("x"))


# erase_fact returns false when fact was absent
func test_erase_fact_returns_false_when_absent() -> void:
	assert_false(_chronicle.erase_fact("ghost"))


# toggle_fact with lifetime sets expiry
func test_toggle_fact_with_lifetime_sets_expiry() -> void:
	_chronicle.toggle_fact("flag", false, 10.0)
	assert_fact("flag", true)
	assert_has_expiry("flag")


# clear_warnings resets dedup
func test_clear_warnings_resets_dedup() -> void:
	# increment_fact on a non-numeric fact routes a warning through the live
	# Chronicle's ChronicleWarningBus (write_coordinator.gd ~508). The bus dedups
	# by message, so its _dedup dict is the closest test-observable proxy for
	# "the warning fired vs was suppressed".
	_chronicle.set_fact("name", "hello")
	var dedup: Dictionary = _chronicle._warnings._dedup

	# First non-numeric increment records the warning in the dedup dict.
	_chronicle.increment_fact("name", 1.0)
	assert_eq(dedup.size(), 1, "first non-numeric increment records one warning")

	# Identical op is suppressed: dedup short-circuits, so no new entry is added.
	_chronicle.increment_fact("name", 1.0)
	assert_eq(dedup.size(), 1, "duplicate warning is suppressed (dedup), not re-recorded")

	# clear_warnings() resets dedup so the same warning can fire again.
	_chronicle.clear_warnings()
	assert_eq(dedup.size(), 0, "clear_warnings() empties the dedup dict")

	_chronicle.increment_fact("name", 1.0)
	assert_eq(dedup.size(), 1, "after clear_warnings(), the warning fires (and dedups) again")


# ── Facade behavior ──


# NaN should not disable auto-advance
func test_set_game_time_nan_should_not_disable_auto_advance() -> void:
	assert_true(_chronicle.is_auto_advancing(),
		"auto-advance should be enabled initially")

	_chronicle.set_game_time(NAN)

	# CORRECT: auto-advance should still be enabled because the time was invalid
	assert_true(_chronicle.is_auto_advancing(),
		"auto-advance should remain enabled after set_game_time(NaN)")


# INF should not disable auto-advance
func test_set_game_time_inf_should_not_disable_auto_advance() -> void:
	assert_true(_chronicle.is_auto_advancing(),
		"auto-advance should be enabled initially")

	_chronicle.set_game_time(INF)

	# CORRECT: auto-advance should still be enabled because the time was invalid
	assert_true(_chronicle.is_auto_advancing(),
		"auto-advance should remain enabled after set_game_time(INF)")


# set_game_time should explicitly reject NaN before doing anything
func test_set_game_time_nan_should_not_flush_expiry() -> void:
	_chronicle.set_fact("temp", "value", false, 1.0)
	advance_time(0.5)
	assert_has_expiry("temp")

	# NaN should be a no-op -- no side effects at all
	_chronicle.set_game_time(NAN)

	# The fact should still exist with its expiry intact
	assert_has_fact("temp")


# clear does not crash when state_reset handler writes
func test_clear_does_not_crash_when_state_reset_handler_writes() -> void:
	_chronicle.set_fact("a", 1)
	var wrote: Array[bool] = [false]

	_chronicle.state_reset.connect(func() -> void:
		# Writes during state_reset from clear() should be deferred
		_chronicle.set_fact("b", 2)
		wrote[0] = true
	)

	_chronicle.clear()
	assert_true(wrote[0], "state_reset handler should have fired")
	# The deferred write from state_reset handler should have been drained
	assert_has_fact("b")


# ── Facade edge cases ──


# set_pattern_matcher(force=true) clears watchers and calls _update_processing
func test_set_pattern_matcher_force_leaves_processing_stale() -> void:
	_chronicle.set_auto_advancing(false)
	_chronicle.watch("some.key", func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	assert_true(_chronicle.is_processing(), "processing should be ON with active watcher")

	_chronicle.set_pattern_matcher(
		func(pattern: String, key: String) -> bool: return pattern == key,
		func(pattern: String) -> String: return "",
		true
	)
	# After force-clearing watchers with auto-advance off, processing should be OFF
	var stats: Dictionary = _chronicle.get_stats()
	assert_eq(stats.watcher_count, 0, "watchers should be cleared by force=true")
	assert_false(_chronicle.is_processing(),
		"processing should be OFF after set_pattern_matcher(force=true) clears all watchers")

	# Restore the default pattern matcher to avoid poisoning later tests
	_chronicle.set_pattern_matcher(
		ChroniclePatternMatcher.matches,
		ChroniclePatternMatcher.validate,
		true
	)


# advance_game_time(0.0) is a silent no-op — does not disable auto-advance
func test_advance_game_time_zero_does_not_disable_auto_advance() -> void:
	assert_true(_chronicle.is_auto_advancing(), "auto-advance starts enabled")
	_chronicle.advance_game_time(0.0)
	assert_true(_chronicle.is_auto_advancing(),
		"advance_game_time(0.0) should NOT disable auto-advance (silent no-op)")


# set_game_time(current_time) is a no-op — does not disable auto-advance
func test_set_game_time_to_current_does_not_disable_auto_advance() -> void:
	assert_true(_chronicle.is_auto_advancing(), "auto-advance starts enabled")
	var t: float = _chronicle.get_game_time()
	_chronicle.set_game_time(t)
	assert_true(_chronicle.is_auto_advancing(),
		"set_game_time(current_time) is a no-op — auto-advance unchanged")


# rollback_steps(-1) returns error result, doesn't crash
func test_rollback_steps_negative_returns_error() -> void:
	var result: Chronicle.RollbackResult = _chronicle.rollback_steps(-1)
	assert_rollback_rejected(result)
	assert_eq(result.requested, -1, "requested should reflect the input")
	assert_eq(result.steps_reverted, 0, "no steps should be reverted")


# erase_fact returns false for nonexistent key
func test_erase_fact_nonexistent_returns_false() -> void:
	var result: bool = _chronicle.erase_fact("never.existed")
	assert_false(result, "erasing nonexistent fact should return false")


# erase_facts empty array returns 0
func test_erase_facts_empty_returns_zero() -> void:
	var result: int = _chronicle.erase_facts([] as Array[String])
	assert_eq(result, 0, "erasing empty array should return 0")


# set_facts with empty dict is a no-op
func test_set_facts_empty_dict_noop() -> void:
	var events := watch_events("*")
	_chronicle.set_facts({})
	events.assert_count(0)


# clear() during mutation is blocked and doesn't corrupt state
func test_clear_blocked_during_watcher_callback() -> void:
	var clear_called: Array = [false]
	_chronicle.watch("trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.clear()
		clear_called[0] = true
	)
	_chronicle.set_fact("trigger", true)
	assert_true(clear_called[0], "watcher callback should have been invoked")
	# clear() was called during mutation — it should have been rejected
	assert_fact("trigger", true)


# deserialize during mutation is blocked
func test_deserialize_blocked_during_mutation() -> void:
	var deser_result: Array = [true]
	_chronicle.watch("trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		deser_result[0] = _chronicle.deserialize({"version": 2, "facts": {}, "timeline": [], "expiry": {}, "game_time": 0.0, "tick": 0, "auto_advance": true})
	)
	_chronicle.set_fact("trigger", true)
	assert_false(deser_result[0], "deserialize during mutation should return false")
	assert_fact("trigger", true)


# validate_pattern returns empty string for valid exact key
func test_validate_pattern_valid_exact_key() -> void:
	var err: String = _chronicle.validate_pattern("player.health")
	assert_eq(err, "", "valid exact key should return empty error string")


# validate_pattern returns empty string for valid glob pattern
func test_validate_pattern_valid_glob() -> void:
	var err: String = _chronicle.validate_pattern("player.*")
	assert_eq(err, "", "valid glob pattern should return empty error string")


# validate_pattern returns error for invalid pattern
func test_validate_pattern_invalid() -> void:
	var err: String = _chronicle.validate_pattern("")
	assert_gt(err.length(), 0, "empty pattern should return non-empty error")


# get_stats returns all documented keys
func test_get_stats_has_all_keys() -> void:
	var stats: Dictionary = _chronicle.get_stats()
	assert_has(stats, "fact_count", "stats should have fact_count")
	assert_has(stats, "watcher_count", "stats should have watcher_count")
	assert_has(stats, "timeline_size", "stats should have timeline_size")
	assert_has(stats, "timeline_cap", "stats should have timeline_cap")
	assert_has(stats, "expiry_count", "stats should have expiry_count")


# watch with empty pattern returns -1
func test_watch_empty_pattern_returns_invalid() -> void:
	var id: int = _chronicle.watch("", func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	assert_eq(id, -1, "empty pattern watch should return -1")


# watch_any with empty patterns array returns -1
func test_watch_any_empty_patterns_returns_invalid() -> void:
	var id: int = _chronicle.watch_any([] as Array[String], func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	assert_eq(id, -1, "empty patterns array should return -1")


# RollbackResult default state
func test_rollback_result_defaults() -> void:
	var r := Chronicle.RollbackResult.new()
	assert_rollback_rejected(r)
	assert_false(r.partial, "default partial should be false")
	assert_eq(r.steps_reverted, 0, "default steps_reverted should be 0")
	assert_eq(r.requested, 0, "default requested should be 0")
	assert_eq(r.error, "", "default error should be empty")


# Serialize with SERIALIZE_USE_SETTING (0) uses project setting cap
func test_serialize_use_setting_constant() -> void:
	_chronicle.set_fact("a", 1)
	var data: Dictionary = _chronicle.serialize(Chronicle.SERIALIZE_USE_SETTING)
	assert_has(data, "facts", "serialized data should have facts")
	assert_has(data, "timeline", "serialized data should have timeline")


# clear_expiry is shorthand for set_expiry(key, 0.0)
func test_clear_expiry_removes_timer() -> void:
	set_time(1.0)
	_chronicle.set_fact("temp", "val", false, 10.0)
	assert_has_expiry("temp")
	assert_true(_chronicle.clear_expiry("temp"), "clear_expiry returns true when an active expiry is cleared")
	assert_no_expiry("temp")
	assert_fact("temp", "val")


# ── Error handling ──


# increment_fact with NaN amount returns null and does not create fact
func test_increment_nan_amount_returns_null() -> void:
	var result: Variant = _chronicle.increment_fact("counter", NAN)
	assert_null(result, "NaN amount should return null")
	assert_no_fact("counter")


# increment_fact with INF amount returns null
func test_increment_inf_amount_returns_null() -> void:
	_chronicle.set_fact("counter", 10)
	var result: Variant = _chronicle.increment_fact("counter", INF)
	assert_null(result, "INF amount should return null")
	assert_fact("counter", 10)  # original value unchanged


# clamp_fact with NaN min returns null
func test_clamp_nan_min_returns_null() -> void:
	_chronicle.set_fact("health", 50)
	var result: Variant = _chronicle.clamp_fact("health", NAN, 100.0)
	assert_null(result, "NaN min should return null")
	assert_fact("health", 50)


# clamp_fact with inverted bounds returns null
func test_clamp_inverted_bounds_returns_null() -> void:
	_chronicle.set_fact("health", 50)
	var result: Variant = _chronicle.clamp_fact("health", 100.0, 10.0)
	assert_null(result, "min > max should return null")
	assert_fact("health", 50)


# set_fact with null value warns and erases
func test_set_fact_null_erases_with_warning() -> void:
	_chronicle.set_fact("to_erase", 42)
	assert_fact("to_erase", 42)
	# set_fact(key, null) should erase the fact
	_chronicle.set_fact("to_erase", null)
	assert_no_fact("to_erase")


# toggle missing key creates it as true
func test_toggle_missing_creates_as_true() -> void:
	var result: Variant = _chronicle.toggle_fact("flag")
	assert_eq(result, true, "toggling missing key should return true")
	assert_fact("flag", true)


# toggle true key sets to false (not erase)
func test_toggle_true_sets_false() -> void:
	_chronicle.set_fact("flag", true)
	var result: Variant = _chronicle.toggle_fact("flag")
	assert_eq(result, false, "toggling true should return false")
	assert_fact("flag", false)  # fact still exists, just false


# set_fact with empty key is rejected
func test_set_fact_empty_key_rejected() -> void:
	_chronicle.set_fact("", 42)
	assert_fact_count("*", 0)


# get_fact with empty key returns default
func test_get_fact_empty_key_returns_default() -> void:
	var result: Variant = _chronicle.get_fact("", "fallback")
	assert_eq(result, "fallback", "empty key should return default")


# has_fact with empty key returns false
func test_has_fact_empty_key_returns_false() -> void:
	assert_no_fact("")


# Uppercase key is rejected
func test_uppercase_dotted_key_rejected() -> void:
	_chronicle.set_fact("Player.HP", 100)
	assert_no_fact("Player.HP")


# Wildcard in key is rejected
func test_set_fact_wildcard_key_rejected() -> void:
	_chronicle.set_fact("player.*", 100)
	assert_no_fact("player.*")


# set_expiry on missing fact returns false
func test_set_expiry_missing_fact_returns_false() -> void:
	var result: bool = _chronicle.set_expiry("nonexistent", 5.0)
	assert_false(result, "set_expiry on missing key should return false")


# set_expiry with negative lifetime is rejected
func test_set_expiry_negative_lifetime_rejected() -> void:
	_chronicle.set_fact("test_key", true)
	var result: bool = _chronicle.set_expiry("test_key", -1.0)
	assert_false(result, "negative lifetime should be rejected")


# set_expiry with NaN lifetime is rejected
func test_set_expiry_nan_lifetime_rejected() -> void:
	_chronicle.set_fact("test_key", true)
	var result: bool = _chronicle.set_expiry("test_key", NAN)
	assert_false(result, "NaN lifetime should be rejected")


# rollback_steps with negative count returns error
func test_rollback_steps_negative_returns_error_result() -> void:
	var result = _chronicle.rollback_steps(-1)
	assert_rollback_rejected(result)


# rollback_steps with zero count is a no-op success
func test_rollback_steps_zero_is_noop() -> void:
	_chronicle.set_fact("a", 1)
	var result = _chronicle.rollback_steps(0)
	assert_rollback_ok(result)
	assert_fact("a", 1)


# rollback_to with NaN time returns error
func test_rollback_to_nan_returns_error() -> void:
	var result = _chronicle.rollback_to(NAN)
	assert_rollback_rejected(result)


# rollback_to with negative time returns error
func test_rollback_to_negative_returns_error() -> void:
	var result = _chronicle.rollback_to(-1.0)
	assert_rollback_rejected(result)


# deserialize with non-Dictionary is rejected
func test_deserialize_non_dict_rejected() -> void:
	# Chronicle.deserialize() now takes Dictionary type — non-dict input is a compile error.
	# Test the internal serializer which still accepts Variant.
	var result: Variant = _chronicle._serializer.deserialize("not a dict")
	assert_null(result, "non-Dictionary input should be rejected")


# deserialize with missing 'facts' key is rejected
func test_deserialize_missing_facts_key_rejected() -> void:
	var result: bool = _chronicle.deserialize({"version": 2})
	assert_false(result, "missing 'facts' key should be rejected")


# deserialize with future version is rejected
func test_deserialize_future_version_rejected() -> void:
	var result: bool = _chronicle.deserialize({"version": 9999, "facts": {}})
	assert_false(result, "future version should be rejected")


# watch with empty pattern returns -1
func test_watch_empty_pattern_returns_negative() -> void:
	var id: int = _chronicle.watch("", func(_k: String, _v: Variant, _o: Variant) -> void: pass)
	assert_eq(id, -1, "empty pattern should return -1")


# unwatch with invalid ID returns false
func test_unwatch_out_of_range_id_returns_false() -> void:
	var result: bool = _chronicle.unwatch(99999)
	assert_false(result, "invalid watch_id should return false")


# advance_game_time with negative delta is ignored
func test_advance_negative_delta_ignored() -> void:
	set_time(10.0)
	advance_time(-5.0)
	assert_game_time(10.0)


# advance_game_time with zero delta is a no-op
func test_advance_zero_delta_noop() -> void:
	set_time(5.0)
	advance_time(0.0)
	assert_game_time(5.0)


# advance_game_time with NaN delta is ignored
func test_advance_nan_delta_ignored() -> void:
	set_time(5.0)
	advance_time(NAN)
	assert_game_time(5.0)


# set_game_time backwards is rejected
func test_set_game_time_backwards_rejected() -> void:
	set_time(10.0)
	_chronicle.set_game_time(5.0)
	assert_game_time(10.0)


# erase_fact on nonexistent key
func test_erase_nonexistent_returns_false() -> void:
	var result: bool = _chronicle.erase_fact("nonexistent")
	assert_false(result, "erasing nonexistent key should return false")


# set_facts with some invalid keys processes valid ones
func test_batch_with_invalid_keys_processes_valid() -> void:
	_chronicle.set_facts({"valid.key": 1, "INVALID": 2, "also.valid": 3})
	assert_fact("valid.key", 1)
	assert_no_fact("INVALID")
	assert_fact("also.valid", 3)


# evaluate with invalid expression returns null
func test_evaluate_invalid_expression_returns_null() -> void:
	var result: Variant = _chronicle.evaluate("AND OR NOT )(")
	assert_null(result, "invalid expression should return null")


# evaluate with empty expression returns null
func test_evaluate_empty_expression_returns_null() -> void:
	var result: Variant = _chronicle.evaluate("")
	assert_null(result, "empty expression should return null")


# set_facts with empty dictionary
func test_set_facts_empty_dict_fires_no_watchers() -> void:
	var events := watch_events("*")
	_chronicle.set_facts({})
	events.assert_count(0)


# erase_facts with empty array
func test_erase_facts_empty_array_returns_zero() -> void:
	var result: int = _chronicle.erase_facts([] as Array[String])
	assert_eq(result, 0, "empty array should return 0")


# clear during watcher dispatch is blocked
func test_clear_during_mutation_blocked() -> void:
	var clear_attempted: Array[bool] = [false]
	_chronicle.watch("trigger", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.clear()
		clear_attempted[0] = true
	)
	_chronicle.set_fact("trigger", true)
	# clear() during mutation is blocked (push_error is emitted and the operation is rejected).
	# The fact should still exist after the dispatch completes.
	assert_true(clear_attempted[0], "watcher should have attempted clear()")
	assert_fact("trigger", true)


# load_file with empty path returns error
func test_load_file_empty_path_returns_error() -> void:
	var result: Error = _chronicle.load_file("")
	assert_eq(result, ERR_FILE_BAD_PATH, "empty path should return ERR_FILE_BAD_PATH")


# save_file with empty path returns error
func test_save_file_empty_path_returns_error() -> void:
	var result: Error = _chronicle.save_file("")
	assert_eq(result, ERR_FILE_BAD_PATH, "empty path should return ERR_FILE_BAD_PATH")


# lifetime 0.0 clears existing expiry
func test_lifetime_zero_clears_expiry() -> void:
	set_time(1.0)
	_chronicle.set_fact("temp", true, false, 10.0)
	assert_has_expiry("temp")
	_chronicle.set_fact("temp", true, false, 0.0)
	assert_no_expiry("temp")


# Deeply nested structure hits copy depth limit without crash
func test_deep_copy_depth_limit() -> void:
	# Build a 70-level deep nested dictionary (beyond the 64 depth limit)
	var deep: Dictionary = {"value": true}
	for i: int in range(70):
		deep = {"nested": deep}
	# is_valid_type rejects data exceeding depth 64 — set_fact fails
	_chronicle.set_fact("deep", deep)
	assert_no_fact("deep")


# rollback_to future time is rejected
func test_rollback_to_future_time_rejected() -> void:
	set_time(5.0)
	_chronicle.set_fact("a", 1)
	var result = _chronicle.rollback_to(100.0)
	assert_rollback_rejected(result)
	assert_fact("a", 1)


# increment on string value returns null
func test_increment_non_numeric_returns_null() -> void:
	_chronicle.set_fact("name", "hello")
	var result: Variant = _chronicle.increment_fact("name", 1.0)
	assert_null(result, "incrementing string should return null")
	assert_fact("name", "hello")  # value unchanged


# clamp on non-numeric value is ignored
func test_clamp_non_numeric_returns_null() -> void:
	_chronicle.set_fact("name", "hello")
	var result: Variant = _chronicle.clamp_fact("name", 0.0, 100.0)
	assert_null(result, "clamping string should return null")
	assert_fact("name", "hello")


# validate_pattern with empty pattern
func test_validate_pattern_empty() -> void:
	var err: String = _chronicle.validate_pattern("")
	assert_ne(err, "", "empty pattern should return error")


# validate_pattern with valid glob
func test_validate_pattern_valid_glob_returns_empty() -> void:
	var err: String = _chronicle.validate_pattern("player.*")
	assert_eq(err, "", "valid glob should return empty string")


# increment on absent key creates at 0 + amount
func test_increment_absent_creates_at_zero() -> void:
	var result: Variant = _chronicle.increment_fact("counter", 5.0)
	assert_eq(result, 5.0, "absent key should start at 0 + amount")
	assert_fact("counter", 5.0)


# decrement on absent key creates at 0 - amount
func test_decrement_absent_creates_negative() -> void:
	var result: Variant = _chronicle.increment_fact("counter", -3.0)
	assert_eq(result, -3.0, "absent key should start at 0 - amount")
	assert_fact("counter", -3.0)


# get_changes_since with negative time returns empty
func test_get_changes_since_negative_returns_empty() -> void:
	_chronicle.set_fact("a", 1)
	var changes: Array[Dictionary] = _chronicle.get_changes_since(-1.0)
	assert_eq(changes.size(), 0, "negative time should return empty")


# get_changes_between with inverted range returns empty
func test_get_changes_between_inverted_returns_empty() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	var changes: Array[Dictionary] = _chronicle.get_changes_between(5.0, 1.0)
	assert_eq(changes.size(), 0, "inverted range should return empty")


# set_fact with Object value is rejected
func test_set_fact_object_type_rejected() -> void:
	var obj := RefCounted.new()
	_chronicle.set_fact("obj", obj)
	assert_no_fact("obj")


# build_key with empty segments
func test_build_key_all_empty_segments() -> void:
	var key: String = Chronicle.build_key(["", "", ""])
	assert_eq(key, "", "all-empty segments should produce empty key")


# build_key with special characters
func test_build_key_special_chars_sanitized() -> void:
	var key: String = Chronicle.build_key(["player", "max-hp"])
	assert_gt(key.length(), 0, "should produce a non-empty key")
	assert_false(key.contains("-"), "hyphens should be sanitized")


# ── Edge cases and boundary conditions ──


# Empty key is silently normalised to "" and rejected by validate_and_normalize.
func test_set_fact_empty_key_no_store() -> void:
	_chronicle.set_fact("", 42)
	assert_no_fact("")
	assert_fact_count("*", 0)


# Derived operations on empty key must also be no-ops.
func test_derived_ops_empty_key() -> void:
	_chronicle.set_fact("")
	_chronicle.toggle_fact("")
	_chronicle.increment_fact("")
	_chronicle.erase_fact("")
	_chronicle.clamp_fact("", 0.0, 10.0)
	assert_fact_count("*", 0)


# Empty dict is an early-return no-op; no watchers, no warnings, no error.
func test_set_facts_empty_dict_no_op() -> void:
	var fired: Array = []
	_chronicle.watch("*", func(_k, _v, _o): fired.append(true))
	_chronicle.set_facts({})
	assert_eq(fired.size(), 0, "no watcher must fire for set_facts({})")
	assert_fact_count("*", 0)


# watch("") must return -1
func test_watch_empty_pattern_returns_minus_one() -> void:
	var id: int = _chronicle.watch("", func(_k, _v, _o): pass)
	assert_eq(id, -1, "watch('') must return -1")


# watch_any([]) must return -1.
func test_watch_any_empty_array_returns_minus_one() -> void:
	var empty_patterns: Array[String] = []
	var id: int = _chronicle.watch_any(empty_patterns, func(_k, _v, _o): pass)
	assert_eq(id, -1, "watch_any([]) must return -1")


# An empty string must return null (parse error).
func test_evaluate_empty_string_returns_null() -> void:
	var result: Variant = _chronicle.evaluate("")
	assert_null(result, "evaluate('') must return null on parse error")


# Whitespace-only expression must also return false.
func test_evaluate_whitespace_only_returns_null() -> void:
	var result: Variant = _chronicle.evaluate("   ")
	assert_null(result, "evaluate('   ') must return null on parse error")


# NAN is a float and IS storable; set_fact must store it.
func test_nan_value_stored() -> void:
	_chronicle.set_fact("x", NAN)
	assert_has_fact("x")
	var v: Variant = _chronicle.get_fact("x")
	assert_true(is_nan(v), "retrieved value must be NAN")


# is_marked on a NAN fact returns false (NAN is falsy).
func test_nan_value_is_not_marked() -> void:
	_chronicle.set_fact("x", NAN)
	assert_false(_chronicle.is_marked("x"), "NAN is falsy, is_marked must return false")


# increment_fact on a NAN-valued fact returns null
func test_increment_nan_fact_returns_null() -> void:
	_chronicle.set_fact("x", NAN)
	var result: Variant = _chronicle.increment_fact("x", 1.0)
	# compute_increment: float(NAN) + 1.0 = NAN, is_nan(result) triggers the guard → returns null
	# increment propagates null
	assert_null(result, "incrementing a NAN fact must return null (overflow/NaN guard)")


# INF float is storable (it is a float, TYPE_FLOAT is in VALID_TYPES).
func test_inf_value_stored() -> void:
	_chronicle.set_fact("x", INF)
	assert_has_fact("x")
	var v: Variant = _chronicle.get_fact("x")
	assert_true(is_inf(v), "retrieved value must be INF")


# increment_fact on INF fact returns null
func test_increment_inf_fact_returns_null() -> void:
	_chronicle.set_fact("x", INF)
	var result: Variant = _chronicle.increment_fact("x", 1.0)
	# float(INF) + 1.0 = INF → is_inf check triggers → compute_increment returns null → increment returns null
	assert_null(result, "incrementing INF must fail with null (overflow guard)")
	# Value must remain unchanged since _write was not called
	var v: Variant = _chronicle.get_fact("x")
	assert_true(is_inf(v), "fact value must remain INF after failed increment")


# increment_fact(key, 0.0) with existing int fact
func test_zero_increment_on_existing_fact() -> void:
	_chronicle.set_fact("counter", 5)
	var fired: Array = []
	_chronicle.watch("counter", func(_k, _v, _o): fired.append(true))
	var result: Variant = _chronicle.increment_fact("counter", 0.0)
	assert_eq(result, 5.0, "zero increment must return current value")
	# _dispatch_and_drain skips dispatch when value == old_value and value != null
	# The write DID happen (5 -> 5), but dispatch_and_drain guards on value==old_value
	assert_eq(fired.size(), 0, "zero increment must not fire watcher (value unchanged)")


# increment_fact(key, NAN) is rejected at the facade level.
func test_nan_increment_rejected() -> void:
	_chronicle.set_fact("x", 1)
	var result: Variant = _chronicle.increment_fact("x", NAN)
	assert_eq(result, null, "NAN increment must return null")
	assert_eq(_chronicle.get_fact("x"), 1, "value must not change after NAN increment")


# increment_fact(key, INF) is rejected at the facade level.
func test_inf_increment_rejected() -> void:
	_chronicle.set_fact("x", 1)
	var result: Variant = _chronicle.increment_fact("x", INF)
	assert_eq(result, null, "INF increment must return null")
	assert_eq(_chronicle.get_fact("x"), 1, "value must not change after INF increment")


# clamp_fact(key, INF, -INF) is caught by is_valid_float checks
func test_clamp_inf_min_neg_inf_max_rejected() -> void:
	_chronicle.set_fact("x", 5)
	_chronicle.clamp_fact("x", INF, -INF)
	assert_eq(_chronicle.get_fact("x"), 5, "clamp with INF bounds must be rejected")


# clamp_fact with inverted valid bounds is rejected
func test_clamp_inverted_valid_bounds_rejected() -> void:
	_chronicle.set_fact("x", 5)
	_chronicle.clamp_fact("x", 10.0, 1.0)
	assert_eq(_chronicle.get_fact("x"), 5, "inverted clamp must not change the value")


# clamp_fact where value is already in range must be a no-op
func test_clamp_already_in_range_no_dispatch() -> void:
	_chronicle.set_fact("x", 5)
	var fired: Array = []
	_chronicle.watch("x", func(_k, _v, _o): fired.append(true))
	_chronicle.clamp_fact("x", 0.0, 10.0)
	# compute_clamp returns null when value is already clamped, so _write is never called
	assert_eq(fired.size(), 0, "clamp of already-clamped value must not fire watcher")
	assert_eq(_chronicle.get_fact("x"), 5, "value must be unchanged")


# Negative lifetime writes the value but without expiry
func test_negative_lifetime_writes_without_expiry() -> void:
	_chronicle.set_fact("x", 1, false, -5.0)
	assert_has_fact("x")
	assert_no_expiry("x")


# set_expiry with negative lifetime is also rejected.
func test_set_expiry_negative_rejected() -> void:
	_chronicle.set_fact("x", 1)
	_chronicle.set_expiry("x", -1.0)
	assert_no_expiry("x")


# Zero lifetime means clear expiry.
func test_zero_lifetime_clears_expiry() -> void:
	_chronicle.set_fact("x", 1, false, 5.0)
	assert_has_expiry("x")
	_chronicle.set_fact("x", 1, false, 0.0)
	assert_no_expiry("x")


# set_expiry with 0.0 also clears expiry.
func test_set_expiry_zero_clears_existing() -> void:
	_chronicle.set_fact("x", 1, false, 5.0)
	_chronicle.set_expiry("x", 0.0)
	assert_no_expiry("x")


# rollback_to(0) when no timeline entries exist is a NO_ACTION
func test_rollback_to_zero_empty_timeline() -> void:
	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)


# rollback_to(0) with entries where FIRST entry is at t=0
func test_rollback_to_zero_after_first_entry_at_zero() -> void:
	# t=0 (default): record a fact — this becomes the "pre-existing" state
	_chronicle.set_fact("a", 99)    # recorded at t=0
	set_time(1.0)
	_chronicle.set_fact("b", 88)    # recorded at t=1
	# rollback_to(0) bisects for entries after t=0 → finds the "b" entry at t=1
	# first_entry.time (0.0) is NOT > target (0.0) → can proceed
	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)
	assert_has_fact("a")
	assert_no_fact("b")


# rollback_to(future_time) is rejected
func test_rollback_to_future_rejected() -> void:
	set_time(1.0)
	var ok = _chronicle.rollback_to(999.0)
	assert_rollback_rejected(ok)
	# State must be unchanged
	assert_game_time(1.0)


# rollback_steps(0) is documented to be a no-op that returns true.
func test_rollback_steps_zero_keeps_state() -> void:
	_chronicle.set_fact("x", 1)
	var result = _chronicle.rollback_steps(0)
	assert_rollback_ok(result)
	assert_fact("x", 1)


# rollback_steps(999999) with only 3 entries performs a partial rollback
func test_rollback_steps_excess_returns_false() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	set_time(3.0)
	_chronicle.set_fact("c", 3)
	var result = _chronicle.rollback_steps(999999)
	assert_rollback_rejected(result)
	# All 3 facts should be erased (partial revert did fire)
	assert_no_fact("a")
	assert_no_fact("b")
	assert_no_fact("c")


# Key with uppercase is rejected.
func test_uppercase_dotless_key_rejected() -> void:
	_chronicle.set_fact("MyKey", 1)
	assert_no_fact("MyKey")
	assert_fact_count("*", 0)


# Key with spaces is rejected.
func test_key_with_spaces_rejected() -> void:
	_chronicle.set_fact("my key", 1)
	assert_no_fact("my key")
	assert_fact_count("*", 0)


# Key starting with dot is rejected.
func test_key_starting_with_dot_rejected() -> void:
	_chronicle.set_fact(".bad", 1)
	assert_no_fact(".bad")
	assert_fact_count("*", 0)


# Key ending with dot is rejected.
func test_key_ending_with_dot_rejected() -> void:
	_chronicle.set_fact("bad.", 1)
	assert_no_fact("bad.")
	assert_fact_count("*", 0)


# Key with consecutive dots is rejected.
func test_key_with_consecutive_dots_rejected() -> void:
	_chronicle.set_fact("a..b", 1)
	assert_no_fact("a..b")
	assert_fact_count("*", 0)


# Key that looks like a glob pattern (contains *) is rejected.
func test_key_with_asterisk_rejected() -> void:
	_chronicle.set_fact("player.*", 1)
	assert_no_fact("player.*")
	assert_fact_count("*", 0)


# Valid key at exactly MAX_KEY_LENGTH (256) is accepted.
func test_max_length_key_accepted() -> void:
	var key: String = "a".repeat(256)
	_chronicle.set_fact(key, 1)
	assert_has_fact(key)


# Key exceeding MAX_KEY_LENGTH (257 chars) is rejected.
func test_over_max_length_key_rejected() -> void:
	var key: String = "a".repeat(257)
	_chronicle.set_fact(key, 1)
	assert_no_fact(key)
	assert_fact_count("*", 0)


# Writing entries beyond timeline cap drops oldest entries without crash.
func test_timeline_at_capacity_drops_oldest() -> void:
	# Use a small cap to avoid making 10000 writes
	var tiny_chronicle: Node = add_child_autoqfree(
		preload("res://addons/chronicle/core/chronicle.gd").new()
	)
	# Can't set cap directly at test time easily; instead verify that set_cap API works
	# via the public coordinator. We'll just write more than the default cap by using
	# the existing _timeline API indirectly.
	# Simpler: set_cap to a small value via reflection.
	tiny_chronicle._timeline.set_cap(3)
	tiny_chronicle.set_auto_advancing(false)
	tiny_chronicle.set_game_time(1.0)
	tiny_chronicle.set_fact("a", 1)
	tiny_chronicle.set_game_time(2.0)
	tiny_chronicle.set_fact("b", 2)
	tiny_chronicle.set_game_time(3.0)
	tiny_chronicle.set_fact("c", 3)
	tiny_chronicle.set_game_time(4.0)
	tiny_chronicle.set_fact("d", 4)  # This should drop the oldest "a" entry
	assert_eq(tiny_chronicle._timeline.size(), 3, "timeline must stay at cap of 3")
	# The newest 3 entries should be b, c, d
	assert_eq(tiny_chronicle._timeline.get_at(0).display_key, "b", "oldest kept entry must be 'b'")


# A deeply nested dict (3 levels) is accepted and deep-copied correctly.
func test_deeply_nested_dict() -> void:
	var deep: Dictionary = {"level1": {"level2": {"level3": {"val": 42}}}}
	_chronicle.set_fact("nested", deep)
	assert_has_fact("nested")
	var retrieved: Variant = _chronicle.get_fact("nested")
	assert_eq(retrieved.level1.level2.level3.val, 42, "deep nesting must round-trip correctly")
	# Verify deep copy: mutating original must not affect stored value
	deep.level1.level2.level3.val = 999
	var retrieved2: Variant = _chronicle.get_fact("nested")
	assert_eq(retrieved2.level1.level2.level3.val, 42, "stored value must be isolated from source mutation")


# Arrays containing NAN/INF are stored
func test_array_with_nan_inf_stored_and_retrieved() -> void:
	var arr: Array = [1.0, NAN, INF, -INF]
	_chronicle.set_fact("arr", arr)
	assert_has_fact("arr")
	var retrieved: Variant = _chronicle.get_fact("arr")
	assert_true(retrieved is Array, "retrieved value must be Array")
	assert_eq(retrieved.size(), 4)
	assert_eq(retrieved[0], 1.0)
	assert_true(is_nan(retrieved[1]), "NAN must survive round-trip via deep_copy")
	assert_true(is_inf(retrieved[2]) and retrieved[2] > 0, "INF must survive round-trip")
	assert_true(is_inf(retrieved[3]) and retrieved[3] < 0, "-INF must survive round-trip")


# set_facts with a non-String key is skipped.
func test_set_facts_non_string_key_skipped() -> void:
	_chronicle.set_facts({1: "value"})
	assert_fact_count("*", 0)


# Very large int values are storable.
func test_large_int_stored() -> void:
	var big: int = 9223372036854775807  # INT64_MAX
	_chronicle.set_fact("big", big)
	assert_fact("big", big)


# increment on large int near INT64_MAX does not crash
func test_increment_near_int64_max_no_crash() -> void:
	var big: int = 9223372036854775807
	_chronicle.set_fact("x", big)
	var result: Variant = _chronicle.increment_fact("x", 1.0)
	# float(INT64_MAX) + 1 = float, exact int path fails, result is a float (not INF).
	# is_inf check: float(INT64_MAX)+1 rounds to 9.22e18 which is not INF, so compute_increment
	# returns a float. No crash is the key assertion.
	assert_ne(result, null, "incrementing near-INT64_MAX must not return null")


# set_cap(0) must be rejected
func test_timeline_cap_zero_rejected() -> void:
	var tl: ChronicleTimeline = ChronicleTimeline.new(
		ChronicleValueUtils.deep_copy,
		func(_m: String) -> void: pass
	)
	var initial_cap: int = tl._cap
	tl.set_cap(0)
	assert_eq(tl._cap, initial_cap, "set_cap(0) must not change the cap")


# rollback_steps with negative step count must return false
func test_rollback_steps_negative_rejected() -> void:
	_chronicle.set_fact("x", 1)
	var result = _chronicle.rollback_steps(-1)
	assert_rollback_rejected(result)
	assert_fact("x", 1)


# watch("player..health") has an empty segment — validate must reject it.
func test_watch_pattern_empty_segment_rejected() -> void:
	var id: int = _chronicle.watch("player..health", func(_k, _v, _o): pass)
	assert_eq(id, -1, "pattern with empty segment must be rejected (watch returns -1)")


# watch("player.*") must be accepted.
func test_watch_pattern_trailing_wildcard_accepted() -> void:
	var id: int = _chronicle.watch("player.*", func(_k, _v, _o): pass)
	assert_gte(id, 0, "valid trailing-wildcard pattern must be accepted")
	_chronicle.unwatch(id)


# 1000 watchers on the same glob pattern must all fire
func test_many_watchers_same_pattern_all_fire() -> void:
	const N: int = 1000
	var fired: Array = [0]
	var ids: Array[int] = []
	for i: int in range(N):
		var id: int = _chronicle.watch("*", func(_k, _v, _o): fired[0] += 1)
		ids.append(id)
	_chronicle.set_fact("x", 1)
	assert_eq(fired[0], N, "all %d watchers must fire once" % N)
	for id: int in ids:
		_chronicle.unwatch(id)


# unwatch(-1) must return false without crashing.
func test_unwatch_negative_id_returns_false() -> void:
	var result: bool = _chronicle.unwatch(-1)
	assert_false(result, "unwatch(-1) must return false")


# unwatch of an already-removed watcher must return false.
func test_unwatch_already_removed_returns_false() -> void:
	var id: int = _chronicle.watch("*", func(_k, _v, _o): pass)
	_chronicle.unwatch(id)
	var result: bool = _chronicle.unwatch(id)
	assert_false(result, "double-unwatch must return false")


# get_fact_history on a key that has never been set must return [].
func test_get_fact_history_unknown_key_empty() -> void:
	var history: Array[Dictionary] = _chronicle.get_fact_history("never_set")
	assert_eq(history.size(), 0, "history of unknown key must be empty")


# KEEP_LIFETIME on a new fact (no existing expiry) must not create an expiry.
func test_keep_lifetime_on_new_fact_no_expiry() -> void:
	# KEEP_LIFETIME = -2.0 by constant; on a new fact there is nothing to keep.
	# _mutate_state path: lifetime == KEEP_LIFETIME, so neither register nor unregister is called.
	_chronicle.set_fact("x", 1, false, _chronicle.KEEP_LIFETIME)
	assert_has_fact("x")
	assert_no_expiry("x")


# build_key with empty segments array produces empty string.
func test_build_key_no_segments() -> void:
	var key: String = Chronicle.build_key([])
	assert_eq(key, "", "build_key([]) must return empty string")


# build_key with a segment that is purely underscores is skipped.
func test_build_key_underscore_only_segment_skipped() -> void:
	var key: String = Chronicle.build_key(["valid", "___", "also_valid"])
	# "___" strips to "", is_empty() so it's skipped
	assert_eq(key, "valid.also_valid", "underscore-only segment must be skipped")


# build_key with a numeric segment gets prefixed with underscore.
func test_build_key_numeric_segment_prefixed() -> void:
	var key: String = Chronicle.build_key(["player", "123"])
	assert_eq(key, "player._123", "numeric segment must be prefixed with underscore")


# deserialize({}) (missing "facts") must return false.
func test_deserialize_missing_facts_returns_false() -> void:
	var ok: bool = _chronicle.deserialize({"version": 1})
	assert_false(ok, "deserialize without 'facts' key must return false")


# deserialize(null) must return false.
func test_deserialize_null_returns_false() -> void:
	# Chronicle.deserialize() now takes Dictionary (typed), so null can't be passed.
	# Test the internal serializer instead.
	var result: Variant = _chronicle._serializer.deserialize(null)
	assert_null(result, "serializer.deserialize(null) must return null")


# erase_facts([]) must return 0 without crashing.
func test_erase_facts_empty_array_keeps_existing() -> void:
	_chronicle.set_fact("x", 1)
	var empty_keys: Array[String] = []
	var count: int = _chronicle.erase_facts(empty_keys)
	assert_eq(count, 0, "erase_facts([]) must return 0")
	assert_fact("x", 1)


# ── Facade / clock regression ──


# Negative delta should be a pure no-op — auto-advance stays on
func test_advance_game_time_negative_preserves_auto_advance() -> void:
	assert_true(_chronicle.is_auto_advancing(), "auto-advance should be on initially")

	_chronicle.advance_game_time(-1.0)

	# FIXED: negative delta is a pure no-op — auto-advance stays on
	assert_true(_chronicle.is_auto_advancing(),
		"negative delta should not disable auto-advance")


# clear() emits state_reset after store is emptied — facts not visible in handler
func test_clear_emits_state_reset_before_store_emptied() -> void:
	_chronicle.set_fact("player.gold", 100)

	var fact_visible_in_handler: Array = [null]
	_chronicle.state_reset.connect(func() -> void:
		fact_visible_in_handler[0] = _chronicle.has_fact("player.gold")
	)

	_chronicle.clear()

	# FIXED: _reset_state() runs BEFORE state_reset emits
	assert_false(fact_visible_in_handler[0],
		"fact should NOT be visible in state_reset handler after fix")


# get_changes_since(NAN) must return [] and not crash.
func test_get_changes_since_nan_returns_empty() -> void:
	_chronicle.set_fact("x", 1)
	var result: Array[Dictionary] = _chronicle.get_changes_since(NAN)
	assert_eq(result.size(), 0, "get_changes_since(NAN) must return []")


# get_changes_since(INF) must return [].
func test_get_changes_since_inf_returns_empty() -> void:
	_chronicle.set_fact("x", 1)
	var result: Array[Dictionary] = _chronicle.get_changes_since(INF)
	assert_eq(result.size(), 0, "get_changes_since(INF) must return []")


# get_changes_since with negative time must return [].
func test_get_changes_since_negative_array_empty() -> void:
	_chronicle.set_fact("x", 1)
	var result: Array[Dictionary] = _chronicle.get_changes_since(-1.0)
	assert_eq(result.size(), 0, "get_changes_since(-1) must return []")


# serialize with SERIALIZE_ALL (-1) includes all entries.
func test_serialize_all_includes_all_entries() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	var data: Dictionary = _chronicle.serialize(_chronicle.SERIALIZE_ALL)
	assert_has(data, "facts", "serialized data must have 'facts'")
	assert_has(data, "timeline", "serialized data must have 'timeline'")
	var tl: Variant = data.get("timeline")
	assert_true(tl is Array, "timeline must be Array")
	assert_eq(tl.size(), 2, "all 2 timeline entries must be included with SERIALIZE_ALL")


# rollback_to(current_time) when no entries are after current time is NO_ACTION.
func test_rollback_to_current_time_no_action() -> void:
	set_time(5.0)
	_chronicle.set_fact("x", 1)
	var ok = _chronicle.rollback_to(5.0)
	assert_rollback_ok(ok)
	# bisect_after(5.0) returns index past all entries at t<=5.0, so cut >= size → NO_ACTION
	assert_fact("x", 1)


# toggle_fact on a key that does not exist must set it to true.
func test_toggle_fact_on_missing_sets_true() -> void:
	var new_state: bool = _chronicle.toggle_fact("flag")
	assert_true(new_state, "toggle on missing key must return true")
	assert_fact("flag", true)


# toggle_fact on true must set to false (not erase).
func test_toggle_fact_on_true_sets_false() -> void:
	_chronicle.set_fact("flag", true)
	var new_state: bool = _chronicle.toggle_fact("flag")
	assert_false(new_state, "toggle on true must return false")
	assert_has_fact("flag")
	assert_fact("flag", false)


# toggle_fact on zero (falsy int) must set to true.
func test_toggle_fact_on_zero_sets_true() -> void:
	_chronicle.set_fact("x", 0)
	var new_state: bool = _chronicle.toggle_fact("x")
	assert_true(new_state, "toggle on falsy int must return true")


# set_game_time to exactly the current time is a no-op
func test_set_game_time_same_value_accepted() -> void:
	set_time(5.0)
	_chronicle.set_game_time(5.0)
	assert_game_time(5.0)


# set_game_time to a past time must be rejected
func test_set_game_time_backward_rejected() -> void:
	set_time(5.0)
	_chronicle.set_game_time(3.0)
	assert_game_time(5.0)


# count_facts with invalid glob returns zero
func test_count_facts_invalid_glob_returns_zero() -> void:
	_chronicle.set_fact("a", 1)
	# "**.b" — first segment is "**", which is a wildcard character not as full segment
	assert_fact_count("**.b", 0)


# A bare "*" pattern must match all facts including those in the _global entity.
func test_wildcard_matches_global_entity_facts() -> void:
	_chronicle.set_fact("bare_key", 1)       # stored as _global.bare_key
	_chronicle.set_fact("player.health", 100) # stored as player.health
	var facts: Dictionary = _chronicle.get_facts("*")
	assert_has(facts, "bare_key", "bare_key must be in get_facts('*')")
	assert_has(facts, "player.health", "player.health must be in get_facts('*')")


# Erasing a fact that has an active expiry must also remove the expiry entry.
func test_erase_fact_clears_expiry() -> void:
	_chronicle.set_fact("x", 1, false, 10.0)
	assert_has_expiry("x")
	_chronicle.erase_fact("x")
	assert_no_fact("x")
	assert_no_expiry("x")


# RingCache at cap 1: second entry evicts first immediately.
func test_ring_cache_cap_one_evicts() -> void:
	var cache: ChronicleRingCache = ChronicleRingCache.new(1)
	cache.put("a", 1)
	assert_eq(cache.get_or_null("a"), 1, "first entry must be retrievable")
	cache.put("b", 2)
	assert_null(cache.get_or_null("a"), "first entry must be evicted after second put")
	assert_eq(cache.get_or_null("b"), 2, "second entry must be retrievable")


# advance_game_time(0.0) must return without changing clock or disabling auto-advance.
func test_advance_game_time_zero_is_noop() -> void:
	_chronicle.set_auto_advancing(true)
	assert_true(_chronicle.is_auto_advancing(), "pre-condition: auto-advancing must be true")
	_chronicle.advance_game_time(0.0)
	# advance_game_time(0.0) returns early — does NOT call _disable_auto_advance
	assert_true(_chronicle.is_auto_advancing(), "auto-advance must remain enabled after advance(0.0)")


# Writing the same value to an existing fact must not fire watchers.
func test_same_value_write_no_dispatch() -> void:
	_chronicle.set_fact("x", 42)
	var fired: Array = [0]
	_chronicle.watch("x", func(_k, _v, _o): fired[0] += 1)
	_chronicle.set_fact("x", 42)
	# _dispatch_and_drain guards: if value == old_value and value != null, skip dispatch
	assert_eq(fired[0], 0, "watcher must NOT fire when writing the same value")


# save_file with empty path returns ERR_FILE_BAD_PATH.
func test_save_file_blank_path_returns_bad_path() -> void:
	var err: Error = _chronicle.save_file("")
	assert_eq(err, ERR_FILE_BAD_PATH, "save_file('') must return ERR_FILE_BAD_PATH")


# load_file with empty path returns ERR_FILE_BAD_PATH.
func test_load_file_blank_path_returns_bad_path() -> void:
	var err: Error = _chronicle.load_file("")
	assert_eq(err, ERR_FILE_BAD_PATH, "load_file('') must return ERR_FILE_BAD_PATH")


# rollback_to before first timeline entry succeeds (R22+)
func test_rollback_to_before_first_timeline_entry_succeeds() -> void:
	set_time(5.0)
	_chronicle.set_fact("a", 1)
	# R22+: rollback to before first entry now succeeds — all entries are undone
	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)
	assert_no_fact("a")


# Deeply nested NOT (up to depth 63) must parse without crash.
func test_expression_deeply_nested_not_63() -> void:
	_chronicle.set_fact("flag", false)
	# 63 NOTs applied to a falsy fact: 63 NOTs of false = true (odd depth)
	var nots: String = "NOT ".repeat(63)
	var expr: String = nots + "flag"
	var result: bool = _chronicle.evaluate(expr)
	# 63 NOTs of false = true (odd number of negations)
	assert_true(result, "63-deep NOT expression must parse successfully and return true")


# Nesting at depth 65 must return false (parse error, depth guard).
func test_expression_too_deeply_nested_returns_null() -> void:
	var nots: String = "NOT ".repeat(65)
	var expr: String = nots + "flag"
	var result: Variant = _chronicle.evaluate(expr)
	assert_null(result, "65-deep NOT expression must return null (depth exceeded)")


# get_changes_between(10.0, 5.0) — inverted range — must return [] gracefully.
func test_get_changes_between_inverted_range_empty() -> void:
	set_time(7.0)
	_chronicle.set_fact("x", 1)
	var result: Array[Dictionary] = _chronicle.get_changes_between(10.0, 5.0)
	# bisect(10.0, false) > bisect_after(5.0) so range(start, end) is empty
	assert_eq(result.size(), 0, "inverted time range must return empty array")


# ── Null safety ──


# set_fact(key, null) routes to erase and fact is gone
func test_set_fact_null_routes_to_erase_and_fact_is_gone() -> void:
	_chronicle.set_fact("n1_key", 42)
	assert_fact("n1_key", 42)

	var changed := collect_signal(_chronicle, "fact_changed")

	# Passing null should silently redirect to erase_fact()
	_chronicle.set_fact("n1_key", null)

	assert_no_fact("n1_key")
	# fact_changed must fire with value=null (erasure signal)
	changed.assert_count(1)
	changed.assert_event(0, "n1_key", null, 42)


# set_facts with null value routes to erase
func test_set_facts_with_null_value_routes_to_erase() -> void:
	_chronicle.set_fact("n1_batch_key", "hello")
	assert_fact("n1_batch_key", "hello")

	# set_facts() with a null value should erase via the _EraseOp path
	_chronicle.set_facts({"n1_batch_key": null})
	assert_no_fact("n1_batch_key")


# set_fact(key, null) on nonexistent key is a no-op
func test_set_fact_null_on_nonexistent_key_is_noop() -> void:
	# Erasing a key that does not exist: erase_fact returns false, no signal
	var changed := collect_signal(_chronicle, "fact_changed")
	_chronicle.set_fact("n1_ghost", null)
	assert_no_fact("n1_ghost")
	changed.assert_count(0)


# get_fact absent key returns null default
func test_get_fact_absent_key_returns_null_default() -> void:
	var v: Variant = _chronicle.get_fact("n2_never_set")
	assert_eq(v, null, "Absent key must return null default")
	assert_no_fact("n2_never_set")


# get_fact present key never returns null
func test_get_fact_present_key_never_returns_null() -> void:
	_chronicle.set_fact("n2_present", true)
	var v: Variant = _chronicle.get_fact("n2_present")
	assert_ne(v, null, "A present fact must never return null")


# get_fact after erase returns null default not stored null
func test_get_fact_after_erase_returns_null_default_not_stored_null() -> void:
	_chronicle.set_fact("n2_erase_me", "value")
	_chronicle.erase_fact("n2_erase_me")
	# After erase, get_fact should return the default (null), NOT a stored null
	var v: Variant = _chronicle.get_fact("n2_erase_me")
	assert_eq(v, null, "Erased key must return null default")
	assert_no_fact("n2_erase_me")


# custom default returned for absent key
func test_custom_default_returned_for_absent_key() -> void:
	var v: Variant = _chronicle.get_fact("n2_missing", "sentinel")
	assert_eq(v, "sentinel", "Custom default must be returned for absent key")


# fact_changed value null only on erase
func test_fact_changed_value_null_only_on_erase() -> void:
	_chronicle.set_fact("n3_key", "initial")
	var changed := collect_signal(_chronicle, "fact_changed")

	_chronicle.erase_fact("n3_key")
	changed.assert_count(1)
	changed.assert_event(0, "n3_key", null, "initial")

	# Writing a new value must NOT produce value=null in the signal
	_chronicle.set_fact("n3_key", "new")
	changed.assert_count(2)
	var last_val: Variant = changed.last().value
	assert_ne(last_val, null, "Writing a non-null value must not produce null in fact_changed")


# set_fact(null) fires fact_changed with null value
func test_set_fact_null_fires_fact_changed_with_null_value() -> void:
	_chronicle.set_fact("n3_via_null", 99)
	var changed := collect_signal(_chronicle, "fact_changed")
	_chronicle.set_fact("n3_via_null", null)
	changed.assert_count(1)
	assert_eq(changed.first().value, null, "set_fact(null) must fire fact_changed with null value")


# watcher receives null value on erase
func test_watcher_receives_null_value_on_erase() -> void:
	_chronicle.set_fact("n4_erase_me", "exists")

	# Use EventCollector (known-working pattern) to capture watcher events
	var events := watch_events("n4_erase_me")

	_chronicle.erase_fact("n4_erase_me")
	events.assert_count(1)
	events.assert_event(0, "n4_erase_me", null, "exists")


# watcher receives null old_value on creation
func test_watcher_receives_null_old_value_on_creation() -> void:
	var events := watch_events("n4_new_key")

	_chronicle.set_fact("n4_new_key", 42)
	events.assert_count(1)
	events.assert_event(0, "n4_new_key", 42, null)


# get_first_change returns null when no match
func test_get_first_change_returns_null_when_no_match() -> void:
	var result: Variant = _chronicle.get_first_change("n5_never_touched")
	assert_eq(result, null, "get_first_change must return null when no matching entries exist")


# get_last_change returns null when no match
func test_get_last_change_returns_null_when_no_match() -> void:
	var result: Variant = _chronicle.get_last_change("n5_also_never_touched")
	assert_eq(result, null, "get_last_change must return null when no matching entries exist")


# get_first_change returns dict when matched
func test_get_first_change_returns_dict_when_matched() -> void:
	_chronicle.set_fact("n5_real_key", "hello")
	var result: Variant = _chronicle.get_first_change("n5_real_key")
	assert_true(result is Dictionary, "get_first_change must return Dictionary when match found")
	assert_has(result, "key")
	assert_has(result, "value")
	assert_has(result, "old_value")


# deserialize null input returns false
func test_deserialize_null_input_returns_false() -> void:
	# Chronicle.deserialize() now takes Dictionary (typed), so null can't be passed directly.
	# Test the internal serializer instead which still accepts Variant.
	var result: Variant = _chronicle._serializer.deserialize(null)
	assert_null(result, "serializer.deserialize(null) must return null")


# deserialize non-dict returns false
func test_deserialize_non_dict_returns_false() -> void:
	# Chronicle.deserialize() now takes Dictionary (typed), so Array can't be passed directly.
	# Test the internal serializer instead which still accepts Variant.
	var result: Variant = _chronicle._serializer.deserialize([1, 2, 3])
	assert_null(result, "serializer.deserialize(Array) must return null")


# deserialize missing facts key returns false
func test_deserialize_missing_facts_key_returns_false() -> void:
	var ok: bool = _chronicle.deserialize({"version": 1})
	assert_false(ok, "deserialize() with missing 'facts' key must return false")


# deserialize valid data succeeds
func test_deserialize_valid_data_succeeds() -> void:
	_chronicle.set_fact("n6_pre", "before")
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	var ok: bool = _chronicle.deserialize(data)
	assert_true(ok, "deserialize() of a valid snapshot must return true")
	assert_fact("n6_pre", "before")


# store get_value with null stored internally returns null
func test_store_get_value_with_null_stored_internally_returns_null() -> void:
	# Access the internal store via the underlying _coordinator or just test
	# the store's own API directly. The store can theoretically receive null
	# if code bypasses the public API. _copy() has an early return for null.
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy)
	# Inject null directly using the internal API (bypasses Chronicle guards)
	store._facts["test_key"] = null
	var result: Variant = store.get_value("test_key")
	assert_eq(result, null, "get_value() on a stored null must return null (not crash)")


# store copy fn handles null value
func test_store_copy_fn_handles_null_value() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy)
	store.set_value("arr_key", [1, 2, 3])
	var v: Variant = store.get_value("arr_key")
	assert_eq(v, [1, 2, 3], "Normal array retrieval must work")
	assert_eq(store.get_value("absent_key"), null, "Absent key default is null")


# set_fact with invalid key is noop
func test_set_fact_with_invalid_key_is_noop() -> void:
	# Empty key should fail validation and not store anything
	_chronicle.set_fact("", 99)
	# The store must remain empty (clear was called in before_each)
	assert_fact_count("*", 0)


# set_fact with uppercase key is noop
func test_set_fact_with_uppercase_key_is_noop() -> void:
	_chronicle.set_fact("BadKey", 99)
	assert_no_fact("BadKey")
	assert_no_fact("badkey")


# set_fact with non-storable type is noop
func test_set_fact_with_non_storable_type_is_noop() -> void:
	# Object instances are not storable
	var obj := Object.new()
	_chronicle.set_fact("n8_obj", obj)
	assert_no_fact("n8_obj")
	obj.free()


# rollback erases facts created after target time
func test_rollback_erases_facts_created_after_target_time() -> void:
	# Anchor at t=0 so the timeline starts before the target rollback time
	_chronicle.set_fact("n9_anchor", "anchor")
	advance_time(10.0)
	_chronicle.set_fact("n9_existing", "before")

	advance_time(10.0)
	_chronicle.set_fact("n9_created_after", "new")

	assert_fact("n9_existing", "before")
	assert_fact("n9_created_after", "new")

	# Rollback to t=5 (after anchor at 0, before "existing" at 10)
	var ok = _chronicle.rollback_to(5.0)
	assert_rollback_ok(ok)

	assert_no_fact("n9_existing")
	assert_no_fact("n9_created_after")


# rollback dispatches null value for erased facts
func test_rollback_dispatches_null_value_for_erased_facts() -> void:
	# Anchor at t=0 so timeline spans before rollback target
	_chronicle.set_fact("n9_anchor2", "anchor")
	advance_time(10.0)
	_chronicle.set_fact("n9_to_erase", "present")

	advance_time(10.0)

	var events := watch_events("n9_to_erase")

	# Rollback to t=5 — before n9_to_erase was created
	var ok = _chronicle.rollback_to(5.0)
	assert_rollback_ok(ok)

	# The watcher must have fired with value=null (erase signal from rollback)
	events.assert_count(1)
	events.assert_event(0, "n9_to_erase", null, "present")
	assert_no_fact("n9_to_erase")


# fact_expired signal carries value not null
func test_fact_expired_signal_carries_value_not_null() -> void:
	var expired := collect_signal(_chronicle, "fact_expired")

	set_time(0.0)
	_chronicle.set_fact("n10_expiring", "captured_value", false, 0.5)
	advance_time(1.0)
	# Flush expiry by serializing (which calls _flush_expiry when idle)
	_chronicle.serialize()

	# The value in fact_expired must be "captured_value", not null
	expired.assert_count(1)
	assert_eq(expired.first().key, "n10_expiring")
	# fact_expired signal is (key, expired_value) — check value
	var ev: Dictionary = expired.first()
	assert_ne(ev.get("value"), null, "fact_expired must carry the fact's value, not null")
	assert_eq(ev.get("value"), "captured_value", "fact_expired value must match the stored value")


# gate resolver returns null when chronicle invalid
func test_gate_resolver_returns_null_when_chronicle_invalid() -> void:
	# The gate's resolver checks is_instance_valid(_chronicle).
	# We test the resolver logic directly by building a standalone gate
	# and then checking that evaluate() handles null gracefully.
	# Since we can't easily free the autoload, we test evaluate()'s null-safety.
	var result: bool = _chronicle.evaluate("n11_unset_key")
	# evaluate() returns false on parse error and false for unset keys
	# A bare key truthy check on an unset key returns false
	assert_false(result, "Unset key must evaluate as false (truthy check)")


# reactor creation mode fires when old_value is null
func test_reactor_creation_mode_fires_when_old_value_is_null() -> void:
	# ReactTo.CREATION fires when old_value == null regardless of source.
	var reactor := add_reactor({
		"watch_pattern": "n12_key",
		"react_to": CompanionFactory.ReactTo.CREATION,
	})
	var events := collect_signal(reactor, "fact_matched")

	# First set: old_value=null → fires
	_chronicle.set_fact("n12_key", "first")
	events.assert_count(1)

	# Overwrite: old_value="first" → should NOT fire
	_chronicle.set_fact("n12_key", "second")
	events.assert_count(1)

	# Erase then re-set: new creation with old_value=null → fires again
	_chronicle.erase_fact("n12_key")
	_chronicle.set_fact("n12_key", "third")
	events.assert_count(2)


# reactor change mode ignores null value erase
func test_reactor_change_mode_ignores_null_value_erase() -> void:
	# ReactTo.CHANGE: if value == null (erase), the filter returns early.
	var reactor := add_reactor({
		"watch_pattern": "n12_change_key",
		"react_to": CompanionFactory.ReactTo.CHANGE,
	})
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("n12_change_key", "initial")
	# Creation event: old_value=null, is_new=true → filtered
	events.assert_count(0)

	_chronicle.set_fact("n12_change_key", "updated")
	# Change event fires
	events.assert_count(1)

	_chronicle.erase_fact("n12_change_key")
	# Erase event: value=null → filtered by `value == null` check in CHANGE mode
	events.assert_count(1)


# watcher null value not deep copied — no crash
func test_watcher_null_value_not_deep_copied_no_crash() -> void:
	_chronicle.set_fact("n13_key", [1, 2, 3])
	var events := watch_events("n13_key")

	_chronicle.erase_fact("n13_key")

	# val should be null (erase), old should be a copy of [1, 2, 3]
	events.assert_count(1)
	events.assert_event(0, "n13_key", null, [1, 2, 3])


# type codec null input returns null
func test_type_codec_null_input_returns_null() -> void:
	var result: Variant = _codec.encode_value(null)
	assert_eq(result, null, "prepare_for_json(null) must return null, not crash")


# type codec restore null returns null
func test_type_codec_restore_null_returns_null() -> void:
	var result: Variant = _codec.decode_value(null)
	# decode_value: null is not a Dictionary or Array, falls through to
	# the float check, returns null as-is
	assert_eq(result, null, "restore_from_json(null) must return null, not crash")


# timeline entry copy handles null values
func test_timeline_entry_copy_handles_null_values() -> void:
	# An erase entry has value=null in the timeline.
	# get_first_change / get_last_change call entry.copy() internally.
	set_time(0.0)
	_chronicle.set_fact("n15_key", "initial")
	advance_time(1.0)
	_chronicle.erase_fact("n15_key")

	# get_last_change copies the entry that has value=null
	var result: Variant = _chronicle.get_last_change("n15_key")
	assert_true(result is Dictionary, "get_last_change must return a Dictionary even for erase entries")
	assert_eq(result.get("value"), null, "Timeline copy of erase entry must have value=null")
	assert_eq(result.get("old_value"), "initial", "Timeline copy of erase entry must have correct old_value")


# expression parse error not cached
func test_expression_parse_error_not_cached() -> void:
	# Parse an invalid expression
	var result1: Variant = _null_engine.parse("!!!invalid")
	assert_eq(result1, null, "Invalid expression must return null from parse()")

	# Parse again — must still return null (not a cached null that is mistaken for a miss)
	var result2: Variant = _null_engine.parse("!!!invalid")
	assert_eq(result2, null, "Second parse of invalid expression must still return null")

	# A valid expression parsed after the invalid one must still work
	var result3: Variant = _null_engine.parse("valid_key")
	assert_not_null(result3, "Valid expression after invalid must parse successfully")


# rollback of nonexistent key does not spuriously dispatch
func test_rollback_of_nonexistent_key_does_not_spuriously_dispatch() -> void:
	# Anchor fact at t=0 so the timeline covers the rollback target time.
	_chronicle.set_fact("n17_anchor", "anchor")
	advance_time(5.0)
	_chronicle.set_fact("n17_post_key", "created_late")

	var events := watch_events("n17_post_key")

	# Rollback to t=2 — after anchor, before n17_post_key was created at t=5
	var ok = _chronicle.rollback_to(2.0)
	assert_rollback_ok(ok)
	# The key was created after t=2, so rollback must erase it.
	# Watcher should fire with value=null (erase).
	events.assert_count(1)
	events.assert_event(0, "n17_post_key", null, "created_late")
	assert_no_fact("n17_post_key")


# recorder null value is rejected not stored
func test_recorder_null_value_is_rejected_not_stored() -> void:
	# null is now a valid type (returns true) — it passes type-check gates
	# and is handled downstream (deep_copy returns null, set_fact erases).
	var is_valid: bool = _registry.is_valid_type(null)
	assert_true(is_valid, "null must be a valid type (handled downstream as erase)")

	# The store must not accept null via set_fact (public API guard)
	_chronicle.set_fact("n18_key", null)
	assert_no_fact("n18_key")


# unwatch glob watcher actually removes it
func test_unwatch_glob_watcher_actually_removes_it() -> void:
	# Use EventCollector (known-working) to verify glob watcher fires/unfires
	# watch_events() auto-asserts a valid watch_id, so registration is already verified.
	var events := watch_events("n19_entity.*")

	_chronicle.set_fact("n19_entity.fact1", true)
	events.assert_count(1)

	var removed: bool = _chronicle.unwatch(events.watch_id)
	assert_true(removed, "unwatch() must return true for a registered glob watcher")

	_chronicle.set_fact("n19_entity.fact2", true)
	events.assert_count(1)  # still 1 — not incremented after unwatch


# watch_any glob unwatch removes all patterns
func test_watch_any_glob_unwatch_removes_all_patterns() -> void:
	# watch_events() auto-asserts a valid watch_id for the multi-glob registration.
	var events := watch_events(["n19_multi.a.*", "n19_multi.b.*"])

	_chronicle.set_fact("n19_multi.a.x", true)
	events.assert_count(1)

	_chronicle.unwatch(events.watch_id)

	_chronicle.set_fact("n19_multi.a.y", true)
	_chronicle.set_fact("n19_multi.b.z", true)
	events.assert_count(1)  # still 1 — not incremented after unwatch


# deep_copy null returns null
func test_deep_copy_null_returns_null() -> void:
	var result: Variant = ChronicleValueUtils.deep_copy(null)
	assert_eq(result, null, "deep_copy(null) must return null")


# timeline erase entry survives copy
func test_timeline_erase_entry_survives_copy() -> void:
	set_time(1.0)
	_chronicle.set_fact("n20_key", "hello")
	advance_time(1.0)
	_chronicle.erase_fact("n20_key")

	var history: Array[Dictionary] = _chronicle.get_fact_history("n20_key")
	assert_eq(history.size(), 2, "History must have set + erase entries")
	# Last entry is the erase — value should be null
	var erase_entry: Dictionary = history[history.size() - 1]
	assert_eq(erase_entry.get("value"), null, "Erase entry in timeline must have value=null")
	# old_value of the erase entry must be the previous value
	assert_eq(erase_entry.get("old_value"), "hello", "Erase entry must record old_value correctly")


# validate_and_normalize empty key returns empty
func test_validate_and_normalize_empty_key_returns_empty() -> void:
	var codec := ChronicleKeyCodec.new(func(_m: String) -> void: pass)
	var result: String = codec.validate_and_normalize("")
	assert_eq(result, "", "Empty key must return empty string from validate_and_normalize")


# has_fact invalid key returns false not crash
func test_has_fact_invalid_key_returns_false_not_crash() -> void:
	# Invalid key must not crash has_fact
	var result: bool = _chronicle.has_fact("")
	assert_false(result, "has_fact with empty key must return false")


# erase_fact invalid key returns false not crash
func test_erase_fact_invalid_key_returns_false_not_crash() -> void:
	var result: bool = _chronicle.erase_fact("")
	assert_false(result, "erase_fact with empty key must return false")


# get_expiry_remaining invalid key returns minus one
func test_get_expiry_remaining_invalid_key_returns_minus_one() -> void:
	var result: float = _chronicle.get_expiry_remaining("")
	assert_eq(result, -1.0, "get_expiry_remaining with empty key must return -1.0")


# set_facts null value erases existing fact
func test_set_facts_null_value_erases_existing_fact() -> void:
	_chronicle.set_fact("n22_key1", "value1")
	_chronicle.set_fact("n22_key2", "value2")

	_chronicle.set_facts({"n22_key1": null, "n22_key2": "new_value2"})

	assert_no_fact("n22_key1")
	assert_fact("n22_key2", "new_value2")


# set_facts null value on nonexistent key is noop
func test_set_facts_null_value_on_nonexistent_key_is_noop() -> void:
	# set_facts() with null on a key that doesn't exist:
	# _mutate_state returns null (is_new=true on an erase-sentinel)
	_chronicle.set_facts({"n22_ghost": null})
	assert_no_fact("n22_ghost")
	assert_fact_count("*", 0)


# ── Facade API arity ──


# set_fact accepts 2-4 args after API merge (optional transient and lifetime)
func test_set_fact_accepts_optional_transient_lifetime() -> void:
	var Chronicle := preload("res://addons/chronicle/core/chronicle.gd")
	var c: Node = add_child_autoqfree(Chronicle.new())
	await get_tree().process_frame

	# 2 args (key, value)
	var ok: bool = c.set_fact("test.key", "val")
	assert_true(ok, "set_fact(key, value) should work with 2 args")

	# 4 args (key, value, transient, lifetime)
	var ok2: bool = c.set_fact("test.key2", "val", true, 5.0)
	assert_true(ok2, "set_fact(key, value, transient, lifetime) should work with 4 args")


# increment_fact accepts 2-4 args after API merge (optional transient and lifetime)
func test_increment_fact_accepts_optional_transient_lifetime() -> void:
	var Chronicle := preload("res://addons/chronicle/core/chronicle.gd")
	var c: Node = add_child_autoqfree(Chronicle.new())
	await get_tree().process_frame

	# 2 args (key, amount)
	var result: Variant = c.increment_fact("test.counter", 1.0)
	assert_true(result is float or result is int, "increment_fact(key, amount) should return a number")

	# 4 args (key, amount, transient, lifetime)
	var result2: Variant = c.increment_fact("test.counter2", 1.0, true, 10.0)
	assert_true(result2 is float or result2 is int,
		"increment_fact(key, amount, transient, lifetime) should work with 4 args")


# Merged set_fact parameter order: transient before lifetime
func test_merged_set_fact_parameter_order() -> void:
	var Chronicle := preload("res://addons/chronicle/core/chronicle.gd")
	var c: Node = add_child_autoqfree(Chronicle.new())
	await get_tree().process_frame

	# set_fact parameter order is (key, value, TRANSIENT, LIFETIME)
	c.set_fact("test.order", "v", true, 5.0)
	assert_true(c.is_transient("test.order"),
		"set_fact with transient=true should mark fact as transient")
	assert_true(c.has_expiry("test.order"),
		"set_fact with lifetime=5.0 should set expiry")


# default_when_missing resolver behavior
func test_default_when_missing_gate() -> void:
	var _engine := ChronicleExpressionEngine.new()
	# _chronicle is the Chronicle node (also accessible as Chronicle autoload via _root)
	# Build resolvers matching what the gate builds
	var resolver_default := func(key: String) -> Variant:
		if _chronicle.has_fact(key):
			return _chronicle.get_fact(key)
		return true
	var resolver_no_default: Callable = _chronicle.get_fact

	# Test 1: bare truthy on missing key with default_when_missing=true
	var ast1: Variant = _engine.parse("missing.key")
	var result1: bool = _engine.evaluate_ast(ast1, resolver_default)
	assert_true(result1, "missing key with default_when_missing=true is truthy")

	# Test 2: NOT expression with missing key and default_when_missing=true
	var ast2: Variant = _engine.parse("NOT missing.key")
	var result2: bool = _engine.evaluate_ast(ast2, resolver_default)
	assert_false(result2, "NOT (default-true missing key) is false")

	# Test 3: Now set the key to a truthy value and verify it evaluates
	_chronicle.set_fact("missing.key", true)
	var result3: bool = _engine.evaluate_ast(ast1, resolver_default)
	assert_true(result3, "truthy fact evaluates true")

	# Test 4: Set the key to false -> truthy check returns false
	_chronicle.set_fact("missing.key", false)
	var result4: bool = _engine.evaluate_ast(ast1, resolver_default)
	assert_false(result4, "false fact evaluates false")

	# Test 5: Comparison expression with missing key
	_chronicle.erase_fact("missing.key")
	var ast5: Variant = _engine.parse("missing.key == TRUE")
	var result5: bool = _engine.evaluate_ast(ast5, resolver_default)
	# resolver returns true for missing key, compare true == true -> true
	assert_true(result5, "missing == TRUE with default-true resolver is true")

	# Test 6: default_when_missing=false should produce false for missing key truthy
	var result6: bool = _engine.evaluate_ast(ast1, resolver_no_default)
	assert_false(result6, "missing key with no default is false")

	# Test 7: Set a key to 0 (falsy int) — truthy returns false
	_chronicle.set_fact("zero.val", 0)
	var ast7: Variant = _engine.parse("zero.val")
	var result7a: bool = _engine.evaluate_ast(ast7, resolver_default)
	assert_false(result7a, "0 is falsy")

	# Test 8: Verify gate behavior survives serialization roundtrip
	_chronicle.set_fact("gate.check", true)
	var gate_ast: Variant = _engine.parse("gate.check")
	assert_true(_engine.evaluate_ast(gate_ast, resolver_no_default), "gate.check truthy before roundtrip")

	roundtrip()

	assert_true(_engine.evaluate_ast(gate_ast, resolver_no_default), "gate.check truthy after roundtrip")


# ── Expression facade API (parse / evaluate / extract / walk) ──

# parse_expression returns an AST for a valid expression, null on parse error.
func test_parse_expression_valid_returns_ast() -> void:
	var ast: Variant = _chronicle.parse_expression("player.hp > 5")
	assert_true(ast is Dictionary, "parse_expression should return a Dictionary AST for a valid expression")


func test_parse_expression_invalid_returns_null() -> void:
	assert_null(_chronicle.parse_expression("AND OR NOT"),
		"parse_expression should return null on a parse error")


# evaluate_expression evaluates a pre-parsed AST against CURRENT facts (re-usable).
func test_evaluate_expression_reads_current_facts() -> void:
	var ast: Variant = _chronicle.parse_expression("flag")
	assert_not_null(ast, "parse_expression('flag') should produce an AST")
	_chronicle.set_fact("flag", true)
	assert_true(_chronicle.evaluate_expression(ast), "evaluate_expression true while flag is true")
	_chronicle.set_fact("flag", false)
	assert_false(_chronicle.evaluate_expression(ast), "same AST re-evaluates false after flag flips")


func test_evaluate_expression_null_ast_returns_false() -> void:
	assert_false(_chronicle.evaluate_expression(null),
		"evaluate_expression(null) should return false without erroring")


# extract_expression_keys returns every fact key referenced by the AST.
func test_extract_expression_keys_returns_referenced_keys() -> void:
	var ast: Variant = _chronicle.parse_expression("player.alive AND enemy.dead")
	assert_not_null(ast)
	var keys: Array = _chronicle.extract_expression_keys(ast)
	assert_has(keys, "player.alive", "extract_expression_keys should include player.alive")
	assert_has(keys, "enemy.dead", "extract_expression_keys should include enemy.dead")


func test_extract_expression_keys_null_ast_returns_empty() -> void:
	assert_eq(_chronicle.extract_expression_keys(null).size(), 0,
		"extract_expression_keys(null) returns an empty array")


# walk_expression_ast invokes leaf_fn on each leaf; null AST is a safe no-op.
func test_walk_expression_ast_visits_leaves() -> void:
	var ast: Variant = _chronicle.parse_expression("player.alive AND enemy.dead")
	assert_not_null(ast)
	var leaf_count: Array[int] = [0]
	_chronicle.walk_expression_ast(ast, func(_leaf: Variant) -> void: leaf_count[0] += 1)
	assert_eq(leaf_count[0], 2, "walk_expression_ast visits exactly 2 leaves (player.alive, enemy.dead); AND is an operator, not a leaf)")


func test_walk_expression_ast_null_ast_no_crash() -> void:
	var leaf_count: Array[int] = [0]
	_chronicle.walk_expression_ast(null, func(_leaf: Variant) -> void: leaf_count[0] += 1)
	assert_eq(leaf_count[0], 0, "walk_expression_ast(null) should visit no leaves and not crash")


# evaluate_bool returns the default on a parse error, the bool result otherwise.
func test_evaluate_bool_valid_expression() -> void:
	_chronicle.set_fact("flag", true)
	assert_true(_chronicle.evaluate_bool("flag"), "evaluate_bool('flag') true when flag is true")
	_chronicle.set_fact("flag", false)
	assert_false(_chronicle.evaluate_bool("flag"), "evaluate_bool('flag') false when flag is false")


func test_evaluate_bool_parse_error_returns_default() -> void:
	assert_true(_chronicle.evaluate_bool("AND OR NOT", true),
		"evaluate_bool returns default=true on a parse error")
	assert_false(_chronicle.evaluate_bool("AND OR NOT", false),
		"evaluate_bool returns default=false on a parse error")


# ── watch / watch_any reject invalid callbacks (return -1) ──

func test_watch_invalid_callback_returns_negative() -> void:
	assert_eq(_chronicle.watch("player.hp", Callable()), -1,
		"watch() with an invalid callback should return -1")
	assert_watcher_count(0)


func test_watch_any_invalid_callback_returns_negative() -> void:
	assert_eq(_chronicle.watch_any(["player.hp", "enemy.hp"] as Array[String], Callable()), -1,
		"watch_any() with an invalid callback should return -1")
	assert_watcher_count(0)


# ── Store hard cap & write interceptor ──

# A new key beyond the store hard cap is rejected; overwriting an existing key still works.
func test_set_fact_rejected_at_store_hard_cap() -> void:
	_chronicle.set_store_hard_cap(1)
	_chronicle.set_fact("cap.a", 1)
	_chronicle.set_fact("cap.b", 2)  # new key beyond cap — rejected (emits push_error, not gated)
	assert_fact("cap.a", 1)
	assert_no_fact("cap.b")
	_chronicle.set_fact("cap.a", 99)  # overwriting an existing key is allowed at cap
	assert_fact("cap.a", 99)


# A write interceptor can modify a value, reject a write (REJECT sentinel), or be removed.
func test_write_interceptor_modifies_rejects_and_removes() -> void:
	_chronicle.set_write_interceptor(func(key: String, value: Variant, _old: Variant) -> Variant:
		if key == "blocked":
			return Chronicle.REJECT
		return value * 2 if value is int else value)
	_chronicle.set_fact("hp", 5)
	assert_fact("hp", 10)  # interceptor doubled it
	_chronicle.set_fact("blocked", 1)
	assert_no_fact("blocked")  # interceptor rejected the write
	# Removing the interceptor (invalid Callable) restores normal writes.
	_chronicle.set_write_interceptor(Callable())
	_chronicle.set_fact("mp", 7)
	assert_fact("mp", 7)


# get_store_hard_cap reflects the configured cap (0 = disabled by default)
func test_get_store_hard_cap_reflects_setting() -> void:
	assert_eq(_chronicle.get_store_hard_cap(), 0, "store hard cap defaults to 0 (disabled)")
	_chronicle.set_store_hard_cap(5)
	assert_eq(_chronicle.get_store_hard_cap(), 5, "get_store_hard_cap returns the configured cap")
