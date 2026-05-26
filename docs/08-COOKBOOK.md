# Chronicle — Cookbook

Practical recipes showing how to build common game systems on top of Chronicle. Each recipe is self-contained: you can copy it, adapt the fact keys, and it works.

---

## Table of Contents

1. [Quest Flags](#1-quest-flags)
2. [Door Locks](#2-door-locks)
3. [Kill Counter](#3-kill-counter)
4. [NPC Reactions](#4-npc-reactions)
5. [Dialogue Branching](#5-dialogue-branching)
6. [Inventory Tracking](#6-inventory-tracking)
7. [Achievement System](#7-achievement-system)
8. [Day/Night Cycle](#8-daynight-cycle)
9. [Migrating from Global.gd](#9-migrating-from-globalgd)
10. [Clamping Health](#10-clamping-health)
11. [One-Shot Event Trigger](#11-one-shot-event-trigger)
12. [Custom Save/Load with Encryption](#12-custom-saveload-with-encryption)

---

## 1. Quest Flags

Mark a quest as complete when a signal fires. Gate the NPC that gives the follow-up dialogue so it only appears after completion.

```gdscript
# boss_swamp.gd — enemy script
func _on_died() -> void:
    Chronicle.set_fact("quest_swamp.boss_defeated")
    Chronicle.set_fact("quest_swamp.status", "complete")
```

```gdscript
# quest_giver_npc.gd — NPC that unlocks after completion
func _ready() -> void:
    # Only appear if the quest is done
    Chronicle.watch("quest_swamp.status", func(key, value, old):
        visible = (value == "complete")
    )
    visible = Chronicle.get_fact("quest_swamp.status") == "complete"
```

Or use a **ChronicleGate** node on the NPC (no code needed):

```
ChronicleGate
  condition: quest_swamp.status == "complete"
  gate_mode: HIDE_WHEN_FALSE
  target_path: (empty — targets parent NPC)
```

---

## 2. Door Locks

A locked door stays invisible and disabled until the player has the key. Uses `HIDE_WHEN_FALSE` so it disappears rather than appearing impassable.

```gdscript
# key_item.gd — picked up by the player
func _on_body_entered(body: Node) -> void:
    if body.is_in_group("player"):
        Chronicle.set_fact("player.has_vault_key")
        queue_free()
```

Add a **ChronicleGate** node as a child of the door's `CollisionShape2D` or the entire door node:

```
ChronicleGate
  condition: player.has_vault_key
  gate_mode: HIDE_WHEN_FALSE
```

When `player.has_vault_key` becomes `true`, the gate switches to open and the door is shown and process-enabled automatically.

---

## 3. Kill Counter

Use `ChronicleRecorder` in INCREMENT mode to count kills without writing any code.

```
Enemy (scene root)
└── ChronicleRecorder
      trigger_signal: "died"      ← signal on the Enemy node
      fact_key: "player.kills"
      record_mode: INCREMENT
      amount: 1
```

Query the count from anywhere:

```gdscript
var total_kills: int = Chronicle.get_fact("player.kills", 0)
```

For per-enemy-type counters, use the `Chronicle.build_key()` sanitizer to build a safe key from the enemy type name:

```gdscript
@export var enemy_type: String = "skeleton"

func _on_died() -> void:
    var key: String = Chronicle.build_key(["player", "kills", enemy_type])
    Chronicle.increment_fact(key)
    # Results in: "player.kills.skeleton", "player.kills.fire_golem", etc.
```

---

## 4. NPC Reactions

A hub NPC changes dialogue based on events happening in other rooms. Uses `ChronicleReactor` to respond to any fact matching `"guard.*"`.

```gdscript
# hub_ghost.gd
var _watcher_id: int
@onready var dialogue_label: Label = $DialogueLabel

func _ready() -> void:
    _watcher_id = Chronicle.watch("guard.*", _on_guard_fact_changed)
    _update_dialogue()

func _on_guard_fact_changed(key: String, value: Variant, old: Variant) -> void:
    _update_dialogue()

func _update_dialogue(key: String = "", value: Variant = null, old: Variant = null) -> void:
    if Chronicle.is_marked("guard.loud_kill"):
        dialogue_label.text = "I heard a commotion from the guard hall..."
    elif Chronicle.is_marked("guard.stealth_kill"):
        dialogue_label.text = "The guard has gone quiet. Strange."
    elif Chronicle.get_fact("guard.alert_level", 0) >= 3:
        dialogue_label.text = "The guards are on high alert."
    else:
        dialogue_label.text = "The vault seems quiet tonight."

func _exit_tree() -> void:
    Chronicle.unwatch(_watcher_id)
```

Or use a **ChronicleReactor** node (no code needed for the trigger):

```
ChronicleReactor
  watch_pattern: guard.*
  target_method: _update_dialogue
  react_to: ANY
```

ChronicleReactor handles cleanup automatically when removed from the scene tree. The code-based `watch()` pattern requires manual `unwatch()` in `_exit_tree()`, as shown above.

---

## 5. Dialogue Branching

Use expression conditions to pick dialogue lines. The expression parser handles complex multi-fact conditions without custom code.

```gdscript
# dialogue_manager.gd
var _branches: Array[Dictionary] = [
    {
        "condition": "quest_dragon.status == \"complete\" AND player.gold >= 500",
        "line": "A dragonslayer with coin to spare — you're the one I've been waiting for."
    },
    {
        "condition": "quest_dragon.status == \"complete\"",
        "line": "The dragon is slain. The kingdom owes you a debt."
    },
    {
        "condition": "player.gold >= 100",
        "line": "You look like you can afford my prices."
    },
    {
        "condition": "TRUE",
        "line": "Move along, I've got nothing for you."
    },
]

func get_dialogue_line() -> String:
    for branch: Dictionary in _branches:
        if Chronicle.evaluate_bool(branch["condition"]):
            return branch["line"]
    return ""
```

Keep the fallback branch's condition as `"TRUE"` — the parser recognizes it as the literal true keyword and always evaluates to `true`.

---

## 6. Inventory Tracking

Store an Array fact for an inventory list. Chronicle validates Array contents recursively — every element must be a JSON-safe type.

```gdscript
# inventory.gd
func add_item(item_name: String) -> void:
    var inv: Array = Chronicle.get_fact("player.inventory", [])
    if item_name not in inv:
        inv.append(item_name)
        Chronicle.set_fact("player.inventory", inv)

func remove_item(item_name: String) -> void:
    var inv: Array = Chronicle.get_fact("player.inventory", [])
    inv.erase(item_name)
    Chronicle.set_fact("player.inventory", inv)

func has_item(item_name: String) -> bool:
    return item_name in Chronicle.get_fact("player.inventory", [])
```

Note: `get_fact()` returns a deep copy. Mutating the returned array does not affect the store -- you must call `set_fact()` with the modified array to persist the change. See also [Pitfall #2: get_fact Returns Deep Copies](10-PITFALLS.md#2-get_fact-returns-deep-copies).

---

## 7. Achievement System

Combine a kill counter with a watcher that checks thresholds.

```gdscript
# achievements.gd
func _ready() -> void:
    # Fire whenever any kill count changes
    Chronicle.watch("player.kills.*", _check_kill_achievements)

func _check_kill_achievements(key: String, value: Variant, old: Variant) -> void:
    var total: int = 0
    for k: String in Chronicle.get_fact_keys("player.kills.*"):
        total += Chronicle.get_fact(k, 0)

    if total >= 10 and not Chronicle.is_marked("achievement.first_blood"):
        Chronicle.set_fact("achievement.first_blood")
        _show_achievement("First Blood", "Kill 10 enemies.")

    if total >= 100 and not Chronicle.is_marked("achievement.centurion"):
        Chronicle.set_fact("achievement.centurion")
        _show_achievement("Centurion", "Kill 100 enemies.")

func _show_achievement(title: String, desc: String) -> void:
    print("Achievement unlocked: %s — %s" % [title, desc])
    # Show your UI overlay here
```

Achievements themselves are Chronicle facts (`achievement.*`), so they persist across save/load automatically.

---

## 8. Day/Night Cycle

Use a single `world.time_of_day` fact to drive visual changes across multiple nodes via gates.

```gdscript
# world_clock.gd
const SECONDS_PER_HOUR: float = 300.0  # 5 real minutes = 1 game hour

var _hour: int = 6
var _accumulator: float = 0.0

func _process(delta: float) -> void:
    _accumulator += delta
    if _accumulator >= SECONDS_PER_HOUR:
        _accumulator = 0.0
        _hour = (_hour + 1) % 24
        var period: String = "day" if (_hour >= 6 and _hour < 20) else "night"
        Chronicle.set_fact("world.hour", _hour)
        Chronicle.set_fact("world.time_of_day", period)
```

Drive visual nodes with **ChronicleGate** nodes — no script needed on the visual nodes:

```
NightSkyLayer (CanvasLayer)
└── ChronicleGate
      condition: world.time_of_day == "night"
      gate_mode: HIDE_WHEN_FALSE

DayAmbientLight (DirectionalLight2D)
└── ChronicleGate
      condition: world.time_of_day == "day"
      gate_mode: HIDE_WHEN_FALSE

ShopkeeperNPC
└── ChronicleGate
      condition: world.hour >= 8 AND world.hour < 18
      gate_mode: HIDE_WHEN_FALSE
```

When `world.time_of_day` changes, every gate that references it re-evaluates simultaneously, with no coordination code between them.

---

## 9. Migrating from Global.gd

Replace a monolithic autoload with Chronicle facts. Before:

```gdscript
# global.gd (old pattern)
extends Node

var player_health: int = 100
var player_gold: int = 0
var quest_started: bool = false
var door_unlocked: bool = false
```

After:

```gdscript
# No Global.gd needed. From any script:
Chronicle.set_fact("player.health", 100)
Chronicle.set_fact("player.gold", 0)

# Boolean flags — use set_fact with default value (true):
Chronicle.set_fact("quest.started")
Chronicle.set_fact("door.unlocked")
```

**Why migrate?**

- `Global.gd` has no reactivity — you poll in `_process()`. Chronicle watches push changes.
- `Global.gd` has no save/load. Chronicle does it in one call.
- `Global.gd` has no history. Chronicle records every change with timestamps.
- `Global.gd` requires knowing the autoload name. Chronicle is global with no coupling.

**Step-by-step:**

1. For each `var` in Global.gd, create a fact key: `player_health` → `"player.health"`
2. Replace reads: `Global.player_health` → `Chronicle.get_fact("player.health", 100)`
3. Replace writes: `Global.player_health = 50` → `Chronicle.set_fact("player.health", 50)`
4. Replace polling: `if Global.quest_done:` in `_process()` → `Chronicle.watch("quest.done", callback)`
5. Delete Global.gd when all references are migrated

---

## 10. Clamping Health

Use `clamp_fact()` to enforce min/max bounds on a numeric fact without branching logic.

```gdscript
# After applying damage or healing:
Chronicle.set_fact("player.health", current_health + heal_amount)
Chronicle.clamp_fact("player.health", 0.0, 100.0)
# Health is now guaranteed to be in [0, 100]
```

---

## 11. One-Shot Event Trigger

Use `watch_once()` when you only need to react to a fact the first time it appears -- the watcher auto-removes after firing.

```gdscript
Chronicle.watch_once("boss.defeated", func(_key, _value, _old):
    trigger_victory_cutscene()
    Chronicle.set_fact("achievement.boss_slayer")
)
```

This is equivalent to `watch("boss.defeated", callback, true)` but more readable.

---

## 12. Custom Save/Load with Encryption

Override Chronicle's file I/O to add encryption, compression, or cloud saves:

```gdscript
extends Node

func _ready() -> void:
    Chronicle.set_save_fn(_encrypted_save)
    Chronicle.set_load_fn(_encrypted_load)

func _encrypted_save(path: String, data: Dictionary) -> Error:
    var json: String = JSON.stringify(data)
    var encrypted: PackedByteArray = _encrypt(json.to_utf8_buffer())
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_buffer(encrypted)
    file.flush()
    file.close()
    return OK

func _encrypted_load(path: String) -> Variant:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null
    var encrypted: PackedByteArray = file.get_buffer(file.get_length())
    var json: String = _decrypt(encrypted).get_string_from_utf8()
    return JSON.parse_string(json)

func _encrypt(data: PackedByteArray) -> PackedByteArray:
    # Replace with your encryption (e.g., AES via Crypto)
    return data

func _decrypt(data: PackedByteArray) -> PackedByteArray:
    # Replace with your decryption
    return data
```

Then save/load works normally:

```gdscript
Chronicle.save_file("user://save.dat")  # Uses your encrypted I/O
Chronicle.load_file("user://save.dat")  # Decrypts automatically
```

To revert to default I/O, pass the built-in callables directly:

```gdscript
Chronicle.set_save_fn(ChronicleFileIO.save_to_file)  # Reverts to built-in FileIO
Chronicle.set_load_fn(ChronicleFileIO.load_from_file)
```

**Warning:** Do not pass `Callable()` to revert -- Chronicle treats an invalid Callable as an error (`push_error` fires) and falls back to defaults as a safety measure, not as an intended API.
