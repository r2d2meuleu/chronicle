## Tests for Expression Language Extensions: IN, NOT IN, BETWEEN operators.
extends GutTest

const Lexer := preload("res://addons/chronicle/core/expression/lexer.gd")

var _engine: ChronicleExpressionEngine


func before_each() -> void:
	_engine = ChronicleExpressionEngine.new()


# Tokenizer — New tokens

# IN keyword recognized
func test_tokenizer_in_keyword() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("status IN")
	assert_eq(tokens[0].type, T.KEY, "status is KEY")
	assert_eq(tokens[1].type, T.IN, "IN is keyword")


# BETWEEN keyword recognized
func test_tokenizer_between_keyword() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("level BETWEEN")
	assert_eq(tokens[0].type, T.KEY, "level is KEY")
	assert_eq(tokens[1].type, T.BETWEEN, "BETWEEN is keyword")


# Bracket and comma tokens
func test_tokenizer_brackets_and_comma() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize('["a", "b"]')
	assert_eq(tokens[0].type, T.LBRACKET, "left bracket")
	assert_eq(tokens[1].type, T.STRING, "first string")
	assert_eq(tokens[2].type, T.COMMA, "comma")
	assert_eq(tokens[3].type, T.STRING, "second string")
	assert_eq(tokens[4].type, T.RBRACKET, "right bracket")


# Dotted key containing IN is still a KEY
func test_tokenizer_dotted_in_is_key() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("state.IN.progress")
	assert_eq(tokens[0].type, T.KEY, "dotted IN is KEY")
	assert_eq(tokens[0].value as String, "state.IN.progress", "full dotted path")


# Dotted key containing BETWEEN is still a KEY
func test_tokenizer_dotted_between_is_key() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("quest.BETWEEN.status")
	assert_eq(tokens[0].type, T.KEY, "dotted BETWEEN is KEY")
	assert_eq(tokens[0].value as String, "quest.BETWEEN.status", "full dotted path")


# Lowercase in/between are keywords (case-insensitive)
func test_tokenizer_lowercase_in_between_are_keywords() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("in between")
	assert_eq(tokens[0].type, T.IN, "lowercase in is keyword")
	assert_eq(tokens[0].value as String, "IN", "lowercase in normalised to IN")
	assert_eq(tokens[1].type, T.BETWEEN, "lowercase between is keyword")
	assert_eq(tokens[1].value as String, "BETWEEN", "lowercase between normalised to BETWEEN")


# Negative number after BETWEEN
func test_tokenizer_negative_after_between() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("x BETWEEN -10 AND 50")
	assert_eq(tokens[2].type, T.NUMBER, "negative number type")
	assert_eq(tokens[2].value, -10.0, "negative number value")


# Negative number after comma in array
func test_tokenizer_negative_after_comma() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("[1, -5]")
	assert_eq(tokens[3].type, T.NUMBER, "negative after comma type")
	assert_eq(tokens[3].value, -5.0, "negative after comma value")


# Negative number after LBRACKET
func test_tokenizer_negative_after_lbracket() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("[-3, 4]")
	assert_eq(tokens[1].type, T.NUMBER, "negative after [ type")
	assert_eq(tokens[1].value, -3.0, "negative after [ value")


# NOT followed by IN are separate tokens
func test_tokenizer_not_in_separate_tokens() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("x NOT IN y")
	assert_eq(tokens[0].type, T.KEY, "x is KEY")
	assert_eq(tokens[1].type, T.NOT, "NOT token")
	assert_eq(tokens[2].type, T.IN, "IN token")
	assert_eq(tokens[3].type, T.KEY, "y is KEY")


# Parser — IN / NOT IN

