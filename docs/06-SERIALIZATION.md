# Chronicle — Serialization

Chronicle provides a complete, crash-safe save/load pipeline. You call `save_file()` to write state to disk, and `load_file()` to reload it. Everything else — transient exclusion, version migration, backup rotation, int/float preservation — happens automatically.

---

## Table of Contents

1. [The Data Format](#1-the-data-format)
2. [serialize()](#2-serialize)
3. [deserialize()](#3-deserialize)
4. [save_file() and load_file()](#4-save_file-and-load_file)
5. [Transient Facts and Serialization](#5-transient-facts-and-serialization)
6. [int/float Type Preservation](#6-intfloat-type-preservation)
7. [Version Migration](#7-version-migration)
8. [Complete Save/Load Example](#8-complete-saveload-example)
9. [Error Handling](#error-handling)
10. [Migration Patterns](#migration-patterns)
11. [Watchers and State Reset](#watchers-and-state-reset)

---

## 1. The Data Format

`serialize()` returns a plain GDScript Dictionary with seven keys:

```json
{
  "version": 2,
  "game_time": 30.1,
  "tick": 87,
  "facts": {
    "player.gold": 500,
    "player.defeated.boss_swamp": true,
    "_global.game_started": true
  },
  "timeline": [
    {"key": "player.gold", "value": 500, "old_value": 0, "time": 12.5, "tick": 42, "expire_at": -1, "old_expire_at": -1, "old_transient": false}
  ],
  "expiry": {
    "player.buff_speed": 4.5
  },
  "auto_advance": true
}
```

**`version`** — integer save version. Currently `2`. Used to gate migration logic on load.

**`facts`** — snapshot of every persistent (non-transient) fact at the moment of serialization. Keys are stored in their internal canonical form: dotless facts like `set_fact("game_started", true)` appear as `"_global.game_started"` in the file, which is self-documenting and unambiguous.

**`game_time`** — the game clock value at the moment of serialization.

**`tick`** — the monotonic write counter at the moment of serialization.

**`timeline`** — the last 1,000 timeline entries (configurable via `chronicle/storage/serialize_timeline_cap` in ProjectSettings). Each entry has `key`, `value`, `old_value`, `time` (game-clock seconds), and `tick` (monotonic write counter). The timeline gives you history: what changed, when, from what.

**`expiry`** — remaining seconds until expiry (relative, not absolute). Converted on save/load.

**`auto_advance`** — whether game clock auto-advances each frame.

---

## 2. serialize()

```gdscript
func serialize(timeline_cap: int = SERIALIZE_USE_SETTING) -> Dictionary
```

Returns the full save payload as a Dictionary. Never fails -- if the store is empty, you get `{version: 2, game_time: 0.0, tick: 0, facts: {}, timeline: [], expiry: {}, auto_advance: true}`. Pass `timeline_cap` to override the project setting; `SERIALIZE_USE_SETTING` (default, `0`) uses the project setting (default 1000 entries), `Chronicle.SERIALIZE_ALL` (`-1`) includes all entries.

**Why override `timeline_cap`?** The default cap (1000 entries) keeps save files small for most games. Override it when your game relies on timeline queries after loading (e.g. a quest journal that replays history), or when debugging save/load round-trips. Pass `Chronicle.SERIALIZE_ALL` to include every entry -- useful for development saves but can produce large files in long sessions.

What it does:

- Iterates `_store`, skipping any key marked `transient`
- Deep-copies each value (callers can't mutate the store through the returned Dictionary)
- Iterates `_timeline`, skipping transient-key entries, keeping the last `SERIALIZE_TIMELINE_CAP` entries
- Returns `{version, game_time, tick, facts, timeline, expiry, auto_advance}`

```gdscript
# Minimal usage
var data: Dictionary = Chronicle.serialize()
```

The returned Dictionary is JSON-safe by construction because `set_fact()` enforces the type whitelist (bool, int, float, String, Array, Dictionary) at write time. In addition to these primitive types, Chronicle natively serializes Godot math types: Vector2/2i, Vector3/3i, Vector4/4i, Color, Quaternion, Rect2/2i, AABB, Plane, Transform2D, Basis, Transform3D, Projection, StringName, NodePath, and all Packed arrays (PackedByteArray, PackedInt32Array, PackedInt64Array, PackedFloat32Array, PackedFloat64Array, PackedStringArray, PackedVector2Array, PackedVector3Array, PackedVector4Array, PackedColorArray). These are encoded with type tags automatically and round-trip through JSON without data loss.

---

## 3. deserialize()

```gdscript
func deserialize(data: Dictionary) -> bool
```

Restores Chronicle state from a previously serialized Dictionary. Returns `true` on success, `false` on failure.

**Validation before any state mutation** — Chronicle validates the data before touching the current state:

1. Checks that `data` is a Dictionary. If not: `push_error`, return `false`, no state change.
2. Reads `data["version"]`. If it is older than `SAVE_VERSION`: runs any registered user migrations (see [Version Migration](#7-version-migration)). If no migration is registered for that version, `push_error`, return `false`, no state change.
3. If the version doesn't match `SAVE_VERSION` after migrations: `push_error`, return `false`, no state change.
4. Checks that `data` has a `"facts"` key. If not: `push_error`, return `false`, no state change.

**After validation passes:**

5. Resets internal state — wipes the store, entity index, transient set, timeline, clock, and **user-registered migrations**. **Watchers are preserved** (unlike `clear()`, which removes them). If you use migrations with multiple `load_file()` calls (e.g., save slot cycling), re-register them before each load.
6. Iterates `data["facts"]`, calling `set_fact()` for each entry. Watchers do NOT fire during this phase — `deserialize()` runs in `DESERIALIZING` mode, which suppresses watch dispatch.
7. Restores the timeline directly (no signals re-fired).
8. Returns `true`.

```gdscript
var ok: bool = Chronicle.deserialize(data)
if not ok:
    push_error("Failed to load save data.")
```

**Important:** `deserialize()` suppresses watch dispatch during fact restoration. Watchers registered before calling `deserialize()` will NOT fire for facts restored during deserialization. If you need to react to the loaded state, use the `state_reset` signal, which fires after `deserialize()` completes.

---

## 4. save_file() and load_file()

These instance methods handle file I/O, crash safety, and backup rotation. They call `serialize()` and `deserialize()` internally.

### save_file()

```gdscript
func save_file(path: String) -> Error
```

Serializes Chronicle state and writes it using the write-then-rename pattern to guarantee a partial write never corrupts the save file. Returns `ERR_FILE_BAD_PATH` immediately if `path` is empty.

> **Path restriction:** Paths must begin with `user://` or `res://`. Other schemes return `ERR_FILE_BAD_PATH`.

1. Serialize state to JSON (pretty-printed with tab indentation).
2. Write to `path + ".tmp"`. If the open fails, return the error immediately — nothing is touched.
3. If `path` already exists, rename it to `path + ".bak"`. If that rename fails, remove the `.tmp` and return the error.
4. Rename `path + ".tmp"` to `path`. If this fails, `.tmp` is preserved for manual recovery and the `.bak` is restored to the primary path. Return the error.
5. Return `OK`.

The `.bak` file is the previous successful save. During each save, any prior `.bak` is removed before the current primary file is renamed to `.bak`, so only one generation of backup is kept.

```gdscript
var err: Error = Chronicle.save_file("user://save.json")
if err != OK:
    push_error("Save failed: " + error_string(err))
```

### load_file()

```gdscript
func load_file(path: String) -> Error
```

Loads and deserializes Chronicle state from disk. Returns `OK` on success, or `ERR_FILE_BAD_PATH` if `path` is empty.

> **Path restriction:** Paths must begin with `user://` or `res://`. Other schemes return `ERR_FILE_BAD_PATH`.

1. If `path` exists, parse it as JSON. If parsing succeeds, deserialize and return `OK`.
2. If `path` is missing or corrupt, try `path + ".bak"`. If that parses, deserialize and return `OK` (with a `push_warning` that the primary was corrupt).
3. If `.bak` is also missing or corrupt, try `path + ".tmp"`. If that parses, `.tmp` is renamed to the primary path (and any existing `.bak` is renamed to `.bak.old`), then deserialize and return `OK` (with a `push_warning`).
4. If all three are missing or corrupt, return `ERR_FILE_CANT_READ`.

```gdscript
var err: Error = Chronicle.load_file("user://save.json")
if err != OK:
    pass  # no save file yet — fresh game
```

### Full File Round-Trip

```gdscript
const SAVE_PATH := "user://save.json"

func save_game() -> void:
    var err := Chronicle.save_file(SAVE_PATH)
    if err != OK:
        push_error("Chronicle save failed: " + error_string(err))

func load_game() -> void:
    var err := Chronicle.load_file(SAVE_PATH)
    if err != OK:
        pass  # no save yet — start fresh
```

---

## 5. Transient Facts and Serialization

Mark a fact as `transient` when it represents runtime-only state that should not survive a save/load cycle:

```gdscript
# Health bar flash state — not meaningful after reload (transient = true)
Chronicle.set_fact("player.ui.flash_active", true, true)

# Enemy spawning position for this session only (transient = true)
Chronicle.set_fact("enemy_goblin_3.spawn_pos_x", 320.0, true)
```

`transient` facts are excluded from **both** `facts` and `timeline` in the serialized output. They exist only in memory.

**Rule of thumb:**
- Flags that affect game logic across sessions → persistent (default)
- UI state, current animation phase, temporary AI state → `transient`

---

## 6. int/float Type Preservation

JSON does not distinguish integers from floats — both serialize as number literals. Without special handling, `42` would round-trip as `42.0`, breaking comparisons like `Chronicle.get_fact("player.gold") == 42`.

Chronicle preserves int/float types automatically during serialization. Whole-number floats (like `5.0`) and special values (`NaN`, `INF`, `-INF`) are tagged with `float_special` so they round-trip without type confusion. Ordinary fractional floats are stored as bare JSON numbers -- JSON preserves fractional values natively, so no tag is needed.

In practice this means:
- `player.gold = 500` → saves as `500`, loads back as `int` `500`
- `player.accuracy = 0.95` → saves as `0.95` (bare JSON number), loads back as `float` `0.95`
- `player.score = 1000.0` → saves with a `float_special` tag, loads back as `float` `1000.0` (preserved)

### Special Float Values

`NaN`, `INF`, `-INF`, and whole-number floats are encoded with a type marker so they are preserved across JSON round-tripping. Ordinary fractional floats (e.g. `0.95`) are stored as plain JSON numbers with no wrapping:

| Value | Serialized form |
|-------|-----------------|
| `NAN` | `{"_chronicle_type": "float_special", "v": "nan"}` |
| `INF` | `{"_chronicle_type": "float_special", "v": "inf"}` |
| `-INF` | `{"_chronicle_type": "float_special", "v": "-inf"}` |
| Whole-number float (e.g. `5.0`) | `{"_chronicle_type": "float_special", "v": "whole", "n": 5}` |
| Non-whole float (e.g. `0.95`) | `0.95` (bare JSON number, no tag) |

This is automatic — you never need to handle these markers yourself. They are packed on `serialize()` and unpacked on `deserialize()`.

---

## 7. Version Migration

Chronicle uses `register_migration()` to handle save files from older game versions.

Chronicle's internal format is version 2. Your game migrations start at version 2 and increment from there. `register_migration(2, fn)` migrates saves from version 2 to 3. Chronicle automatically chains all registered migrations in order until the data version matches its internal `SAVE_VERSION`.

If no migration is registered for a needed version step, `deserialize()` returns `false`.

Chronicle includes a built-in migration from v1 to v2 that renames the `expiring_facts` key to `expiry`. User migrations registered via `register_migration()` take the same version slot format.

When you change your game's save format (adding a key, renaming a field, restructuring data), register a migration:

```gdscript
# Register a migration from save version 2 to 3
Chronicle.register_migration(2, func(data: Dictionary) -> Dictionary:
    # Example: rename a key, add a default, restructure timeline
    if "player.experience" in data["facts"]:
        data["facts"]["player.xp"] = data["facts"]["player.experience"]
        data["facts"].erase("player.experience")
    data["version"] = 3
    return data
)
```

`deserialize()` applies user migrations in order before restoring state. If a save file is at version `v` and `SAVE_VERSION` is higher, Chronicle calls the migration registered for version `v`, then checks the result's version, and continues until the version matches. If no migration is registered for the needed version, `deserialize()` returns `false` with a `push_error`.

`register_migration()` accepts an optional `force` parameter (default `false`). If `force=true`, it overrides any existing migration registered for that version. Without `force`, re-registering the same version emits an error and returns `false`.

**If the save version is newer than the running plugin:** `deserialize()` returns `false` and emits a `push_error`. This prevents older plugin builds from silently corrupting newer save files.

> **Note:** `register_migration()` is for user migrations — it is your responsibility to register migrations when you change your own save format. Chronicle has one built-in migration (v1 to v2) that handles the internal `expiring_facts` to `expiry` rename. User migrations registered for the same version slot override the built-in one.

---

## 8. Complete Save/Load Example

This example shows a production-quality save system for a game built on Chronicle. It handles: autosave on quit, manual save slots, load-on-start, and new-game initialization.

```gdscript
extends Node

const SAVE_PATH := "user://save.json"

func _ready() -> void:
    # Prevent Godot from closing before the autosave in _notification() runs.
    get_tree().set_auto_accept_quit(false)

# Called from your main scene's _ready()
func start_game() -> void:
    var err: Error = Chronicle.load_file(SAVE_PATH)
    if err == OK:
        _on_game_loaded()
    else:
        _new_game()


func _new_game() -> void:
    Chronicle.clear()
    # Set initial world state
    Chronicle.set_fact("game.started", true)
    Chronicle.set_fact("player.gold", 0)
    Chronicle.set_fact("player.health", 100)
    Chronicle.set_fact("world.day", 1)
    print("New game started.")


func _on_game_loaded() -> void:
    print("Loaded save. Day: ", Chronicle.get_fact("world.day"))


func save_game() -> void:
    var err := Chronicle.save_file(SAVE_PATH)
    if err != OK:
        push_error("Chronicle save failed: " + error_string(err))
    else:
        print("Game saved.")


# Autosave on quit
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        save_game()
        get_tree().quit()
```

### What the save file looks like after one session

```json
{
    "version": 2,
    "facts": {
        "_global.game_started": true,
        "player.gold": 250,
        "player.health": 85,
        "world.day": 3,
        "quest_main.status": "active",
        "door_vault.locked": false
    },
    "timeline": [
        {"key": "game_started", "value": true, "old_value": null, "time": 0.0, "tick": 1, "expire_at": -1, "old_expire_at": -1, "old_transient": false},
        {"key": "player.gold", "value": 250, "old_value": 0, "time": 45.2, "tick": 17, "expire_at": -1, "old_expire_at": -1, "old_transient": false}
    ]
}
```

Note that dotless facts (`game_started`) appear in `facts` as `"_global.game_started"` but appear in `timeline` entries with their display form (`"game_started"`). This is intentional: the write coordinator stores the denormalized display key in timeline entries.

---

## Error Handling

### What happens when deserialize() fails?

If the data is invalid (wrong type, corrupt structure, version too new), `deserialize()` returns `false` and **Chronicle state is unchanged**. It's safe to retry with different data.

Individual invalid facts or timeline entries are dropped with warnings — the rest still loads. Only structural errors (missing `facts` dict, non-Dictionary input) cause full rejection.

### What happens when load_file() fails?

`load_file()` tries three paths in order:
1. Primary file (e.g., `user://save.json`)
2. Backup file (`user://save.json.bak`)
3. Temporary file (`user://save.json.tmp`)

If all three fail, returns `ERR_FILE_CANT_READ` or `ERR_INVALID_DATA`. Chronicle state is unchanged.

### Atomic Writes

`save_file()` uses a write-then-rename pattern:
1. Write to `path.tmp`
2. If `path` exists, rename to `path.bak`
3. Rename `path.tmp` to `path`
4. On failure, restore from `path.bak`

This prevents corruption from mid-write crashes or power loss.

---

## Migration Patterns

Use `Chronicle.register_migration()` when your game's save format changes across versions.

### Renaming a fact key

```gdscript
# Call before any load_file():
Chronicle.register_migration(2, func(data: Dictionary) -> Dictionary:
    if "player.experience" in data["facts"]:
        data["facts"]["player.xp"] = data["facts"]["player.experience"]
        data["facts"].erase("player.experience")
    data["version"] = 3
    return data
)
```

### Changing a value's structure

```gdscript
# Old: player.gold = 500 (int)
# New: player.currency = {"gold": 500, "silver": 0}
Chronicle.register_migration(3, func(data: Dictionary) -> Dictionary:
    if "player.gold" in data["facts"]:
        var gold: int = data["facts"]["player.gold"]
        data["facts"]["player.currency"] = {"gold": gold, "silver": 0}
        data["facts"].erase("player.gold")
    data["version"] = 4
    return data
)
```

### How migrations chain

Migrations run in sequence: v2→v3→v4→...→current. Each function must increment `data["version"]` by exactly 1. If any migration fails, the load is aborted.

---

## Watchers and State Reset

`deserialize()` and `load_file()` **preserve existing watchers**. After loading:
1. All facts are cleared and replaced with saved state
2. Watchers remain registered but do NOT fire during deserialization -- `deserialize()` runs in `DESERIALIZING` mode, which suppresses watch dispatch
3. `state_reset` signal emits once after all facts are restored
4. Watchers fire normally for any changes made AFTER the load completes

`state_reset` is a signal on the Chronicle node with no arguments. Connect to it to re-initialize UI after any state reset (clear, load, rollback).

This is intentional — companion nodes (Gates, Reactors) remain functional after save/load. They re-evaluate on the `state_reset` signal rather than on individual fact writes during deserialization. If you want a full clean slate including watchers, call `clear()` explicitly.
