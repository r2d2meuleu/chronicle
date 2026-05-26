# Chronicle — Companion Nodes

Chronicle provides three nodes that let you wire facts to scene behavior without writing scripts. All three are thin wrappers around the public API — everything they do, you can do in GDScript too.

**Add them via Scene -> Add Child Node** and search for "Chronicle".

### How Companion Nodes Find Chronicle

All companion nodes share a `chronicle_path` export property and a three-tier resolution strategy:

1. **Explicit path** -- If `chronicle_path` is set, uses that NodePath directly. Warns and returns `null` (companion disabled) if it does not resolve to a Chronicle node — does **not** fall back to ancestor walk.
2. **Ancestor walk** -- If no explicit path, walks up the scene tree from the companion's parent looking for the first Chronicle node. Useful when embedding multiple Chronicle instances in different scene branches.
3. **Autoload fallback** -- If no ancestor is found, uses the `Chronicle` autoload singleton registered by the plugin.

In most projects you never set `chronicle_path` -- the autoload fallback handles everything. Set it only when you have multiple Chronicle instances and need to bind a companion to a specific one.

---

## Shared Methods (All Companion Nodes)

All companion nodes (ChronicleRecorder, ChronicleGate, ChronicleReactor) inherit from the same base class and share these methods:

| Method | Description |
|--------|-------------|
| `get_chronicle() -> ChronicleEngine` | Returns the Chronicle instance this companion is bound to |
| `set_chronicle(chronicle: ChronicleEngine) -> void` | Binds this companion to a specific Chronicle instance. Pass `null` to revert to ancestor/autoload resolution. Non-null values must be in the scene tree. Triggers re-registration of watches. |

---

## ChronicleRecorder

Records a fact when a signal fires on the parent node.

### Exports

| Property | Type | Default | Description |
|---|---|---|---|
| `trigger_signal` | String | `""` | Signal name on the parent node |
| `fact_key` | String | `""` | Dot-path key to write |
| `value` | Variant | `true` | Value to store (hidden when record_mode = INCREMENT) |
| `record_mode` | RecordMode | `ONCE` | When and how to record |
| `amount` | float | `1.0` | Amount to add (shown only when record_mode = INCREMENT) |
| `lifetime` | float | `KEEP_LIFETIME` | TTL in seconds. `0.0` clears expiry. `KEEP_LIFETIME` (-2.0) preserves existing expiry. |
| `transient` | bool | `false` | If true, recorded fact is excluded from saves |

### RecordMode Enum

| Mode | Behavior |
|---|---|
| `ONCE` | Records on the first trigger only. Subsequent triggers are ignored. **Not reset by `Chronicle.clear()` or rollback** — call `reset()` to re-arm. |
| `ALWAYS` | Overwrites the fact on every trigger. |
| `INCREMENT` | Adds `amount` to the current value on every trigger. Initializes to 0 if absent. |

### Signal

`fact_recorded(key: String, value: Variant, old_value: Variant)` — emitted after each successful write. `old_value` is the previous value before this write (`null` if absent in `ONCE`/`ALWAYS` mode, `0.0` if absent in `INCREMENT` mode).

### Behavior Notes

- Connects to `parent.trigger_signal` in `_ready()`. If the signal doesn't exist on the parent, emits an error via `push_error()` and does nothing.
- Disconnects cleanly in `_exit_tree()`.
- Shows a yellow warning icon in the editor if `trigger_signal` or `fact_key` is empty.

### Methods

| Method | Description |
|--------|-------------|
| `set_custom_trigger(fn: Callable) -> void` | Override recording logic. Signature: `fn(chronicle: ChronicleEngine, fact_key: String)` |
| `has_fired() -> bool` | Returns `true` if a ONCE-mode recorder has already fired this session |
| `reset() -> void` | Reset a ONCE-mode recorder so it can fire again |

### Variadic Signal Handling

The Recorder handles parent signals with any number of parameters (0 to 5+). It uses `unbind()` internally — your signal can carry damage amounts, hit positions, or any other data. The Recorder ignores signal arguments and just triggers the recording.

### Examples

**Record when a pickup is collected (ONCE):**

```
HealthPack (Area2D)
├── Sprite2D
├── CollisionShape2D
└── ChronicleRecorder
    trigger_signal: "body_entered"
    fact_key: "powerup.health_pack.collected"
    value: true
    record_mode: ONCE
```

**Count kills with INCREMENT:**

```
Enemy (CharacterBody2D)
└── ChronicleRecorder
    trigger_signal: "died"
    fact_key: "player.kills.skeleton"
    record_mode: INCREMENT
    amount: 1
```

**Update a mutable value every time (ALWAYS):**

```
NPC (Node2D)
└── ChronicleRecorder
    trigger_signal: "dialogue_started"
    fact_key: "npc_maria.last_talked_to"
    value: true
    record_mode: ALWAYS
```

**Connect to the `fact_recorded` signal from another node:**

