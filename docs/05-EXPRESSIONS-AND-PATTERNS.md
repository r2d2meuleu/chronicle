# Chronicle — Expressions and Patterns

Chronicle uses two distinct syntaxes: **expressions** for ChronicleGate conditions, and **patterns** for wildcard queries and watchers.

---

## Expression Syntax

Expressions are used in `ChronicleGate.condition`. They are parsed once at `_ready()` and evaluated on demand.

### Bare Key (Truthy Check)

A fact key by itself checks that the key exists AND its value is truthy (not `false`, `0`, `0.0`, `""`, or `null`).

```
door.unlocked
player.has_sword
quest_dragon.completed
```

Equivalent to `Chronicle.is_marked("door.unlocked")`.

### Comparisons

Supported operators: `==`, `!=`, `>`, `<`, `>=`, `<=`

```
player.gold >= 100
player.health > 0
quest.status == "completed"
quest.status != "failed"
player.level >= 5
enemy.health <= 0
```

The right-hand side can be a number, a string literal (double-quoted), `TRUE`, `FALSE`, or another fact key.

```
# Compare two facts to each other
player.gold >= player.debt
```

### Boolean Operators

**Keywords are case-insensitive.** `AND`, `and`, `And` all work identically. The lexer normalizes to uppercase internally via `to_upper()` before keyword lookup.

```
player.has_sword AND player.has_shield
player.gold >= 100 or player.has_key
not door.locked
```

### Parentheses

Use parentheses to control evaluation order.

```
(player.has_sword OR player.has_bow) AND player.gold >= 50
(quest.act == "2" OR quest.act == "3") AND NOT quest.completed
```

### Operator Precedence

From highest to lowest binding:

| Priority | Operator | Associativity |
|----------|----------|---------------|
| 1 | `()` parentheses | Grouping |
| 2 | `NOT` (prefix) | Right |
| 3 | `==`, `!=`, `>`, `<`, `>=`, `<=`, `IN`, `NOT IN`, `BETWEEN`, `NOT BETWEEN`, `MATCHES`, `NOT MATCHES` | Non-associative |
| 4 | `AND` | Left |
| 5 | `OR` | Left |

`NOT a AND b` evaluates as `(NOT a) AND b`, not `NOT (a AND b)`.

### TRUE and FALSE Literals

```
# A gate that is always open (useful with SIGNAL_ONLY mode for testing)
TRUE

# A gate that is always closed
FALSE
```

### Set Membership (`IN` / `NOT IN`)

Check if a fact's value is contained in an array of values.

```
player.class IN ["warrior", "paladin", "knight"]
NOT player.class IN ["mage", "warlock"]
```

### Range Check (`BETWEEN` / `NOT BETWEEN`)

Inclusive range check: `key BETWEEN val1 AND val2`.

```
player.level BETWEEN 5 AND 10
NOT player.gold BETWEEN 0 AND 99
```

### Regex Match (`MATCHES` / `NOT MATCHES`)

Regex match against a string fact value. Patterns are implicitly anchored -- the parser wraps every pattern as `^(?:pattern)$`, so `MATCHES "fail"` is an exact match, not a substring search. Use `.*` to match substrings.

```
quest.status MATCHES "comp.*"      # matches "completed", "compromised", etc.
quest.status MATCHES ".*fail.*"    # substring match for "fail" anywhere
NOT npc.name MATCHES "^Guard.*"    # redundant ^ but harmless — anchored already
npc.name MATCHES "Guard"           # exact match only — does NOT match "Guardian"
```

### Full Grammar Summary

