extends RefCounted
class_name ChronicleDeferredQueue


const QUEUE_CAP: int = 64
const DRAIN_CAP: int = 256
var _queue: Array[Callable] = []
var _drain_index: int = 0
var _cascade_warn_emitted: bool = false


func enqueue(op: Callable, context: String, cascade_depth: int,
		max_cascade: int, warn_fn: Callable) -> bool:
	if (_queue.size() - _drain_index) >= QUEUE_CAP:
		push_error("[Chronicle] Deferred queue overflow in %s — operation dropped." % context)
		return false
	if cascade_depth >= max_cascade and not _cascade_warn_emitted:
		warn_fn.call("Cascade depth %d reached in %s." % [max_cascade, context])
		_cascade_warn_emitted = true
	_queue.append(op)
	return true


func drain(transition_fn: Callable, mode_idle: int, mode_draining: int, warn_fn: Callable) -> void:
	if not transition_fn.call(mode_draining):
		return
	_drain_index = 0
	var drain_count: int = 0
	while _drain_index < _queue.size():
		if drain_count >= DRAIN_CAP:
			push_error("[Chronicle] Drain iteration cap (%d) reached. Breaking watcher cascade loop." % DRAIN_CAP)
			break
		var entry: Callable = _queue[_drain_index]
		_drain_index += 1
		if not entry.is_valid():
			push_error("[Chronicle] DeferredQueue contained an invalid Callable — skipping.")
			continue
		entry.call()
		drain_count += 1
	if _drain_index < _queue.size():
		_queue = _queue.slice(_drain_index)
		_cascade_warn_emitted = false
		warn_fn.call("Cascade drain cap hit — %d entries remain, resuming next write." % _queue.size())
	else:
		_queue.clear()
		if drain_count > 0 and _cascade_warn_emitted:
			warn_fn.call("Cascade resolved: %d deferred facts drained." % drain_count)
		_cascade_warn_emitted = false
	_drain_index = 0
	transition_fn.call(mode_idle)


func is_empty() -> bool:
	return _drain_index >= _queue.size()


func clear() -> void:
	_queue.clear()
	_drain_index = 0
	_cascade_warn_emitted = false
