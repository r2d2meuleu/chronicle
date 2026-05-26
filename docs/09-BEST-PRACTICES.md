# Chronicle — Best Practices

Guidelines for writing clean, maintainable, performant games with Chronicle. Most of these emerge from real problems that occur when a codebase grows beyond a few dozen facts.

---

## Table of Contents

1. [Key Naming](#1-key-naming)
2. [Entity Naming](#2-entity-naming)
3. [Value Conventions](#3-value-conventions)
4. [Transient vs Persistent Facts](#4-transient-vs-persistent-facts)
5. [Performance Guidelines](#5-performance-guidelines)
6. [Debugging Techniques](#6-debugging-techniques)
7. [Testing Facts](#7-testing-facts)
8. [Namespace Conventions for Large Teams](#8-namespace-conventions-for-large-teams)
9. [When NOT to Use Chronicle](#9-when-not-to-use-chronicle)

---

## 1. Key Naming

### Use the entity.property convention

Chronicle's wildcard system is entity-first. `"player.*"` returns everything about the player. `"quest_dragon.*"` returns everything about one quest. Design your keys so that entity queries make sense.

```gdscript
# Good — entity-first, queries cleanly
Chronicle.set_fact("player.gold", 250)
Chronicle.set_fact("player.defeated.boss_swamp", true)
Chronicle.set_fact("quest_dragon.status", "active")

# Bad — property-first, queries nothing useful
Chronicle.set_fact("gold.player", 250)
Chronicle.set_fact("defeated.player.boss_swamp", true)
```

### Use snake_case throughout

All characters in keys must be `[a-z0-9_.]`. Uppercase is rejected — the key validator returns an error for any uppercase character.

```gdscript
# Good
Chronicle.set_fact("npc_old_merchant.trust", 70)

# Bad — uppercase letters are rejected with a validation error
Chronicle.set_fact("NPC_OldMerchant.Trust", 70)  # will not store
```

### Cap at 4 segments

Keys with more than 4 dot-separated segments become hard to read and hard to query. If you need deeper structure, flatten or group.

```gdscript
# Good — 3 segments
Chronicle.set_fact("player.inventory.sword", true)

# Bad — too deep, impossible to query meaningfully
Chronicle.set_fact("player.inventory.weapons.swords.rusty_blade.damage", 12)
```

### Use constants for keys that appear in multiple files

String literals scattered across files are a typo waiting to happen. Define your important keys once.

```gdscript
# facts.gd (autoloaded, or a static class)
class_name Facts
const PLAYER_GOLD := "player.gold"
const QUEST_MAIN_STATUS := "quest_main.status"
const VAULT_UNLOCKED := "vault_door.unlocked"
```

```gdscript
# usage
Chronicle.set_fact(Facts.VAULT_UNLOCKED, true)
```

For dynamically generated keys (enemy names, item IDs), use `Chronicle.build_key()`:

```gdscript
var key: String = Chronicle.build_key(["player", "killed", enemy_type_name])
# Sanitizes: lowercased, spaces/dots to underscores, pure numbers prefixed
```

---

## 2. Entity Naming

### Singular nouns

Entities represent a specific thing, not a category. Use singular names.

```
player        npc_maria       quest_dragon
door_vault    chest_tower_b2  world
```

### Instances with underscore + identifier

When you have multiple of the same type, append an underscore and a unique identifier. Use the room name, position, or a numeric ID — whatever is stable.

```gdscript
# Multiple doors — each is a distinct entity
Chronicle.set_fact("door_hub_east.locked", true)
Chronicle.set_fact("door_hub_west.locked", false)
Chronicle.set_fact("door_vault.locked", true)
```

Avoid numbering from 0 if the numbers are unstable (e.g., spawn order). Use a meaningful identifier instead.

---

## 3. Value Conventions

| What you're representing | Type | Example |
|--------------------------|------|---------|
| A yes/no state or event | `bool` | `door.locked = true` |
| A countable amount | `int` | `player.gold = 250` |
| A percentage or ratio | `float` | `game.completion = 0.75` |
| A named state from a fixed set | `String` | `quest.status = "active"` |
| A collection of items | `Array` (of strings) | `player.inventory = ["sword", "shield"]` |
| Structured sub-data | `Dictionary` | `npc_smith.prices = {"sword": 100}` |

**Prefer booleans for flags.** `player.alive = true` is better than `player.alive = "alive"`. Boolean comparisons are fast and the expression parser handles them cleanly (`player.alive` evaluates as a truthy fact).

**Prefer integers for counters.** `player.gold` as an `int` allows `increment_fact()` (pass a negative amount to decrement) without type promotion.

**Prefer strings for named states.** `quest.status = "complete"` reads better than `quest.complete = true` when there are more than two states (`"inactive"`, `"active"`, `"complete"`, `"failed"`).

---

## 4. Transient vs Persistent Facts

The `transient` flag controls whether a fact survives serialization. Choose based on whether the fact is meaningful to a player who quits and reloads.

### Use persistent (default) for

- Quest progress and completion flags
- Player stats: gold, XP, health
- World state: locked doors, activated switches, killed bosses
- Achievement flags
- NPC relationship values
- Any fact that drives game logic on reload

### Use transient for

- UI state: which menu panel is open, whether a tooltip is visible
- Current animation phase or AI state
- Temporary combat modifiers that reset on death
- Debug/dev flags set at runtime
- Any fact that only makes sense in the current session

```gdscript
# Persistent — survives reload
Chronicle.set_fact("boss_swamp.defeated", true)

# transient — session only, excluded from serialize()
Chronicle.set_fact("ui.inventory_open", true, true)
Chronicle.set_fact("player.combat_haste_active", true, true)
```

---

## 5. Performance Guidelines

Chronicle is fast for typical game workloads. Stay within these limits and you will not have performance problems.

| What | Safe budget | Warning zone | Notes |
|------|-------------|--------------|-------|
| `set_fact()` calls per frame | < 500 | > 1,000 | No hard cap; cascade depth limit (8) applies to recursive watcher callbacks, not sequential calls |
| Active watchers | < 500 | > 2,000 | Glob watchers cost O(glob_count) per write; exact-key watchers are O(1) |
| Total facts in store | < 10,000 | > 10,000 | `push_warning` at 10,000 (repeats every 5,000); configurable hard cap available |
| Expression complexity | < 10 operators | > 30 operators | Complex expressions are still sub-millisecond |
| Timeline cap | 10,000 (default) | > 100,000 | Oldest entries dropped when cap is reached |
| Key length | < 128 characters | hard cap: 256 | Readability degrades well before the hard cap |

These are guidelines, not hard limits. Profile your specific game. See [11-LIMITS-AND-PERFORMANCE.md](11-LIMITS-AND-PERFORMANCE.md) for detailed measurements.

### Avoid one-fact-per-event patterns

```gdscript
# Bad — creates a new fact for every skeleton killed
Chronicle.set_fact("player.killed.skeleton_" + str(kill_counter))

# Good — a single counter
Chronicle.increment_fact("player.kills.skeleton")
```

### Prefer exact-key watchers over glob watchers

Exact-key watchers are O(1) dispatch. Glob watchers are O(glob_count) on every write. If you have 50 glob watchers and you are writing 10 facts per frame, that is 500 pattern checks per frame.

```gdscript
# Good — exact key, O(1)
Chronicle.watch("player.gold", _on_gold_changed)

# Fine for broad coverage, but use sparingly
Chronicle.watch("player.*", _on_any_player_fact_changed)
```

### Mark intermediate writes as transient

If you are updating a position or timer every frame, use a `transient` fact. This prevents the timeline from filling up with high-frequency writes.

```gdscript
func _process(delta: float) -> void:
    Chronicle.set_fact("player.ui.health_display", current_health, true)
```

---

## 6. Debugging Techniques

### Use the F9 overlay first

Before adding print statements, press F9. The **Fact Feed** shows every write in real time. The **Fact Inspector** shows every current value. The **Gate Status** panel shows why gates are open or closed. This answers most questions in under 30 seconds.

### Check the fact feed for unexpected writes

If a gate is not opening, the first thing to verify is whether the fact it depends on is actually being written. Open the overlay, switch to Fact Feed, and trigger the expected event. If the key does not appear, the write is not happening — check your script, signal connections, or ChronicleRecorder configuration.

### Inspect gate conditions

In Gate Status, each gate shows its name and Open/Closed status. To see the condition expression, select the gate node in the Scene tree dock and read its `condition` property. Then match the expression against Fact Inspector values. A common mistake: the expression uses `player.gold >= 100` but the actual fact is `"player.gold"` with a value of `"100"` (String) instead of `100` (int). The comparison returns `false` due to type mismatch.

### Print serialize() during development

When debugging serialization issues, call `print(Chronicle.serialize())` or add a debug key binding that dumps the full state:

```gdscript
func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.keycode == KEY_F12 and event.pressed:
        print(JSON.stringify(Chronicle.serialize(), "\t"))
```

---

## 7. Testing Facts

Chronicle's pure-GDScript design makes facts easy to test. Use GUT 9.6.0 or any test framework.

### Verify facts in unit tests

```gdscript
# test_chronicle_api.gd (GUT 9.6.0)
func test_mark_fact_sets_bool_true() -> void:
    Chronicle.clear()
    Chronicle.set_fact("player.alive")
    assert_true(Chronicle.get_fact("player.alive"))
    assert_true(Chronicle.is_marked("player.alive"))

func test_transient_excluded_from_serialize() -> void:
    Chronicle.clear()
    Chronicle.set_fact("world.day", 3)
    Chronicle.set_fact("ui.flash", true, true)
    var data: Dictionary = Chronicle.serialize()
    assert_true(data["facts"].has("world.day"))
    assert_false(data["facts"].has("ui.flash"))
```

### Test serialization roundtrips

```gdscript
func test_serialize_roundtrip() -> void:
    Chronicle.clear()
    Chronicle.set_fact("player.gold", 500)
    Chronicle.set_fact("quest.status", "complete")
    var data: Dictionary = Chronicle.serialize()
    Chronicle.clear()
    assert_true(Chronicle.deserialize(data))
    assert_eq(Chronicle.get_fact("player.gold"), 500)
    assert_eq(Chronicle.get_fact("quest.status"), "complete")
```

### Test gate conditions without a scene tree

```gdscript
func test_gate_expression() -> void:
    Chronicle.clear()
    Chronicle.set_fact("player.gold", 150)
    assert_true(Chronicle.evaluate("player.gold >= 100"))
```

### Use Chronicle.clear() in test setup

Every test should start from a clean state. Call `Chronicle.clear()` in `before_each()` to prevent test interference.

```gdscript
func before_each() -> void:
    Chronicle.clear()
```

---

## 8. Namespace Conventions for Large Teams

In large games with multiple systems, prefix keys with the system name to avoid collisions:

```gdscript
# Combat system owns "combat.*"
Chronicle.set_fact("combat.player.state", "attacking")

# Quest system owns "quest.*"
Chronicle.set_fact("quest.main.state", "active")

# UI system owns "ui.*" (transient)
Chronicle.set_fact("ui.inventory.open", true, true)
```

**Rules:**

- Each system owns a top-level prefix
- Document owned prefixes in a shared `FACTS.md` or constants file
- Cross-system reads are fine; cross-system writes require explicit contracts
- Transient UI state uses the `ui.*` namespace

---

## 9. When NOT to Use Chronicle

Chronicle is for **game state that matters** — facts that affect gameplay, persist across scenes, or trigger reactions. Do NOT use it for:

- **Per-frame physics data** — positions, velocities, rotations. Use node properties.
- **Particle state** — ephemeral visual effects. Use GPUParticles.
- **Network packets** — use Godot's multiplayer API.
- **Large binary data** — textures, audio. Use ResourceLoader.
- **Rapidly oscillating values** — values that change every frame fill the timeline uselessly. If you must track them, mark as transient.

**Rule of thumb:** If you wouldn't put it in a save file, don't put it in Chronicle (or mark it `transient`).