| Construct | Syntax | Example |
|---|---|---|
| Bare key truthy | `key` | `door.unlocked` |
| Equality | `key == value` | `status == "done"` |
| Inequality | `key != value` | `status != "failed"` |
| Greater than | `key > value` | `player.level > 5` |
| Less than | `key < value` | `timer < 30.0` |
| Greater or equal | `key >= value` | `player.gold >= 100` |
| Less or equal | `key <= value` | `health <= 0` |
| IN | `key IN [values]` | `class IN ["mage", "cleric"]` |
| NOT IN | `key NOT IN [values]` | `class NOT IN ["thief"]` |
| BETWEEN | `key BETWEEN a AND b` | `level BETWEEN 5 AND 10` |
| NOT BETWEEN | `key NOT BETWEEN a AND b` | `gold NOT BETWEEN 0 AND 99` |
| MATCHES | `key MATCHES "pattern"` | `name MATCHES "^Sir"` |
| NOT MATCHES | `key NOT MATCHES "pattern"` | `name NOT MATCHES "^Guard"` |
| AND | `expr AND expr` | `a AND b` |
| OR | `expr OR expr` | `a OR b` |
| NOT | `NOT expr` | `NOT door.locked` |
| Parentheses | `(expr)` | `(a OR b) AND c` |
| TRUE literal | `TRUE` | `TRUE` |
| FALSE literal | `FALSE` | `FALSE` |
| String literal | `"value"` | `status == "active"` |

### Null Handling (Missing Facts)

When a fact referenced in an expression doesn't exist, it resolves to `null`:

| Operator | Null behavior |
|----------|--------------|
| Bare key (truthy) | `null` → `false` |
| `==` | `null == null` → `true`; `null == anything` → `false` |
| `!=` | `null != null` → `false`; `null != anything` → `true` |
| `>`, `<`, `>=`, `<=` | Any null operand → `false` |
| `IN` | `null IN [...]` → `false` |
| `BETWEEN` | `null BETWEEN a AND b` → `false` |
| `MATCHES` | `null MATCHES "..."` → `false` |

### Limits and Caching

- **Max nesting depth:** 64 levels of parentheses or `NOT` operators. Exceeding this returns `null` (parse error).
- **AST cache:** 256 expressions cached. Repeated `evaluate()` calls with the same string skip parsing.
- **Regex cache:** 512 compiled patterns cached for `MATCHES` operator.
- **Short-circuit evaluation:** `AND` stops on first `false`; `OR` stops on first `true`.

### String Escape Sequences

String literals support: `\"` (quote), `\\` (backslash), `\n` (newline), `\t` (tab).

### evaluate() / evaluate_bool() from Scripts

`Chronicle.evaluate(expression)` returns a `Variant` (`true`/`false` or `null` on parse error). `Chronicle.evaluate_bool(expression)` returns `false` on parse error instead of `null`, which is convenient for conditionals:

```gdscript
var can_buy: Variant = Chronicle.evaluate("player.gold >= 100 AND shop.open")
if can_buy == null:
    push_error("Bad expression syntax")
elif can_buy:
    open_shop_ui()

# Or use evaluate_bool() for simpler conditionals:
if Chronicle.evaluate_bool("player.gold >= 100 AND shop.open"):
    open_shop_ui()
```

### Keyword Rules

**Keywords are case-insensitive.** The lexer calls `to_upper()` on each word before checking the keyword table, so `AND`, `and`, `And`, `aNd` all resolve to the same operator.

| Token | Keyword? |
|---|---|
| `AND` / `and` / `And` | Yes — boolean AND |
| `OR` / `or` / `Or` | Yes — boolean OR |
| `NOT` / `not` / `Not` | Yes — boolean NOT |
| `TRUE` / `true` / `True` | Yes — boolean true literal |
| `FALSE` / `false` / `False` | Yes — boolean false literal |
| `IN` / `in` | Yes — set membership |
| `BETWEEN` / `between` | Yes — inclusive range check |
| `MATCHES` / `matches` | Yes — regex match |

A word containing dots is always treated as a fact key path, even if it contains reserved substrings. `and.or.not` is a fact path, not a parse error.

### Error Handling

If a condition has a syntax error, ChronicleGate emits a warning, and the gate defaults to **closed** (condition evaluates to `false`). A yellow warning icon appears on the node in the editor.

Parse errors include the column position:

```
[Chronicle] Expression parse error at col 12: unexpected token 'AND'.
```

---

## Extending the Expression System

Chronicle's expression language is extensible. You can register custom operators that work alongside the built-in ones.

### Simple Expressions (Recommended)

