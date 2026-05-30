# Chronicle Test Project

GUT 9.6.0 test suite.

## Running (core and production MUST be separate processes — combined they OOM)

```bash
# Core (+ integration/nodes/io/editor/scenarios/stress)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=test/core,test/integration,test/nodes,test/io,test/editor,test/scenarios,test/stress
# Production (separate process)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=test/production
```

**Engine-error gate:** `.gutconfig.json` sets `"failure_error_types": ["engine"]`, so any runtime `SCRIPT ERROR` (e.g. `Invalid access`, wrong-arity call, `Nonexistent function`) FAILS the test instead of being silently logged while the test "passes". A test that INTENTIONALLY triggers an engine error (corrupt-file I/O, editor-only classes, malformed regex) must declare it with `assert_engine_error_count(N, "why")` to consume the expected error. `push_error`/`push_warning` are NOT gated (Chronicle's own validation warnings don't fail tests).

## Test Conventions

- In-tree nodes: `autoqfree()`/`add_child_autoqfree()`; off-tree: `autofree()`. Never manual `free()` for fixture cleanup — manual `queue_free()`/`free()` is allowed only when freeing is the behavior under test, or for a raw `Object` instance.
- Chronicle instances in tests: `add_child_autoqfree(Chronicle.new())`, not the 2-step autoqfree + add_child.
- Gate assertions: `assert_gate_open/closed` for HIDE/SHOW modes. Raw `assert_true(parent.visible)` for SIGNAL_ONLY (it doesn't modify visibility).
- Signal capture: `collect_signal(source, "name")` handles 2/3/4-arg key/value signals (`fact_expired`, `fact_matched`, `fact_recorded`, `fact_changed`). For 0/1-arg lifecycle signals (`state_reset`, `state_rolled_back`, gate `gate_opened`/`gate_closed`) use `collect_any_signal(source, "name")`. Exception: re-entrant callbacks with essential side effects use a manual `.connect`.
- GUT assertions (canonical idioms — enforced by the meta-test, see below):
  - Membership: `assert_has(x, y)` / `assert_does_not_have(x, y)`, not `assert_true(x.has(y))`. (Object-method `.has()` on a RefCounted like `ChronicleStore`/`ChronicleExpiry` is NOT Dict/Array membership — keep `assert_true(obj.has(k), "msg")` with a trailing `# meta-allow:has-membership`.)
  - Ordering/range: `assert_gt`/`assert_gte`/`assert_lt`/`assert_lte`/`assert_between`, not `assert_true(a > b)`.
  - Null: `assert_not_null`/`assert_null`, not `assert_true(x != null)`.
  - Bool results: `assert_true(b)`/`assert_false(b)`, not `assert_eq(b, true)` (keep the deliberate bool-vs-truthy `assert_eq(get_fact(k), true)` WITH a message).
  - "Ran without crashing" markers: `pass_test("why")`, never bare `assert_true(true)`.
  - Prefer exact over loose: assert the deterministic value/cause (`assert_eq(n, 900)`, `err.contains("reserved")`), not `> 0` / `!= ""`. If a count is deterministic (e.g. a self-limiting cascade that runs exactly N times), assert the exact count.
  - Assertion messages are ENCOURAGED for clarity but NOT required on every assert. A self-evident bool/precondition check (`assert_true(ok)` after a known-good setup, `assert_false(found)`) may omit the message when the test name + neighboring asserts already give context. The meta-test does not enforce messages — a missing message is not, by itself, a defect.
  - But `assert_true(x is Dictionary)` not `assert_is` (GUT's assert_is fails on value types).
- Enum aliases: `CompanionFactory.RecordMode.ONCE`, not the long form through script preloads.
- No `class_name` in test files. Only support/ files get class_name.
- Extend `ChronicleTestSuite`. Exception: pure-logic tests (expression parser, pattern matcher) extend `GutTest`.
- File mapping: `test_gate.gd` tests `chronicle_gate.gd`. Keep tests in the file that matches their source. Notably: `ChronicleValueUtils` tests live in `test_value_utils.gd`; `ChronicleWarningBus` tests in `test_warning_bus.gd`; `ChronicleRingCache` tests in `test_ring_buffer.gd`; `ChroniclePatternMatcher` tests in `test_pattern_matcher.gd`. `test_key_codec.gd` is now a pure-logic `GutTest` file (covers only the key codec — no `_chronicle`).
- Naming: descriptive `test_<behavior>` only — NO audit-code prefixes (`bugN`/`edgeN`/`aXX_Y`/`test_NN_` ordinals). Semantic numbers are fine (`test_500_facts_...`). A test's name must match its assertion's polarity (no `_returns_false` that asserts success). If audit traceability is needed, use a `# audit: <code>` comment, not the function name.
- Section headers: one style — `# ── Name ──` (unicode bars). No `# ===` ASCII boxes, no per-test `# N.` running counters (they drift).
- Convention enforcement: `test/meta/test_suite_conventions.gd` scans every test file and FAILS the build on reintroduced anti-patterns (tautologies, `.has()` membership, `assert_true(a>b)` ordering, null-compare, audit-prefix names, unguarded benches). Sanctioned exceptions use a trailing `# meta-allow:<rule>` comment. Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=test/meta`.

## Framework Helpers — Use These Instead of Raw Assertions

**IMPORTANT: Always use the helpers below instead of writing raw assertion logic. These exist to keep tests consistent and provide better failure messages.**

### ChronicleTestSuite (extend this in all tests)

Provides `_chronicle` (autoload instance, cleared in `before_each`).

**Watcher factories** (return EventCollector):
- `watch_events(pattern)` — persistent watcher. Pattern is String or Array[String].
- `watch_once_events(pattern)` — one-shot watcher.
  - **Note:** `watch_events`/`watch_once_events` auto-assert valid watch_id. For intentionally invalid patterns, use `EventCollector.watch()` directly.
- `make_collector()` — bare EventCollector (no watch registered). For manual callback plumbing.

**Signal collectors** (return EventCollector):
- `collect_signal(source, signal_name)` — single unified collector for any signal arity (2/3/4 args). The lambda has 1 mandatory + 3 optional params, so Godot binds it to 2-arg (`fact_expired`: key, value), 3-arg (`fact_matched`/`fact_recorded`: key, value, old_value), and 4-arg (`fact_changed`: key, value, old_value, erase_source — `erase_source` is dropped before capture) signals. Captures `(key, value, old_value, time)`, stamping real game time from `_chronicle`.

**Node creation** (auto-cleaned):
- `add_node(name)` — Node added to tree root.
- `add_node_2d(name)` — Node2D (visible=true) added to tree root. Use for gate targets.
- `add_signaled_node(signal_name, signal_args)` — Node with a custom user signal.

**Companion node creation** (auto-cleaned, fully wired):
- `add_gate(condition, config)` — Node2D target with ChronicleGate child. Returns the target. Use with `assert_gate_open/closed`.
- `add_reactor(config)` — SpyNode parent with ChronicleReactor child. Returns the reactor. Parent accessible via `reactor.get_parent()`.
- `add_recorder(config)` — Signaled parent with ChronicleRecorder child. Returns the parent. Emit trigger signal on it.

**Fact assertions**:
- `assert_fact(key, expected)` — asserts `has_fact` AND `get_fact == expected`. Use instead of raw `assert_eq(_chronicle.get_fact(...))`.
- `assert_has_fact(key)` — asserts the fact exists, value not checked. Use when only existence matters (e.g., falsy values like `0`).
- `assert_no_fact(key)` — asserts fact does NOT exist. Use instead of `assert_false(_chronicle.has_fact(...))`.
- `assert_marked(key)` / `assert_not_marked(key)` — for `is_marked` checks.
- `assert_fact_count(pattern, expected)` — asserts `count_facts(pattern) == expected`.
- `assert_facts(expected_dict)` — asserts all key/value pairs exist. Use for bulk operations.
- `assert_transient(key)` / `assert_not_transient(key)` — assert the fact exists and is / is not marked transient (`is_transient`).
- `assert_fact_type(key, expected_type)` — asserts `typeof(get_fact(key)) == expected_type` (a `TYPE_*` constant). Asserts existence first.
- `assert_has_expiry(key)` / `assert_no_expiry(key)` — assert the fact does / does not have an active expiry (`has_expiry`).

**Coordinator / state assertions**:
- `assert_idle()` — asserts the write coordinator is idle (`_coordinator.is_idle()` AND `_cascade_depth == 0`). Use after cascades.
- `assert_rollback_ok(result)` / `assert_rollback_rejected(result)` — assert `result.success` is true / false. Pass the value returned by `rollback_to()` / `rollback_steps()`.

**Gate assertions** (HIDE/SHOW modes only):
- `assert_gate_open(target)` — asserts visible=true AND process_mode=INHERIT.
- `assert_gate_closed(target)` — asserts visible=false AND process_mode=DISABLED.

**Warning assertions** (configuration warnings on companion nodes):
- `assert_has_warning(node, substring)` — asserts `_get_configuration_warnings()` contains a warning with the substring.
- `assert_no_warnings(node)` — asserts `_get_configuration_warnings()` is empty.

**Timeline / history assertions**:
- `assert_history(key, expected_values, expected_times=[], expected_old_values=[])` — asserts `get_fact_history(key)` matches values, and optionally times and/or old_values. The 4th param `expected_old_values` checks each entry's `old_value` (when non-empty, its length must equal `expected_values`); use `null` entries for "no old value". Use instead of raw `get_fact_history` + manual loops.
- `assert_history_size(key, expected)` — asserts the number of history entries for `key`. For high-volume tests where listing every value is impractical.
- `assert_history_first(key, expected_value)` / `assert_history_last(key, expected_value)` — assert the first / last history entry's value.
- `assert_first_change(pattern, expected_key, expected_value)` / `assert_last_change(pattern, expected_key, expected_value)` — assert the earliest / most recent timeline entry matching `pattern` (a Dictionary) has the given `key` and `value`. Replaces `get_first_change`/`get_last_change` + null-check + field access.
- `assert_no_first_change(pattern)` / `assert_no_last_change(pattern)` — assert no timeline entry matches `pattern`.
- `assert_changes_since_count(since_time, expected)` — asserts `get_changes_since(since_time).size() == expected`.

**Clock helpers**:
- `set_time(t)` — calls `_chronicle.set_game_time(t)`.
- `advance_time(delta)` — calls `_chronicle.advance_game_time(delta)`.
- `assert_game_time(expected)` — asserts `get_game_time() == expected`.

**Watcher assertions**:
- `assert_watcher_count(expected)` — asserts `get_stats().watcher_count == expected`.

**Cascade helper**:
- `build_cascade_chain(prefix, depth=8)` → final key — registers a linear watcher cascade `watch("<prefix>.i")` → `set_fact("<prefix>.(i+1)")` and returns `"<prefix>.<depth>"`. Use instead of hand-rolling linear chains in cascade/stress tests.

**Lifecycle-signal capture**:
- `collect_any_signal(source, signal_name)` → EventCollector — for ANY-arity signals (0–4 args), used for `state_reset`/`state_rolled_back`/`gate_opened`/`gate_closed`. Records raw args per emission; assert with `assert_emission_count(n)` / `assert_emission_args(index, [...])`.

**Signal counting** (lightweight emission counters when EventCollector is overkill):
- `make_counter()` → `Array` — a single-element mutable counter `[0]`.
- `make_signal_sink(counter)` → `Callable` — a no-arg callable that does `counter[0] += 1`; connect it to a signal and assert on `counter[0]`.

**Spy assertions** (for reactors created via `add_reactor`, whose SpyNode parent records `on_fact` calls):
- `assert_spy_calls(reactor, expected)` — asserts the SpyNode parent recorded `expected` calls. Reads `reactor.get_parent().calls`.
- `assert_spy_call(reactor, index, key=SKIP, value=SKIP, old_value=SKIP)` — asserts a specific recorded call's fields. Pass `EventCollector.SKIP` to skip a field.

**File helpers**:
- `save_temp(path, data)` — saves and registers for cleanup in `after_each`.
- `register_temp(path)` — register a path (and its `.bak`) for `after_each` deletion when a test writes via a path the base doesn't already track (e.g. direct `ChronicleFileIO`/`save_file`). Don't hand-roll `_temp_files.append` or a bespoke `after_each`.
- `roundtrip()` → `Dictionary` — serialize the current Chronicle, `clear()`, then `deserialize()` back into the same instance. For "does state survive a save/load cycle" tests (transient facts are dropped). Returns the serialized Dictionary so callers can inspect the wire format. Use for pure type-fidelity checks.
- `serialize_into_new()` → `Node` — serialize the current Chronicle and deserialize into a FRESH autoqueued instance (asserts deserialize succeeds); returns it. Use instead of the hand-rolled `add_child_autoqfree(Chronicle.new()) + deserialize` when a test needs a second live instance.
- `read_file(path)` → `Variant` — static helper. Load and decode a saved Chronicle file for inspection (verify on-disk wire format or migration output). Returns `null` on load failure.
- Timeline-cap teardown is automatic: the base `before_each` snapshots `get_timeline_cap()` and `after_each` restores it, so tests may freely `set_timeline_cap(...)` without leaking the cap to later tests. Don't add per-file cap restores.
- Persistent-config isolation is automatic: `before_each` resets the save/load callables, store hard cap, write interceptor, and pattern matcher to their defaults (`clear()` does NOT reset these), so a test may freely call `set_save_fn`/`set_load_fn`/`set_store_hard_cap`/`set_write_interceptor`/`set_pattern_matcher` without leaking into later tests. Don't add per-test restores for these.

### EventCollector

Captures `(key, value, old_value, time)` events from watchers or signals.

**Assertions** (all delegate to GUT with full event dump on failure):
- `assert_count(expected)` — number of collected events.
- `assert_event(index, key, value, old_value)` — check specific event. Pass `EventCollector.SKIP` to skip a field.
- `assert_keys(expected_keys)` — assert collected keys in order.
- `assert_values(expected_values)` — assert collected values in order.
- `assert_value_transition(index, expected_old, expected_new)` — check old->new at index.
- `assert_event_time(index, expected_time)` — check timestamp. Each event captures the real game time (`_chronicle.get_game_time()`) at emission.
- `assert_no_key(key)` — assert key never appeared in events.
- `assert_valid_id()` — assert `watch_id >= 0`.
- `assert_invalid_id()` — assert `watch_id == -1`.

**Any-arity signal capture** (via `collect_any_signal` / `EventCollector.connect_any`):
- `assert_emission_count(expected)` — number of signal emissions.
- `assert_emission_args(index, expected_args)` — the raw args array of a specific emission (e.g. `[]` for 0-arg `state_reset`, `[5.0]` for `state_rolled_back`).

**Accessors**:
- `count()` — number of events.
- `keys()` — all keys in order.
- `first()` / `last()` — first/last event dict.
- `clear()` — reset for multi-phase tests.
- `callback()` — the raw Callable for manual plumbing.

### CompanionFactory

Creates companion nodes from config dicts. Always use enum aliases.

**Factory methods**:
- `CompanionFactory.make_gate({condition, gate_mode, target_path, default_when_missing, chronicle_path})`
- `CompanionFactory.make_reactor({watch_pattern, target_method, react_to, one_shot, chronicle_path})`
- `CompanionFactory.make_recorder({trigger_signal, fact_key, value, record_mode, amount, chronicle_path})`

**Enum aliases** (use these, not the long preload form):
- `CompanionFactory.GateMode.HIDE_WHEN_FALSE` / `.SHOW_WHEN_FALSE` / `.QUEUE_FREE_WHEN_TRUE` / `.SIGNAL_ONLY`
- `CompanionFactory.ReactTo.ANY` / `.CREATION` / `.CHANGE` / `.ERASURE`
- `CompanionFactory.RecordMode.ONCE` / `.ALWAYS` / `.INCREMENT`

### Spy Node

`preload("res://test/support/chronicle_spy_node.gd")` — set as script on a Node. Has `calls: Array[Dictionary]` and `on_fact(key, value, old_value)` method for reactor `target_method` testing. Each call dict has `{key, value, old_value}`.

### ExpressionTestHelpers

`ExpressionTestHelpers.run_expr(engine, expr, facts)` → `bool` — parse + evaluate an expression against a facts dict (returns `false` on parse failure). Used by the expression test files' `_run_expr` forwarder; call it directly for pure-logic expression tests.

### Chronicle API Reference

**Signals**:
- `fact_changed(key, value, old_value, erase_source)` — fires on any mutation (set, erase, expiry-erase, rollback). `value` is `null` when the fact is deleted. `erase_source` is an `EraseSource` enum value (`USER`, `EXPIRY`, `ROLLBACK`).
- `state_reset` — fires after `clear()`, `deserialize()`, `load_file()`, or `rollback_*()` when state actually changes. Also fires after rollback when facts changed. Does not fire on no-op rollbacks (e.g., rolling back to the current time with no entries to undo).
- `state_rolled_back(target_time)` — fires after a successful rollback.
- `fact_expired(key, expired_value)` — fires when an expiring fact's lifetime reaches zero.

**Write methods**:
- `set_fact(key, value, transient, lifetime)` — set a fact. `lifetime=0.0` clears expiry; `KEEP_LIFETIME` preserves it. `transient=true` excludes the fact from serialization. Passing `null` as value erases the fact.
- `erase_fact(key)` → `bool` — remove a fact entirely. Returns true if the fact existed.
- `increment_fact(key, amount, transient, lifetime)` → `Variant` — numeric increment; returns new value (null on error).
- `clamp_fact(key, min_value, max_value, transient, lifetime)` — clamp a numeric fact in-place; no-op if already within range or non-numeric.
- `set_facts(entries, transient, lifetime)` → `int` — bulk write.
- `erase_facts(keys)` → `int` — bulk erase. Returns count of facts actually erased.
- `toggle_fact(key, transient, lifetime)` — toggle a boolean fact: sets to `true` if missing or falsy, sets to `false` if truthy. Returns the new state. Note: toggle-off sets `false`, not erase — `has_fact()` returns `true` after toggle-off.
- `set_expiry(key, lifetime)` → `bool` — add or update expiry on an existing fact without changing its value.

**Read methods**:
- `get_fact(key, default)` — returns the stored value or `default` (null) if missing.
- `has_fact(key)` — true if the fact exists.
- `is_marked(key)` — true if the fact exists and is truthy.
- `get_facts(pattern)` — returns a `{key: value}` dict for all facts matching `pattern`. Default `pattern = "*"` returns all facts.
- `get_fact_keys(pattern)` — returns `Array[String]` of matching keys.
- `count_facts(pattern)` — returns the number of matching keys.
- `is_transient(key)` — true if the fact exists and is marked transient.
- `get_fact_changes_between(key, since_time, until_time)` — timeline entries for a single key within the closed range [since_time, until_time].
- `get_first_change(pattern)` → `Variant` — earliest timeline entry matching pattern as Dictionary, or `null` if no match.
- `get_last_change(pattern)` → `Variant` — most recent timeline entry matching pattern as Dictionary, or `null` if no match.
- `evaluate(expression)` → `Variant` — evaluate a Chronicle expression string against current facts. Returns `true`/`false` for valid expressions, `null` on parse error.
- `get_changes_since(time)` / `get_changes_between(since, until)` — timeline slices.
- `get_fact_history(key)` — full change history for a single key.

**Watch methods**:
- `watch(pattern, callback, once)` → `int` watch_id. Returns -1 if the pattern is invalid or the callback is not valid.
- `watch_any(patterns, callback, once)` → `int` watch_id.
- `watch_once(pattern, callback)` → `int` watch_id — convenience for `watch(pattern, callback, true)`.
- `watch_any_once(patterns, callback)` → `int` watch_id — one-shot watcher for any of the given patterns, auto-unwatches after first match.
- `unwatch(watch_id)` → `bool` — remove a single watcher by id. Returns true if found and removed.
- `unwatch_pattern(pattern)` → `int` — remove all watchers registered with the exact pattern string. Returns count removed.
- `unwatch_all()` — remove every watcher immediately.

**Clock methods**:
- `get_game_time()` — current game clock value.
- `set_game_time(value)` — set clock manually (disables auto-advance).
- `advance_game_time(delta)` — advance clock manually (disables auto-advance).
- `is_auto_advancing()` — true if clock advances automatically via `_process`.
- `set_auto_advancing(enabled)` — enable or disable auto-advance.
- `get_expiry_remaining(key)` / `has_expiry(key)` — expiry queries.
- `set_expiry(key, lifetime)` → `bool` — routes through coordinator: creates timeline entries, rollback-reversible.

**Stats / utility**:
- `get_stats()` → `{fact_count, watcher_count, timeline_size, timeline_cap, expiry_count}`.
- `clear()` — reset all state and emit `state_reset`.
- `clear_warnings()` — reset warning deduplication so previously-suppressed warnings can fire again.
- `serialize()` / `deserialize(data)` — in-memory snapshot.
- `save_file(path)` / `load_file(path)` — disk persistence.
- `set_save_fn(fn)` / `set_load_fn(fn)` — override default file I/O callables.
- `rollback_to(target_time)` / `rollback_steps(step_count)` — undo history.
- `build_key(segments: Array[String])` → `String` — static method. Joins segments with dots, sanitizing each segment.
- `register_migration(from_version, migrate_fn, force=false)` → `bool` — instance method (call on the Chronicle instance, not the class). Register a callable to migrate save data from `from_version` to `from_version + 1`. User migrations only — called by `deserialize()`. Delegates to `ChronicleSerializer.register_migration()`.
- `register_expression_handler(node_type, eval_fn, keys_fn, walk_fn, force)` → `bool` — instance method. Register a custom expression AST node handler. Delegates to `ChronicleExpressionEvaluator.register_handler()`.
- `unregister_expression_handler(node_type)` → `bool` — instance method. Remove a previously registered custom expression AST node handler. Delegates to `ChronicleExpressionEvaluator.unregister_handler()`.
- `register_type(type_id, tag, pack, unpack, copy, keys, truthy_fn, force)` — instance method. `force: bool = false` param — pass `true` to override an existing tag registration.
- `register_keyword(keyword, token_type, parse_fn, negatable)` → `bool` — instance method. Register a custom keyword operator for expression parsing (added to both lexer and compiler).
- `unregister_keyword(keyword)` → `bool` — instance method. Remove a previously registered custom keyword from both compiler and lexer.
- `EraseSource` enum — re-exported on `Chronicle` from `ChronicleWriteCoordinator`. Values: `USER`, `EXPIRY`, `ROLLBACK`.
- `Chronicle.SERIALIZE_ALL` — constant (`-1`), re-exported from `ChronicleSerializer.SERIALIZE_ALL`. Pass as `timeline_cap` to `serialize()` to include all timeline entries (no cap applied).
- `Chronicle.DEFERRED` — static sentinel (RefCounted) returned by `increment_fact`/`toggle_fact`/`clamp_fact` when the write is deferred (called at MAX_CASCADE_DEPTH). Compare by identity: `result == Chronicle.DEFERRED`.
- `Chronicle.REJECT` — static sentinel (RefCounted); return it from a `set_write_interceptor` callback to prevent the write.
- `Chronicle.EXPIRY_NONE` — constant (`-1.0`); `get_expiry_remaining(key)` returns it when the key has no active expiry.
- `Chronicle.SERIALIZE_USE_SETTING` — constant (`0`); the default `timeline_cap` for `serialize()` (uses the `chronicle/storage/serialize_timeline_cap` project setting).
- `ChronicleReactor.set_filter(fn)` — attach a custom predicate `func(key, value, old_value) -> bool` that runs before `react_to`. Return `false` to suppress a match.
- `ChronicleReactor.reset()` — re-arm a `one_shot` reactor so it can fire again. `ChronicleRecorder.reset()` — re-arm a `ONCE`-mode recorder; `ChronicleRecorder.has_fired()` → `bool` reports whether it has fired.

**Expression facade** (build/evaluate ASTs directly; `evaluate(expr)` is the convenience wrapper):
- `parse_expression(source)` → `Variant` — parse an expression string into an AST, or `null` on parse error.
- `evaluate_expression(ast, resolver=Callable())` → `bool` — evaluate a pre-parsed AST (default fact resolver if none given). A `null`/non-Dictionary AST evaluates to `false`.
- `evaluate_bool(expression, default=false)` → `bool` — evaluate and return `default` on parse error.
- `extract_expression_keys(ast)` → `Array[String]` — all fact keys referenced by the AST.
- `walk_expression_ast(ast, leaf_fn)` — call `leaf_fn(node)` on each leaf node; a `null` AST is a safe no-op.

**Expiry / config / introspection**:
- `clear_expiry(key)` → `bool` — remove a fact's expiry (returns `false` when deferred).
- `flush_expiry()` → `bool` — process pending expiries immediately (call before `serialize()` to drop expired facts).
- `get_store_hard_cap()` → `int` — current store hard cap (`0` = disabled). Set via `set_store_hard_cap(cap)`; a new key beyond the cap is rejected.
- `set_pattern_matcher(matches_fn, validate_pattern_fn, force=false)` — replace the watch/query matcher; `force=true` clears existing watchers first.
- `validate_pattern(pattern)` → `String` — validate a watch/query pattern. Returns `""` if valid, else an error message.
- `is_valid_type(value)` → `bool` — true if `value` is a storable type (built-in or registered).
- `is_type_registered(type_id)` / `is_keyword_registered(keyword)` / `is_expression_handler_registered(node_type)` → `bool` — registration introspection.

**Registration** (instance methods — call on the Chronicle instance):
- `register_script_type(script, tag, pack_fn, unpack_fn, copy_fn=, required_keys=, truthy_fn=)` → `bool` — register a GDScript-attached value type for serialization. Returns `false` if the tag is reserved or already registered.
- `register_simple_expression(keyword, eval_fn)` → `bool` — register a custom keyword whose handler reads a single `"key"` field (auto-generates the keys/walk functions).
- `unregister_type(type_id)` → `bool` — remove a previously registered custom type.

Note: `fact_matched` (reactors) and `fact_recorded` (recorders) are companion-node signals, not Chronicle signals — capture them with `collect_signal(node, "...")`.

## Benchmarks

100 benchmarks across 3 tiers in `test/benchmarks/`. They use the `bench_` prefix (excluded from normal test runs) and run as a SEPARATE process from core/production (slow; up to several minutes at 100K+ scale).

```bash
# Per tier
godot --headless -s addons/gut/gut_cmdln.gd -gdir=test/benchmarks/micro/  -gprefix=bench_
godot --headless -s addons/gut/gut_cmdln.gd -gdir=test/benchmarks/macro/  -gprefix=bench_
godot --headless -s addons/gut/gut_cmdln.gd -gdir=test/benchmarks/stress/ -gprefix=bench_
# Single file / single benchmark
godot --headless -s addons/gut/gut_cmdln.gd -gdir=test/benchmarks/micro/ -gprefix=bench_ -gselect=bench_fact_write.gd
godot --headless -s addons/gut/gut_cmdln.gd -gdir=test/benchmarks/micro/ -gprefix=bench_ -gselect=bench_fact_write.gd -gunit_test_name=test_bench_overwrite_with_watchers
```

Results print to console (percentile tables) and JSON (`bench_results/`, gitignored).

### Benchmark conventions

- **Extend `BenchSuite`** (`test/benchmarks/core/bench_suite.gd`, which extends `ChronicleTestSuite`). It provides the `BenchHelper`/`BenchResults` consts, shared `_noop`/`_engine`, the `after_all()` flush, and `guard()`. Bench-only helpers live on BenchSuite, never on `ChronicleTestSuite`.
- **Correctness guards:** every bench proves the timed op did real work via `guard(condition, msg)` (so a silent regression fails instead of benchmarking nothing). EVERY bench is guarded — including `memory_per_fact` (its guard runs outside the timed memory window). In `run_scale_bench` the `guard_fn` takes the current scale and runs for EVERY scale, not just the first.
- **Measure real changes, not no-ops:** the write coordinator short-circuits an unchanged-value write (`write_coordinator.gd:158`) BEFORE dispatch, so re-setting the same value measures a suppressed no-op. For any op whose cost depends on a real state change (watcher/cascade/reactor dispatch), use `BenchHelper.measure_each(func(i: int) -> void: set_fact(key, i))` so each iteration writes a genuinely different value. `measure()` is for ops that are already state-changing/idempotent.
- **Stats:** `compute_stats` returns float min/percentiles(interpolated)/mean/stddev plus `valid`/`count`; `measure`/`measure_batched`/`measure_each` return `Array[float]` (sub-µs precision). `measure_batched` asserts `batch_size > 0`.
- **Scale loops:** use `BenchHelper.run_scale_bench(tier, suite, name, unit, SCALES, LABELS, setup_fn, op_fn, table_kind, batch_size=0, note="", guard_fn=func(scale)->void, scale_col="scale")` for the canonical clear→populate→measure→record→print loop. Bespoke methods (single-scale, OS-memory, per-iteration closure state) stay manual.
- **Naming:** scale-array consts are file-local `SCALES` / `LABELS`. Units: `us/op` (per-operation), `us/frame` (frame sims), `us` (whole-op latency), `bytes/fact` (memory).
- **Fixtures (two distinct generators by design):** `BenchSuite.populate_entities(entity_count, props_per, prefix="entity")` writes a DETERMINISTIC int grid (`<prefix>_e.prop_p = e*props+p`) — use in benchmarks where timed writes must be repeatable. `ScaleHelper.generate_entity_facts(chronicle, entity_count, keys_per_entity)` (production) writes TYPED-variety values — use in scale tests that need type diversity. They are intentionally separate (repeatable-timing vs type-coverage); pick by intent.
- **Storable values:** `set_fact` requires Dictionary keys to be `String` — GDScript lua-style literals (`{a = 1}`) produce StringName keys and are REJECTED. Use quoted keys (`{"a": 1}`) for nested-dict bench values.