# Parse key IN literal array
func test_parser_in_literal_array() -> void:
	var ast: Variant = _engine.parse('status IN ["done", "failed"]')
	assert_not_null(ast)
	assert_eq(ast.node_type, "in", "node type is in")
	assert_eq(ast.operand.op_type, "key", "operand is key")
	assert_eq(ast.operand.value as String, "status", "operand key is status")
	assert_false(ast.negated, "not negated")
	assert_eq(ast.rhs.rhs_type, "array", "rhs is array")
	assert_eq(ast.rhs.elements.size(), 2, "array has 2 elements")
	assert_eq(ast.rhs.elements[0].op_type, "string", "element 0 is string")
	assert_eq(ast.rhs.elements[0].value as String, "done", "element 0 value")
	assert_eq(ast.rhs.elements[1].value as String, "failed", "element 1 value")


# Parse key IN key (RHS resolves to array at runtime)
func test_parser_in_key_rhs() -> void:
	var ast: Variant = _engine.parse("player.class IN allowed_classes")
	assert_not_null(ast)
	assert_eq(ast.node_type, "in", "node type is in")
	assert_eq(ast.operand.value as String, "player.class", "operand key")
	assert_eq(ast.rhs.rhs_type, "key", "rhs is key")
	assert_eq(ast.rhs.value as String, "allowed_classes", "rhs key")
	assert_false(ast.negated, "not negated")


# Parse key NOT IN literal array
func test_parser_not_in_literal_array() -> void:
	var ast: Variant = _engine.parse('class NOT IN ["mage", "sorcerer"]')
	assert_not_null(ast)
	assert_eq(ast.node_type, "in", "node type is in")
	assert_true(ast.negated, "is negated")
	assert_eq(ast.rhs.rhs_type, "array", "rhs is array")


# Parse key NOT IN key
func test_parser_not_in_key_rhs() -> void:
	var ast: Variant = _engine.parse("weapon NOT IN banned_weapons")
	assert_not_null(ast)
	assert_eq(ast.node_type, "in", "node type is in")
	assert_true(ast.negated, "is negated")
	assert_eq(ast.rhs.rhs_type, "key", "rhs is key")
	assert_eq(ast.rhs.value as String, "banned_weapons", "rhs key")


# Parse IN with empty array
func test_parser_in_empty_array() -> void:
	var ast: Variant = _engine.parse("x IN []")
	assert_not_null(ast)
	assert_eq(ast.node_type, "in", "node type is in")
	assert_eq(ast.rhs.rhs_type, "array", "rhs is array")
	assert_eq(ast.rhs.elements.size(), 0, "empty array")


# Parse IN with single element
func test_parser_in_single_element() -> void:
	var ast: Variant = _engine.parse("x IN [42]")
	assert_not_null(ast)
	assert_eq(ast.rhs.elements.size(), 1, "single element")
	assert_eq(ast.rhs.elements[0].op_type, "number", "element is number")
	assert_eq(ast.rhs.elements[0].value, 42.0, "element value")


# Parse IN with mixed types
func test_parser_in_mixed_types() -> void:
	var ast: Variant = _engine.parse('x IN [1, "two", TRUE, FALSE]')
	assert_not_null(ast)
	assert_eq(ast.rhs.elements.size(), 4, "4 elements")
	assert_eq(ast.rhs.elements[0].op_type, "number", "number")
	assert_eq(ast.rhs.elements[1].op_type, "string", "string")
	assert_eq(ast.rhs.elements[2].op_type, "bool", "bool true")
	assert_eq(ast.rhs.elements[2].value, true, "true value")
	assert_eq(ast.rhs.elements[3].op_type, "bool", "bool false")
	assert_eq(ast.rhs.elements[3].value, false, "false value")


# Parse error: unterminated array
func test_parser_in_unterminated_array() -> void:
	var ast: Variant = _engine.parse('x IN ["a", "b"')
	assert_null(ast)


# Parse error: missing RHS after IN
func test_parser_in_missing_rhs() -> void:
	var ast: Variant = _engine.parse("x IN")
	assert_null(ast)


# NOT IN combined with unary NOT: NOT key NOT IN [...]
func test_parser_not_combined_with_not_in() -> void:
	var ast: Variant = _engine.parse('NOT x NOT IN ["a"]')
	assert_not_null(ast)
	assert_eq(ast.node_type, "not", "outer is NOT")
	assert_eq(ast.operand.node_type, "in", "inner is in")
	assert_true(ast.operand.negated, "inner is negated (NOT IN)")


