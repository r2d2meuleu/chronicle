## Owns key grammar: validation, normalization.
##
## Key naming lifecycle:
##   raw_key   — user-supplied string (e.g. "health", "player.health")
##   norm_key  — internal normalized form: always has entity prefix (e.g. "_global.health", "player.health")
##   display_key — denormalized for user display: strips "_global." prefix (e.g. "health", "player.health")
##
## raw_key → validate_and_normalize() → norm_key
## norm_key → denormalize() → display_key
class_name ChronicleKeyCodec
extends RefCounted

const GLOBAL_ENTITY_PREFIX: String = "_global."
const MAX_KEY_LENGTH: int = 256
const _ORD_DOT := 46
const _ORD_ASTERISK := 42
const _ORD_UNDERSCORE := 95
const _ORD_LOWER_A := 97
const _ORD_LOWER_Z := 122
const _ORD_UPPER_A := 65
const _ORD_UPPER_Z := 90
const _ORD_DIGIT_0 := 48
const _ORD_DIGIT_9 := 57
const _NORM_CACHE_CAP: int = 2048

var _norm_cache: ChronicleRingCache
var _denorm_cache: ChronicleRingCache
var _warn_fn: Callable
var _validate_pattern_fn: Callable


func _init(warn_fn: Callable) -> void:
	_warn_fn = warn_fn
	_norm_cache = ChronicleRingCache.new(_NORM_CACHE_CAP)
	_denorm_cache = ChronicleRingCache.new(_NORM_CACHE_CAP)


func set_validate_pattern_fn(fn: Callable) -> void:
	_validate_pattern_fn = fn


## Results are ring-buffer cached (FIFO eviction).
func validate_and_normalize(raw_key: String) -> String:
	var cached: Variant = _norm_cache.get_or_null(raw_key)
	if cached != null:
		return cached
	var err: String = validate_key(raw_key)
	if not err.is_empty():
		push_error("[Chronicle] Invalid key \"%s\": %s" % [raw_key, err])
		# Invalid keys cached as "" sentinel; separate cache instance with 2048 cap prevents pollution.
		_norm_cache.put(raw_key, "")
		return ""
	var has_dot: bool = "." in raw_key
	var norm: String = raw_key if has_dot else GLOBAL_ENTITY_PREFIX + raw_key
	_norm_cache.put(raw_key, norm)
	_denorm_cache.put(norm, raw_key)
	return norm


## Returns true if a user-supplied key or pattern targets the reserved internal
## "_global" namespace. Exact keys, watch patterns, and query patterns are all held
## to this rule so users cannot read/watch Chronicle's internal global facts.
static func is_reserved(raw: String) -> bool:
	return raw == "_global" or raw.begins_with("_global.")


## Returns an error message string, or "" if valid.
## Rejects the reserved "_global." prefix — use for user-supplied keys only.
static func validate_key(raw_key: String) -> String:
	var err: String = validate_key_syntax(raw_key)
	if not err.is_empty():
		return err
	if is_reserved(raw_key):
		return "reserved internal prefix \"_global\" — use keys without a namespace (e.g. \"health\" not \"_global.health\")"
	return ""


## Validates key character set, length, and structure without checking reserved prefixes.
## Use for normalized/internal keys (e.g. deserialized data that legitimately uses "_global.").
static func validate_key_syntax(raw_key: String) -> String:
	if raw_key.is_empty():
		return "empty key"
	if raw_key.length() > MAX_KEY_LENGTH:
		return "key length %d exceeds maximum %d" % [raw_key.length(), MAX_KEY_LENGTH]
	for i: int in range(raw_key.length()):
		var c: int = raw_key.unicode_at(i)
		if c == _ORD_DOT:
			continue
		elif not ((c >= _ORD_LOWER_A and c <= _ORD_LOWER_Z) or (c >= _ORD_DIGIT_0 and c <= _ORD_DIGIT_9) or c == _ORD_UNDERSCORE):
			if c == _ORD_ASTERISK:
				return "wildcard in key \"%s\"" % raw_key
			if c >= _ORD_UPPER_A and c <= _ORD_UPPER_Z:
				return "uppercase char '%s' at position %d in key \"%s\" — use lowercase [a-z0-9_.]" % [char(c), i, raw_key]
			return "invalid char '%s' at position %d in key \"%s\" — use [a-z0-9_.]" % [char(c), i, raw_key]
	if raw_key.begins_with("."):
		return "invalid key \"%s\" — must not start with a dot" % raw_key
	if raw_key.ends_with("."):
		return "invalid key \"%s\" — must not end with a dot" % raw_key
	if ".." in raw_key:
		return "invalid key \"%s\" — consecutive dots not allowed" % raw_key
	return ""


