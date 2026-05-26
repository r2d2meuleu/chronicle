extends RefCounted
class_name ChronicleRollback


var _timeline: ChronicleTimeline
var _store: ChronicleStore
var _key_codec: ChronicleKeyCodec


func _init(timeline: ChronicleTimeline, store: ChronicleStore, key_codec: ChronicleKeyCodec) -> void:
	_timeline = timeline
	_store = store
	_key_codec = key_codec


func rollback_to(target_time: float) -> ChronicleRollbackResult:
	var cut: int = _timeline.bisect_after(target_time)
	if cut >= _timeline.size():
		var result := ChronicleRollbackResult.new()
		result.success = true
		result._target_time = target_time
		return result
	return _execute(cut, target_time)


## Skips transient facts when counting steps.
func rollback_steps(step_count: int) -> ChronicleRollbackResult:
	if _timeline.size() == 0:
		var result := ChronicleRollbackResult.new()
		result.success = true
		return result
	var steps_reverted: int = 0
	var cut: int = _timeline.size()
	for i: int in range(_timeline.size() - 1, -1, -1):
		var entry: ChronicleTimeline.Entry = _timeline.get_at(i)
		if _store.is_transient(entry.norm_key):
			continue
		steps_reverted += 1
		cut = i
		if steps_reverted == step_count:
			break
	if steps_reverted == 0:
		var result := ChronicleRollbackResult.new()
		result.success = true
		return result
	var target_time: float
	if cut > 0:
		target_time = _timeline.get_at(cut - 1).time
	else:
		target_time = 0.0
	if steps_reverted < step_count:
		var result := _execute(cut, target_time)
		result.success = false
		result.partial = true
		result.steps_reverted = steps_reverted
		return result
	var result := _execute(cut, target_time)
	result.steps_reverted = steps_reverted
	return result


## Transient facts are excluded from rollback: they are not restored and not counted as steps.
## A transient fact set at time T will survive rollback past T with its current value.
## This is by design — transient facts represent ephemeral state outside the timeline.
func _execute(cut: int, target_time: float) -> ChronicleRollbackResult:
	var restore_map: Dictionary[String, Dictionary] = {}
	for i: int in range(cut, _timeline.size()):
		var entry: ChronicleTimeline.Entry = _timeline.get_at(i)
		var norm_key: String = entry.norm_key
		if _store.is_transient(norm_key):
			continue
		if norm_key not in restore_map:
			var current_value: Variant = _store.get_value(norm_key, null)
			var safe_old: Variant = current_value
			restore_map[norm_key] = {
				display_key = entry.display_key,
				restore_value = entry.old_value,
				pre_rollback_value = safe_old,
				old_transient = entry.old_transient,
				old_expire_at = entry.old_expire_at,
			}

	var result := ChronicleRollbackResult.new()
	result.success = true
	result._target_time = target_time
	result._restore_map = restore_map
	result._cut = cut
	return result