# IN with AND: a IN [...] AND b
func test_parser_in_and_boolean() -> void:
	var ast: Variant = _engine.parse('status IN ["done"] AND player.alive')
	assert_not_null(ast)
	assert_eq(ast.node_type, "and", "root is and")
	assert_eq(ast.children[0].node_type, "in", "left is in")
	assert_eq(ast.children[1].node_type, "truthy", "right is truthy")


# Unary NOT before IN: NOT key IN [...]
func test_parser_unary_not_before_in() -> void:
	var ast: Variant = _engine.parse('NOT status IN ["bad"]')
	assert_not_null(ast)
	assert_eq(ast.node_type, "not", "root is NOT")
	assert_eq(ast.operand.node_type, "in", "operand is in")
	assert_false(ast.operand.negated, "the IN itself is not negated")


# Parser — BETWEEN

# Parse BETWEEN with literal bounds
func test_parser_between_literal_bounds() -> void:
	var ast: Variant = _engine.parse("level BETWEEN 5 AND 15")
	assert_not_null(ast)
	assert_eq(ast.node_type, "between", "node type is between")
	assert_eq(ast.operand.op_type, "key", "operand is key")
	assert_eq(ast.operand.value as String, "level", "operand key")
	assert_eq(ast.low.op_type, "number", "low is number")
	assert_eq(ast.low.value, 5.0, "low value")
	assert_eq(ast.high.op_type, "number", "high is number")
	assert_eq(ast.high.value, 15.0, "high value")


# Parse BETWEEN with key bounds
func test_parser_between_key_bounds() -> void:
	var ast: Variant = _engine.parse("level BETWEEN zone.min AND zone.max")
	assert_not_null(ast)
	assert_eq(ast.node_type, "between", "node type is between")
	assert_eq(ast.low.op_type, "key", "low is key")
	assert_eq(ast.low.value as String, "zone.min", "low key")
	assert_eq(ast.high.op_type, "key", "high is key")
	assert_eq(ast.high.value as String, "zone.max", "high key")


# Parse BETWEEN with mixed bounds (literal + key)
func test_parser_between_mixed_bounds() -> void:
	var ast: Variant = _engine.parse("level BETWEEN 1 AND zone.max")
	assert_not_null(ast)
	assert_eq(ast.low.op_type, "number", "low is literal")
	assert_eq(ast.high.op_type, "key", "high is key")


# Parse BETWEEN with negative bound
func test_parser_between_negative_bound() -> void:
	var ast: Variant = _engine.parse("temp BETWEEN -10 AND 50")
	assert_not_null(ast)
	assert_eq(ast.low.op_type, "number", "low is number")
	assert_eq(ast.low.value, -10.0, "low is -10")
	assert_eq(ast.high.value, 50.0, "high is 50")


# BETWEEN with boolean AND after: key BETWEEN a AND b AND other
func test_parser_between_followed_by_and() -> void:
	var ast: Variant = _engine.parse("level BETWEEN 5 AND 15 AND active")
	assert_not_null(ast)
	assert_eq(ast.node_type, "and", "root is AND")
	assert_eq(ast.children[0].node_type, "between", "left is between")
	assert_eq(ast.children[0].low.value, 5.0, "between low")
	assert_eq(ast.children[0].high.value, 15.0, "between high")
	assert_eq(ast.children[1].node_type, "truthy", "right is truthy")
	assert_eq(ast.children[1].key as String, "active", "right key")


# Two BETWEEN expressions with AND
func test_parser_two_between_with_and() -> void:
	var ast: Variant = _engine.parse("x BETWEEN 1 AND 5 AND y BETWEEN 10 AND 20")
	assert_not_null(ast)
	assert_eq(ast.node_type, "and", "root is AND")
	assert_eq(ast.children[0].node_type, "between", "first is between")
	assert_eq(ast.children[0].operand.value as String, "x", "first operand")
	assert_eq(ast.children[1].node_type, "between", "second is between")
	assert_eq(ast.children[1].operand.value as String, "y", "second operand")


