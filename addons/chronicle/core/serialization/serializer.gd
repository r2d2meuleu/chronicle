extends RefCounted
class_name ChronicleSerializer
const SAVE_VERSION: int = 2


class Snapshot extends RefCounted:
	var game_time: float = 0.0
	var tick: int = 0
	var facts: Dictionary = {}
	var timeline_entries: Array[Dictionary] = []
	var expiry_entries: Dictionary[String, float] = {}
	var auto_advance: bool = true

const SERIALIZE_ALL: int = -1

var _user_migrations: Dictionary[int, Callable] = {}
var _builtin_migrations: Dictionary[int, Callable] = {}


func clear_user_migrations() -> void:
	_user_migrations.clear()

var _store: ChronicleStore
var _key_codec: ChronicleKeyCodec
var _serialize_cap: int
var _deserialize_cap: int
var _codec: ChronicleTypeCodec
var _registry: ChronicleTypeRegistry


func register_migration(from_version: int, migrate_fn: Callable, force: bool = false) -> bool:
	if not migrate_fn.is_valid():
		push_error("[Chronicle] register_migration(%d): migrate_fn must be a valid Callable." % from_version)
		return false
	if from_version in _user_migrations and not force:
		push_error("[Chronicle] register_migration(%d): already registered. Pass force=true to override." % from_version)
		return false
	if from_version in _builtin_migrations:
		push_warning("[Chronicle] register_migration(%d): overrides built-in migration." % from_version)
	_user_migrations[from_version] = migrate_fn
	return true


func _init(
	store: ChronicleStore,
	key_codec: ChronicleKeyCodec,
	codec: ChronicleTypeCodec,
	registry: ChronicleTypeRegistry,
	serialize_cap: int = 1000,
) -> void:
	_store = store
	_key_codec = key_codec
	_codec = codec
	_registry = registry
	_serialize_cap = serialize_cap
	_deserialize_cap = serialize_cap
	_builtin_migrations[1] = func(dict: Dictionary) -> Dictionary:
		if "expiring_facts" in dict:
			dict["expiry"] = dict["expiring_facts"]
			dict.erase("expiring_facts")
		dict["version"] = 2
		return dict


func serialize(timeline: ChronicleTimeline, expiry: ChronicleExpiry, clock: ChronicleGameClock = null, timeline_cap: int = SERIALIZE_ALL) -> Dictionary:
	var facts: Dictionary = {}
	for norm_key: String in _store.get_keys_raw():
		if _store.is_transient(norm_key):
			continue
		facts[norm_key] = _store.get_value(norm_key)

	var total: int = timeline.size()
	var cap: int
	if timeline_cap == SERIALIZE_ALL:
		cap = total
	elif timeline_cap > 0:
		cap = timeline_cap
	else:
		cap = _serialize_cap
	if cap <= 0:
		cap = total

	var non_transient_indices: Array[int] = []
	for i: int in range(total):
		var entry: ChronicleTimeline.Entry = timeline.get_at(i)
		if entry == null:
			continue
		if entry.old_transient or _store.is_transient(entry.norm_key):
			continue
		non_transient_indices.append(i)

	var start: int = maxi(0, non_transient_indices.size() - cap)
	var timeline_entries: Array[Dictionary] = []
	for i: int in range(start, non_transient_indices.size()):
		var entry: ChronicleTimeline.Entry = timeline.get_at(non_transient_indices[i])
		timeline_entries.append({
			"key": entry.display_key,
			"norm_key": entry.norm_key,
			"value": ChronicleValueUtils.deep_copy(entry.value, 64, _registry.copy_value),
			"old_value": ChronicleValueUtils.deep_copy(entry.old_value, 64, _registry.copy_value),
			"time": entry.time,
			"tick": entry.tick,
			"expire_at": entry.expire_at,
			"old_expire_at": entry.old_expire_at,
			"old_transient": entry.old_transient,
		})

	var expiry_data: Dictionary = {}
	var now: float = clock.get_time() if clock != null else 0.0
	var raw_entries: Dictionary = expiry.get_entries()
	for norm_key: String in raw_entries:
		if _store.is_transient(norm_key):
			continue
		var remaining: float = raw_entries[norm_key] - now
		if remaining > 0.0:
			expiry_data[norm_key] = remaining

	var result: Dictionary = {
		"version": SAVE_VERSION,
		"game_time": now,
		"tick": timeline.get_tick(),
		"facts": facts,
		"timeline": timeline_entries,
		"expiry": expiry_data,
		"auto_advance": clock.is_auto_advancing() if clock != null else true,
	}
	return _codec.encode_value(result)


