## Ring-buffer-backed timeline that records every fact mutation in chronological order.
extends RefCounted
class_name ChronicleTimeline

class Entry extends RefCounted:
	var display_key: String
	var norm_key: String
	var value: Variant
	var old_value: Variant
	var time: float
	var tick: int
	var expire_at: float
	var old_expire_at: float
	var old_transient: bool

	static func create(p_key: String, p_norm_key: String, p_value: Variant, p_old_value: Variant,
			p_time: float, p_tick: int, p_expire_at: float,
			p_old_expire_at: float, p_old_transient: bool) -> Entry:
		var e := Entry.new()
		e.display_key = p_key
		e.norm_key = p_norm_key
		e.value = p_value
		e.old_value = p_old_value
		e.time = p_time
		e.tick = p_tick
		e.expire_at = p_expire_at
		e.old_expire_at = p_old_expire_at
		e.old_transient = p_old_transient
		return e

	func copy(copy_fn: Callable) -> Entry:
		return Entry.create(display_key, norm_key, copy_fn.call(value), copy_fn.call(old_value),
			time, tick, expire_at, old_expire_at, old_transient)

	func to_dict() -> Dictionary:
		return {key = display_key, value = value, old_value = old_value, time = time}



# Array[Variant] because GDScript typed arrays don't accept null for RefCounted element types.
var _buffer: Array[Variant] = []
var _head: int = 0
var _size: int = 0
var _tick: int = 0
var _cap: int = 10000
var _overflow_warned: bool = false
var _structural_gen: int = 0

var _copy_fn: Callable
var _warn_fn: Callable


func _init(copy_fn: Callable, warn_fn: Callable) -> void:
	_copy_fn = copy_fn
	_warn_fn = warn_fn
	_buffer.resize(_cap)


func set_cap(cap: int) -> void:
	if cap <= 0:
		push_error("[Chronicle] Timeline cap must be > 0 (received %d) — ignored." % cap)
		return
	if cap == _cap:
		return
	if cap < _size:
		var drop: int = _size - cap
		var orig_size: int = _size
		_head = (_head + drop) % _buffer.size()
		_size = cap
		_warn_fn.call("set_cap(%d): current size %d exceeds new cap — oldest %d entries dropped." % [cap, orig_size, drop])
	_overflow_warned = false
	var old_size: int = _size
	var old_entries: Array[Variant] = []
	for i: int in range(old_size):
		old_entries.append(get_at(i))
	_cap = cap
	_buffer.resize(cap)
	_buffer.fill(null)
	_head = 0
	_size = old_size
	for i: int in range(old_size):
		_buffer[i] = old_entries[i]
	_tick += 1
	_structural_gen += 1


## value is copied via the injected copy_fn; old_value must already be copied by the caller.
func append(display_key: String, norm_key: String, value: Variant, old_value: Variant,
		time: float, expire_at: float = ChronicleExpiry.NO_EXPIRY,
		old_expire_at: float = ChronicleExpiry.NO_EXPIRY, old_transient: bool = false) -> void:
	if OS.is_debug_build() and _size > 0:
		var last_entry: Entry = get_at(_size - 1)
		if time < last_entry.time:
			push_error("[Chronicle] Timeline: non-monotonic append %.4f < %.4f" % [time, last_entry.time])
	_tick += 1
	var entry := Entry.create(display_key, norm_key, _copy_fn.call(value), old_value,
		time, _tick, expire_at, old_expire_at, old_transient)
	_push_entry(entry)


func _push_entry(entry: Entry) -> void:
	if _size < _cap:
		_buffer[(_head + _size) % _cap] = entry
		_size += 1
	else:
		_buffer[_head] = entry
		_head = (_head + 1) % _cap
		_structural_gen += 1
		if not _overflow_warned:
			_warn_fn.call("Timeline at cap (%d) — oldest entries are being dropped." % _cap)
			_overflow_warned = true


func get_at(logical_index: int) -> Entry:
	if logical_index < 0 or logical_index >= _size:
		return null
	var physical: int = (_head + logical_index) % _cap
	return _buffer[physical]


func _bisect(target_time: float, inclusive: bool) -> int:
	var lo: int = 0
	var hi: int = _size
	while lo < hi:
		var mid: int = (lo + hi) / 2
		var entry: Entry = get_at(mid)
		if entry == null:
			push_error("[Chronicle] _bisect: null entry at logical index %d (size=%d, head=%d)" % [mid, _size, _head])
			return lo
		var entry_time: float = entry.time
		var cmp: bool = (entry_time <= target_time) if inclusive else (entry_time < target_time)
		if cmp:
			lo = mid + 1
		else:
			hi = mid
	return lo


func bisect_at_or_after(target_time: float) -> int:
	return _bisect(target_time, false)


func bisect_after(target_time: float) -> int:
	return _bisect(target_time, true)


func get_tick() -> int:
	return _tick


func set_tick(new_tick: int) -> void:
	_tick = new_tick


func get_structural_gen() -> int:
	return _structural_gen


func get_cap() -> int:
	return _cap


func size() -> int:
	return _size


func is_empty() -> bool:
	return _size == 0


func truncate(new_size: int) -> void:
	if new_size < 0:
		new_size = 0
	if new_size > _size:
		new_size = _size
	if new_size == _size:
		return
	for i: int in range(new_size, _size):
		_buffer[(_head + i) % _cap] = null
	_size = new_size
	_tick += 1
	_structural_gen += 1


func set_entries(entries: Array[Variant]) -> void:
	_buffer.resize(_cap)
	_buffer.fill(null)
	_head = 0
	_overflow_warned = false
	var valid_count: int = 0
	var start: int = maxi(0, entries.size() - _cap)
	for j: int in range(start, entries.size()):
		var e: Variant = entries[j]
		if e is Entry:
			_buffer[valid_count] = e.copy(_copy_fn)
			valid_count += 1
		elif e is Dictionary:
			_buffer[valid_count] = Entry.create(
				e.get("key", ""), e.get("norm_key", ""), _copy_fn.call(e.get("value", null)),
				_copy_fn.call(e.get("old_value", null)),
				e.get("time", 0.0), e.get("tick", 0),
				e.get("expire_at", ChronicleExpiry.NO_EXPIRY), e.get("old_expire_at", ChronicleExpiry.NO_EXPIRY),
				e.get("old_transient", false))
			valid_count += 1
		else:
			_warn_fn.call("set_entries: skipped element at index %d (type %s)." % [j, type_string(typeof(e))])
	_size = valid_count
	_structural_gen += 1


func clear() -> void:
	_buffer.fill(null)
	_head = 0
	_size = 0
	_tick = 0
	_overflow_warned = false
	_structural_gen += 1