# NOT BETWEEN (unary NOT wrapping BETWEEN)
func test_parser_not_between() -> void:
	var ast: Variant = _engine.parse("NOT level BETWEEN 5 AND 15")
	assert_not_null(ast)
	assert_eq(ast.node_type, "not", "root is NOT")
	assert_eq(ast.operand.node_type, "between", "operand is between")


# Parse error: missing AND in BETWEEN
func test_parser_between_missing_and() -> void:
	var ast: Variant = _engine.parse("level BETWEEN 5 15")
	assert_null(ast)


# Parse error: missing upper bound
func test_parser_between_missing_upper() -> void:
	var ast: Variant = _engine.parse("level BETWEEN 5 AND")
	assert_null(ast)


# Evaluator — IN / NOT IN

func _run_expr(expr: String, facts: Dictionary, engine: ChronicleExpressionEngine = null) -> bool:
	return ExpressionTestHelpers.run_expr(engine if engine != null else _engine, expr, facts)


# IN membership — true
func test_eval_in_member_true() -> void:
	assert_true(_run_expr('status IN ["done", "failed"]', {"status": "done"}))


# IN membership — false
func test_eval_in_member_false() -> void:
	assert_false(_run_expr('status IN ["done", "failed"]', {"status": "active"}))


# NOT IN — true (not a member)
func test_eval_not_in_true() -> void:
	assert_true(_run_expr('class NOT IN ["mage", "sorcerer"]', {"class": "warrior"}))


# NOT IN — false (is a member)
func test_eval_not_in_false() -> void:
	assert_false(_run_expr('class NOT IN ["mage", "sorcerer"]', {"class": "mage"}))


# IN with null LHS (missing key) — false
func test_eval_in_null_lhs() -> void:
	assert_false(_run_expr('status IN ["done"]', {}))


# NOT IN with null LHS — true (null is not in anything)
func test_eval_not_in_null_lhs() -> void:
	assert_true(_run_expr('status NOT IN ["done"]', {}))


# IN with key RHS resolving to Array — true
func test_eval_in_key_rhs_true() -> void:
	assert_true(_run_expr("weapon IN allowed", {"weapon": "sword", "allowed": ["sword", "axe"]}))


# IN with key RHS resolving to Array — false
func test_eval_in_key_rhs_false() -> void:
	assert_false(_run_expr("weapon IN allowed", {"weapon": "staff", "allowed": ["sword", "axe"]}))


# IN with key RHS resolving to non-Array — false (warning)
func test_eval_in_key_rhs_non_array() -> void:
	assert_false(_run_expr("weapon IN allowed", {"weapon": "sword", "allowed": "not_an_array"}))


# IN with key RHS resolving to null — false (warning)
func test_eval_in_key_rhs_null() -> void:
	assert_false(_run_expr("weapon IN allowed", {"weapon": "sword"}))


# NOT IN with key RHS resolving to null — false (fail-closed)
func test_eval_not_in_key_rhs_null() -> void:
	assert_false(_run_expr("weapon NOT IN allowed", {"weapon": "sword"}))


# NOT IN with key RHS resolving to non-Array — false (fail-closed)
func test_eval_not_in_key_rhs_non_array() -> void:
	assert_false(_run_expr("weapon NOT IN allowed", {"weapon": "sword", "allowed": 42}))


# IN empty array — always false
func test_eval_in_empty_array() -> void:
	assert_false(_run_expr("x IN []", {"x": 42}))


# IN int/float equality: 5 IN [5.0] — true
func test_eval_in_int_float_equality() -> void:
	assert_true(_run_expr("x IN [5.0]", {"x": 5}))


# IN with mixed types — matches correct element
func test_eval_in_mixed_types() -> void:
	assert_true(_run_expr('x IN [1, "hello", TRUE]', {"x": "hello"}))
	assert_false(_run_expr('x IN [1, "hello", TRUE]', {"x": "world"}))


# IN with boolean value
func test_eval_in_boolean() -> void:
	assert_true(_run_expr("flag IN [TRUE, FALSE]", {"flag": true}))


