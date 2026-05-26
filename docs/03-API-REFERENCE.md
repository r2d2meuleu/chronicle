# Chronicle — API Reference

Complete reference for all public methods, signals, and constants on the `Chronicle` autoload singleton.

---

## Timeline Entry Format

Timeline entries returned by `get_first_change`, `get_last_change`, `get_fact_history`, `get_changes_since`, and `get_changes_between` are Dictionaries with these fields:

| Field | Type | Description |
|-------|------|-------------|
| `key` | `String` | The fact key (denormalized display form) |
| `value` | `Variant` | The value written (`null` for erasures) |
| `old_value` | `Variant` | The previous value before this write |
| `time` | `float` | Game clock time at write (`get_game_time()`) |
| `tick` | `int` | Monotonic write counter |

```gdscript
var entry: Dictionary = Chronicle.get_last_change("player.*")
# entry.key      -> "player.gold"
# entry.value    -> 250
# entry.old_value -> 100
# entry.time     -> 45.2
# entry.tick     -> 17
```

---

## Enums

### `EraseSource`

Re-exported from `ChronicleWriteCoordinator`. Identifies why a fact was erased. Passed as the fourth argument to `fact_changed` listeners when `value` is `null`.

| Value | When |
|-------|------|
| `EraseSource.USER` | Explicit `erase_fact()` or overwrite with `null` |
| `EraseSource.EXPIRY` | Fact's lifetime expired |
| `EraseSource.ROLLBACK` | Fact removed during rollback |

---

## Constants and Sentinels

### `REJECT: RefCounted` (static var)


Sentinel value. Return from a write interceptor (registered via `set_write_interceptor()`) to reject the write entirely. The fact will not be changed.

```gdscript
Chronicle.set_write_interceptor(func(key, value, old_value):
    if key == "player.health" and value < 0:
        return Chronicle.REJECT  # block negative health
    return value
)
```

### `DEFERRED: RefCounted` (static var)

Sentinel value returned by `toggle_fact()`, `increment_fact()`, and `clamp_fact()` when the write is deferred because it was called from inside a watcher callback at maximum cascade depth. Compare with `is` or `==` to detect deferral.

> **Note:** `set_fact()` and `erase_fact()` signal deferral through their `bool` return value (`false`) rather than returning `DEFERRED`.

```gdscript
var result: Variant = Chronicle.toggle_fact("light.on")
if result is RefCounted and result == Chronicle.DEFERRED:
    print("Write was deferred to a queue")
```

### `KEEP_LIFETIME: float = -2.0`

Sentinel value for the `lifetime` parameter. Preserves a fact's existing expiry unchanged. This is the default for all write methods. Pass `0.0` to explicitly clear an existing expiry.

```gdscript
Chronicle.set_fact("quest.started", true, false, Chronicle.KEEP_LIFETIME)
```

### `SERIALIZE_ALL: int = -1`

Pass as `timeline_cap` to `serialize()` to include every timeline entry, bypassing the project setting cap.

```gdscript
var full_data: Dictionary = Chronicle.serialize(Chronicle.SERIALIZE_ALL)
```

### `EXPIRY_NONE: float = -1.0`

Returned by `get_expiry_remaining()` when a fact has no expiry set.

```gdscript
var remaining: float = Chronicle.get_expiry_remaining("buff.shield")
if remaining == Chronicle.EXPIRY_NONE:
    print("No expiry")
```

### `SERIALIZE_USE_SETTING: int = 0`

Default value for `serialize()`'s `timeline_cap` parameter. Uses the project setting (`chronicle/storage/serialize_timeline_cap`, default 1000).

---

## Signals

### `fact_changed(key: String, value: Variant, old_value: Variant, erase_source: EraseSource)`

Emitted after any fact write. The `erase_source` parameter is only meaningful when `value` is `null` (erasure); otherwise it is always `EraseSource.USER`.

```gdscript
Chronicle.fact_changed.connect(func(key, value, old_value, source):
    if value == null:
        print("%s erased by %s" % [key, source])
)
```

### `state_reset`

Emitted after state has been fully reset (via `clear()`, `deserialize()`, or rollback with changes). When fired after rollback, `state_rolled_back` fires first.

### `state_rolled_back(target_time: float)`

Emitted after a successful rollback to the given game time. Fires before `state_reset`. Writes triggered by rollback-dispatch handlers are deferred and not yet visible when this signal fires.

### `fact_expired(key: String, expired_value: Variant)`

Emitted when a fact's lifetime expires and it is removed from the store. Destructive operations (`clear`, `rollback_to`, `deserialize`) are blocked from handlers connected to this signal.

```gdscript
Chronicle.fact_expired.connect(func(key, value):
    print("%s expired with value: %s" % [key, value])
)
```

---

## Write Methods

### `set_fact`

```gdscript
func set_fact(key: String, value: Variant = true, transient: bool = false, lifetime: float = KEEP_LIFETIME) -> bool
```

Sets or creates a fact in the store.