For most custom operators, use `register_keyword()` + `register_simple_expression()`. The keyword registration teaches the lexer to recognize the syntax, and `register_simple_expression()` handles the AST evaluation boilerplate -- you only write the evaluation logic.

```gdscript
# Step 1: Register the keyword with the lexer (token_type must be >= 1000)
Chronicle.register_keyword("STARTS_WITH", 1000, func(state, operand, negated):
    var tok = state.tokens[state.pos]
    state.pos += 1
    return {"node_type": "STARTS_WITH", "key": operand.value, "arg": tok.value}
)

# Step 2: Register the evaluation handler
Chronicle.register_simple_expression("STARTS_WITH", func(key, arg, resolver):
    var value: Variant = resolver.call(key)
    return value is String and value.begins_with(str(arg))
)

# Now usable in expressions and gate conditions:
Chronicle.evaluate("quest.name STARTS_WITH \"dragon\"")
```

**Important:** `register_simple_expression()` only registers the evaluation handler -- it does NOT register the keyword with the lexer. Without the `register_keyword()` call, the lexer tokenizes `STARTS_WITH` as a KEY token and the operator silently does not work.

**Limitation:** `register_simple_expression` does not support negation. The `eval_fn` only receives `key`, `arg`, and `resolver` — it has no access to the AST `negated` field. If you need a negatable operator (`NOT STARTS_WITH`), use the full `register_keyword()` + `register_expression_handler()` pair instead (see Advanced section below).

### Advanced: Custom Keywords + Expression Handlers

For operators that need custom parsing (e.g. multi-argument syntax), use the lower-level `register_keyword()` + `register_expression_handler()` pair. `register_keyword()` teaches the lexer/parser to recognize the syntax, and `register_expression_handler()` teaches the evaluator how to execute it.

The `parse_fn` passed to `register_keyword()` receives three arguments:
- `state: ParseState` — the parser state (has `.tokens` array and `.pos` index)
- `operand: Dictionary` — `{op_type = "key", value = <key_string>}` (the left-hand key, already parsed)
- `negated: bool` — `true` if the keyword was preceded by `NOT`

The `token_type` must be >= `1000` (`Lexer.FIRST_CUSTOM_TOKEN_TYPE`).

```gdscript
# Register a DIVISIBLE_BY operator: player.kills DIVISIBLE_BY 10

var parse_divisible := func(state: Variant, operand: Dictionary, negated: bool) -> Variant:
    # operand.value is the left-hand key (e.g. "player.kills")
    # Consume the next token as the argument
    var tok: Dictionary = state.tokens[state.pos]
    state.pos += 1
    var result: Dictionary = {"node_type": "divisible_by", "key": operand.value, "arg": tok.value}
    if negated:
        result["negated"] = true
    return result

Chronicle.register_keyword("DIVISIBLE_BY", 1000, parse_divisible, true)  # true = negatable

var eval_divisible := func(ast: Dictionary, resolver: Callable) -> Variant:
    var val: Variant = resolver.call(ast.key)
    var divisible: bool = val is int and ast.arg is int and val % ast.arg == 0
    return not divisible if ast.get("negated", false) else divisible

var keys_divisible := func(ast: Dictionary, keys: Array[String]) -> void:
    if ast.key not in keys:
        keys.append(ast.key)

var walk_divisible := func(ast: Dictionary, leaf_fn: Callable) -> void:
    leaf_fn.call(ast)

Chronicle.register_expression_handler("divisible_by", eval_divisible, keys_divisible, walk_divisible)
```

See the [API Reference](03-API-REFERENCE.md) for full parameter documentation.

---

## Pattern Syntax

Patterns are used in:
- `Chronicle.get_fact_keys(pattern)`
- `Chronicle.count_facts(pattern)`
- `Chronicle.get_first_change(pattern)`
- `Chronicle.get_last_change(pattern)`
- `Chronicle.watch(pattern, callback)`
- `ChronicleReactor.watch_pattern`

### Valid Patterns

