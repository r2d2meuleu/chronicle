class_name ChronicleTypeCodec
extends RefCounted

const _JSON_SAFE_INT_MAX: int = 9007199254740992

var _registry: ChronicleTypeRegistry


func _init(registry: ChronicleTypeRegistry) -> void:
	_registry = registry


func encode_value(value: Variant, _depth: int = 64) -> Variant:
	if value == null:
		return null
	if _depth <= 0:
		push_error("[Chronicle] encode_value: max recursion depth reached.")
		return null
	var t: int = typeof(value)

	# Must precede the primitives check — float is not pass-through.
	if t == TYPE_FLOAT:
		if is_nan(value):
			return {ChronicleTypeRegistry.TAG_KEY: "float_special", "v": "nan"}
		if is_inf(value):
			if value > 0:
				return {ChronicleTypeRegistry.TAG_KEY: "float_special", "v": "inf"}
			else:
				return {ChronicleTypeRegistry.TAG_KEY: "float_special", "v": "-inf"}
		if absf(value) <= float(_JSON_SAFE_INT_MAX) and value == float(int(value)):
			return {ChronicleTypeRegistry.TAG_KEY: "float_special", "v": "whole", "n": value}
		return value

	if t == TYPE_INT:
		if value > _JSON_SAFE_INT_MAX or value < -_JSON_SAFE_INT_MAX:
			return {ChronicleTypeRegistry.TAG_KEY: "int_large", "v": str(value)}
		return value

	if t == TYPE_BOOL or t == TYPE_STRING:
		return value

	if t == TYPE_ARRAY:
		var result: Array[Variant] = []
		for item: Variant in value:
			result.append(encode_value(item, _depth - 1))
		return result

	if t == TYPE_DICTIONARY:
		var result: Dictionary = {}
		for k: Variant in value:
			if k is not String:
				push_error("[Chronicle] TypeCodec: non-String dictionary key (%s) — skipping." % type_string(typeof(k)))
				continue
			result[k] = encode_value(value[k], _depth - 1)
		if ChronicleTypeRegistry.TAG_KEY in result:
			return {ChronicleTypeRegistry.TAG_KEY: "escaped_dict", "_data": result}
		return result

	var handler: Variant = _registry.get_handler_for_value(value)
	if handler != null:
		var h: ChronicleTypeRegistry.TypeHandler = handler
		var packed: Variant = h.pack.call(value)
		# User-registered types (empty keys) may return raw floats needing recursion; built-ins handle it themselves.
		if h.required_keys.is_empty():
			return encode_value(packed, _depth - 1)
		return packed

	push_error("[Chronicle] Cannot serialize type %s (%d). Store only bool, int, float, String, Array, Dictionary, or call Chronicle.register_type() / Chronicle.register_script_type() to add support." % [type_string(t), t])
	return null


## Do NOT call twice on the same value — repeated restore corrupts whole floats to int.
func decode_value(value: Variant, _depth: int = 64) -> Variant:
	if _depth <= 0:
		push_error("[Chronicle] decode_value: max recursion depth reached.")
		return null
	if value is Dictionary:
		if value.has(ChronicleTypeRegistry.TAG_KEY):
			var tag: String = value[ChronicleTypeRegistry.TAG_KEY]
			if tag == "float_special":
				var v: String = value.get("v", "")
				match v:
					"nan": return NAN
					"inf": return INF
					"-inf": return -INF
					"whole":
						var n: Variant = value.get("n", null)
						if not (n is int or n is float):
							push_warning("[Chronicle] float_special 'whole' has non-numeric 'n': %s — defaulting to 0.0." % str(n))
							return 0.0
						return float(n)
				push_warning("[Chronicle] Unknown float_special value: \"%s\"" % v)
				return 0.0
			if tag == "int_large":
				var v_str: String = value.get("v", "0")
				if v_str.is_valid_int():
					return int(v_str)
				push_warning("[Chronicle] int_large has non-integer 'v': \"%s\" — defaulting to 0." % v_str)
				return 0
			# User dict that contained TAG_KEY — unwrap the escape wrapper.
			if tag == "escaped_dict":
				if not value.has("_data"):
					push_error("[Chronicle] escaped_dict missing '_data' key — data lost.")
					return {}
				var data: Dictionary = value.get("_data", {})
				var restored: Dictionary = {}
				for k: Variant in data:
					restored[k] = decode_value(data[k], _depth - 1)
				return restored
			var handler: ChronicleTypeRegistry.TypeHandler = _registry.get_handler(tag)
			if handler != null:
				if not handler.required_keys.is_empty():
					for rk: String in handler.required_keys:
						if not value.has(rk):
							push_warning("[Chronicle] Type \"%s\" missing required key \"%s\" — fact dropped." % [tag, rk])
							return null
				return handler.unpack.call(value)
			push_warning("[Chronicle] Unknown type tag: \"%s\" — fact dropped." % tag)
			return null
		var result: Dictionary = {}
		for k: Variant in value:
			var restored: Variant = decode_value(value[k], _depth - 1)
			if restored == null and value[k] != null:
				push_warning("[Chronicle] decode_value: dict value for key \"%s\" dropped (unknown type or depth exceeded)." % str(k))
			result[k] = restored
		return result
	if value is Array:
		var result: Array[Variant] = []
		for item: Variant in value:
			var restored: Variant = decode_value(item, _depth - 1)
			if restored == null and item != null:
				push_warning("[Chronicle] decode_value: array element dropped (unknown type or depth exceeded).")
			result.append(restored)
		return result
	# Restore integers from JSON roundtrip: JSON parses whole numbers as float.
	if value is float and is_finite(value) and absf(value) <= 9007199254740992.0:
		if value == float(int(value)):
			return int(value)
	return value