func deserialize(data: Variant) -> Snapshot:
	if not (data is Dictionary):
		push_error("[Chronicle] deserialize: expected Dictionary, got %s." % type_string(typeof(data)))
		return null
	var dict: Dictionary = data
	dict = _migrate(dict)
	if dict.is_empty():
		return null
	if not dict.has("facts"):
		push_error("[Chronicle] deserialize() received invalid data — missing \"facts\" key. File may be truncated.")
		return null
	dict = _codec.decode_value(dict)
	if not dict.has("facts") or not (dict.get("facts") is Dictionary):
		push_error("[Chronicle] Deserialized data missing valid 'facts' Dictionary. Load aborted.")
		return null
	var raw_tick: Variant = dict.get("tick", 0)
	if not (raw_tick is int or raw_tick is float) or float(raw_tick) < 0.0 or float(raw_tick) > 2_000_000_000.0:
		push_warning("[Chronicle] Deserialized tick invalid — reset to 0.")
		dict["tick"] = 0
	if not (dict.get("auto_advance") is bool):
		dict["auto_advance"] = true
	var timeline_raw: Variant = dict.get("timeline", [])
	if not (timeline_raw is Array):
		push_error("[Chronicle] deserialize: 'timeline' is not an Array.")
		return null
	if timeline_raw.size() > _deserialize_cap:
		push_warning("[Chronicle] Timeline has %d entries (cap %d) — truncating to newest." % [timeline_raw.size(), _deserialize_cap])
		timeline_raw = timeline_raw.slice(timeline_raw.size() - _deserialize_cap)
	var expiry_raw: Variant = dict.get("expiry", {})
	if not (expiry_raw is Dictionary):
		push_error("[Chronicle] deserialize: 'expiry' is not a Dictionary.")
		return null
	var raw_time: Variant = dict.get("game_time", 0.0)
	var game_time: float = float(raw_time) if (raw_time is int or raw_time is float) else 0.0
	if is_nan(game_time) or is_inf(game_time) or game_time < 0.0:
		push_warning("[Chronicle] Deserialized game_time invalid — reset to 0.")
		game_time = 0.0
	var timeline_entries: Array[Dictionary] = _validate_timeline(timeline_raw)
	var expiry_entries: Dictionary[String, float] = _validate_expiry(expiry_raw, game_time)
	var validated_facts: Dictionary = {}
	for key: String in dict["facts"]:
		var key_err: String = ChronicleKeyCodec.validate_key_syntax(key)
		if not key_err.is_empty():
			push_warning("[Chronicle] Deserialized fact key '%s' is invalid (%s) — dropped." % [key, key_err])
			continue
		var val: Variant = dict["facts"][key]
		if val == null:
			push_warning("[Chronicle] Deserialized null value for key \"%s\" — skipped." % key)
			continue
		if _registry.is_valid_type(val):
			validated_facts[key] = val
		else:
			push_warning("[Chronicle] Deserialized fact '%s' has invalid type (%s) — dropped." % [key, type_string(typeof(val))])
	var raw_fact_count: int = dict.get("facts", {}).size()
	if validated_facts.size() < raw_fact_count:
		push_warning("[Chronicle] deserialize: %d of %d facts dropped due to type errors." % [raw_fact_count - validated_facts.size(), raw_fact_count])
	var s := Snapshot.new()
	s.game_time = game_time
	s.tick = int(dict.get("tick", 0))
	s.facts = validated_facts
	s.timeline_entries = timeline_entries
	s.expiry_entries = expiry_entries
	s.auto_advance = dict.get("auto_advance", true)
	return s


func _migrate(dict: Dictionary) -> Dictionary:
	var raw_version: Variant = dict.get("version", 0)
	if not (raw_version is int or raw_version is float):
		push_error("[Chronicle] deserialize: 'version' is not numeric (%s) — aborting." % type_string(typeof(raw_version)))
		return {}
	var version: int = int(raw_version)
	if version > SAVE_VERSION:
		push_error("[Chronicle] Save file version %d is newer than this build (v%d) — cannot load." % [version, SAVE_VERSION])
		return {}
	while version < SAVE_VERSION:
		var prev_version: int = version
		var migrate_fn: Variant = null
		if version in _user_migrations:
			migrate_fn = _user_migrations[version]
		elif version in _builtin_migrations:
			migrate_fn = _builtin_migrations[version]
		if migrate_fn != null:
			dict = migrate_fn.call(dict)
			if not (dict is Dictionary):
				push_error("[Chronicle] Migration from version %d returned non-Dictionary." % prev_version)
				return {}
			if not dict.has("version"):
				push_error("[Chronicle] Migration from version %d did not set 'version' key in output." % prev_version)
				return {}
			version = int(dict["version"])
			if version != prev_version + 1:
				push_error("[Chronicle] Migration from v%d produced v%d — expected v%d." % [prev_version, version, prev_version + 1])
				return {}
		else:
			push_error("[Chronicle] No migration registered for version %d → %d." % [version, SAVE_VERSION])
			return {}
	if version != SAVE_VERSION:
		push_error("[Chronicle] Data version %d does not match expected %d after migrations." % [version, SAVE_VERSION])
		return {}
	return dict


