# Chronicle — Common Pitfalls

Fourteen mistakes that are easy to make and hard to notice until something breaks. Each has a symptom, root cause, and fix.

---

## Table of Contents

1. [String Typos in Keys](#1-string-typos-in-keys)
2. [get_fact Returns Deep Copies](#2-get_fact-returns-deep-copies)
3. [Circular Watchers](#3-circular-watchers)
4. [Storing Unsupported Types](#4-storing-unsupported-types)
5. [Forgetting the transient Flag](#5-forgetting-the-transient-flag)
6. [Gate Expression Case Sensitivity](#6-gate-expression-case-sensitivity)
7. [Hot Reload Wipes Chronicle State](#7-hot-reload-wipes-chronicle-state)
8. [increment_fact() on a Non-Numeric Fact](#8-increment_fact-on-a-non-numeric-fact)
9. [clear() Destroys Watchers, deserialize()/load_file() Preserves Them](#9-clear-destroys-watchers-deserializeload_file-preserves-them)
10. [Same-Value Writes Are Suppressed from Signals and Watchers](#10-same-value-writes-are-suppressed-from-signals-and-watchers)
11. [toggle_fact() Sets false Instead of Erasing](#11-toggle_fact-sets-false-instead-of-erasing)
12. [Calling Destructive Operations from Watcher Callbacks](#12-calling-destructive-operations-from-watcher-callbacks)
13. [Comparing Different Types Returns False (Not Error)](#13-comparing-different-types-returns-false-not-error)
14. [Setting `transient = false` With a Positive Lifetime Does Nothing](#14-setting-transient--false-with-a-positive-lifetime-does-nothing)

---

## 1. String Typos in Keys

**Symptom:** A gate never opens. A watcher never fires. `Chronicle.get_fact("player.god")` returns `null` when you expected `250`.

**Root cause:** A typo in a string literal. `"player.god"` vs `"player.gold"`. Chronicle cannot warn you because both are valid key names — it just treats them as two different facts.

**Fix:** Define important keys as constants in a shared file and reference the constant everywhere.

```gdscript
# facts.gd
class_name Facts
const PLAYER_GOLD := "player.gold"
const QUEST_MAIN := "quest_main.status"
const VAULT_UNLOCKED := "vault_door.unlocked"
```

```gdscript
# Usage — typos are now compile-time errors
Chronicle.set_fact(Facts.PLAYER_GOLD, 250)
Chronicle.watch(Facts.VAULT_UNLOCKED, _on_vault_changed)
```

For dynamically built keys (e.g., including enemy names or item IDs), use `Chronicle.build_key()`:

```gdscript
# Sanitizes the input: lowercase, dots and spaces become underscores
var key: String = Chronicle.build_key(["player", "killed", enemy_name])
```

The EditorInspectorPlugin also color-codes fact keys in the Inspector: green for known keys, orange for unrecognized. Use those hints during development. See also [Cookbook #1: Quest Flags](08-COOKBOOK.md#1-quest-flags) for a complete constants pattern example.

---

## 2. get_fact Returns Deep Copies

**Symptom:** You retrieve an Array from Chronicle, modify it, and the change is not reflected when you call `get_fact()` again.

**Root cause:** `get_fact()` returns a deep copy of the stored value. This is by design: it prevents external code from corrupting Chronicle's internal store by mutating a returned reference.

```gdscript
# BAD — mutating the returned copy has no effect on the store
var inv: Array = Chronicle.get_fact("player.inventory", [])
inv.append("sword")
# Chronicle still has the old array without "sword"
print(Chronicle.get_fact("player.inventory"))  # ["bow"] — unchanged
```

**Fix:** Always call `set_fact()` with the modified value.

```gdscript
# Good — retrieve, modify, write back
var inv: Array = Chronicle.get_fact("player.inventory", [])
inv.append("sword")
Chronicle.set_fact("player.inventory", inv)
```

This pattern is intentional: every mutation goes through the write coordinator, which updates the entity index, appends to the timeline, and dispatches watchers. Silent mutation through references would bypass all of that.

---

## 3. Circular Watchers

**Symptom:** The console shows `[Chronicle] Cascade depth 8 reached in set_fact("...")`. Facts update in unexpected bursts. Some writes are deferred into an internal queue.

**Root cause:** Watcher A writes fact B, watcher B writes fact A (or writes A back to the same value, or writes fact C which writes fact A). The cascade depth limit (8) stops the infinite loop, but the deferred queue may still build up.

```gdscript
# BAD: circular — each write triggers the other
Chronicle.watch("player.health", func(k, v, old):
    Chronicle.set_fact("player.health_normalized", v / 100.0)
)
Chronicle.watch("player.health_normalized", func(k, v, old):
    Chronicle.set_fact("player.health", v * 100.0)  # loops back!
)
```

**Fix:** Break the cycle. Derived facts should only be written in one direction — from source to derived, never back. Guard writes with an equality check.

```gdscript
# Good: one-directional derivation
Chronicle.watch("player.health", func(k, v, old):
    if v is int or v is float:
        Chronicle.set_fact("player.health_normalized", v / 100.0)
)
```

If you genuinely need bidirectional sync (unusual), guard with a flag:

```gdscript
var _syncing: bool = false

func _on_health_changed(k, v, old) -> void:
    if _syncing:
        return
    _syncing = true
    Chronicle.set_fact("player.health_normalized", float(v) / 100.0)
    _syncing = false
```

Legitimate cascade depth is almost always 1 or 2. If you see depth warnings in normal gameplay, there is a cycle.

---

## 4. Storing Unsupported Types

**Symptom:** `[Chronicle] set_fact("enemy.target") received Object, not a storable type. Use bool, int, float, String, Array, Dictionary, or Godot value types (Vector2, Color, etc.).` The fact is never stored.

**Root cause:** Chronicle rejects `Callable` and `Object` subclasses (nodes, resources, references). All other Godot value types are accepted: `Vector2`, `Vector3`, `Color`, `NodePath`, `Rect2`, `Transform2D`, packed arrays, etc. are all supported via the built-in type registry and will serialize/deserialize correctly.

**Fix:** Store data values, not live object references.

```gdscript
# Bad — Object references are not storable
Chronicle.set_fact("enemy.target", $Player)

# Good — store the node path or an identifier
Chronicle.set_fact("enemy.target_path", str($Player.get_path()))

# These all work fine — Godot value types are supported
Chronicle.set_fact("enemy.position", enemy.position)        # Vector2
Chronicle.set_fact("player.tint", Color.RED)                 # Color
Chronicle.set_fact("checkpoint.path", ^"Level/Spawn")        # NodePath
```

If you need a custom value type, register it with `Chronicle.register_type()`.

---

## 5. Forgetting the transient Flag

**Symptom:** Save files grow large. Loading a save restores weird intermediate states (like "UI tooltip was visible"). On reload, systems behave oddly because ephemeral runtime state was persisted.

**Root cause:** Every `set_fact()` call is persistent by default. If you write frame-by-frame state (health bars, animation phases, AI blackboard values) without the `transient` flag, it accumulates in save files.

```gdscript
# Bad — this gets saved to disk every session
func _process(delta: float) -> void:
    Chronicle.set_fact("player.ui.health_bar_width", health_bar.size.x)
```

**Fix:** Pass `transient = true` (3rd argument) for any fact that is only meaningful in the current session.

```gdscript
# Good — excluded from serialize()
Chronicle.set_fact("player.ui.health_bar_width", health_bar.size.x, true)
Chronicle.set_fact("enemy.patrol_target", patrol_points[0], true)
Chronicle.set_fact("combat.active", true, true)
```

---

## 6. Gate Expression Case Sensitivity

**Symptom:** A `ChronicleGate` condition has a fact key that starts with `and`, `or`, `not`, `true`, or `false` (with no dot) and is being misinterpreted as a keyword.

**Root cause:** The expression parser recognizes `AND`, `OR`, `NOT`, `TRUE`, `FALSE` as keywords **case-insensitively**. Any bare word without a dot that matches these names (in any case) is treated as a keyword, not a fact path.

```
# BAD — "and" is treated as a keyword, not a fact key
and_condition  # this is a parse error

# BAD — any casing of TRUE is a keyword literal, not a fact key
TRUE           # boolean true literal
true           # also a boolean true literal (case-insensitive)

# GOOD — use a dotted fact key to avoid keyword collision
player.and_condition
flags.true_value
```

**Fix:** If you have fact keys that match keyword names, use a dotted form (e.g., `flags.not_started`). Check `_get_configuration_warnings()` on the Gate node — parse errors are reported there with the column number.

---

## 7. Hot Reload Wipes Chronicle State

**Symptom:** During development, after saving `chronicle.gd` or toggling the plugin off/on, all in-memory facts are gone. Gates behave as if nothing has happened. Watchers are no longer firing.

**Root cause:** Editing the Chronicle autoload script causes Godot to re-initialize the autoload node, which re-runs `_ready()` and resets all member variables to their declared defaults. All facts, watchers, and the timeline are wiped.

This is expected Godot behavior, not a Chronicle bug. It is documented in the [Plugin Lifecycle](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html).

**Fix:**

- During development, do not edit `chronicle.gd` while testing gameplay — or, reload your save after editing.
- Keep your game's fact initialization logic in `_new_game()` or `_on_game_loaded()` so you can re-run it after a hot reload.
- If you need to iterate quickly on Chronicle itself, write a test project and use GdUnit4 headless tests instead of manual play sessions.

Note: editing companion node scripts (`chronicle_recorder.gd`, etc.) is safe — those nodes re-run `_ready()` on reload, which re-registers their watchers against the (still-running) Chronicle autoload.

---

## 8. increment_fact() on a Non-Numeric Fact

**Symptom:** `[Chronicle] increment_fact("quest.status", amount=1.0000) — current value is active (String), not numeric.` The value is not changed. `increment_fact()` returns `null`.

**Root cause:** `increment_fact()` requires the existing value to be `int`, `float`, or absent. If the key already holds a String, bool, Array, or Dictionary, `increment_fact()` refuses to overwrite it and returns `null`.

This is a safe default — it warns you about the type mismatch rather than silently overwriting your quest status string with a number.

```gdscript
# BAD — quest.status was set to "active" earlier
Chronicle.set_fact("quest.status", "active")
Chronicle.increment_fact("quest.status")  # warns, returns null, value unchanged
```

**Fix:** Use separate keys for counters and status strings.

```gdscript
# Good — separate concerns
Chronicle.set_fact("quest.status", "active")           # String status
Chronicle.increment_fact("quest.kill_count")           # int counter
```

If you are seeing this warning and did not intend to mix types on a key, it usually means the key has a typo — the wrong key name is being incremented, and the correct key has a String value. Use the F9 overlay's Fact Inspector to verify what type the key currently holds.

---

## 9. clear() Destroys Watchers, deserialize()/load_file() Preserves Them

**Symptom:** After loading a save file, your watchers still fire as expected. But after calling `clear()`, none of them fire anymore.

**Root cause:** `clear()` is a hard reset — it wipes facts, timeline, clock, expiry, coordinator state, user-registered migrations, AND all registered watchers. In contrast, `deserialize()` and `load_file()` wipe facts, timeline, clock, expiry, and user migrations — but **preserve watchers**.

**Fix:** If you need to reset state but keep watchers, use `deserialize()` or `load_file()` instead of `clear()`. If you use `clear()`, re-register your watchers afterward. Connect to the `state_reset` signal to re-evaluate state after any load:

```gdscript
Chronicle.state_reset.connect(func():
    # Re-evaluate UI or game state after a load/clear
    _refresh_hud()
)
```

---

## 10. Same-Value Writes Are Suppressed from Signals and Watchers

**Symptom:** You call `set_fact("player.gold", 100)` when the value is already `100`, but `fact_changed` does not fire and no watchers trigger.

**Root cause:** Chronicle suppresses same-value writes from both the `fact_changed` signal and watcher dispatch. However, the timeline still records the write. This is by design — it prevents unnecessary signal/watcher churn while maintaining a complete audit trail.

**Fix:** If you need to detect re-writes of the same value, query the timeline directly with `get_fact_history()`. Do not rely on `fact_changed` or watchers for same-value notifications.

---

## 11. toggle_fact() Sets false Instead of Erasing

**Symptom:** After toggling a fact off, `has_fact()` still returns `true`.

**Root cause:** `toggle_fact()` sets the value to `false` when the fact is truthy — it does not erase the fact. This means `has_fact()` returns `true` even after toggle-off, because the key still exists with a `false` value.

```gdscript
Chronicle.set_fact("player.stealth")       # value = true
Chronicle.toggle_fact("player.stealth")    # value = false (NOT erased)
Chronicle.has_fact("player.stealth")       # true — key still exists
Chronicle.is_marked("player.stealth")      # false — value is falsy
```

**Fix:** Use `is_marked()` instead of `has_fact()` when checking toggle state. If you need the fact fully removed, use `erase_fact()` explicitly.

---

## 12. Calling Destructive Operations from Watcher Callbacks

**Symptom:** `clear()`, `rollback_to()`, or `load_file()` does nothing when called from inside a watcher callback or `fact_matched` handler.

**Root cause:** Chronicle blocks destructive operations during active dispatch to prevent state corruption. The call is rejected and a `push_error` is emitted.

**Fix:** Defer the destructive call to the next frame:

```gdscript
# Wrong — blocked with push_error:
Chronicle.watch("trigger.reload", func(key, value, old):
    Chronicle.load_file("user://save.json")  # Blocked!
)

# Right — defer to next frame:
Chronicle.watch("trigger.reload", func(key, value, old):
    (func(): Chronicle.load_file("user://save.json")).call_deferred()
)
```

---

## 13. Comparing Different Types Returns False (Not Error)

**Symptom:** An expression like `player.gold >= "100"` always evaluates to `false` even though `player.gold` is `500`.

**Root cause:** `500 >= "100"` is a cross-type comparison (int vs String). Chronicle returns `false` for ordered comparisons between incompatible types rather than crashing.

**Fix:** Ensure the literal type matches the fact's value type:

```gdscript
# Wrong — comparing int fact to string literal:
# condition: player.gold >= "100"

# Right — numeric literal:
# condition: player.gold >= 100
```

This also applies to `==`: `5 == "5"` is `false` (different types). Use consistent types throughout.

---

## 14. Setting `transient = false` With a Positive Lifetime Does Nothing

**Symptom:** You pass `transient = false` to keep an expiring fact in save files, but it doesn't appear in `serialize()` output.

**Root cause:** When `lifetime > 0.0`, Chronicle automatically forces `transient = true`. This is intentional — an expiring fact's timer state is not persisted, so loading it later would produce stale data with no active timer.

```gdscript
# This does NOT persist — lifetime > 0 overrides transient to true
Chronicle.set_fact("buff.shield", true, false, 10.0)

# After serialize(), "buff.shield" is NOT in the output
```

**Fix:** If you need a fact to both expire AND persist, manage the timer yourself:

```gdscript
# Persistent fact + manual timer
Chronicle.set_fact("buff.shield", true)
Chronicle.set_fact("buff.shield_remaining", 10.0)

# In _process(), decrement and erase when done:
var remaining: float = Chronicle.get_fact("buff.shield_remaining", 0.0)
remaining -= delta
if remaining <= 0.0:
    Chronicle.erase_fact("buff.shield")
    Chronicle.erase_fact("buff.shield_remaining")
else:
    Chronicle.set_fact("buff.shield_remaining", remaining)
```