| Parameter | Description |
|-----------|-------------|
| `key` | Dot-separated fact key (e.g. `"player.health"`) |
| `value` | Any Variant value to store (default `true`) |
| `transient` | If `true`, fact is excluded from serialization and rollback |
| `lifetime` | Seconds until expiry. `KEEP_LIFETIME` (default) preserves existing expiry; `0.0` clears expiry; positive values set a new expiry timer |

> **Transient promotion:** When `lifetime > 0.0`, Chronicle automatically forces `transient = true` regardless of what you pass. Expiring facts are inherently temporary — they would be invalid after load (their timer is gone), so persisting them would produce stale data. This applies to all write methods with a `lifetime` parameter.

**Warning:** `transient` is positional. `set_fact("k", true, true)` passes `true` as transient. Use named arguments or explicit defaults when passing lifetime: `set_fact("k", true, false, 30.0)`.

```gdscript
Chronicle.set_fact("player.health", 100)
Chronicle.set_fact("buff.speed", 1.5, false, 30.0)  # expires in 30s
Chronicle.set_fact("ui.open", true, true)  # transient
```

---

### `toggle_fact`

```gdscript
func toggle_fact(key: String, transient: bool = false, lifetime: float = KEEP_LIFETIME) -> Variant
```

Toggles a boolean fact: sets to `true` if absent/falsy, sets to `false` if truthy. Returns the new boolean state, `Chronicle.DEFERRED` if the write was deferred (e.g. during cascade), or `null` if the key is invalid.

```gdscript
var is_on: Variant = Chronicle.toggle_fact("light.enabled")
if is_on != null:
    print("Light is now: %s" % is_on)
```

---

### `increment_fact`

```gdscript
func increment_fact(key: String, amount: float = 1.0, transient: bool = false, lifetime: float = KEEP_LIFETIME) -> Variant
```

Increments a numeric fact by `amount`. Creates the fact at `0` if absent (resulting value is `amount`). Returns the new value, `Chronicle.DEFERRED` if the write was deferred, or `null` on error (e.g. key invalid, existing value non-numeric).

```gdscript
Chronicle.increment_fact("player.kills")
Chronicle.increment_fact("player.xp", 50.0)
```

---

### `clamp_fact`

```gdscript
func clamp_fact(key: String, min_value: float, max_value: float, transient: bool = false, lifetime: float = KEEP_LIFETIME) -> Variant
```

Clamps a numeric fact to `[min_value, max_value]`. No-op if the fact is absent or non-numeric. Returns the new value, `Chronicle.DEFERRED` if the write was deferred, or `null` on error.

```gdscript
Chronicle.set_fact("player.health", 999)
Chronicle.clamp_fact("player.health", 0.0, 100.0)  # caps at 100
```

---

### `erase_fact`

```gdscript
func erase_fact(key: String) -> bool
```

Removes a fact from the store. Emits `fact_changed(key, null, old_value, EraseSource.USER)` if the fact existed. Returns `true` if the fact was present and erased, `false` otherwise. Returns `false` when the erase is deferred (e.g., called inside a watcher callback at max cascade depth).

```gdscript
var was_present: bool = Chronicle.erase_fact("player.buff")
```

---

### `set_facts`

```gdscript
func set_facts(entries: Dictionary, transient: bool = false, lifetime: float = KEEP_LIFETIME) -> int
```

Sets multiple facts in a single batch. Keys are fact names, values are fact values. Empty dictionaries are silently ignored. Returns `0` when the batch is deferred.

```gdscript
Chronicle.set_facts({
    "player.health": 100,
    "player.mana": 50,
    "player.name": "Hero",
})
```

---

### `erase_facts`

```gdscript
func erase_facts(keys: Array[String]) -> int
```

Erases multiple facts by key. Erasures are sequential (not atomic); watchers fire between each erasure. Returns the number of facts actually erased.

```gdscript
var erased: int = Chronicle.erase_facts(["buff.a", "buff.b", "buff.c"])
print("Erased %d buffs" % erased)
```

---

## Read Methods

### `get_fact`

```gdscript
func get_fact(key: String, default: Variant = null) -> Variant
```

Returns the current value of a fact, or `default` if not set.

**Important:** Returns deep copies of stored values. Mutating the returned value does not affect the store.

```gdscript
var hp: Variant = Chronicle.get_fact("player.health", 0)
var inv: Variant = Chronicle.get_fact("player.inventory", [])  # safe to mutate
```

---

### `has_fact`

```gdscript
func has_fact(key: String) -> bool
```

Returns `true` if a fact with the given key exists in the store (regardless of its value).

```gdscript
if Chronicle.has_fact("player.name"):
    print("Player exists")
```

---

### `is_marked`

```gdscript
func is_marked(key: String) -> bool
```

Returns `true` if the fact exists and its value is truthy. Useful for boolean flag checks.

```gdscript
if Chronicle.is_marked("quest.dragon_slain"):
    unlock_achievement()
```

---

### `get_facts`

```gdscript
func get_facts(pattern: String = "*") -> Dictionary
```

Returns all facts matching a glob pattern as a `{ key: value }` dictionary. Defaults to all facts. Values are deep copies.

```gdscript
var player_data: Dictionary = Chronicle.get_facts("player.*")
var all_data: Dictionary = Chronicle.get_facts()
```