# IN combined with AND
func test_eval_in_combined_and() -> void:
	assert_true(_run_expr('status IN ["done"] AND gold >= 100', {"status": "done", "gold": 150}))
	assert_false(_run_expr('status IN ["done"] AND gold >= 100', {"status": "done", "gold": 50}))


# Evaluator — BETWEEN

# BETWEEN — in range (true)
func test_eval_between_in_range() -> void:
	assert_true(_run_expr("level BETWEEN 5 AND 15", {"level": 10}))


# BETWEEN — below range (false)
func test_eval_between_below_range() -> void:
	assert_false(_run_expr("level BETWEEN 5 AND 15", {"level": 3}))


# BETWEEN — above range (false)
func test_eval_between_above_range() -> void:
	assert_false(_run_expr("level BETWEEN 5 AND 15", {"level": 20}))


# BETWEEN — at lower bound (inclusive — true)
func test_eval_between_at_lower_bound() -> void:
	assert_true(_run_expr("level BETWEEN 5 AND 15", {"level": 5}))


# BETWEEN — at upper bound (inclusive — true)
func test_eval_between_at_upper_bound() -> void:
	assert_true(_run_expr("level BETWEEN 5 AND 15", {"level": 15}))


# BETWEEN — equal bounds: key BETWEEN 5 AND 5
func test_eval_between_equal_bounds() -> void:
	assert_true(_run_expr("level BETWEEN 5 AND 5", {"level": 5}))
	assert_false(_run_expr("level BETWEEN 5 AND 5", {"level": 6}))


# BETWEEN — key bounds
func test_eval_between_key_bounds() -> void:
	assert_true(_run_expr("level BETWEEN zone.min AND zone.max", {"level": 10, "zone.min": 5, "zone.max": 15}))
	assert_false(_run_expr("level BETWEEN zone.min AND zone.max", {"level": 3, "zone.min": 5, "zone.max": 15}))


# BETWEEN — null subject (warning + false)
func test_eval_between_null_subject() -> void:
	assert_false(_run_expr("level BETWEEN 5 AND 15", {}))


# BETWEEN — null bound (warning + false)
func test_eval_between_null_bound() -> void:
	assert_false(_run_expr("level BETWEEN zone.min AND 15", {"level": 10}))


# BETWEEN — non-numeric subject (warning + false)
func test_eval_between_non_numeric_subject() -> void:
	assert_false(_run_expr("name BETWEEN 5 AND 15", {"name": "hello"}))


# BETWEEN — non-numeric bound (warning + false)
func test_eval_between_non_numeric_bound() -> void:
	assert_false(_run_expr("level BETWEEN zone.min AND 15", {"level": 10, "zone.min": "five"}))


# BETWEEN — inverted bounds (warning + false)
func test_eval_between_inverted_bounds() -> void:
	assert_false(_run_expr("level BETWEEN 15 AND 5", {"level": 10}))


# BETWEEN — float values
func test_eval_between_float() -> void:
	assert_true(_run_expr("pos BETWEEN 0.0 AND 1.0", {"pos": 0.5}))
	assert_true(_run_expr("pos BETWEEN 0.0 AND 1.0", {"pos": 0.0}))
	assert_true(_run_expr("pos BETWEEN 0.0 AND 1.0", {"pos": 1.0}))
	assert_false(_run_expr("pos BETWEEN 0.0 AND 1.0", {"pos": 1.1}))


# BETWEEN combined with AND
func test_eval_between_combined_and() -> void:
	assert_true(_run_expr("level BETWEEN 5 AND 15 AND active", {"level": 10, "active": true}))
	assert_false(_run_expr("level BETWEEN 5 AND 15 AND active", {"level": 10, "active": false}))


# NOT BETWEEN (via unary NOT)
func test_eval_not_between() -> void:
	assert_true(_run_expr("NOT level BETWEEN 5 AND 15", {"level": 3}))
	assert_false(_run_expr("NOT level BETWEEN 5 AND 15", {"level": 10}))