func _validate_timeline(timeline_raw: Array) -> Array[Dictionary]:
	var timeline_entries: Array[Dictionary] = []
	for raw_entry: Variant in timeline_raw:
		if not (raw_entry is Dictionary):
			push_warning("[Chronicle] Deserialize: dropping non-Dictionary timeline entry (%s)." % type_string(typeof(raw_entry)))
			continue
		var entry_key: String = raw_entry.get("key", "")
		if entry_key.is_empty() or not ChronicleKeyCodec.validate_key_syntax(entry_key).is_empty():
			push_warning("[Chronicle] Deserialized timeline entry key '%s' is invalid — dropped." % entry_key)
			continue
		var t_value: Variant = raw_entry.get("value", null)
		var t_old_value: Variant = raw_entry.get("old_value", null)
		if t_value != null and not _registry.is_valid_type(t_value):
			push_warning("[Chronicle] Timeline entry value for key '%s' has invalid type (%s) — dropped." % [entry_key, type_string(typeof(t_value))])
			continue
		if t_old_value != null and not _registry.is_valid_type(t_old_value):
			push_warning("[Chronicle] Timeline entry old_value for key '%s' has invalid type (%s) — dropped." % [entry_key, type_string(typeof(t_old_value))])
			continue
		var t_time: Variant = raw_entry.get("time", 0.0)
		if not (t_time is int or t_time is float) or is_nan(float(t_time)) or is_inf(float(t_time)):
			push_warning("[Chronicle] Deserialize: dropping timeline entry with invalid time: %s" % str(t_time))
			continue
		var t_tick: Variant = raw_entry.get("tick", 0)
		if not (t_tick is int or t_tick is float):
			push_warning("[Chronicle] Deserialize: dropping timeline entry with invalid tick: %s" % str(t_tick))
			continue
		var t_expire: Variant = raw_entry.get("expire_at", ChronicleExpiry.NO_EXPIRY)
		if not (t_expire is int or t_expire is float):
			t_expire = ChronicleExpiry.NO_EXPIRY
		var t_old_expire: Variant = raw_entry.get("old_expire_at", ChronicleExpiry.NO_EXPIRY)
		if not (t_old_expire is int or t_old_expire is float):
			t_old_expire = ChronicleExpiry.NO_EXPIRY
		var t_old_transient: Variant = raw_entry.get("old_transient", false)
		if t_old_transient is not bool:
			t_old_transient = false
		timeline_entries.append({
			"key": entry_key,
			"norm_key": _key_codec.normalize_unchecked(entry_key),
			"value": ChronicleValueUtils.deep_copy(t_value),
			"old_value": ChronicleValueUtils.deep_copy(t_old_value),
			"time": float(t_time),
			"tick": int(t_tick),
			"expire_at": float(t_expire),
			"old_expire_at": float(t_old_expire),
			"old_transient": t_old_transient as bool,
		})
	return timeline_entries


func _validate_expiry(expiry_raw: Dictionary, game_time: float) -> Dictionary[String, float]:
	var expiry_entries: Dictionary[String, float] = {}
	for norm_key: String in expiry_raw:
		var key_err: String = ChronicleKeyCodec.validate_key_syntax(norm_key)
		if not key_err.is_empty():
			push_warning("[Chronicle] Deserialized expiry key '%s' is invalid (%s) — dropped." % [norm_key, key_err])
			continue
		var raw: Variant = expiry_raw[norm_key]
		if not (raw is int or raw is float):
			push_warning("[Chronicle] deserialize: invalid expiry for \"%s\" (type %s) — skipped." % [norm_key, type_string(typeof(raw))])
			continue
		var remaining: float = float(raw)
		if is_nan(remaining) or is_inf(remaining) or remaining <= 0.0:
			push_warning("[Chronicle] deserialize: invalid expiry remaining for \"%s\" (%.4f) — skipped." % [norm_key, remaining])
			continue
		if remaining > 1_000_000.0:
			push_warning("[Chronicle] Expiry remaining for '%s' is %.1f (>1M) — clamped to 1000000." % [norm_key, remaining])
			remaining = 1_000_000.0
		expiry_entries[norm_key] = game_time + remaining
	return expiry_entries