---

### `is_transient`

```gdscript
func is_transient(key: String) -> bool
```

Returns `true` if the fact is marked as transient (excluded from serialization and rollback).

```gdscript
if Chronicle.is_transient("ui.menu_open"):
    print("This fact won't be saved")
```

---

### `evaluate`

```gdscript
func evaluate(expression: String) -> Variant
```

Evaluates a boolean expression string against current facts. Returns `true`/`false` for valid expressions, or `null` for parse errors.

```gdscript
var can_enter: Variant = Chronicle.evaluate("player.level >= 5 AND quest.key_found")
if can_enter == true:
    open_door()
```

---

### `evaluate_bool`

```gdscript
func evaluate_bool(expression: String, default: bool = false) -> bool
```

Convenience wrapper around `evaluate()`. Returns `default` (default `false`) on parse error instead of `null`, making it safe to use directly in `if` conditions.

```gdscript
if Chronicle.evaluate_bool("player.gold >= 100 AND shop.open"):
    open_shop_ui()
```

---

### `parse_expression`

```gdscript
func parse_expression(source: String) -> Variant
```

Parses a Chronicle expression string into an AST (abstract syntax tree) without evaluating it. Returns the AST on success, or `null` on parse error. Use with `evaluate_expression()` to avoid re-parsing the same expression repeatedly.

```gdscript
var ast: Variant = Chronicle.parse_expression("player.level >= 5 AND quest.key_found")
if ast != null:
    # Evaluate later without re-parsing
    var result: bool = Chronicle.evaluate_expression(ast)
```

---

### `evaluate_expression`

```gdscript
func evaluate_expression(ast: Variant, resolver: Callable = Callable()) -> bool
```

Evaluates a pre-parsed AST (from `parse_expression()`). Uses the default fact resolver if `resolver` is not provided. Pass a custom resolver with signature `func(key: String) -> Variant` to override how fact values are looked up.

```gdscript
var ast: Variant = Chronicle.parse_expression("player.gold >= 100")
var result: bool = Chronicle.evaluate_expression(ast)
```

---

### `extract_expression_keys`

```gdscript
func extract_expression_keys(ast: Variant) -> Array[String]
```

Returns all fact keys referenced in a parsed AST. Useful for registering targeted watchers that only fire when relevant keys change.

```gdscript
var ast: Variant = Chronicle.parse_expression("player.gold >= 100 AND quest.done")
var keys: Array[String] = Chronicle.extract_expression_keys(ast)
# keys -> ["player.gold", "quest.done"]
```

---

### `walk_expression_ast`

```gdscript
func walk_expression_ast(ast: Variant, leaf_fn: Callable) -> void
```

Walks an expression AST, calling `leaf_fn` on each leaf node (Dictionary). Use this for custom AST inspection or transformation.

| Parameter | Description |
|-----------|-------------|
| `ast` | A parsed AST from `parse_expression()` |
| `leaf_fn` | `func(node: Dictionary) -> void` -- called on each leaf node |

```gdscript
var ast: Variant = Chronicle.parse_expression("a.x AND b.y >= 5")
Chronicle.walk_expression_ast(ast, func(node: Dictionary):
    print("Leaf node type: %s" % node.get("node_type", ""))
)
```

---

## Query Methods

### `get_fact_keys`

```gdscript
func get_fact_keys(pattern: String = "*") -> Array[String]
```

Returns all fact keys matching a glob pattern.

```gdscript
var quest_keys: Array[String] = Chronicle.get_fact_keys("quest.*")
```

---

### `count_facts`

```gdscript
func count_facts(pattern: String = "*") -> int
```

Returns the number of facts matching a glob pattern.

```gdscript
var buff_count: int = Chronicle.count_facts("buff.*")
```

---

### `get_first_change`

```gdscript
func get_first_change(pattern: String = "*") -> Variant
```

Returns the earliest timeline entry matching a pattern as a Dictionary, or `null` if none found.

```gdscript
var first: Variant = Chronicle.get_first_change("player.*")
if first != null:
    print("First player change at time: %s" % first.time)
```

---

### `get_last_change`

```gdscript
func get_last_change(pattern: String = "*") -> Variant
```

Returns the most recent timeline entry matching a pattern as a Dictionary, or `null` if none found.

```gdscript
var last: Variant = Chronicle.get_last_change("quest.*")
```

---

### `get_changes_since`

```gdscript
func get_changes_since(since_time: float) -> Array[Dictionary]
```

Returns all timeline entries recorded after `since_time`. Returns empty array for invalid times (negative, NaN, INF).

```gdscript
var recent: Array[Dictionary] = Chronicle.get_changes_since(10.0)
for entry in recent:
    print("%s = %s at %.2f" % [entry.key, entry.value, entry.time])
```

---

### `get_fact_history`

```gdscript
func get_fact_history(key: String) -> Array[Dictionary]
```

Returns all timeline entries for a specific fact key, oldest first.

```gdscript
var history: Array[Dictionary] = Chronicle.get_fact_history("player.health")
```

---

### `get_changes_between`

```gdscript
func get_changes_between(since_time: float, until_time: float) -> Array[Dictionary]
```