# Key Extraction

# IN with literal array — extracts only LHS key
func test_keys_in_literal_array() -> void:
	var ast: Variant = _engine.parse('status IN ["done", "failed"]')
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 1, "one key")
	assert_eq(keys[0] as String, "status", "LHS key extracted")


# IN with key RHS — extracts both keys
func test_keys_in_key_rhs() -> void:
	var ast: Variant = _engine.parse("weapon IN allowed_weapons")
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 2, "two keys")
	assert_has(keys, "weapon", "LHS key")
	assert_has(keys, "allowed_weapons", "RHS key")


# NOT IN — same extraction as IN
func test_keys_not_in() -> void:
	var ast: Variant = _engine.parse("x NOT IN banned")
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 2, "two keys")
	assert_has(keys, "x", "LHS key")
	assert_has(keys, "banned", "RHS key")


# BETWEEN with literal bounds — extracts only subject
func test_keys_between_literal() -> void:
	var ast: Variant = _engine.parse("level BETWEEN 5 AND 15")
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 1, "one key")
	assert_eq(keys[0] as String, "level", "subject key")


# BETWEEN with key bounds — extracts all three
func test_keys_between_key_bounds() -> void:
	var ast: Variant = _engine.parse("level BETWEEN zone.min AND zone.max")
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 3, "three keys")
	assert_has(keys, "level", "subject key")
	assert_has(keys, "zone.min", "low bound key")
	assert_has(keys, "zone.max", "high bound key")


# Compound expression — all keys from all operators
func test_keys_compound_all_operators() -> void:
	var ast: Variant = _engine.parse('status IN ["done"] AND level BETWEEN zone.min AND zone.max OR weapon NOT IN banned')
	var keys := _engine.extract_keys(ast)
	assert_has(keys, "status", "status")
	assert_has(keys, "level", "level")
	assert_has(keys, "zone.min", "zone.min")
	assert_has(keys, "zone.max", "zone.max")
	assert_has(keys, "weapon", "weapon")
	assert_has(keys, "banned", "banned")
	assert_eq(keys.size(), 6, "six unique keys")


# Deduplication: same key in multiple positions
func test_keys_deduplication() -> void:
	var ast: Variant = _engine.parse("level BETWEEN 1 AND 10 AND level >= 5")
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 1, "deduplicated to one")
	assert_eq(keys[0] as String, "level", "level")


# MATCHES Operator — Tokenizer

# MATCHES keyword recognized
func test_tokenizer_matches_keyword() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize('state MATCHES "idle"')
	assert_eq(tokens[0].type, T.KEY, "state is KEY")
	assert_eq(tokens[1].type, T.MATCHES, "MATCHES is keyword")
	assert_eq(tokens[2].type, T.STRING, "pattern is STRING")


# Lowercase matches is keyword (case-insensitive)
func test_tokenizer_lowercase_matches_is_keyword() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("matches")
	assert_eq(tokens[0].type, T.MATCHES, "lowercase matches is keyword")
	assert_eq(tokens[0].value as String, "MATCHES", "lowercase matches normalised to MATCHES")


# Dotted path containing MATCHES is KEY
func test_tokenizer_dotted_matches_is_key() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("state.MATCHES.result")
	assert_eq(tokens[0].type, T.KEY, "dotted path is KEY")
	assert_eq(tokens[0].value as String, "state.MATCHES.result")


# NOT and MATCHES are separate tokens
func test_tokenizer_not_matches_separate_tokens() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize('key NOT MATCHES "x"')
	assert_eq(tokens[0].type, T.KEY, "key")
	assert_eq(tokens[1].type, T.NOT, "NOT is separate")
	assert_eq(tokens[2].type, T.MATCHES, "MATCHES is separate")
	assert_eq(tokens[3].type, T.STRING, "pattern")


# Negative number allowed after MATCHES token
func test_tokenizer_negative_after_matches() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("MATCHES -5")
	assert_eq(tokens[0].type, T.MATCHES)
	assert_eq(tokens[1].type, T.NUMBER)
	assert_eq(tokens[1].value, -5.0)