static func parse_entity(norm_key: String) -> String:
	var dot_pos: int = norm_key.find(".")
	if dot_pos == -1:
		return norm_key
	return norm_key.substr(0, dot_pos)


func normalize_unchecked(raw_key: String) -> String:
	if raw_key.is_empty():
		return ""
	if "." in raw_key:
		return raw_key
	return GLOBAL_ENTITY_PREFIX + raw_key


func denormalize(norm_key: String) -> String:
	var cached: Variant = _denorm_cache.get_or_null(norm_key)
	if cached != null:
		return cached
	var display: String
	if norm_key.begins_with(GLOBAL_ENTITY_PREFIX):
		display = norm_key.substr(GLOBAL_ENTITY_PREFIX.length())
	else:
		display = norm_key
	_denorm_cache.put(norm_key, display)
	return display


func validate_watch_pattern(pattern: String) -> String:
	# Reserved-prefix guard applies to patterns too (consistent with exact keys via
	# validate_key) — a wildcard like "_global.*" must not expose internal global facts.
	if is_reserved(pattern):
		return "reserved internal prefix \"_global\" — patterns must not target the internal global namespace"
	if "*" not in pattern:
		return validate_key(pattern)
	var validate: Callable = _validate_pattern_fn if _validate_pattern_fn.is_valid() else ChroniclePatternMatcher.validate
	return validate.call(pattern)


func normalize_pattern(pattern: String) -> String:
	if pattern == "*":
		return pattern
	if pattern != pattern.to_lower():
		push_error("[Chronicle] Pattern \"%s\" contains uppercase characters. Keys and patterns must be lowercase." % pattern)
		return ""
	if "*" in pattern:
		# Reserved-prefix guard (consistent with exact keys / validate_watch_pattern).
		if is_reserved(pattern):
			_warn_fn.call("Invalid query pattern \"%s\": reserved internal prefix \"_global\"" % pattern)
			return ""
		var validate: Callable = _validate_pattern_fn if _validate_pattern_fn.is_valid() else ChroniclePatternMatcher.validate
		var err: String = validate.call(pattern)
		if not err.is_empty():
			_warn_fn.call("Invalid query pattern \"%s\": %s" % [pattern, err])
			return ""
		return pattern
	var err: String = validate_key(pattern)
	if not err.is_empty():
		_warn_fn.call("Invalid query pattern \"%s\": %s" % [pattern, err])
		return ""
	return pattern if "." in pattern else GLOBAL_ENTITY_PREFIX + pattern


func denormalize_pattern(pattern: String) -> String:
	if pattern == "*":
		return pattern
	if "*" in pattern:
		return pattern
	return denormalize(pattern)


func clear() -> void:
	_norm_cache.clear()
	_denorm_cache.clear()


static func build_key(segments: Array[String]) -> String:
	var cleaned: Array[String] = []
	for segment: String in segments:
		var original: String = segment
		var s: String = segment
		s = s.to_lower()
		s = s.strip_edges()
		var sanitized: String = ""
		for i: int in range(s.length()):
			var c: int = s.unicode_at(i)
			if (c >= _ORD_LOWER_A and c <= _ORD_LOWER_Z) or (c >= _ORD_DIGIT_0 and c <= _ORD_DIGIT_9) or c == _ORD_UNDERSCORE:
				sanitized += s[i]
			else:
				sanitized += "_"
		s = sanitized
		var before_strip: String = s
		while s.begins_with("_"):
			s = s.substr(1)
		while s.ends_with("_"):
			s = s.substr(0, s.length() - 1)
		if s != before_strip and not before_strip.is_empty():
			push_warning("[Chronicle] build_key: segment \"%s\" sanitized to \"%s\"." % [original.strip_edges(), s])
		if s.is_empty():
			continue
		if s.is_valid_int():
			s = "_" + s
			push_warning("[Chronicle] build_key: numeric segment \"%s\" prefixed to \"%s\"." % [original.strip_edges(), s])
		cleaned.append(s)
	if cleaned.is_empty() and not segments.is_empty():
		push_warning("[Chronicle] build_key: all segments were stripped — returning empty key.")
	return ".".join(cleaned)