Returns all timeline entries in the half-open range `(since_time, until_time]` (exclusive lower bound, inclusive upper bound). Returns empty array if `since_time > until_time` or either time is invalid.

```gdscript
var window: Array[Dictionary] = Chronicle.get_changes_between(5.0, 15.0)
```

---

### `get_fact_changes_between`

```gdscript
func get_fact_changes_between(key: String, since_time: float, until_time: float) -> Array[Dictionary]
```

Returns timeline entries for a specific fact key in the half-open range `(since_time, until_time]`. Returns empty array on invalid range.

```gdscript
var hp_changes: Array[Dictionary] = Chronicle.get_fact_changes_between("player.health", 0.0, 60.0)
```

---

## Reactive Methods

### `watch`

```gdscript
func watch(pattern: String, callback: Callable, once: bool = false) -> int
```

Registers a callback for changes to facts matching `pattern` (glob syntax). Returns a watch ID for use with `unwatch()`. Returns `-1` if the pattern is invalid or the callback is not valid.

**Callback signature:** `func(key: String, value: Variant, old_value: Variant) -> void`

| Parameter | Description |
|-----------|-------------|
| `pattern` | Glob pattern (e.g. `"player.*"`, `"quest.*.completed"`) |
| `callback` | Callable invoked on matching changes |
| `once` | If `true`, auto-unwatches after the first match |

```gdscript
var id: int = Chronicle.watch("player.health", func(key, value, old):
    print("Health changed: %s -> %s" % [old, value])
)
```

---

### `watch_any`

```gdscript
func watch_any(patterns: Array[String], callback: Callable, once: bool = false) -> int
```

Registers a callback that fires when any of the given patterns match a change. Fires at most once per dispatch even if multiple patterns match the same key. Returns a watch ID, or `-1` on error.

**Callback signature:** `func(key: String, value: Variant, old_value: Variant) -> void`

```gdscript
var id: int = Chronicle.watch_any(["player.health", "player.mana"], func(key, val, old):
    update_hud()
)
```

---

### `watch_once`

```gdscript
func watch_once(pattern: String, callback: Callable) -> int
```

Registers a one-shot callback that auto-unwatches after the first match. Equivalent to `watch(pattern, callback, true)`. Returns a watch ID, or `-1` if the pattern is invalid or the callback is not valid.

```gdscript
Chronicle.watch_once("boss.defeated", func(_key, _val, _old):
    trigger_cutscene()
)
```

---

### `watch_any_once`

```gdscript
func watch_any_once(patterns: Array[String], callback: Callable) -> int
```

Registers a one-shot callback for any of the given patterns. Auto-unwatches after the first match. Equivalent to `watch_any(patterns, callback, true)`. Returns a watch ID, or `-1` on error.

```gdscript
Chronicle.watch_any_once(["exit.a", "exit.b"], func(key, _v, _o):
    print("Player used exit: %s" % key)
)
```

---

### `unwatch`

```gdscript
func unwatch(watch_id: int) -> bool
```

Removes a watcher by its ID (returned from `watch`/`watch_any`/`watch_once`). Returns `true` if the watcher existed and was removed.

```gdscript
var id: int = Chronicle.watch("player.*", my_callback)
# Later:
Chronicle.unwatch(id)
```

---

### `unwatch_pattern`

```gdscript
func unwatch_pattern(pattern: String) -> int
```

Removes all watchers registered with the given pattern, including entire `watch_any` groups that contain it. Returns the number of watchers removed.

```gdscript
var removed: int = Chronicle.unwatch_pattern("player.*")
```

---

### `unwatch_all`

```gdscript
func unwatch_all() -> void
```

Removes all registered watchers.

```gdscript
Chronicle.unwatch_all()
```

---

### `validate_pattern`

```gdscript
func validate_pattern(pattern: String) -> String
```

Validates a watch pattern. Returns an empty string `""` if valid, or an error message describing why the pattern is invalid.

```gdscript
var err: String = Chronicle.validate_pattern("player.**")
if err != "":
    push_error("Bad pattern: %s" % err)
```

---

### `set_pattern_matcher`

```gdscript
func set_pattern_matcher(matches_fn: Callable, validate_pattern_fn: Callable, force: bool = false) -> void
```

Replaces the glob pattern matcher used by watches and queries. Both callables must be valid. Fails if watchers are currently registered unless `force=true` is passed (which clears all existing watchers first).

| Parameter | Description |
|-----------|-------------|
| `matches_fn` | `func(pattern: String, key: String) -> bool` — returns whether key matches pattern |
| `validate_pattern_fn` | `func(pattern: String) -> String` — returns `""` if valid, error message otherwise |
| `force` | If `true`, clears all existing watchers before replacing the matcher |

```gdscript
Chronicle.set_pattern_matcher(my_regex_match, my_regex_validate, true)
```

---

## Clock Methods

### `get_game_time`

```gdscript
func get_game_time() -> float
```

Returns the current game clock time in seconds.

```gdscript
var t: float = Chronicle.get_game_time()
```

---

### `set_game_time`

```gdscript
func set_game_time(value: float) -> void
```

