# Chronicle: Quick Start

> After this guide, you'll have Chronicle installed, a fact stored, and a node reacting to it without manual signal wiring or scripts on the receiving end.

Get Chronicle running in 5 minutes.

## 1. Install

Download or clone the Chronicle repository, then copy the `addons/chronicle/` folder into your Godot project root:

```
your_project/
└── addons/
    └── chronicle/
        ├── plugin.cfg
        ├── plugin.gd
        ├── core/
        ├── nodes/
        └── ...
```

## 2. Enable the Plugin

Open **Project → Project Settings → Plugins** and enable **Chronicle**.

This registers the `Chronicle` autoload singleton. The three companion node types (ChronicleRecorder, ChronicleGate, ChronicleReactor) are available automatically via their `class_name` declarations.

## 3. Set Your First Fact

From any script, call the autoload directly:

```gdscript
Chronicle.set_fact("door.unlocked", true)
```

That's it. The fact is stored, timestamped, and dispatched to any watchers.

## 4. Read It Back

```gdscript
if Chronicle.has_fact("door.unlocked"):
    open_door()

# Or get the value with a fallback default
var is_open: bool = Chronicle.get_fact("door.unlocked", false)
```

## 5. React Without Polling: ChronicleGate

Instead of checking facts in `_process`, add a **ChronicleGate** node and let it handle visibility automatically.

**Scene setup:**

```
TreasureChest (Node2D)
├── Sprite2D
├── CollisionShape2D
└── ChronicleGate          ← add this node as a child
```

**ChronicleGate inspector settings:**

| Property | Value |
|---|---|
| Condition | `key.collected` |
| Gate Mode | `HIDE_WHEN_FALSE` |
| Target Path | *(empty, defaults to parent)* |

The treasure chest is hidden until the player collects the key, then it appears. The gate parses the condition once at `_ready()`, watches only the keys it references, and re-evaluates whenever those keys change. No signal wiring between the key and the chest.

## 6. Run It

```gdscript
# From any script, trigger node, or the Godot console
Chronicle.set_fact("key.collected", true)
# The TreasureChest becomes visible immediately.
```

---

## Complete Working Example

The following scene shows a treasure chest that appears after the player picks up a key.

**Scene tree:**

```
World (Node2D)
├── Player (CharacterBody2D)
│   └── ...
├── KeyItem (Area2D)               ← the pickup
│   ├── Sprite2D
│   ├── CollisionShape2D
│   └── ChronicleRecorder          ← records the fact on pickup
└── TreasureChest (Node2D)         ← the reward
    ├── Sprite2D
    ├── CollisionShape2D
    └── ChronicleGate              ← reacts to the fact
```

**ChronicleRecorder on KeyItem:**

| Property | Value |
|---|---|
| Trigger Signal | `body_entered` |
| Fact Key | `key.collected` |
| Value | `true` |
| Record Mode | `ONCE` |

**ChronicleGate on TreasureChest:**

| Property | Value |
|---|---|
| Condition | `key.collected` |
| Gate Mode | `HIDE_WHEN_FALSE` |

No scripts required on the chest. No signal connections. The treasure chest is hidden until `key.collected` is set, then appears instantly.

**Optional: verify from script:**

```gdscript
func _on_player_interact_with_chest() -> void:
    if Chronicle.has_fact("key.collected"):
        open_chest()
    else:
        show_message("You need a key to open this.")
```

---

## What Chronicle Replaces

Now that you've seen Chronicle work, here's what the same setup looks like without it.

An experienced Godot developer would write a generic Dictionary autoload:

```gdscript
# game_state.gd (autoload)
signal state_changed(key: String)
var _data: Dictionary = {}

func set_value(key: String, value: Variant) -> void:
    _data[key] = value
    state_changed.emit(key)

func get_value(key: String, default: Variant = null) -> Variant:
    return _data.get(key, default)

func save() -> void:
    var f := FileAccess.open("user://save.dat", FileAccess.WRITE)
    f.store_var(_data)
    f.close()

func load_save() -> void:
    var f := FileAccess.open("user://save.dat", FileAccess.READ)
    _data = f.get_var()
    f.close()
    state_changed.emit("")
```

That's ~20 lines, handles unlimited keys, and save/load is one call. This is a legitimate approach and works fine for many games.

**Where it falls short**, and where Chronicle earns its keep:

| Capability | Generic autoload | Chronicle |
|-----------|-----------------|-----------|
| Store and retrieve values | Yes | Yes |
| Notify on change | Single generic signal; listeners must filter by key | Pattern-based watchers with glob matching (`"player.*"`) |
| Query by pattern | Manual iteration | `get_fact_keys("quest.*")`, `count_facts("player.defeated.*")` |
| Node-based reactivity | Connect signals manually per scene, or use groups | ChronicleGate, Reactor, Recorder with zero scripts and zero signal wiring |
| Conditional expressions | Write your own parser | `"player.gold >= 100 AND quest.done"` built in |
| Save/load | `store_var` preserves all Variant types, but has no atomic writes (corruption on crash) and no version migration | Crash-safe atomic writes with `.bak`/`.tmp` fallback and built-in version migration |
| Change history | Not available | Full timeline of every write, queryable by key or time range |
| Rollback / undo | Not available | `rollback_to(time)` / `rollback_steps(n)` |
| Expiring values (TTL) | Write your own timer system | `set_fact("buff.speed", 1.5, false, 30.0)` with automatic expiry |
| Runtime debugging | `print()` | F9 overlay with fact feed, inspector, gate status, reactor log |

Chronicle is not a replacement for a Dictionary. It's the infrastructure you'd eventually build on top of one — reactivity, persistence, history, debugging — already tested and ready to use.

---

## What's Next

- [02-CORE-CONCEPTS.md](02-CORE-CONCEPTS.md) — facts, entities, types, transient scope
- [03-API-REFERENCE.md](03-API-REFERENCE.md) — every method with examples
- [04-COMPANION-NODES.md](04-COMPANION-NODES.md) — Recorder, Gate, Reactor in depth
- [05-EXPRESSIONS-AND-PATTERNS.md](05-EXPRESSIONS-AND-PATTERNS.md) — condition syntax and wildcards
- [11-LIMITS-AND-PERFORMANCE.md](11-LIMITS-AND-PERFORMANCE.md) — capacity planning and frame budgets
