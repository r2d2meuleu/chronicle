class_name ChronicleValueUtils
extends RefCounted


## custom_copy_fn handles registered custom types: func(value: Variant) -> Variant.
static func deep_copy(value: Variant, max_depth: int = 64, custom_copy_fn: Callable = Callable()) -> Variant:
	if value == null:
		return null
	if max_depth <= 0:
		push_error("[Chronicle] deep_copy: max recursion depth reached.")
		return value
	var t: int = typeof(value)
	if t == TYPE_BOOL or t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_STRING:
		return value
	if t == TYPE_ARRAY:
		var copy: Array = value.duplicate(false)
		for i: int in copy.size():
			copy[i] = deep_copy(copy[i], max_depth - 1, custom_copy_fn)
		return copy
	if t == TYPE_DICTIONARY:
		var copy: Dictionary = value.duplicate(false)
		for k: Variant in copy.keys():
			copy[k] = deep_copy(copy[k], max_depth - 1, custom_copy_fn)
		return copy
	if t in _NEEDS_COPY_TYPES:
		return value.duplicate()
	if custom_copy_fn.is_valid():
		return custom_copy_fn.call(value)
	return value


static func is_valid_float(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


const _NEEDS_COPY_TYPES: Dictionary[int, bool] = {
	TYPE_ARRAY: true, TYPE_DICTIONARY: true,
	TYPE_PACKED_BYTE_ARRAY: true, TYPE_PACKED_INT32_ARRAY: true,
	TYPE_PACKED_INT64_ARRAY: true, TYPE_PACKED_FLOAT32_ARRAY: true,
	TYPE_PACKED_FLOAT64_ARRAY: true, TYPE_PACKED_STRING_ARRAY: true,
	TYPE_PACKED_VECTOR2_ARRAY: true, TYPE_PACKED_VECTOR3_ARRAY: true,
	TYPE_PACKED_VECTOR4_ARRAY: true, TYPE_PACKED_COLOR_ARRAY: true,
}


static func needs_copy(type_id: int) -> bool:
	return type_id in _NEEDS_COPY_TYPES


static func safe_copy(value: Variant, custom_copy_fn: Callable = Callable()) -> Variant:
	if value == null:
		return null
	if not needs_copy(typeof(value)):
		return value
	return deep_copy(value, 64, custom_copy_fn)


## truthy_fn_resolver looks up custom truthy handlers: func(type_id: int) -> Callable.
static func is_truthy(value: Variant, truthy_fn_resolver: Callable = Callable()) -> bool:
	if value == null:
		return false
	if value is bool:
		return value
	if value is int or value is float:
		if value is float and is_nan(value):
			return false
		return value != 0
	if value is String:
		return not value.is_empty()
	if value is Array:
		return not value.is_empty()
	if value is Dictionary:
		return not value.is_empty()
	if value is PackedByteArray or value is PackedStringArray or value is PackedInt32Array or value is PackedInt64Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedVector2Array or value is PackedVector3Array or value is PackedVector4Array or value is PackedColorArray:
		return not value.is_empty()
	if truthy_fn_resolver.is_valid():
		var truthy_fn: Callable = truthy_fn_resolver.call(typeof(value))
		if truthy_fn.is_valid():
			return truthy_fn.call(value)
	return true


static func _as_int_if_whole(v: float) -> Variant:
	var i: int = int(v)
	if float(i) == v:
		return i
	return v


static func compute_increment(current: Variant, amount: float) -> Variant:
	if current == null:
		current = 0
	if not (current is int or current is float):
		return null
	var result: float = float(current) + amount
	if is_inf(result) or is_nan(result):
		return null
	if current is int and amount == floorf(amount) and not is_inf(amount):
		return _as_int_if_whole(result)
	return result


static func compute_clamp(current: Variant, min_value: float, max_value: float) -> Variant:
	if current == null or not (current is int or current is float):
		return null
	var clamped: float = clampf(float(current), min_value, max_value)
	if is_nan(clamped):
		return null
	if float(current) == clamped:
		return current
	if current is int:
		return _as_int_if_whole(clamped)
	return clamped