Sets the game clock to an absolute time. Forward jumps only — values less than the current time are ignored with a warning. Use `rollback_to()` to go backwards.

```gdscript
Chronicle.set_game_time(120.0)  # jump to 2 minutes
```

---

### `advance_game_time`

```gdscript
func advance_game_time(delta: float) -> void
```

Advances the game clock by `delta` seconds. Negative values are ignored with a warning. Zero is silently ignored (no warning). NaN/INF values produce an error.

```gdscript
Chronicle.advance_game_time(5.0)  # advance 5 seconds
```

---

### `set_auto_advancing`

```gdscript
func set_auto_advancing(enabled: bool) -> void
```

Enables or disables automatic game clock advancement each frame via `_process`. When enabled, the clock advances by the frame delta every frame.

```gdscript
Chronicle.set_auto_advancing(true)  # clock ticks with game time
```

---

### `is_auto_advancing`

```gdscript
func is_auto_advancing() -> bool
```

Returns `true` if the game clock advances automatically each frame.

```gdscript
if Chronicle.is_auto_advancing():
    print("Clock is running")
```

---

## Expiry Methods

### `set_expiry`

```gdscript
func set_expiry(key: String, lifetime: float) -> bool
```

Sets or removes expiry on an existing fact without changing its value. Pass a positive number for seconds until expiry, or `0.0` to clear the expiry. Returns `true` if the expiry was applied, `false` if the key is invalid or the fact doesn't exist.

```gdscript
Chronicle.set_expiry("buff.shield", 30.0)  # expires in 30s
Chronicle.set_expiry("buff.shield", 0.0)   # clear expiry
```

---

### `clear_expiry`

```gdscript
func clear_expiry(key: String) -> bool
```

Removes any expiry timer on the given key. Equivalent to `set_expiry(key, 0.0)`.

```gdscript
Chronicle.clear_expiry("buff.shield")
```

---

### `get_expiry_remaining`

```gdscript
func get_expiry_remaining(key: String) -> float
```

Returns the remaining seconds before a fact expires. Returns `EXPIRY_NONE` (`-1.0`) if the fact has no expiry set or the key is invalid.

```gdscript
var remaining: float = Chronicle.get_expiry_remaining("buff.shield")
if remaining != Chronicle.EXPIRY_NONE:
    print("Shield expires in %.1fs" % remaining)
```

---

### `has_expiry`

```gdscript
func has_expiry(key: String) -> bool
```

Returns `true` if the fact has a lifetime expiry set.

```gdscript
if Chronicle.has_expiry("buff.speed"):
    print("Speed buff is temporary")
```

---

### `flush_expiry`

```gdscript
func flush_expiry() -> bool
```

Flushes all expired facts immediately, erasing them and emitting `fact_expired` for each. Call before `serialize()` if you want expired facts removed from the save data. Returns `true` if the flush ran, `false` if skipped (coordinator not idle).

```gdscript
Chronicle.flush_expiry()
var clean_data: Dictionary = Chronicle.serialize()
```

---

## Rollback Methods

### `rollback_to`

```gdscript
func rollback_to(target_time: float) -> RollbackResult
```

Restores all facts to their state at `target_time` by reversing timeline entries. Returns a `RollbackResult` (global class: `ChronicleRollbackResult`). Emits `state_rolled_back` then `state_reset` on success. Cannot be called during a mutation (watcher callback, expiry handler, etc.).

**RollbackResult properties:**

| Property | Type | Description |
|----------|------|-------------|
| `success` | `bool` | `true` if rollback completed fully |
| `partial` | `bool` | `true` if state was partially modified (always `false` for `rollback_to`) |
| `steps_reverted` | `int` | Number of steps reverted (`0` for time-based rollback) |
| `requested` | `int` | Number of steps requested (`0` for time-based rollback) |
| `error` | `String` | Error message if failed, empty string on success |

```gdscript
var result = Chronicle.rollback_to(10.0)
if result.success:
    print("Rolled back to t=10.0")
else:
    push_error(result.error)
```

---

### `rollback_steps`

```gdscript
func rollback_steps(step_count: int) -> RollbackResult
```

Undoes the last `step_count` timeline entries. On partial revert (fewer steps available than requested), `success` is `false` but `partial` is `true` — state IS modified in this case. `step_count` must be >= 0.

**RollbackResult properties:**

| Property | Type | Description |
|----------|------|-------------|
| `success` | `bool` | `true` if all requested steps were reverted |
| `partial` | `bool` | `true` if fewer steps were available (state still modified) |
| `steps_reverted` | `int` | Actual number of steps undone |
| `requested` | `int` | The `step_count` that was passed in |

```gdscript
var result = Chronicle.rollback_steps(3)
if result.partial:
    print("Only reverted %d of %d" % [result.steps_reverted, result.requested])
```

---

## Persistence Methods

### `serialize`

```gdscript
func serialize(timeline_cap: int = SERIALIZE_USE_SETTING) -> Dictionary
```

Returns the Chronicle state as a JSON-safe dictionary. Transient facts are excluded. Timeline entries are capped by the project setting (default 1000); pass a positive int to override, or `SERIALIZE_ALL` to include all entries.