# MATCHES Operator — Parser

# MATCHES produces correct AST node with compiled RegEx
func test_parse_matches_basic() -> void:
	var ast: Variant = _engine.parse('state MATCHES "idle"')
	assert_eq(ast.node_type, "matches")
	assert_eq(ast.operand.op_type, "key")
	assert_eq(ast.operand.value as String, "state")
	assert_eq(ast.pattern as String, "idle")
	assert_false(ast.negated, "not negated")


# NOT MATCHES produces negated AST node
func test_parse_not_matches() -> void:
	var ast: Variant = _engine.parse('id NOT MATCHES "test_.*"')
	assert_eq(ast.node_type, "matches")
	assert_eq(ast.operand.value as String, "id")
	assert_eq(ast.pattern as String, "test_.*")
	assert_true(ast.negated, "is negated")


# Invalid regex pattern produces null AST
func test_parse_matches_invalid_pattern() -> void:
	var ast: Variant = _engine.parse('key MATCHES "[unclosed"')
	assert_null(ast, "invalid regex returns null AST")
	# RegEx.compile on the malformed pattern emits one engine error before the
	# parser rejects it and returns null. Declaring it confirms the failure path ran.
	assert_engine_error_count(1, "malformed regex emits one RegEx compile error before parse returns null")


# Missing STRING after MATCHES — parse error
func test_parse_matches_missing_pattern() -> void:
	var ast: Variant = _engine.parse("key MATCHES")
	assert_null(ast, "missing pattern returns null")


# Non-string token after MATCHES — parse error
func test_parse_matches_non_string_rhs() -> void:
	var ast: Variant = _engine.parse("key MATCHES 42")
	assert_null(ast, "number after MATCHES is error")


# Empty pattern compiles successfully
func test_parse_matches_empty_pattern() -> void:
	var ast: Variant = _engine.parse('key MATCHES ""')
	assert_eq(ast.node_type, "matches")
	assert_eq(ast.pattern as String, "")


# NOT key NOT MATCHES — double negation
func test_parse_not_key_not_matches() -> void:
	var ast: Variant = _engine.parse('NOT state NOT MATCHES "dead"')
	assert_eq(ast.node_type, "not", "outer NOT")
	assert_eq(ast.operand.node_type, "matches", "inner is matches")
	assert_true(ast.operand.negated, "inner is negated (NOT MATCHES)")


# MATCHES precedence with AND/OR
func test_parse_matches_precedence() -> void:
	var ast: Variant = _engine.parse('state MATCHES "idle" AND level > 5')
	assert_eq(ast.node_type, "and", "AND is root")
	assert_eq(ast.children[0].node_type, "matches")
	assert_eq(ast.children[1].node_type, "compare")


# MATCHES Operator — Evaluator

# Full match — exact string matches
func test_eval_matches_exact() -> void:
	assert_true(_run_expr('state MATCHES "idle"', {"state": "idle"}))


# Full match — partial string does NOT match (no substring matching)
func test_eval_matches_no_partial() -> void:
	assert_false(_run_expr('state MATCHES "idle"', {"state": "idle_2"}))


# Wildcard pattern matches
func test_eval_matches_wildcard() -> void:
	assert_true(_run_expr('state MATCHES "idle.*"', {"state": "idle_running"}))
	assert_false(_run_expr('state MATCHES "idle.*"', {"state": "not_idle"}))


# Alternation in pattern
func test_eval_matches_alternation() -> void:
	assert_true(_run_expr('state MATCHES "idle|patrol"', {"state": "idle"}))
	assert_true(_run_expr('state MATCHES "idle|patrol"', {"state": "patrol"}))
	assert_false(_run_expr('state MATCHES "idle|patrol"', {"state": "chase"}))


# Explicit partial via .*
func test_eval_matches_explicit_partial() -> void:
	assert_true(_run_expr('name MATCHES ".*Hero.*"', {"name": "The Hero Falls"}))
	assert_false(_run_expr('name MATCHES ".*Hero.*"', {"name": "The Villain Rises"}))


