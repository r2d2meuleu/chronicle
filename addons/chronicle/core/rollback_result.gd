class_name ChronicleRollbackResult
extends RefCounted

## Whether the rollback completed successfully. [code]false[/code] on partial revert or failure.
var success: bool = false
## [code]true[/code] when the rollback partially succeeded (fewer steps than requested). State IS modified.
var partial: bool = false
## Number of non-transient timeline entries actually reverted.
var steps_reverted: int = 0
## The [code]step_count[/code] originally passed to [method Chronicle.rollback_steps].
var requested: int = 0
## Error description, or empty string on success.
var error: String = ""

## Internal: {norm_key: {display_key, restore_value, pre_rollback_value, old_transient, old_expire_at}}
var _restore_map: Dictionary = {}
## Internal: entries at and after this index are removed from the timeline.
var _cut: int = 0
## Internal: the target time for the rollback.
var _target_time: float = 0.0
## Internal: only set on FAILED — the earliest entry time in the timeline. Vestigial; kept for debug introspection.
var _first_entry_time: float = 0.0