| Parameter | Description |
|-----------|-------------|
| `timeline_cap` | `SERIALIZE_USE_SETTING` (0): use project setting. `SERIALIZE_ALL` (-1): no cap. Positive int: exact cap. |

**Serialized format (version 2):**

```gdscript
{
    "version": 2,
    "game_time": 45.0,
    "tick": 12,
    "facts": {"player.health": 100, "quest.started": true},
    "timeline": [{"key": "player.health", "value": 100, "old_value": 80, "time": 44.0, "tick": 11, "expire_at": -1.0, "old_expire_at": -1.0, "old_transient": false}],
    "expiry": {"buff.shield": 25.0},
    "auto_advance": true,
}
```

Note: The `"expiry"` key maps fact keys to remaining seconds (not absolute times). The `"auto_advance"` key records whether the clock was auto-advancing.

```gdscript
var data: Dictionary = Chronicle.serialize()
var full: Dictionary = Chronicle.serialize(Chronicle.SERIALIZE_ALL)
```

---

### `deserialize`

```gdscript
func deserialize(data: Dictionary) -> bool
```

Replaces all state from a previously serialized dictionary. Returns `true` on success, `false` on invalid data or if called during mutation. Preserves existing watchers (unlike `clear()` which destroys them). Emits `state_reset` after restoration.

```gdscript
var data: Dictionary = load_saved_game()
if not Chronicle.deserialize(data):
    push_error("Failed to load state")
```

---

### `save_file`

```gdscript
func save_file(path: String) -> Error
```

Serializes and writes state to a file. Returns `OK` on success, or an `Error` code (`ERR_FILE_BAD_PATH` for empty path, file-system errors otherwise).

```gdscript
var err: Error = Chronicle.save_file("user://save.json")
if err != OK:
    push_error("Save failed: %s" % error_string(err))
```

---

### `load_file`

```gdscript
func load_file(path: String) -> Error
```

Loads and deserializes state from a file. Returns `OK` on success. Possible errors: `ERR_FILE_BAD_PATH` (empty path), `ERR_FILE_CANT_READ` (file unreadable or null), `ERR_INVALID_DATA` (not a Dictionary or deserialization failed).

```gdscript
var err: Error = Chronicle.load_file("user://save.json")
if err == OK:
    print("Game loaded at time %.1f" % Chronicle.get_game_time())
```

---

### `set_save_fn`

```gdscript
func set_save_fn(save_fn: Callable) -> void
```

Overrides the default file save callable used by `save_file()`. The callable must have the signature `func(path: String, data: Dictionary) -> Error`. Reverts to default if the callable is invalid.

```gdscript
Chronicle.set_save_fn(func(path: String, data: Dictionary) -> Error:
    # Custom encryption, compression, etc.
    return ResourceSaver.save(path, data)
)
```

---

### `set_load_fn`

```gdscript
func set_load_fn(load_fn: Callable) -> void
```

Overrides the default file load callable used by `load_file()`. The callable must have the signature `func(path: String) -> Variant` (returns Dictionary or null). Reverts to default if the callable is invalid.

```gdscript
Chronicle.set_load_fn(func(path: String) -> Variant:
    return my_decrypt_and_load(path)
)
```

---

### `clear`

```gdscript
func clear() -> void
```

Destroys all state: facts, watchers, timeline, expiry, and clock. Emits `state_reset` after everything is cleared. Cannot be called during a mutation.

**Warning:** Unlike `deserialize()`, this destroys all watchers. Reconnect watchers after calling `clear()`.

```gdscript
Chronicle.clear()  # full reset, watchers gone
```

---

## Configuration Methods

### `set_timeline_cap`

```gdscript
func set_timeline_cap(cap: int) -> void
```

Sets the timeline ring-buffer capacity at runtime. Entries beyond the new cap are trimmed (oldest removed first).

```gdscript
Chronicle.set_timeline_cap(5000)
```

---

### `set_store_hard_cap`

```gdscript
func set_store_hard_cap(cap: int) -> void
```

Sets the store hard cap at runtime. When greater than 0, new fact keys beyond this count are rejected. Set to 0 to disable the cap.

```gdscript
Chronicle.set_store_hard_cap(10000)
```

---

### `get_timeline_cap`

```gdscript
func get_timeline_cap() -> int
```

Returns the current timeline ring-buffer capacity (the maximum number of entries retained in memory).

```gdscript
var cap: int = Chronicle.get_timeline_cap()
print("Timeline can hold %d entries" % cap)
```

---

### `get_store_hard_cap`

```gdscript
func get_store_hard_cap() -> int
```

Returns the current store hard cap. Returns `0` if the cap is disabled (no limit on unique fact keys).

```gdscript
var cap: int = Chronicle.get_store_hard_cap()
if cap > 0:
    print("Store limited to %d unique keys" % cap)
```

---

### `set_write_interceptor`

```gdscript
func set_write_interceptor(fn: Callable) -> void
```

Sets a function called before every non-erase write. The interceptor can modify the value or reject the write entirely.