```gdscript
$HealthPack/ChronicleRecorder.fact_recorded.connect(func(key, value, old_value):
    hud.flash_pickup_icon()
)
```

---

## ChronicleGate

Enables, disables, or frees a target node based on a condition expression.

### Exports

| Property | Type | Default | Description |
|---|---|---|---|
| `condition` | String | `""` | Boolean expression referencing fact keys |
| `gate_mode` | GateMode | `HIDE_WHEN_FALSE` | What to do when condition is true/false |
| `target_path` | NodePath | `""` | Node to control. Empty = parent node. |
| `default_when_missing` | bool | `false` | When enabled, missing facts resolve to `true` instead of `false` |

### GateMode Enum

| Mode | When condition is TRUE | When condition is FALSE |
|---|---|---|
| `HIDE_WHEN_FALSE` | `visible = true`, process mode restored to original | `visible = false`, process disabled |
| `SHOW_WHEN_FALSE` | `visible = false`, process disabled | `visible = true`, process mode restored to original |
| `QUEUE_FREE_WHEN_TRUE` | `target.queue_free()` and gate `queue_free()` | Nothing |
| `SIGNAL_ONLY` | Emits `gate_opened` | Emits `gate_closed` |

### Signals

- `gate_opened` — condition just became true
- `gate_closed` — condition just became false

### default_when_missing

When `false` (default): missing facts evaluate as `false`. The gate stays closed until the fact is explicitly set.

When `true`: missing facts evaluate as `true`. Useful for "show unless explicitly disabled" patterns.

### Behavior Notes

- Parses the condition once at `_ready()`. Extracts all fact keys the expression references. Registers a watcher only for those keys — re-evaluates only when a relevant key changes.
- Evaluates once on `_ready()` for initial state — the target is immediately in the correct state before the first frame.
- Unwatches in `_exit_tree()`.
- Shows a yellow warning icon in the editor if `condition` is empty or has parse errors.
- `target_path` is hidden in the inspector when `gate_mode = SIGNAL_ONLY`.
- Show/hide (`HIDE_WHEN_FALSE`, `SHOW_WHEN_FALSE`) uses duck typing to check for `"visible"` property (`"visible" in target`), so it works with any node that has a `visible` property — not only CanvasItem nodes.

### Methods

| Method | Description |
|--------|-------------|
| `is_open() -> bool` | Returns whether the gate is currently in the "open" state |
| `set_custom_apply(fn: Callable) -> void` | Override gate behavior. Signature: `fn(is_open: bool, target: Node)` — `is_open` is already inverted for `SHOW_WHEN_FALSE` |

Note: The gate uses `_transition_to()` (private) internally to change state. It is not part of the public API. If you need to manually control gate state from a `set_custom_apply` callback, set the target node's properties directly within the callback.

### Lifecycle

- Gate re-evaluates automatically on `state_reset` (after save/load or rollback)
- Gate only re-evaluates when watched facts change (not every frame)
- `gate_opened` / `gate_closed` signals emit only on state transitions, not every evaluation

### Examples

**Hide a door until a key is collected:**

```
Door (Node2D)
└── ChronicleGate
    condition: "key.collected"
    gate_mode: HIDE_WHEN_FALSE
```

**Show a "locked" overlay when NOT holding the key:**

```
LockedOverlay (Control)
└── ChronicleGate
    condition: "key.collected"
    gate_mode: SHOW_WHEN_FALSE
```

**Permanently remove a chest after it's looted:**

```
Chest (Node2D)
└── ChronicleGate
    condition: "chest_tower_b2.looted"
    gate_mode: QUEUE_FREE_WHEN_TRUE
```

**Compound expression — vault opens only when both conditions are met:**

```
VaultDoor (Node2D)
└── ChronicleGate
    condition: "armory.sword.taken AND library.lore.read"
    gate_mode: HIDE_WHEN_FALSE
```

**Signal-only — trigger cutscene without modifying a node:**

```
CutsceneController (Node)
└── ChronicleGate
    condition: "boss.defeated"
    gate_mode: SIGNAL_ONLY

# In CutsceneController:
$ChronicleGate.gate_opened.connect(_play_victory_cutscene)
```

**Control a node other than the parent:**

```
GateController (Node)
└── ChronicleGate
    condition: "player.has_lantern"
    gate_mode: HIDE_WHEN_FALSE
    target_path: "../DarkOverlay"
```

---

## ChronicleReactor

Fires a callback when facts matching a pattern appear or change. More flexible than ChronicleGate — use it when you need to run code rather than toggle visibility.

### Exports

| Property | Type | Default | Description |
|---|---|---|---|
| `watch_pattern` | String | `""` | Glob pattern for fact keys to monitor |
| `react_to` | ReactTo | `ANY` | Which change types trigger the reaction |
| `one_shot` | bool | `false` | Fire once then auto-unwatch until `reset()` |
| `target_method` | String | `""` | Method name on parent to call (optional) |

