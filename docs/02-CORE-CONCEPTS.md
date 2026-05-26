# Chronicle — Core Concepts

## Facts

A **fact** is a key-value pair stored in Chronicle. Keys are dot-separated strings. Values can be any common Godot type -- int, float, String, bool, Array, Dictionary, Vector2, Color, and more. No registration needed for built-in types.

```gdscript
Chronicle.set_fact("player.gold", 250)
Chronicle.set_fact("door_3.locked", false)
Chronicle.set_fact("quest_dragon.status", "active")
```

Facts are global. Any node can write them, any node can read them. Neither side needs to know the other exists.

---

## Keys

Keys follow the format `entity.property` or `entity.detail.property`.

```
player.gold
player.defeated.boss_swamp
npc_maria.trust
door_3.locked
quest_dragon.status
```

**Rules:**

- Allowed characters: `[a-z0-9_.]` — uppercase is rejected
- Convention: lowercase snake_case
- Recommended max depth: 4 segments
- `*` is forbidden in keys (reserved for patterns)
- Whitespace is forbidden

### The Entity

The **entity** is the first segment before the first dot.

```
"player.gold"        → entity: "player"
"npc_maria.trust"    → entity: "npc_maria"
"door_3.locked"      → entity: "door_3"
```

Entity-first naming makes wildcard queries natural:

```gdscript
# Everything about the player
var player_facts: Array[String] = Chronicle.get_fact_keys("player.*")

# Everything about a specific NPC
var maria_facts: Array[String] = Chronicle.get_fact_keys("npc_maria.*")
```

### Dotless Keys

Keys without a dot work fine -- Chronicle handles namespacing internally by prefixing them with `_global.`. This is transparent: all public API methods normalize on the way in and denormalize on the way out.

```gdscript
Chronicle.set_fact("game_started", true)
Chronicle.has_fact("game_started")  # true — just works
```

> **Note:** In save files, dotless keys appear as `"_global.game_started"` — this is expected and self-documenting.

---

## Values

Chronicle accepts all common Godot value types out of the box. The six JSON primitives are always supported:

| Type | Example | Typical Use |
|---|---|---|
| `bool` | `true`, `false` | Flags, states, visited/done |
| `int` | `42`, `-5` | Counters, gold, kills |
| `float` | `3.14` | Percentages, timers |
| `String` | `"active"` | Multi-state enums, names |
| `Array` | `[1, 2, 3]` | Item lists, ordered data |
| `Dictionary` | `{"x": 1}` | Structured sub-data |

In addition, the type registry provides built-in support for all common Godot types: `Vector2`, `Vector2i`, `Vector3`, `Vector3i`, `Vector4`, `Vector4i`, `Color`, `Quaternion`, `Rect2`, `Rect2i`, `AABB`, `Plane`, `Transform2D`, `Basis`, `Transform3D`, `Projection`, `StringName`, `NodePath`, and all `Packed*Array` types. These are automatically serialized and deserialized through the type registry's pack/unpack system.

Arrays and Dictionaries are recursively validated — nested values must also be valid types. Dictionary keys must be strings.

Only `Callable` and `Object` subclasses are rejected. If you need a custom type, register it with `Chronicle.register_type()`.

---

## Transient Facts

A **transient fact** (also called `transient`) exists at runtime but is excluded from `serialize()`. Use it for session-only state that should not persist across saves.

```gdscript
# Mark this key as transient — excluded from saves
Chronicle.set_fact("player.in_combat", true, true)  # transient=true
```

> **Important:** When `lifetime > 0.0`, Chronicle automatically forces `transient = true`. Expiring facts are inherently temporary — they would be invalid after load because their timer state is not preserved. You cannot have a fact that both expires AND persists across saves.

---

## The Timeline

Chronicle keeps an append-only history of every fact change. This is the **timeline**.

Each entry returned by the query methods (`get_fact_history`, `get_changes_since`, etc.) has the shape:

```gdscript
{
    key: String,          # the fact key (denormalized)
    value: Variant,       # value written (null for erase_fact)
    old_value: Variant,   # previous value before this write
    time: float,          # get_game_time() at write (paused-aware)
}
```