| Parameter | Description |
|-----------|-------------|
| `fn` | `func(key: String, value: Variant, old_value: Variant) -> Variant` -- return the (possibly modified) value, or `Chronicle.REJECT` to prevent the write. Pass an invalid Callable to remove the interceptor. |

```gdscript
Chronicle.set_write_interceptor(func(key, value, old_value):
    if key == "player.health":
        return clampf(value, 0.0, 100.0)  # auto-clamp health
    return value
)

# Remove the interceptor:
Chronicle.set_write_interceptor(Callable())
```

---

## Utility Methods

### `build_key`

```gdscript
static func build_key(segments: Array[String]) -> String
```

Joins an array of segments into a normalized dot-separated fact key. Each segment is sanitized: lowercased, non-`[a-z0-9_]` characters replaced with underscores, leading/trailing underscores stripped, and pure-numeric segments prefixed with `_`. Empty segments after sanitization are dropped. Emits `push_warning` when sanitization changes a segment. Static method — can be called without an instance.

```gdscript
var key: String = Chronicle.build_key(["player", "inventory", "sword"])
# Result: "player.inventory.sword"

var safe: String = Chronicle.build_key(["Player", "Kill Count", "42"])
# Result: "player.kill_count._42"
```

---

### `get_stats`

```gdscript
func get_stats() -> Dictionary
```

Returns a dictionary with diagnostic counts.

| Key | Type | Description |
|-----|------|-------------|
| `fact_count` | `int` | Number of facts in the store |
| `watcher_count` | `int` | Number of active watchers |
| `timeline_size` | `int` | Number of entries currently in the timeline |
| `timeline_cap` | `int` | Maximum timeline capacity |
| `expiry_count` | `int` | Number of facts with active expiry timers |

```gdscript
var stats: Dictionary = Chronicle.get_stats()
print("Facts: %d, Watchers: %d, Timeline: %d/%d" % [stats.fact_count, stats.watcher_count, stats.timeline_size, stats.timeline_cap])
```

---

### `clear_warnings`

```gdscript
func clear_warnings() -> void
```

Clears the internal warning deduplication state so previously-suppressed warnings can fire again. Useful in tests or after recovering from a known bad state.

```gdscript
Chronicle.clear_warnings()
```

---

### `is_valid_type`

```gdscript
func is_valid_type(value: Variant) -> bool
```

Returns `true` if the value's type is storable by Chronicle. Valid types: `null`, `bool`, `int`, `float`, `String`, `Array` (with valid elements), `Dictionary` (with String keys and valid values), and any registered custom type.

```gdscript
if Chronicle.is_valid_type(my_data):
    Chronicle.set_fact("data.key", my_data)
else:
    push_warning("Cannot store this type in Chronicle")
```

---

## Type Registration Methods

Type registration methods configure Chronicle's serialization and expression systems at runtime.

### `register_type`

```gdscript
func register_type(type_id: int, tag: String, pack_fn: Callable, unpack_fn: Callable, copy_fn: Callable = Callable(), keys: Array[String] = [], truthy_fn: Callable = Callable(), force: bool = false) -> bool
```

Registers a custom type for serialization. Returns `true` on success, `false` if `tag` is already registered (unless `force=true`).

| Parameter | Description |
|-----------|-------------|
| `type_id` | Godot type ID (e.g. from `typeof()`) or custom int for script types |
| `tag` | Unique string tag used in serialized data (e.g. `"vec2"`) |
| `pack_fn` | `func(value) -> Dictionary` — converts value to JSON-safe dict |
| `unpack_fn` | `func(dict: Dictionary) -> Variant` — reconstructs from dict |
| `copy_fn` | Optional deep-copy override: `func(value) -> Variant` |
| `keys` | Sub-field names for expression dot-access (e.g. `["x", "y"]`) |
| `truthy_fn` | Optional override for `is_truthy()` checks on this type |
| `force` | If `true`, overrides an existing registration with the same tag |

```gdscript
Chronicle.register_type(
    TYPE_VECTOR2, "vec2",
    func(v): return {"x": v.x, "y": v.y},
    func(d): return Vector2(d.x, d.y),
    Callable(), ["x", "y"]
)
```

---

### `register_script_type`

```gdscript
func register_script_type(script: GDScript, tag: String, pack_fn: Callable, unpack_fn: Callable, copy_fn: Callable = Callable(), required_keys: Array[String] = [], truthy_fn: Callable = Callable()) -> bool
```

Registers a script-based custom type for serialization. Unlike `register_type()`, this matches values by their attached GDScript, enabling support for script-defined value objects (e.g. custom RefCounted subclasses).

| Parameter | Description |
|-----------|-------------|
| `script` | The GDScript to match (e.g. `preload("res://my_type.gd")`) |
| `tag` | Unique string tag for the serialized format |
| `pack_fn` | `func(value) -> Dictionary` -- converts the value to a serializable Dictionary |
| `unpack_fn` | `func(dict: Dictionary) -> Variant` -- reconstructs the value from the Dictionary |
| `copy_fn` | Optional deep-copy override: `func(value) -> Variant` |
| `required_keys` | Required Dictionary keys for validation |
| `truthy_fn` | Optional override for `is_truthy()` checks on this type |