### ReactTo Enum

| Mode | Fires when... |
|---|---|
| `ANY` | Any change (creation, modification, or erasure) |
| `CREATION` | A fact first appears (`old_value` is null) |
| `CHANGE` | An existing fact's value changes (excludes creation/erasure) |
| `ERASURE` | A fact is deleted (`value` is null) |

### Signal

`fact_matched(key: String, value: Variant, old_value: Variant)` — emitted on every match that passes the `react_to` filter.

### Methods

| Method | Description |
|--------|-------------|
| `set_filter(fn: Callable) -> void` | Custom filter. Signature: `fn(key: String, value: Variant, old_value: Variant) -> bool`. Return `false` to suppress. |
| `reset() -> void` | Reset a one-shot reactor so it can fire again |

### target_method Callback

If `target_method` is set, the parent's method is called with the same signature:

```gdscript
func on_fact_changed(key: String, value: Variant, old_value: Variant) -> void:
    pass
```

If the method doesn't exist on the parent, a warning is emitted via `push_warning()` (but `fact_matched` is still emitted).

#### set_filter example

```gdscript
var reactor: ChronicleReactor = $ChronicleReactor
reactor.set_filter(func(key, value, old_value):
    return value is int and value > 0  # only positive integers
)
```

### Behavior Notes

- Validates the pattern in `_ready()`. Invalid patterns emit a warning and don't register.
- Unwatches in `_exit_tree()`.
- When `one_shot = true`, the watcher is removed after the first match.
- Shows a yellow warning icon if `watch_pattern` is empty or if `target_method` doesn't exist on the parent.
- After `state_reset` (load or rollback), reactors with `react_to = ANY` or `react_to = CREATION` replay all existing facts as CREATION events (`old_value` is `null`). Reactors with `react_to = CHANGE` or `react_to = ERASURE` do not replay. One-shot reactors can fire and become spent during replay.

### Examples

**Call a method when any player fact changes:**

```
HUDController (Control)
└── ChronicleReactor
    watch_pattern: "player.*"
    target_method: "on_player_fact_changed"
    react_to: ANY
```

```gdscript
# In HUDController:
func on_player_fact_changed(key: String, value: Variant, old_value: Variant) -> void:
    if key == "player.gold":
        gold_label.text = str(value)
    elif key == "player.health":
        health_bar.value = int(value)
```

**Trigger dialogue only once when the player enters a new area:**

```
HubRoom (Node2D)
└── ChronicleReactor
    watch_pattern: "hub.visited"
    target_method: "start_ghost_greeting"
    react_to: CREATION
    one_shot: true
```

**React to any defeat event:**

```
AchievementTracker (Node)
└── ChronicleReactor
    watch_pattern: "player.defeated.*"
    target_method: "check_achievement"
    react_to: CREATION
```

```gdscript
# In AchievementTracker:
func check_achievement(key: String, value: Variant, old_value: Variant) -> void:
    var boss_name: String = key.replace("player.defeated.", "")
    Achievements.unlock("killed_" + boss_name)
```

**Respond only to value changes (not initial set):**

```
AlertSystem (Node)
└── ChronicleReactor
    watch_pattern: "guard.alert_level"
    target_method: "on_alert_changed"
    react_to: CHANGE
```

---

## Walkthrough: Adding a Gate to a Door

Step-by-step for the most common Chronicle use case.

**Goal:** A door node that is hidden until the player collects a key.

**Step 1.** In your scene, find or create the door node:

```
Level (Node2D)
├── Player (CharacterBody2D)
├── KeyPickup (Area2D)
└── Door (StaticBody2D)
```

**Step 2.** Add a ChronicleRecorder to the KeyPickup:

- Select `KeyPickup`, click `Add Child Node`, search for `ChronicleRecorder`.
- In the Inspector:
  - `Trigger Signal`: `body_entered`
  - `Fact Key`: `key.collected`
  - `Value`: `true`
  - `Record Mode`: `ONCE`

**Step 3.** Add a ChronicleGate to the Door:

- Select `Door`, click `Add Child Node`, search for `ChronicleGate`.
- In the Inspector:
  - `Condition`: `key.collected`
  - `Gate Mode`: `HIDE_WHEN_FALSE`
  - `Target Path`: *(leave empty — defaults to parent)*

**Step 4.** Run the scene.

The Door is immediately hidden (condition is false — `key.collected` doesn't exist yet). When the Player enters the KeyPickup Area2D, the Recorder fires, sets `key.collected = true`, the Gate re-evaluates, and the Door becomes visible.

No scripts needed. No polling. No coupling between the pickup and the door.

**Step 5 (optional).** Verify the fact in your game script:

```gdscript
func _on_player_interact() -> void:
    if Chronicle.has_fact("key.collected"):
        enter_door()
    else:
        $UI/MessageLabel.text = "The door is locked."
```
