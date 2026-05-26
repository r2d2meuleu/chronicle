## See ChronicleTypeCodec for encoding/decoding, builtin_types.gd for registrations.
class_name ChronicleTypeRegistry
extends RefCounted

const TAG_KEY := "_chronicle_type"


class TypeHandler extends RefCounted:
	var type_id: int
	var tag: String
	var pack: Callable
	var unpack: Callable
	var copy: Callable
	var required_keys: Array[String]
	var truthy_fn: Callable
	func _init(tid: int, t: String, p: Callable, u: Callable,
			c: Callable, k: Array[String], tf: Callable) -> void:
		type_id = tid
		tag = t
		pack = p
		unpack = u
		copy = c
		required_keys = k
		truthy_fn = tf


var _type_handlers: Dictionary[String, TypeHandler] = {}
var _script_handlers: Dictionary = {}  # GDScript -> TypeHandler

var _type_id_to_tag: Dictionary[int, String] = {}
var _type_id_to_copy_fn: Dictionary[int, Callable] = {}

const VALID_TYPES: Dictionary[int, bool] = {
	TYPE_BOOL: true,
	TYPE_INT: true,
	TYPE_FLOAT: true,
	TYPE_STRING: true,
	TYPE_ARRAY: true,
	TYPE_DICTIONARY: true,
}

const _RESERVED_TAGS: PackedStringArray = ["float_special", "escaped_dict", "int_large"]


func register_type(type_id: int, tag: String, pack_fn: Callable, unpack_fn: Callable, copy_fn: Callable = Callable(), keys: Array[String] = [], truthy_fn: Callable = Callable(), force: bool = false) -> bool:
	# Validate before any state changes
	if not pack_fn.is_valid():
		push_error("[Chronicle] register_type(\"%s\"): pack Callable is invalid." % tag)
		return false
	if not unpack_fn.is_valid():
		push_error("[Chronicle] register_type(\"%s\"): unpack Callable is invalid." % tag)
		return false
	if tag.is_empty():
		push_error("[Chronicle] register_type(): tag must be a non-empty string.")
		return false
	if tag in _RESERVED_TAGS:
		push_error("[Chronicle] register_type(): tag \"%s\" is reserved for internal serialization." % tag)
		return false
	if tag in _type_handlers:
		if not force:
			push_error("[Chronicle] Type tag '%s' already registered. Use force=true to override." % tag)
			return false
		# force=true: check type_id collision BEFORE erasing old entry
		var old_handler: TypeHandler = _type_handlers[tag]
		if type_id != old_handler.type_id and type_id in _type_id_to_tag:
			push_error("[Chronicle] register_type() collision: type_id %d already registered as \"%s\"." % [type_id, _type_id_to_tag[type_id]])
			return false
		_type_id_to_tag.erase(old_handler.type_id)
		_type_id_to_copy_fn.erase(old_handler.type_id)
		_type_handlers.erase(tag)
	elif type_id in _type_id_to_tag:
		push_error("[Chronicle] register_type() collision: type_id %d already registered as \"%s\"." % [type_id, _type_id_to_tag[type_id]])
		return false
	if not copy_fn.is_valid():
		var _pack := pack_fn
		var _unpack := unpack_fn
		copy_fn = func(v: Variant) -> Variant: return _unpack.call(_pack.call(v))
	# No state was mutated above on the happy path
	_type_handlers[tag] = TypeHandler.new(type_id, tag, pack_fn, unpack_fn, copy_fn, keys, truthy_fn)
	_type_id_to_tag[type_id] = tag
	_type_id_to_copy_fn[type_id] = copy_fn
	return true


func unregister_type(type_id: int) -> bool:
	if type_id not in _type_id_to_tag:
		return false
	var tag: String = _type_id_to_tag[type_id]
	_type_handlers.erase(tag)
	_type_id_to_tag.erase(type_id)
	_type_id_to_copy_fn.erase(type_id)
	return true


func get_handler(tag: String) -> Variant:
	return _type_handlers.get(tag, null)


func get_tag_for_type(type_id: int) -> String:
	return _type_id_to_tag.get(type_id, "")


func is_type_registered(type_id: int) -> bool:
	return type_id in _type_id_to_tag


func get_truthy_fn(type_id: int) -> Callable:
	var tag: String = get_tag_for_type(type_id)
	if tag.is_empty():
		return Callable()
	var handler: TypeHandler = _type_handlers.get(tag, null)
	if handler == null:
		return Callable()
	return handler.truthy_fn


func copy_value(value: Variant) -> Variant:
	var type_id: int = typeof(value)
	if type_id in _type_id_to_copy_fn:
		var fn: Callable = _type_id_to_copy_fn[type_id]
		if fn.is_valid():
			return fn.call(value)
	return value


func is_valid_type(value: Variant, depth: int = 64) -> bool:
	if value == null:
		return true
	var t: int = typeof(value)
	if t in VALID_TYPES:
		if t == TYPE_ARRAY:
			if depth <= 0:
				return false
			for item: Variant in value:
				if not is_valid_type(item, depth - 1):
					return false
			return true
		if t == TYPE_DICTIONARY:
			if depth <= 0:
				return false
			for key: Variant in value:
				if typeof(key) != TYPE_STRING:
					return false
				if not is_valid_type(value[key], depth - 1):
					return false
			return true
		return true
	if value is Object and value.get_script() != null and value.get_script() in _script_handlers:
		return true
	return is_type_registered(t)


## Registers a script-based custom type for serialization. Unlike [method register_type], this
## matches values by their attached GDScript rather than by Godot type_id, enabling support for
## script-defined value objects (e.g. custom Resource subclasses).
func register_script_type(script: GDScript, tag: String, pack_fn: Callable,
		unpack_fn: Callable, copy_fn: Callable = Callable(),
		required_keys: Array[String] = [], truthy_fn: Callable = Callable()) -> bool:
	if tag in _type_handlers:
		push_error("[Chronicle] Tag '%s' already registered." % tag)
		return false
	if tag in _RESERVED_TAGS:
		push_error("[Chronicle] Tag '%s' is reserved." % tag)
		return false
	if not copy_fn.is_valid():
		var _pack := pack_fn
		var _unpack := unpack_fn
		copy_fn = func(v: Variant) -> Variant: return _unpack.call(_pack.call(v))
	var handler := TypeHandler.new(TYPE_OBJECT, tag, pack_fn, unpack_fn, copy_fn, required_keys, truthy_fn)
	_type_handlers[tag] = handler
	_script_handlers[script] = handler
	return true


## Returns the handler for a value, checking script-based handlers first, then type_id-based.
## Returns [code]null[/code] if no handler is found.
func get_handler_for_value(value: Variant) -> Variant:
	if value is Object and value.get_script() != null and value.get_script() in _script_handlers:
		return _script_handlers[value.get_script()]
	var tag: String = _type_id_to_tag.get(typeof(value), "")
	if tag.is_empty():
		return null
	return _type_handlers.get(tag)


func clear_handlers() -> void:
	_type_handlers.clear()
	_type_id_to_tag.clear()
	_type_id_to_copy_fn.clear()
	_script_handlers.clear()
