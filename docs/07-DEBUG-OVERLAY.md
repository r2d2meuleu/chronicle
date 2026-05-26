# Chronicle — Debug Overlay

The debug overlay is a runtime inspection panel that shows every fact write, every gate evaluation, every reactor match, and performance metrics — all live, while the game runs. It is toggled with F9 (configurable) and compiles out of release builds entirely.

---

## Table of Contents

1. [Enabling the Overlay](#1-enabling-the-overlay)
2. [Compile-Out in Release Builds](#2-compile-out-in-release-builds)
3. [Layout](#3-layout)
4. [Panel Reference](#4-panel-reference)
   - [Fact Feed](#41-fact-feed)
   - [Fact Inspector](#42-fact-inspector)
   - [Gate Status](#43-gate-status)
   - [Reactor Log](#44-reactor-log)
   - [Perf Monitor](#45-perf-monitor)
5. [Configuring the Overlay](#5-configuring-the-overlay)
6. [Debugging Workflows](#6-debugging-workflows)

---

## 1. Enabling the Overlay

The overlay is active automatically in debug builds. No code changes needed.

When `OS.is_debug_build()` returns `true` (i.e., when you run the game from the Godot editor, or export with a debug template), Chronicle's autoload instantiates the overlay at startup:

```gdscript
# In chronicle.gd _ready():
if not Engine.is_editor_hint():
    if OS.is_debug_build() or OS.has_feature("CHRONICLE_DEBUG"):
        var script: GDScript = load("res://addons/chronicle/debug/debug_overlay.gd")
        if script != null:
            add_child(script.new())
```

The `enabled_in_release` setting is NOT checked at autoload time -- it is checked inside the overlay's own `_ready()` method (see Section 2). The autoload only loads the overlay in debug builds or when the `CHRONICLE_DEBUG` feature flag is present.

Press **F9** while the game is running to toggle visibility.

You can also force the overlay in a release build by adding a custom feature flag:

```
Project Settings → Export → Custom Features → CHRONICLE_DEBUG
```

---

## 2. Compile-Out in Release Builds

The overlay checks `OS.is_debug_build()` at startup and calls `queue_free()` immediately if it returns `false`:

```gdscript
func _ready() -> void:
    var enabled_in_release: bool = ProjectSettings.get_setting("chronicle/debug/enabled_in_release", false)
    if not (OS.is_debug_build() or enabled_in_release or OS.has_feature("CHRONICLE_DEBUG")):
        queue_free()
        return
    # ... initialize panels
```

This ensures zero runtime overhead in production — the node is freed before its first `_process()` call.

Additionally, the `EditorExportPlugin` strips the entire `addons/chronicle/debug/` directory from release exports when `chronicle/debug/enabled_in_release` is `false` (the default). The debug code does not exist in the release binary at all.

To change this behavior:

```
Project Settings → chronicle → debug → enabled_in_release → true
```

Set this only if you are building a QA build or need to collect field reports.

---

## 3. Layout

The overlay is a `CanvasLayer` at layer 128 (above most game UI), docked to the right side of the viewport. It occupies approximately 35% of the viewport width and the full height.

The background is semi-transparent so game content remains visible behind it.

`process_mode` is set to `PROCESS_MODE_ALWAYS`, so the overlay works while the game is paused. You can freeze the game and inspect facts without the overlay disappearing.

All five panels live in a `TabContainer`. Click a tab to switch panels.

---

## 4. Panel Reference

### 4.1 Fact Feed

**What it shows:** Every fact write in real time, newest at the bottom.

**Data source:** Connected to the `fact_changed` signal on the Chronicle autoload.

**Update strategy:** Signal-driven. No polling. The feed holds a ring buffer of 200 entries — when full, the oldest entry is removed.

**Format:**

Each line shows the game clock timestamp, key, and value. The format varies by change type:

```
[12.50] player.gold = 250              # creation (new fact)
[15.10] player.gold 250 → 500         # change (old → new)
[30.00] player.health 85 → [erased]   # erasure
```

Creation events (where `old_value` is `null`) use `=` to show the initial value. Change events show `old_value → new_value`. Erasure events (where `value` is `null`) show `old_value → [erased]`.

**Use case:** Catch unexpected writes. If a fact you don't recognize is changing, it shows up here immediately.

### 4.2 Fact Inspector

**What it shows:** All current facts, browsable and filterable.

**Data source:** Calls `get_facts()` on tab focus to retrieve all current keys and values.

**Update strategy:** Full rebuild on tab focus and on search text changes. The tree is repopulated each time to reflect current state.

**Controls:**

- **Search bar (LineEdit):** Type text to filter facts by substring match (case-insensitive). Filters live as you type.
- **Tree:** Flat list of all matching facts. Each row shows the full key and its current value.

**Use case:** Check the exact value of any fact at any point in time. Useful when a gate is not responding — confirm the fact exists and has the expected value.

### 4.3 Gate Status

**What it shows:** All `ChronicleGate` nodes in the scene, grouped by their current open/closed state.

**Data source:** Gate nodes self-register by adding themselves to the Godot group `chronicle_gates` in `_ready()`. The overlay iterates this group on tab focus to rebuild the gate status display.

**Tree structure:**

```
Gates
├── Open
│   └── vault_door
└── Closed
    ├── magic_shop
    └── secret_door
```

**Use case:** Instantly see which gates are open or closed. The overlay shows gate name and Open/Closed status only — it does not display the condition expression. To debug why a gate is closed, inspect the gate's `condition` property in the Scene tree dock, then switch to **Fact Inspector** in the overlay to check the values of the referenced keys.

### 4.4 Reactor Log

**What it shows:** Every time a `ChronicleReactor` fires a match, with the reactor's name, the matched key, and the value.

**Data source:** Connected to the `fact_matched` signal on all ChronicleReactor nodes. Uses the `ChronicleNodeUtils.GROUP_REACTORS` (`"chronicle_reactors"`) group for discovery.

**Update strategy:** Signal-driven ring buffer of 200 entries. Reactor signals are only connected when the Reactor Log tab is first focused, not at overlay startup. Reactor events that fire before you open the Reactor Log tab are not captured.

```
18.3 hub_ghost_reactor guard.stealth_kill = true
22.1 kill_counter_reactor player.kill_count = 3
```

**Use case:** Verify that reactors are firing when expected, and not firing when they shouldn't be. If a callback is being called unexpectedly, this panel shows you the exact key and value that triggered it.

### 4.5 Perf Monitor

**What it shows:** Four real-time performance metrics, updated at 1 Hz via a `Timer`.

| Metric | What it measures |
|--------|-----------------|
| Facts | Current number of facts in `_store` |
| Watchers | Total registered watchers (exact + glob) |
| Gates | Number of ChronicleGate nodes in the scene |
| Reactors | Number of ChronicleReactor nodes in the scene |

**Use case:** Check whether you are approaching recommended limits (10K facts, 500 watchers). See [11-LIMITS-AND-PERFORMANCE.md](11-LIMITS-AND-PERFORMANCE.md) for detailed thresholds.

---

## 5. Configuring the Overlay

These settings live in `Project Settings → chronicle → debug`:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `chronicle/debug/overlay_hotkey` | String | `"F9"` | Key to toggle overlay visibility |
| `chronicle/debug/enabled_in_release` | bool | `false` | Allow overlay in release exports |

To change the hotkey to F8:

```
Project Settings → chronicle → debug → overlay_hotkey → "F8"
```

The overlay reads this setting at `_ready()` and maps the key via `_unhandled_input()`.

---

## 6. Debugging Workflows

### "My gate isn't opening"

1. Press F9 to open the overlay.
2. Go to **Gate Status**. Find the gate. Confirm it shows "Closed".
3. In the Godot Scene tree, select the gate node and read its `condition` property.
4. Switch to **Fact Inspector** in the overlay. Search for each key in the condition. Check values.
5. If a key is missing entirely, the condition evaluated with `default_when_missing = false` (the gate's default). Either set the fact or enable `default_when_missing` on the gate.
6. If a key has an unexpected value, switch to **Fact Feed** and look for the last write to that key. Find where the wrong value came from.

### "My reactor is firing too many times"

1. Open **Reactor Log**. Note how many times your reactor appears and what keys triggered it.
2. Check the reactor's `react_to` setting. If it is `ANY`, it fires on creation AND change. Use `CHANGE` to skip the initial write.
3. If the reactor should only fire once, verify `one_shot` is enabled in the Inspector. If using code, call `reset()` to re-arm after the first fire.
4. If a key is being written in a loop (watcher sets a fact, which fires another watcher), check **Perf Monitor** for high reactors-fired/sec and open **Fact Feed** to spot the cascading writes.

### "My facts are not being saved"

1. After saving, open **Fact Inspector** and check each key you expect to be saved.
2. Call `Chronicle.serialize()` in the debugger (or print it) and inspect the `"facts"` dictionary.
3. Any key absent from the serialized output but present in the Inspector is transient — check `set_fact()` calls for that key and verify the `transient` argument.

### "The game is running slowly after a long session"

1. Open **Perf Monitor**. Check the fact count — if it is near 10,000, you may have a key-per-event leak (e.g., unique keys for each enemy killed).
2. Switch to **Fact Inspector** and filter by entity. Look for entities with hundreds of entries.
3. Consider using `increment()` on a single counter instead of one boolean per event.
4. Check the watcher count. More than 500 watchers can degrade write performance. Glob watchers are especially costly as they are checked on every write.