| Pattern | Meaning | Matches |
|---|---|---|
| `"player.gold"` | Exact match | Only `"player.gold"` |
| `"player.*"` | Trailing wildcard | `"player.gold"`, `"player.health"`, `"player.defeated.boss"` |
| `"a.*.c"` | Mid-segment wildcard | Matches exactly one segment: `"a.foo.c"`, `"a.bar.c"` (not `"a.x.y.c"`) |
| `"*.key"` | Leading wildcard | Matches any entity with that suffix: `"door.key"`, `"chest.key"` |
| `"*"` | Match all | Every key in the store |

The trailing wildcard `.*` matches any key that starts with the prefix. This includes keys at any depth:

```gdscript
# "player.*" matches all of these:
# player.gold
# player.health
# player.defeated.boss_swamp
# player.inventory.sword
```

Mid-segment wildcards (`a.*.c`) match exactly one segment between the surrounding segments. Leading wildcards (`*.key`) match exactly one preceding segment — `*.hp` matches `player.hp` but NOT `player.stats.hp`.

### Invalid Patterns

These patterns are rejected at registration time with a warning:

| Pattern | Why invalid |
|---|---|
| `""` | Empty — always invalid |
| `".player.gold"`, `"player.gold."` | Leading or trailing dot — malformed key structure |
| `"player..gold"` | Consecutive dots — malformed key structure |
| `"player*"`, `"gua*rd.hp"` | Mixed wildcard — `*` must be an entire segment, not part of one |
| `"Player.gold"`, `"quest.Status"` | Uppercase characters — use lowercase `a-z`, `0-9`, underscore only |

### Cross-Entity Queries

Leading wildcards (`"*.locked"`) match any key with exactly one segment before the suffix:

```gdscript
# Watch all locked facts across all entities
var id: int = Chronicle.watch("*.locked", _on_any_lock_changed)

# Query all locked keys
var locked_keys: Array[String] = Chronicle.get_fact_keys("*.locked")
```

Alternatively, use `watch_any()` for an explicit list:

```gdscript
var id: int = Chronicle.watch_any(
    ["door_1.locked", "door_2.locked", "door_3.locked"],
    _on_door_changed
)
```

### Pattern Matching Implementation

Exact keys and trailing wildcards use fast `begins_with()` checks. Mid-segment and leading wildcards use segment-level matching.

```
"*"            → always true
"player.*"     → key.begins_with("player.")
"player.gold"  → key == "player.gold"
"a.*.c"        → matches one segment between "a." and ".c"
"*.locked"     → matches exactly one segment before ".locked" (e.g. "door.locked", not "big.door.locked")
```

---

## Practical Examples

**Gate that opens after completing two objectives:**

```
condition: armory.sword.taken AND library.lore.read
```

**Gate for a merchant who only appears with enough gold or a special item:**

```
condition: player.gold >= 500 OR player.has_merchant_pass
```

**Gate that shows a tutorial hint until the player has acted:**

```
condition: player.has_moved OR player.has_attacked
gate_mode: SHOW_WHEN_FALSE
```

The hint is visible when neither `player.has_moved` nor `player.has_attacked` is set. Once either becomes truthy, the condition is true and the hint hides.

**Watch all quest facts for a journal system:**

```gdscript
Chronicle.watch("quest.*", func(key, value, old):
    journal.refresh_entry(key.replace("quest.", ""))
)
```

**Watch multiple exact keys efficiently:**

```gdscript
var _hud_watch: int = -1

func _ready() -> void:
    _hud_watch = Chronicle.watch_any(
        ["player.gold", "player.health", "player.level"],
        _on_hud_fact_changed
    )

func _exit_tree() -> void:
    Chronicle.unwatch(_hud_watch)

func _on_hud_fact_changed(key: String, value: Variant, _old: Variant) -> void:
    match key:
        "player.gold":   gold_label.text = str(value)
        "player.health": health_bar.value = int(value)
        "player.level":  level_label.text = "Lv %d" % value
```

**Count matching facts:**

```gdscript
# How many armory items were taken?
var count: int = Chronicle.count_facts("armory.*.taken")

# Did the player defeat at least 3 bosses?
var boss_kills: int = Chronicle.count_facts("player.defeated.*")
if boss_kills >= 3:
    Chronicle.set_fact("achievement.boss_slayer")
```