> **Note:** The serialized timeline (in save files) includes additional fields: `tick`, `norm_key`, `expire_at`, `old_expire_at`, and `old_transient`. See [Serialization](06-SERIALIZATION.md) for the full format.

The timeline is capped at 10,000 entries (configurable in Project Settings under `chronicle/storage/timeline_cap`). When the cap is reached, oldest entries are dropped. Note: this is the *storage* cap. A separate *serialization* cap (default 1,000 entries) controls how much timeline history is included in save files — see `chronicle/storage/serialize_timeline_cap`.

**Querying the timeline:**

```gdscript
# Every change to a specific key
var history: Array[Dictionary] = Chronicle.get_fact_history("player.gold")

# All changes since a checkpoint
var checkpoint: float = Chronicle.get_game_time()
# ... time passes ...
var recent: Array[Dictionary] = Chronicle.get_changes_since(checkpoint)
```

---

## Fact Truth Lifecycle

A fact goes through three states:

1. **Absent** — `has_fact()` returns `false`. `get_fact()` returns the default.
2. **Present** — stored with a value. `has_fact()` returns `true`.
3. **Erased** — removed with `erase_fact()`. Returns to absent state.

`is_marked()` is a convenience check: the fact must exist AND its value must be truthy (not `false`, `0`, `0.0`, `""`, or `null`).

```gdscript
Chronicle.set_fact("door.open", false)
Chronicle.has_fact("door.open")   # true — the key exists
Chronicle.is_marked("door.open")  # false — value is falsy

Chronicle.set_fact("door.open", true)
Chronicle.is_marked("door.open")  # true
```

---

## Key Naming Conventions

**Entity names:** singular nouns, unique identifier or name.

```
player      npc_maria     door_3      quest_dragon     world
```

**Property names:** past-tense verbs or adjectives for booleans, bare nouns for values.

```
player.gold              # value
player.alive             # boolean state
npc_maria.defeated       # past-tense boolean
door_3.locked            # adjective boolean
quest_dragon.status      # string enum value
```

**Anti-patterns to avoid:**

```gdscript
# BAD: redundant prefix adds no entity context
Chronicle.set_fact("state.player.gold", 100)

# BAD: uppercase is rejected by the key validator
Chronicle.set_fact("Player.Gold", 100)

# BAD: type name in key
Chronicle.set_fact("player.gold_int", 100)

# BAD: too deep (max 4 segments recommended)
Chronicle.set_fact("player.inventory.weapons.swords.rusty_blade.damage", 15)
```

---

## Constraints

### Thread Safety

Chronicle is single-threaded. All API calls must happen on the main thread. Do not call `set_fact()`, `watch()`, or any Chronicle method from a background thread or `Thread.new()` callback.

### Mutation Guards

These operations are blocked during watcher callbacks, expiry handlers, and active dispatches:
- `clear()`
- `deserialize()` / `load_file()`
- `rollback_to()` / `rollback_steps()`

If called while Chronicle is processing any internal operation (dispatch, expiry, rollback, clear, or restore), the call is blocked and a `push_error` is emitted. This prevents infinite loops and state corruption.

### Deep-Copy Guarantee

`get_fact()` always returns a deep copy. Mutating the returned Array or Dictionary does NOT modify the stored value:

```gdscript
var inventory: Array = Chronicle.get_fact("player.inventory", [])
inventory.append("sword")  # Does NOT affect the store!
# You must write it back:
Chronicle.set_fact("player.inventory", inventory)
```

This is intentional — it prevents accidental mutations and makes the store deterministic.

### Re-Entrancy

Yes, you can call `set_fact()` from inside a `watch()` callback. The write is processed inline, and any watchers it triggers also fire immediately. This works up to 8 levels deep. Beyond that, writes are deferred to an internal queue (max 64 pending items, with a drain cap of 256 iterations). Writes are also deferred during certain system operations (expiry handling, rollback finalization, clearing, restoring).