```gdscript
var MyType := preload("res://my_type.gd")
Chronicle.register_script_type(
    MyType, "my_type",
    func(v): return {"data": v.data},
    func(d): var t = MyType.new(); t.data = d.data; return t
)
```

---

### `unregister_type`

```gdscript
func unregister_type(type_id: int) -> bool
```

Removes a previously registered custom type by its type ID. Returns `true` if the type was registered and removed.

```gdscript
Chronicle.unregister_type(TYPE_VECTOR2)
```

---

### `is_type_registered`

```gdscript
func is_type_registered(type_id: int) -> bool
```

Returns `true` if a type with the given `type_id` has been registered for serialization.

```gdscript
if not Chronicle.is_type_registered(TYPE_VECTOR3):
    register_vec3()
```

---

### `is_keyword_registered`

```gdscript
func is_keyword_registered(keyword: String) -> bool
```

Returns `true` if a custom keyword has been registered with the expression parser.

```gdscript
if not Chronicle.is_keyword_registered("BETWEEN"):
    register_between_keyword()
```

---

### `register_migration`

```gdscript
func register_migration(from_version: int, migrate_fn: Callable, force: bool = false) -> bool
```

Registers a data-migration function for a specific serialization version. The callable transforms save data from `from_version` to `from_version + 1`. Returns `true` on success.

```gdscript
Chronicle.register_migration(1, func(data: Dictionary) -> Dictionary:
    # Migrate v1 -> v2: rename "expiring_facts" to "expiry"
    if data.has("expiring_facts"):
        data["expiry"] = data["expiring_facts"]
        data.erase("expiring_facts")
    data["version"] = 2
    return data
)
```

---

### `register_expression_handler`

```gdscript
func register_expression_handler(node_type: String, eval_fn: Callable, keys_fn: Callable, walk_fn: Callable, force: bool = false) -> bool
```

Registers a custom expression-handler for a given AST node type. Returns `true` on success.

| Parameter | Description |
|-----------|-------------|
| `node_type` | String identifier for the AST node (e.g. `"between"`) |
| `eval_fn` | `func(ast: Dictionary, resolver: Callable) -> Variant` — evaluates the node |
| `keys_fn` | `func(ast: Dictionary, keys: Array[String]) -> void` — appends referenced fact keys to the passed-in `keys` array |
| `walk_fn` | `func(ast: Dictionary, leaf_fn: Callable) -> void` — walks child nodes, calling `leaf_fn` on leaves |
| `force` | Override existing handler if `true` |

```gdscript
Chronicle.register_expression_handler("between", eval_between, keys_between, walk_between)
```

---

### `unregister_expression_handler`

```gdscript
func unregister_expression_handler(node_type: String) -> bool
```

Removes a previously registered custom expression-handler by node type. Returns `true` if the handler existed and was removed.

```gdscript
Chronicle.unregister_expression_handler("between")
```

---

### `register_keyword`

```gdscript
func register_keyword(keyword: String, token_type: int, parse_fn: Callable, negatable: bool = false) -> bool
```

Registers a custom keyword operator for Chronicle expression parsing. Returns `true` on success.

| Parameter | Description |
|-----------|-------------|
| `keyword` | The keyword string (e.g. `"BETWEEN"`) |
| `token_type` | Integer token type for the lexer. Must be >= `1000` (`Lexer.FIRST_CUSTOM_TOKEN_TYPE`) |
| `parse_fn` | `func(state: ParseState, operand: Dictionary, negated: bool) -> Variant` — receives the parser state, the left-hand operand `{op_type = "key", value = <key_string>}`, and whether `NOT` preceded the keyword. Returns an AST node Dictionary. |
| `negatable` | If `true`, the keyword can be prefixed with `NOT` |

```gdscript
Chronicle.register_keyword("BETWEEN", 1000, parse_between_fn, true)
```

---

### `register_simple_expression`

```gdscript
func register_simple_expression(keyword: String, eval_fn: Callable) -> bool
```

Convenience wrapper for registering a single-key expression operator. Handles the boilerplate of keys/walk functions automatically. Recommended for most custom expression needs.

| Parameter | Description |
|-----------|-------------|
| `keyword` | The AST node type string (e.g. `"starts_with"`) |
| `eval_fn` | `func(key: String, arg: Variant, resolver: Callable) -> bool` -- receives the key name, the operator argument from the AST, and a resolver callable |

```gdscript
Chronicle.register_simple_expression("STARTS_WITH", func(key, arg, resolver):
    var value: Variant = resolver.call(key)
    return value is String and value.begins_with(str(arg))
)
```

---

### `is_expression_handler_registered`

```gdscript
func is_expression_handler_registered(node_type: String) -> bool
```

Returns `true` if a custom (non-built-in) expression handler is registered for the given AST node type.

```gdscript
if not Chronicle.is_expression_handler_registered("starts_with"):
    register_my_starts_with_handler()
```

---

### `unregister_keyword`

```gdscript
func unregister_keyword(keyword: String) -> bool
```

Removes a previously registered custom keyword operator from both the compiler and lexer.

```gdscript
Chronicle.unregister_keyword("BETWEEN")
```