# User-provided anchors (redundant but valid)
func test_eval_matches_user_anchors() -> void:
	assert_true(_run_expr('tag MATCHES "^done$"', {"tag": "done"}))
	assert_false(_run_expr('tag MATCHES "^done$"', {"tag": "undone"}))


# Character class followed by quantifier — allowed (not a ReDoS risk)
func test_eval_matches_character_class() -> void:
	var ast: Variant = _engine.parse('id MATCHES "quest_[0-9]+"')
	assert_not_null(ast, "quantifier after ] is allowed — character classes are not ReDoS risk")
	assert_true(_run_expr('id MATCHES "quest_[0-9]+"', {"id": "quest_123"}), "character class quantifier matches")
	assert_false(_run_expr('id MATCHES "quest_[0-9]+"', {"id": "quest_"}), "character class quantifier rejects no digits")


# NOT MATCHES — true when no match
func test_eval_not_matches_true() -> void:
	assert_true(_run_expr('state NOT MATCHES "dead"', {"state": "alive"}))


# NOT MATCHES — false when matches
func test_eval_not_matches_false() -> void:
	assert_false(_run_expr('state NOT MATCHES "dead"', {"state": "dead"}))


# Null LHS — silent false
func test_eval_matches_null_lhs() -> void:
	assert_false(_run_expr('state MATCHES "idle"', {}))


# Null LHS with NOT MATCHES — still false (fail-closed)
func test_eval_not_matches_null_lhs_fail_closed() -> void:
	assert_false(_run_expr('state NOT MATCHES "idle"', {}))


# Non-string LHS — warning + false
func test_eval_matches_non_string_lhs() -> void:
	assert_false(_run_expr('level MATCHES "\\d+"', {"level": 42}))


# Non-string LHS with NOT MATCHES — still false (fail-closed)
func test_eval_not_matches_non_string_lhs_fail_closed() -> void:
	assert_false(_run_expr('level NOT MATCHES "\\d+"', {"level": 42}))


# Boolean LHS — false (not a string)
func test_eval_matches_bool_lhs() -> void:
	assert_false(_run_expr('flag MATCHES "true"', {"flag": true}))


# MATCHES combined with AND
func test_eval_matches_combined_and() -> void:
	assert_true(_run_expr('state MATCHES "idle|patrol" AND active', {"state": "idle", "active": true}))
	assert_false(_run_expr('state MATCHES "idle|patrol" AND active', {"state": "idle", "active": false}))


# MATCHES combined with OR
func test_eval_matches_combined_or() -> void:
	assert_true(_run_expr('state MATCHES "dead" OR health == 0', {"state": "alive", "health": 0}))
	assert_false(_run_expr('state MATCHES "dead" OR health == 0', {"state": "alive", "health": 50}))


# Case sensitivity — MATCHES is case-sensitive by default
func test_eval_matches_case_sensitive() -> void:
	assert_false(_run_expr('name MATCHES "hero"', {"name": "Hero"}))
	assert_true(_run_expr('name MATCHES "(?i)hero"', {"name": "Hero"}))


# MATCHES Operator — Key Extraction

# MATCHES extracts only LHS key
func test_keys_matches_lhs_only() -> void:
	var ast: Variant = _engine.parse('state MATCHES "idle"')
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 1, "one key")
	assert_eq(keys[0] as String, "state")


# NOT MATCHES extracts only LHS key
func test_keys_not_matches_lhs_only() -> void:
	var ast: Variant = _engine.parse('id NOT MATCHES "test_.*"')
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 1, "one key")
	assert_eq(keys[0] as String, "id")


# Compound expression with MATCHES — all keys extracted
func test_keys_matches_compound() -> void:
	var ast: Variant = _engine.parse('state MATCHES "idle" AND level > 5 OR name NOT MATCHES "test"')
	var keys := _engine.extract_keys(ast)
	assert_has(keys, "state", "state")
	assert_has(keys, "level", "level")
	assert_has(keys, "name", "name")
	assert_eq(keys.size(), 3, "three unique keys")
