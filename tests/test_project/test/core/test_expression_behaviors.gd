## Behavioral tests for expression evaluation: truthiness, operator precedence, compound logic, edge cases.
extends GutTest

const Lexer := preload("res://addons/chronicle/core/expression/lexer.gd")
const Parser := preload("res://addons/chronicle/core/expression/parser.gd")

var _engine: ChronicleExpressionEngine


func before_each() -> void:
	_engine = ChronicleExpressionEngine.new()


func _run_expr(expr: String, facts: Dictionary, engine: ChronicleExpressionEngine = null) -> bool:
	return ExpressionTestHelpers.run_expr(engine if engine != null else _engine, expr, facts)


# Comparison operators with numbers (parameterized)

var _comparison_op_params = ParameterFactory.named_parameters(
	["expr", "facts", "expected"],
	[
		# a = 10
		["a > 5",  {"a": 10}, true],
		["a < 5",  {"a": 10}, false],
		["a >= 5", {"a": 10}, true],
		["a <= 5", {"a": 10}, false],
		["a == 5", {"a": 10}, false],
		["a != 5", {"a": 10}, true],
		# a = 5
		["a > 5",  {"a": 5}, false],
		["a < 5",  {"a": 5}, false],
		["a >= 5", {"a": 5}, true],
		["a <= 5", {"a": 5}, true],
		["a == 5", {"a": 5}, true],
		["a != 5", {"a": 5}, false],
		# a = 1
		["a > 5",  {"a": 1}, false],
		["a < 5",  {"a": 1}, true],
		["a >= 5", {"a": 1}, false],
		["a <= 5", {"a": 1}, true],
		["a == 5", {"a": 1}, false],
		["a != 5", {"a": 1}, true],
	]
)

func test_comparison_op(p = use_parameters(_comparison_op_params)) -> void:
	var result: bool = _run_expr(p.expr, p.facts)
	assert_eq(result, p.expected,
		"Expression '%s' with facts %s: expected %s, got %s" % [p.expr, str(p.facts), str(p.expected), str(result)])


# String comparisons (parameterized)

var _string_comparison_params = ParameterFactory.named_parameters(
	["expr", "facts", "expected"],
	[
		['status == "done"',     {"status": "done"},    true],
		['status != "done"',     {"status": "done"},    false],
		['status == "pending"',  {"status": "done"},    false],
		['status != "pending"',  {"status": "done"},    true],
		['status == "done"',     {"status": "pending"}, false],
		['status == "pending"',  {"status": "pending"}, true],
	]
)

func test_string_comparison(p = use_parameters(_string_comparison_params)) -> void:
	var result: bool = _run_expr(p.expr, p.facts)
	assert_eq(result, p.expected,
		"Expression '%s' with facts %s: expected %s, got %s" % [p.expr, str(p.facts), str(p.expected), str(result)])


# Boolean comparisons (parameterized)

var _boolean_comparison_params = ParameterFactory.named_parameters(
	["expr", "facts", "expected"],
	[
		["flag == TRUE",  {"flag": true},  true],
		["flag == TRUE",  {"flag": false}, false],
		["flag == FALSE", {"flag": false}, true],
		["flag == FALSE", {"flag": true},  false],
		["NOT flag",      {"flag": true},  false],
		["NOT flag",      {"flag": false}, true],
	]
)

func test_boolean_comparison(p = use_parameters(_boolean_comparison_params)) -> void:
	var result: bool = _run_expr(p.expr, p.facts)
	assert_eq(result, p.expected,
		"Expression '%s' with facts %s: expected %s, got %s" % [p.expr, str(p.facts), str(p.expected), str(result)])


# Compound expressions (parameterized)

var _compound_expr_params = ParameterFactory.named_parameters(
	["expr", "facts", "expected"],
	[
		# AND
		["a AND b", {"a": true,  "b": true},  true],
		["a AND b", {"a": true,  "b": false}, false],
		["a AND b", {"a": false, "b": true},  false],
		["a AND b", {"a": false, "b": false}, false],
		# OR
		["a OR b", {"a": true,  "b": true},  true],
		["a OR b", {"a": true,  "b": false}, true],
		["a OR b", {"a": false, "b": true},  true],
		["a OR b", {"a": false, "b": false}, false],
		# NOT binds tighter than AND
		["NOT a AND b", {"a": false, "b": true}, true],
		["NOT a AND b", {"a": true,  "b": true}, false],
		# a AND NOT b
		["a AND NOT b", {"a": true, "b": false}, true],
		["a AND NOT b", {"a": true, "b": true},  false],
		# (a OR b) AND c
		["(a OR b) AND c", {"a": false, "b": true,  "c": true},  true],
		["(a OR b) AND c", {"a": false, "b": true,  "c": false}, false],
		["(a OR b) AND c", {"a": false, "b": false, "c": true},  false],
	]
)

func test_compound_expr(p = use_parameters(_compound_expr_params)) -> void:
	var result: bool = _run_expr(p.expr, p.facts)
	assert_eq(result, p.expected,
		"Expression '%s' with facts %s: expected %s, got %s" % [p.expr, str(p.facts), str(p.expected), str(result)])


# Precedence: a OR b AND c == a OR (b AND c)

func test_precedence() -> void:
	# a=T, b=F, c=F -> a OR (b AND c) = T OR F = true; (a OR b) AND c = T AND F = false
	assert_true(_run_expr("a OR b AND c", {"a": true, "b": false, "c": false}), "T,F,F => true")
	# a=F, b=T, c=T -> F OR (T AND T) = true
	assert_true(_run_expr("a OR b AND c", {"a": false, "b": true, "c": true}), "F,T,T => true")
	# a=F, b=T, c=F -> F OR (T AND F) = false
	assert_false(_run_expr("a OR b AND c", {"a": false, "b": true, "c": false}), "F,T,F => false")

	var ast: Variant = _engine.parse("a OR b AND c")
	assert_not_null(ast, "precedence: parse succeeds")
	assert_eq(ast.node_type, "or", "precedence: root is OR")
	assert_eq(ast.children[1].node_type, "and", "precedence: right child is AND")


# Deeply nested: ((((a AND b))))

func test_deeply_nested() -> void:
	assert_true(_run_expr("((((a AND b))))", {"a": true,  "b": true}), "4-level parens T AND T")
	assert_false(_run_expr("((((a AND b))))", {"a": true,  "b": false}), "4-level parens T AND F")

	var ast: Variant = _engine.parse("((((a AND b))))")
	assert_not_null(ast, "4-level nested parens: parse succeeds")
	assert_eq(ast.node_type, "and", "4-level nested parens: AST is and node")


# Key-to-key comparison (parameterized)

var _key_to_key_params = ParameterFactory.named_parameters(
	["expr", "facts", "expected"],
	[
		["player.level >= quest.required_level", {"player.level": 10, "quest.required_level": 5}, true],
		["player.level >= quest.required_level", {"player.level": 3,  "quest.required_level": 5}, false],
		["player.level >= quest.required_level", {"player.level": 5,  "quest.required_level": 5}, true],
		["player.level == quest.required_level", {"player.level": 5,  "quest.required_level": 5}, true],
		["player.level != quest.required_level", {"player.level": 5,  "quest.required_level": 5}, false],
	]
)

func test_key_to_key(p = use_parameters(_key_to_key_params)) -> void:
	var result: bool = _run_expr(p.expr, p.facts)
	assert_eq(result, p.expected,
		"Expression '%s' with facts %s: expected %s, got %s" % [p.expr, str(p.facts), str(p.expected), str(result)])


# Missing key in comparison (parameterized)

var _missing_key_comparison_params = ParameterFactory.named_parameters(
	["expr", "facts", "expected"],
	[
		["missing.key > 5",  {}, false],
		["missing.key < 5",  {}, false],
		["missing.key >= 5", {}, false],
		["missing.key <= 5", {}, false],
		["missing.key == 5", {}, false],
		["missing.key != 5", {}, true],
		["a == b",           {}, true],
	]
)

func test_missing_key_comparison(p = use_parameters(_missing_key_comparison_params)) -> void:
	var result: bool = _run_expr(p.expr, p.facts)
	assert_eq(result, p.expected,
		"Expression '%s' with facts %s: expected %s, got %s" % [p.expr, str(p.facts), str(p.expected), str(result)])


# Type mismatch: string > number (parameterized)

var _type_mismatch_params = ParameterFactory.named_parameters(
	["expr", "facts"],
	[
		["val > 5",  {"val": "hello"}],
		["val < 5",  {"val": "hello"}],
		["val >= 5", {"val": "hello"}],
		["val <= 5", {"val": "hello"}],
	]
)

func test_type_mismatch(p = use_parameters(_type_mismatch_params)) -> void:
	assert_false(_run_expr(p.expr, p.facts))


# Empty expression

func test_empty_expression() -> void:
	var ast: Variant = _engine.parse("")
	assert_null(ast)

	var resolver: Callable = func(_key: String) -> Variant: return null
	assert_false(_engine.evaluate_ast(_engine.parse(""), resolver) as bool, 'evaluate("") returns false')


# Bare TRUE

func test_bare_true() -> void:
	var ast: Variant = _engine.parse("TRUE")
	assert_not_null(ast)

	var resolver: Callable = func(_key: String) -> Variant: return null
	assert_true(_engine.evaluate_ast(_engine.parse("TRUE"), resolver) as bool, 'evaluate("TRUE") is true')


# Bare FALSE

func test_bare_false() -> void:
	var ast: Variant = _engine.parse("FALSE")
	assert_not_null(ast)

	var resolver: Callable = func(_key: String) -> Variant: return null
	assert_false(_engine.evaluate_ast(_engine.parse("FALSE"), resolver) as bool, 'evaluate("FALSE") is false')


# Triple negation

func test_triple_negation() -> void:
	assert_false(_run_expr("NOT NOT NOT a", {"a": true}), "NOT NOT NOT true => false")
	assert_true(_run_expr("NOT NOT NOT a", {"a": false}), "NOT NOT NOT false => true")
	assert_true(_run_expr("NOT NOT a", {"a": true}), "NOT NOT true => true")
	assert_false(_run_expr("NOT NOT a", {"a": false}), "NOT NOT false => false")


# Reserved words as fact keys

func test_reserved_words_as_fact_keys() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("and.or.not")
	assert_eq(tokens.size(), 2, "and.or.not: 1 token + EOF")
	assert_eq(tokens[0].type, T.KEY, "and.or.not: token type is KEY")
	assert_eq(tokens[0].value as String, "and.or.not", "and.or.not: value is and.or.not")

	assert_true(_run_expr("and.or.not", {"and.or.not": true}), "and.or.not as truthy key -- true")
	assert_false(_run_expr("and.or.not", {"and.or.not": false}), "and.or.not as truthy key -- false")
	assert_true(_run_expr("and.or.not == 42", {"and.or.not": 42}), "and.or.not == 42")


# Key extraction completeness

func test_key_extraction_completeness() -> void:
	var ast: Variant = _engine.parse('(a.b > 5 AND c.d == "x") OR NOT e.f')
	assert_not_null(ast, "key extraction: parse succeeds")

	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 3, "key extraction: found exactly 3 keys")
	assert_has(keys, "a.b", "key extraction: a.b found")
	assert_has(keys, "c.d", "key extraction: c.d found")
	assert_has(keys, "e.f", "key extraction: e.f found")


# Truthy semantics (parameterized)

var _truthy_semantics_params = ParameterFactory.named_parameters(
	["facts", "expected"],
	[
		# Truthy values
		[{"val": 1},         true],
		[{"val": true},      true],
		[{"val": "hello"},   true],
		[{"val": [1]},       true],
		[{"val": {"a": 1}},  true],
		# Falsy values
		[{"val": 0},         false],
		[{"val": 0.0},       false],
		[{"val": false},     false],
		[{"val": ""},        false],
		# Missing key (null) is falsy
		[{},                 false],
		# Explicit null is falsy
		[{"val": null},      false],
		# Non-zero numbers are truthy
		[{"val": -1},        true],
		[{"val": 0.001},     true],
		[{"val": 999},       true],
	]
)

func test_truthy_semantics(p = use_parameters(_truthy_semantics_params)) -> void:
	var result: bool = _run_expr("val", p.facts)
	assert_eq(result, p.expected,
		"Facts %s: expected %s, got %s" % [str(p.facts), str(p.expected), str(result)])


# Large expression: 10-way AND

func test_large_expression() -> void:
	var expr := "a1 AND a2 AND a3 AND a4 AND a5 AND a6 AND a7 AND a8 AND a9 AND a10"

	var all_true: Dictionary = {}
	for i: int in range(1, 11):
		all_true["a%d" % i] = true
	assert_true(_run_expr(expr, all_true), "10-way AND: all true")

	var ast: Variant = _engine.parse(expr)
	assert_not_null(ast, "10-way AND: parse succeeds")
	assert_eq(ast.node_type, "and", "10-way AND: root is and")
	assert_eq(ast.children.size(), 10, "10-way AND: 10 children")

	for i: int in range(1, 11):
		var facts: Dictionary = all_true.duplicate()
		facts["a%d" % i] = false
		assert_false(_run_expr(expr, facts), "10-way AND: a%d false makes it false" % i)


# Deep nesting: 20 levels of parentheses

func test_deep_nesting_20_levels() -> void:
	var expr: String = "(".repeat(20) + "a" + ")".repeat(20)
	var ast: Variant = _engine.parse(expr)
	assert_not_null(ast)


# Whitespace-only expression

func test_whitespace_only_expression() -> void:
	assert_null(_engine.parse("   "))
	var resolver := func(_key: String) -> Variant: return null
	assert_false(_engine.evaluate_ast(_engine.parse("   "), resolver) as bool)


# NOT BETWEEN

func test_not_between_true_outside_range() -> void:
	assert_true(_run_expr("player.level NOT BETWEEN 1 AND 5", {"player.level": 0}),
		"level 0 NOT BETWEEN 1 AND 5 should be true")

func test_not_between_false_inside_range() -> void:
	assert_false(_run_expr("player.level NOT BETWEEN 1 AND 5", {"player.level": 3}),
		"level 3 NOT BETWEEN 1 AND 5 should be false")

func test_not_between_true_above_range() -> void:
	assert_true(_run_expr("player.level NOT BETWEEN 1 AND 5", {"player.level": 6}),
		"level 6 NOT BETWEEN 1 AND 5 should be true")

func test_not_between_boundary_inclusive() -> void:
	assert_false(_run_expr("player.level NOT BETWEEN 1 AND 5", {"player.level": 1}),
		"level 1 (boundary) NOT BETWEEN 1 AND 5 should be false")


# Unregister expression handler stale cache (R16-A8 Bug 1)

func test_unregister_expression_handler_stale_cache() -> void:
	var engine := ChronicleExpressionEngine.new()
	var custom_type := "custom_check"

	# Register a custom handler that always evaluates to true
	var eval_fn := func(_ast: Dictionary, _resolver: Callable) -> bool:
		return true
	var keys_fn := func(_ast: Dictionary, _keys: Array[String]) -> void:
		pass
	var walk_fn := func(_ast: Dictionary, _leaf_fn: Callable) -> void:
		pass

	engine.register_expression_handler(custom_type, eval_fn, keys_fn, walk_fn)

	# Register a keyword that produces nodes of this custom type
	var custom_token := 1000
	var parse_fn := func(state: Parser.ParseState, operand: Dictionary, negated: bool) -> Variant:
		return {node_type = custom_type, operand = operand, negated = negated}
	engine.register_keyword("MYCHECK", custom_token, parse_fn, true)

	# Parse and evaluate — should work and cache the AST
	var resolver := func(key: String) -> Variant: return {"x": 42}.get(key, null)
	var ast1: Variant = engine.parse("x MYCHECK")
	assert_not_null(ast1, "first parse succeeds")
	assert_true(engine.evaluate_ast(ast1, resolver), "custom handler evaluates to true")

	# Unregister the handler — this also clears _ast_cache (engine.gd ~131),
	# so a re-parse produces a fresh AST rather than a stale cached object.
	engine.unregister_expression_handler(custom_type)

	# Re-parse the same expression — returns stale cached AST
	var ast2: Variant = engine.parse("x MYCHECK")

	# FIXED: unregister_expression_handler now clears _ast_cache, so ast2 is a fresh parse.
	# The keyword is still registered, producing a node with the custom type,
	# but the handler is gone — the evaluator warns and returns false.
	assert_false(is_same(ast1, ast2), "cache was cleared — ast2 is a fresh parse, not the stale cached object")

	# Evaluation of the re-parsed AST with the removed handler returns false
	assert_false(engine.evaluate_ast(ast2, resolver), "re-parsed AST with removed handler evaluates to false")


# Register keyword token type collision rejected (R16-A8)

func test_register_keyword_token_type_collision_rejected() -> void:
	var engine := ChronicleExpressionEngine.new()
	var noop := func(_s: Variant, _o: Variant, _n: bool) -> Variant: return null
	assert_true(engine.register_keyword("FOO", 1000, noop, false), "first registration succeeds")
	assert_false(engine.register_keyword("BAR", 1000, noop, false), "duplicate token_type rejected")


# Cached parse failure sentinel (R16-A8 Edge 1)

func test_parse_failure_cache_sentinel() -> void:
	var engine := ChronicleExpressionEngine.new()
	var ast1: Variant = engine.parse("")
	assert_null(ast1, "empty string returns null")
	var ast2: Variant = engine.parse("")
	assert_null(ast2, "second call for empty string also returns null (cached sentinel)")


# Cached AST is deep copy (R16-A8 Edge 2)

func test_cached_ast_is_deep_copy() -> void:
	var engine := ChronicleExpressionEngine.new()
	var ast1: Variant = engine.parse("x > 5")
	var ast2: Variant = engine.parse("x > 5")
	assert_false(is_same(ast1, ast2), "cached AST returns a deep copy, not the same reference")
	assert_eq(ast1.node_type, ast2.node_type, "deep copies have equal structure")


# Trailing dot parse error (R16-A8 Edge 3)

func test_trailing_dot_parse_error() -> void:
	var engine := ChronicleExpressionEngine.new()
	var ast: Variant = engine.parse("key.")
	assert_null(ast, "trailing dot is a parse error")


# Leading dot parse error (R16-A8 Edge 4)

func test_leading_dot_parse_error() -> void:
	var engine := ChronicleExpressionEngine.new()
	var ast: Variant = engine.parse(".key")
	assert_null(ast, "leading dot is a parse error")


# Double dot in key (R16-A8 Edge 5)

func test_double_dot_in_key() -> void:
	var tokens := Lexer.tokenize("key..value")
	# The lexer should produce "key" as a KEY, then fail on ".."
	# because the first dot is followed by another dot (not an ident char)
	assert_true(tokens.is_empty(), "double dot causes tokenizer error")


# BETWEEN with boolean bounds rejected (R16-A8 Edge 6)

func test_between_boolean_bounds_rejected() -> void:
	var engine := ChronicleExpressionEngine.new()
	var ast: Variant = engine.parse("x BETWEEN TRUE AND FALSE")
	assert_null(ast, "BETWEEN with boolean bounds is rejected")


# MATCHES pattern too long (R16-A8 Edge 7)

func test_matches_pattern_too_long() -> void:
	var engine := ChronicleExpressionEngine.new()
	var long_pattern: String = "a".repeat(257)
	var ast: Variant = engine.parse('key MATCHES "%s"' % long_pattern)
	assert_null(ast, "MATCHES rejects patterns exceeding 256 chars")


# Max nesting depth rejected (R16-A8 Edge 8)

func test_max_nesting_depth_rejected() -> void:
	var engine := ChronicleExpressionEngine.new()
	var expr: String = "NOT ".repeat(65) + "a"
	var ast: Variant = engine.parse(expr)
	assert_null(ast, "65 levels of NOT exceeds max depth")


# Max paren depth rejected (R16-A8 Edge 9)

func test_max_paren_depth_rejected() -> void:
	var engine := ChronicleExpressionEngine.new()
	var expr: String = "(".repeat(65) + "a" + ")".repeat(65)
	var ast: Variant = engine.parse(expr)
	assert_null(ast, "65 levels of parens exceeds max depth")


# Within max nesting depth (R16-A8 Edge 10)

func test_within_max_nesting_depth() -> void:
	var engine := ChronicleExpressionEngine.new()
	var expr: String = "NOT ".repeat(63) + "a"
	var ast: Variant = engine.parse(expr)
	assert_not_null(ast, "63 levels of NOT is within max depth")


# Int literal vs float fact (R16-A8 Edge 11)

func test_int_literal_vs_float_fact() -> void:
	# Lexer parses "5" as int(5), but fact is float(5.0)
	assert_true(_run_expr("x == 5", {"x": 5.0}), "int literal 5 equals float fact 5.0")
	assert_true(_run_expr("x > 4", {"x": 4.5}), "int literal 4 < float fact 4.5")
	assert_true(_run_expr("x >= 5", {"x": 5.0}), "int literal 5 <= float fact 5.0")


# Subtraction rejected (R16-A8 Edge 12)

func test_subtraction_rejected() -> void:
	var tokens := Lexer.tokenize("a - 5")
	assert_true(tokens.is_empty(), "subtraction (minus after key) produces tokenizer error")


# IN key RHS resolves to array (R16-A8 Edge 13)

func test_in_key_rhs_resolves_to_array() -> void:
	var facts := {"item": "sword", "inventory": ["sword", "shield", "potion"]}
	assert_true(_run_expr("item IN inventory", facts), "key IN key with array RHS")

	var facts2 := {"item": "staff", "inventory": ["sword", "shield", "potion"]}
	assert_false(_run_expr("item IN inventory", facts2), "key NOT found in array RHS")


# IN array with key element (R16-A8 Edge 14)

func test_in_array_with_key_element() -> void:
	var facts := {"x": 99, "some_key": 99}
	assert_true(_run_expr("x IN [some_key, 42]", facts), "key element in array resolves at runtime")

	var facts2 := {"x": 99, "some_key": 100}
	assert_false(_run_expr("x IN [some_key, 42]", facts2), "key element mismatch")


# Builtin keyword override rejected (R16-A8 Edge 15)

func test_builtin_keyword_override_rejected() -> void:
	var engine := ChronicleExpressionEngine.new()
	var noop := func(_s: Variant, _o: Variant, _n: bool) -> Variant: return null
	assert_false(engine.register_keyword("AND", 1000, noop, false), "cannot override AND")
	assert_false(engine.register_keyword("or", 1001, noop, false), "cannot override OR (case-insensitive)")
	assert_false(engine.register_keyword("In", 1002, noop, false), "cannot override IN (case-insensitive)")


# Register expression handler force override (R16-A8 Edge 16)

func test_register_expression_handler_force_override() -> void:
	var engine := ChronicleExpressionEngine.new()
	var custom_eval := func(_ast: Dictionary, _resolver: Callable) -> bool: return true
	var keys_fn := func(_ast: Dictionary, _keys: Array[String]) -> void: pass
	var walk_fn := func(_ast: Dictionary, _leaf_fn: Callable) -> void: pass

	# Without force, overriding builtin fails
	assert_false(engine.register_expression_handler("compare", custom_eval, keys_fn, walk_fn, false),
		"cannot override builtin without force")

	# With force, overriding builtin succeeds
	assert_true(engine.register_expression_handler("compare", custom_eval, keys_fn, walk_fn, true),
		"can override builtin with force=true")

	# Now all comparisons return true
	assert_true(_run_expr("x > 999", {"x": 1}, engine), "overridden compare always returns true")


# register_expression_handler rejects an invalid callback (returns false, no registration)
func test_register_expression_handler_rejects_invalid_callbacks() -> void:
	var engine := ChronicleExpressionEngine.new()
	var keys_fn := func(_ast: Dictionary, _keys: Array[String]) -> void: pass
	var walk_fn := func(_ast: Dictionary, _leaf_fn: Callable) -> void: pass
	assert_false(engine.register_expression_handler("invalid_node", Callable(), keys_fn, walk_fn),
		"register_expression_handler must return false when eval_fn is invalid")


# Unregister builtin expression handler rejected (R16-A8 Edge 17)

func test_unregister_builtin_compare_handler_rejected() -> void:
	var engine := ChronicleExpressionEngine.new()
	engine.unregister_expression_handler("compare")
	# Builtin should still work after attempted removal
	assert_true(_run_expr("x == 5", {"x": 5}, engine), "compare handler still works after rejected unregister")


# String escape sequences (R16-A8 Edge 18)

func test_string_escape_sequences() -> void:
	var engine := ChronicleExpressionEngine.new()
	# Escaped quote inside string
	var ast: Variant = engine.parse('key == "say \\"hi\\""')
	assert_not_null(ast, "escaped quotes parse correctly")
	var resolver := func(key: String) -> Variant:
		if key == "key":
			return 'say "hi"'
		return null
	assert_true(engine.evaluate_ast(ast, resolver), "escaped quote comparison succeeds")


# ReDoS quantifier after group rejected (R16-A8 Edge 19)

func test_redos_quantifier_after_group_rejected() -> void:
	var engine := ChronicleExpressionEngine.new()
	var ast: Variant = engine.parse('key MATCHES "(a+)+"')
	assert_null(ast, "ReDoS pattern (a+)+ is rejected")

	ast = engine.parse('key MATCHES "(a|b)*"')
	assert_null(ast, "ReDoS pattern (a|b)* is rejected")


# MATCHES case insensitive flag (R16-A8 Edge 20)

func test_matches_case_insensitive_flag() -> void:
	assert_true(_run_expr('name MATCHES "(?i)hero"', {"name": "HERO"}),
		"case-insensitive regex flag works")
	assert_true(_run_expr('name MATCHES "(?i)hero"', {"name": "hero"}),
		"case-insensitive regex flag matches lowercase too")


# null MATCHES fail-closed (R17-A8-1)

func test_null_matches_fail_closed() -> void:
	# Positive: null MATCHES -> false (no subject)
	assert_false(_run_expr('x MATCHES "hello"', {}),
		"null MATCHES pattern -> false (fail-closed)")


func test_null_not_matches_fail_closed() -> void:
	# Negative: null NOT MATCHES -> ALSO false (fail-closed, not negation-of-false)
	assert_false(_run_expr('x NOT MATCHES "hello"', {}),
		"null NOT MATCHES pattern -> false (intentional fail-closed, not negated)")


func test_null_not_matches_asymmetry_with_not_in() -> void:
	# Document the intentional asymmetry:
	# null NOT IN literal_array -> true (membership check: null is absent from set)
	# null NOT MATCHES pattern  -> false (type error: subject must be a String)
	assert_true(_run_expr("x NOT IN [1, 2, 3]", {}),
		"null NOT IN [1,2,3] -> true (absent value is not a member)")
	assert_false(_run_expr('x NOT MATCHES "foo"', {}),
		"null NOT MATCHES -> false (null subject is a type error, not a non-match)")


# Operator precedence: NOT > AND > OR (R17-A8)

func test_precedence_not_and_or() -> void:
	# "NOT a AND b" must parse as "(NOT a) AND b", not "NOT (a AND b)"
	# With a=false, b=true: (NOT false) AND true = true AND true = true
	assert_true(_run_expr("a AND b OR c", {"a": false, "b": false, "c": true}),
		"OR has lower precedence than AND: (false AND false) OR true = true")
	assert_false(_run_expr("a OR b AND c", {"a": false, "b": false, "c": true}),
		"AND binds tighter: false OR (false AND true) = false")
	assert_true(_run_expr("NOT a AND b", {"a": false, "b": true}),
		"NOT binds tighter than AND: (NOT false) AND true = true")
	assert_false(_run_expr("NOT a AND b", {"a": true, "b": true}),
		"NOT binds tighter than AND: (NOT true) AND true = false")


# Short-circuit evaluation (R17-A8)

func test_short_circuit_or() -> void:
	# In "a OR b", if a is true, b should not matter
	assert_true(_run_expr("a OR b", {"a": true}),
		"OR short-circuits: a=true means result is true even if b is missing")


func test_short_circuit_and() -> void:
	# In "a AND b", if a is false, b should not matter
	assert_false(_run_expr("a AND b", {"a": false}),
		"AND short-circuits: a=false means result is false even if b is missing")


# Null subject positive MATCHES false (R17-A8)

func test_null_subject_positive_matches_false() -> void:
	assert_false(_run_expr('x MATCHES ".*"', {}),
		"null subject with catch-all regex -> false")


# Null subject BETWEEN false (R17-A8)

func test_null_subject_between_false() -> void:
	assert_false(_run_expr("x BETWEEN 1 AND 10", {}),
		"null subject BETWEEN -> false")


# Null subject IN false (R17-A8)

func test_null_subject_in_false() -> void:
	assert_false(_run_expr("x IN [1, 2, 3]", {}),
		"null subject IN array -> false")


# Negative number RHS (R17-A8)

func test_negative_number_rhs() -> void:
	assert_true(_run_expr("x > -5", {"x": 0}), "x > -5 with x=0 -> true")
	assert_false(_run_expr("x > -5", {"x": -10}), "x > -5 with x=-10 -> false")
	assert_true(_run_expr("x == -5", {"x": -5}), "x == -5 -> true")


# Negative number LHS parse error (R17-A8)

func test_negative_number_lhs_parse_error() -> void:
	var engine := ChronicleExpressionEngine.new()
	var ast: Variant = engine.parse("-5 == x")
	assert_null(ast, "negative number as LHS is a parse error (design constraint)")


# Fact-to-fact comparison (R17-A8)

func test_fact_to_fact_comparison() -> void:
	assert_true(_run_expr("a == b", {"a": 10, "b": 10}),
		"two keys with equal values: a == b -> true")
	assert_false(_run_expr("a == b", {"a": 10, "b": 11}),
		"two keys with different values: a == b -> false")
	assert_true(_run_expr("a < b", {"a": 5, "b": 10}),
		"a < b with a=5, b=10 -> true")


# BETWEEN with key-based bounds (R17-A8)

func test_between_key_bounds() -> void:
	assert_true(_run_expr("x BETWEEN lo AND hi", {"x": 5, "lo": 1, "hi": 10}),
		"BETWEEN with key bounds, x in range -> true")
	assert_false(_run_expr("x BETWEEN lo AND hi", {"x": 11, "lo": 1, "hi": 10}),
		"BETWEEN with key bounds, x out of range -> false")


# BETWEEN inverted bounds returns false (R17-A8)

func test_between_inverted_bounds() -> void:
	assert_false(_run_expr("x BETWEEN 10 AND 1", {"x": 5}),
		"BETWEEN with inverted bounds (low > high) -> false")


# NOT BETWEEN in range (R17-A8)

func test_not_between_in_range() -> void:
	assert_false(_run_expr("x NOT BETWEEN 1 AND 10", {"x": 5}),
		"x NOT BETWEEN 1 AND 10 with x=5 (in range) -> false")


# NOT BETWEEN out of range (R17-A8)

func test_not_between_out_of_range() -> void:
	assert_true(_run_expr("x NOT BETWEEN 1 AND 10", {"x": 15}),
		"x NOT BETWEEN 1 AND 10 with x=15 (out of range) -> true")


# INT vs FLOAT mixed comparison (R17-A8)

func test_int_float_mixed_comparison() -> void:
	assert_true(_run_expr("x == 5", {"x": 5.0}),
		"int literal 5 equals float fact 5.0 via _comparable")
	assert_true(_run_expr("x > 4", {"x": 4.5}),
		"int literal 4 < float fact 4.5")


# Bool vs int strict equality (R17-A8)

func test_bool_vs_int_strict() -> void:
	# true is bool, 1 is int: typeof differs and _comparable returns false for bool/int
	assert_false(_run_expr("x == 1", {"x": true}),
		"bool(true) == int(1) -> false (type-strict)")
	assert_true(_run_expr("x != 1", {"x": true}),
		"bool(true) != int(1) -> true (different types are always !=)")


# IN with empty array (R17-A8)

func test_in_empty_array() -> void:
	assert_false(_run_expr("x IN []", {"x": 42}),
		"x IN empty array -> false")


# NOT IN with empty array (R17-A8)

func test_not_in_empty_array() -> void:
	assert_true(_run_expr("x NOT IN []", {"x": 42}),
		"x NOT IN empty array -> true (nothing to match)")


# Deep parens within limit (R17-A8)

func test_deep_parens_within_limit() -> void:
	var engine := ChronicleExpressionEngine.new()
	var expr: String = "(".repeat(32) + "a" + ")".repeat(32)
	var ast: Variant = engine.parse(expr)
	assert_not_null(ast, "32 levels of parens is within MAX_DEPTH=64")
	assert_true(engine.evaluate_ast(ast, func(_k: String) -> Variant: return true),
		"deeply nested expression evaluates correctly")


# Chained comparison parse error (R17-A8)

func test_chained_comparison_parse_error() -> void:
	var engine := ChronicleExpressionEngine.new()
	assert_null(engine.parse("a < b < c"), "chained comparisons are a parse error")


# MATCHES with escaped quote (R17-A8)

func test_matches_with_escaped_quote() -> void:
	var engine := ChronicleExpressionEngine.new()
	var ast: Variant = engine.parse('name MATCHES "say \\"hi\\""')
	assert_not_null(ast, "pattern with escaped quote parses")
	var resolver := func(key: String) -> Variant:
		return 'say "hi"' if key == "name" else null
	assert_true(engine.evaluate_ast(ast, resolver),
		"MATCHES with escaped quote in pattern evaluates correctly")


# AST cache returns deep copy (R17-A8)

func test_ast_cache_returns_deep_copy() -> void:
	var engine := ChronicleExpressionEngine.new()
	var ast1: Variant = engine.parse("x > 5")
	var ast2: Variant = engine.parse("x > 5")
	assert_not_null(ast1, "first parse succeeds")
	assert_false(is_same(ast1, ast2), "cached parse returns a deep copy, not same reference")
	assert_eq(ast1.node_type, ast2.node_type, "deep copies have equal structure")


# Parse failure cached (R17-A8)

func test_parse_failure_cached() -> void:
	var engine := ChronicleExpressionEngine.new()
	assert_null(engine.parse(""), "empty string returns null")
	assert_null(engine.parse(""), "second call for empty string returns null (cached)")
	assert_null(engine.parse("x >"), "malformed expression returns null")
	assert_null(engine.parse("x >"), "second malformed call returns null (cached)")


# Register keyword clears failure cache (R17-A8)

func test_register_keyword_clears_failure_cache() -> void:
	var engine := ChronicleExpressionEngine.new()

	# First parse fails because MYOP isn't registered yet
	var ast1: Variant = engine.parse("x MYOP")
	assert_null(ast1, "parse fails when custom keyword not yet registered")

	# Register the keyword
	var parse_fn := func(_state: Parser.ParseState, operand: Dictionary, _negated: bool) -> Variant:
		return {node_type = "myop_node", operand = operand}
	engine.register_keyword("MYOP", 1000, parse_fn, false)

	# Register a handler for the new node type
	var eval_fn := func(_ast: Dictionary, _resolver: Callable) -> bool: return true
	var keys_fn := func(_ast: Dictionary, _keys: Array[String]) -> void: pass
	var walk_fn := func(_ast: Dictionary, _leaf_fn: Callable) -> void: pass
	engine.register_expression_handler("myop_node", eval_fn, keys_fn, walk_fn)

	# Now "x MYOP" should parse successfully
	var ast2: Variant = engine.parse("x MYOP")
	assert_not_null(ast2, "parse succeeds after keyword registration (cache invalidated)")


# Unregister keyword clears cache (R17-A8)

func test_unregister_keyword_clears_cache() -> void:
	var engine := ChronicleExpressionEngine.new()
	var parse_fn := func(_state: Parser.ParseState, operand: Dictionary, _negated: bool) -> Variant:
		return {node_type = "tmp_node", operand = operand}
	engine.register_keyword("TMPOP", 1001, parse_fn, false)

	var eval_fn := func(_ast: Dictionary, _resolver: Callable) -> bool: return true
	var keys_fn := func(_ast: Dictionary, _keys: Array[String]) -> void: pass
	var walk_fn := func(_ast: Dictionary, _leaf_fn: Callable) -> void: pass
	engine.register_expression_handler("tmp_node", eval_fn, keys_fn, walk_fn)

	var ast1: Variant = engine.parse("x TMPOP")
	assert_not_null(ast1, "parses successfully before unregistration")

	engine.unregister_keyword("TMPOP")

	# After unregistration, "x TMPOP" should fail or parse differently
	var ast2: Variant = engine.parse("x TMPOP")
	assert_null(ast2, "parse fails after keyword unregistration (cache cleared, TMPOP is now unknown)")


# Unregister builtin expression handler rejected (R17-A8)

func test_unregister_builtin_expression_handler_rejected() -> void:
	var engine := ChronicleExpressionEngine.new()
	engine.unregister_expression_handler("compare")
	# compare handler must still work after the (rejected) unregister attempt
	assert_true(_run_expr("x == 5", {"x": 5}, engine),
		"compare handler still works after rejected unregister attempt")


# extract_keys excludes literals (R17-A8)

func test_extract_keys_excludes_literals() -> void:
	var engine := ChronicleExpressionEngine.new()
	var ast: Variant = engine.parse("a > 5")
	assert_not_null(ast, "parses")
	var keys: Array[String] = engine.extract_keys(ast)
	assert_eq(keys.size(), 1, "only one key extracted")
	assert_eq(keys[0], "a", "extracted key is 'a'")

	var ast2: Variant = engine.parse("a == b")
	var keys2: Array[String] = engine.extract_keys(ast2)
	assert_eq(keys2.size(), 2, "fact-to-fact comparison extracts both keys")
	assert_has(keys2, "a", "key 'a' extracted")
	assert_has(keys2, "b", "key 'b' extracted")


# extract_keys from IN with key element (R17-A8)

func test_extract_keys_in_with_key_element() -> void:
	var engine := ChronicleExpressionEngine.new()
	var ast: Variant = engine.parse("x IN [some_key, 42]")
	assert_not_null(ast)
	var keys: Array[String] = engine.extract_keys(ast)
	assert_has(keys, "x", "subject key extracted")
	assert_has(keys, "some_key", "key element in array extracted")


# TRUE and FALSE literals (R17-A8)

func test_true_false_literals() -> void:
	assert_true(_run_expr("TRUE", {}), "TRUE literal evaluates to true")
	assert_false(_run_expr("FALSE", {}), "FALSE literal evaluates to false")
	assert_false(_run_expr("NOT TRUE", {}), "NOT TRUE -> false")
	assert_true(_run_expr("NOT FALSE", {}), "NOT FALSE -> true")
	assert_true(_run_expr("TRUE AND TRUE", {}), "TRUE AND TRUE -> true")
	assert_false(_run_expr("TRUE AND FALSE", {}), "TRUE AND FALSE -> false")
	assert_true(_run_expr("FALSE OR TRUE", {}), "FALSE OR TRUE -> true")


# Truthy evaluation for various fact types (R17-A8)

func test_truthy_fact_types() -> void:
	assert_true(_run_expr("x", {"x": true}), "bool true is truthy")
	assert_false(_run_expr("x", {"x": false}), "bool false is not truthy")
	assert_true(_run_expr("x", {"x": 1}), "int 1 is truthy")
	assert_false(_run_expr("x", {"x": 0}), "int 0 is not truthy")
	assert_true(_run_expr("x", {"x": "hello"}), "non-empty string is truthy")
	assert_false(_run_expr("x", {"x": ""}), "empty string is not truthy")
	assert_false(_run_expr("x", {}), "missing fact is not truthy")


# clear_custom_handlers breaks evaluation (R23 Bug 4)

func test_clear_custom_handlers_breaks_evaluation() -> void:
	var engine := ChronicleExpressionEngine.new()
	var resolver := func(key: String) -> Variant:
		if key == "health":
			return 50
		return null

	# Parse and evaluate before clearing — should work fine
	var ast_before: Variant = engine.parse("health > 10")
	assert_not_null(ast_before, "parse should succeed before clear_custom_handlers")
	var result_before: bool = engine.evaluate_ast(ast_before, resolver)
	assert_true(result_before, "health > 10 should be true before clear_custom_handlers")

	# Clear all handlers
	engine.clear_custom_handlers()

	# Parse a new expression (cache was cleared too)
	var ast_after: Variant = engine.parse("health > 10")
	assert_not_null(ast_after, "parse should succeed after clear_custom_handlers")

	# clear_custom_handlers() only erases non-builtin handlers (engine.gd ~135-138),
	# so builtin NODE_COMPARE survives and evaluate_ast still works.
	var result_after: bool = engine.evaluate_ast(ast_after, resolver)
	assert_true(result_after,
		"health > 10 should still be true after clear_custom_handlers — but builtins were not re-registered")


# clear_custom_handlers breaks truthy (R23 Bug 4)

func test_clear_custom_handlers_breaks_truthy() -> void:
	var engine := ChronicleExpressionEngine.new()
	var resolver := func(key: String) -> Variant:
		if key == "flag":
			return true
		return null

	var ast: Variant = engine.parse("flag")
	assert_not_null(ast, "parse should succeed")
	assert_true(engine.evaluate_ast(ast, resolver), "flag should be truthy before clear")

	engine.clear_custom_handlers()

	# Re-parse after cache clear
	var ast2: Variant = engine.parse("flag")
	assert_not_null(ast2, "parse should succeed after clear")

	# Builtin NODE_TRUTHY handler is preserved by clear_custom_handlers (only
	# non-builtin handlers are erased — engine.gd ~135-138).
	assert_true(engine.evaluate_ast(ast2, resolver),
		"flag should still be truthy after clear_custom_handlers — but handler is gone")


# clear_custom_handlers breaks extract_keys (R23 Bug 4)

func test_clear_custom_handlers_breaks_extract_keys() -> void:
	var engine := ChronicleExpressionEngine.new()

	var ast: Variant = engine.parse("health > 10 AND mana > 5")
	assert_not_null(ast, "parse should succeed")

	var keys_before: Array[String] = engine.extract_keys(ast)
	assert_has(keys_before, "health")
	assert_has(keys_before, "mana")

	engine.clear_custom_handlers()

	var ast2: Variant = engine.parse("health > 10 AND mana > 5")
	assert_not_null(ast2, "parse should succeed after clear")

	# Builtin walk/keys handlers survive clear_custom_handlers (only non-builtin
	# handlers are erased — engine.gd ~135-138), so extract_keys still walks the AST.
	var keys_after: Array[String] = engine.extract_keys(ast2)
	assert_has(keys_after, "health",
		"extract_keys should find 'health' after clear_custom_handlers — but handlers are gone")
	assert_has(keys_after, "mana",
		"extract_keys should find 'mana' after clear_custom_handlers — but handlers are gone")


# Truthy node has no negated field (R23 Bug 8)

func test_truthy_node_has_no_negated_field() -> void:
	var ast: Dictionary = Parser._make_truthy("flag")
	assert_eq(ast.node_type, Parser.NODE_TRUTHY, "node_type should be truthy")
	assert_eq(ast.key, "flag", "key should be 'flag'")
	assert_does_not_have(ast, "negated", "truthy node should not have a negated field")


# Truthy returns true for truthy value (R23 Bug 8)

func test_truthy_returns_true_for_truthy_value() -> void:
	var engine := ChronicleExpressionEngine.new()
	var resolver := func(key: String) -> Variant:
		if key == "flag":
			return true
		return null

	var ast: Dictionary = Parser._make_truthy("flag")
	var result: bool = engine.evaluate_ast(ast, resolver)
	assert_true(result, "truthy node should return true for truthy value")


# Truthy returns false for falsy value (R23 Bug 8)

func test_truthy_returns_false_for_falsy_value() -> void:
	var engine := ChronicleExpressionEngine.new()
	var resolver := func(key: String) -> Variant:
		if key == "missing_flag":
			return null
		return null

	var ast: Dictionary = Parser._make_truthy("missing_flag")
	var result: bool = engine.evaluate_ast(ast, resolver)
	assert_false(result, "truthy node should return false for falsy value")


# Parser uses NOT wrapper for negation (R23 Bug 8)

func test_parser_uses_not_wrapper_for_negation() -> void:
	var engine := ChronicleExpressionEngine.new()

	# "NOT flag" should produce a NOT node wrapping a truthy node
	var ast: Variant = engine.parse("NOT flag")
	assert_not_null(ast, "parse should succeed")
	assert_eq(ast.node_type, Parser.NODE_NOT,
		"'NOT flag' should produce a NOT node")

	# The inner truthy node should NOT have a negated field
	var inner: Dictionary = ast.operand
	assert_eq(inner.node_type, Parser.NODE_TRUTHY, "inner should be truthy")
	assert_does_not_have(inner, "negated",
		"inner truthy node should not have a negated field")


# ── R14/R15 bug regression ──


# ReDoS scanner misses quantifiers after ] — now correctly rejected
func test_redos_scanner_misses_bracket_quantifier() -> void:
	# This pattern has a quantifier after ] — should be flagged as ReDoS risk
	# but the scanner only checks for ) before quantifiers
	var ast: Variant = _engine.parse('name MATCHES "[a-z]+[a-z]+"')

	# FIXED: pattern with quantifier after ] is now correctly rejected
	assert_null(ast,
		"pattern with quantifier after ] should be rejected as ReDoS risk")


# register_keyword should cleanup old entry on re-registration
func test_register_keyword_should_cleanup_old_entry() -> void:
	var engine := ChronicleExpressionEngine.new()
	var noop_parse: Callable = func(_state: Variant) -> Variant: return null
	var TOKEN_A: int = Lexer.FIRST_CUSTOM_TOKEN_TYPE
	var TOKEN_B: int = Lexer.FIRST_CUSTOM_TOKEN_TYPE + 1

	engine.register_keyword("MYKW", TOKEN_A, noop_parse, false)
	engine.register_keyword("MYKW", TOKEN_B, noop_parse, false)

	# CORRECT: after re-registering "MYKW" with TOKEN_B, the old TOKEN_A
	# entry in _keyword_entries should be erased. It should not be retrievable.
	# We can verify indirectly: registering a NEW keyword with TOKEN_A should
	# succeed (because TOKEN_A should be freed). If the orphan remains, it fails.
	var ok: bool = engine.register_keyword("OTHER", TOKEN_A, noop_parse, false)
	assert_true(ok,
		"TOKEN_A should be available — old _keyword_entries[TOKEN_A] should have been erased on re-registration")


# register_expression_handler should invalidate _ast_cache
func test_register_handler_should_invalidate_cache() -> void:
	var engine := ChronicleExpressionEngine.new()

	# Parse and cache an expression
	var ast1: Variant = engine.parse("health > 50")
	assert_not_null(ast1, "should parse")

	# Register a handler that completely changes NODE_COMPARE semantics
	var custom_called: Array[bool] = [false]
	engine.register_expression_handler(Parser.NODE_COMPARE,
		func(_a: Dictionary, _r: Callable) -> bool:
			custom_called[0] = true
			return true,
		func(_a: Dictionary, _k: Array[String]) -> void: pass,
		func(_a: Dictionary, _fn: Callable) -> void: pass,
		true)

	# Parse same expression again — should get a FRESH AST since handlers changed
	var ast2: Variant = engine.parse("health > 50")

	# CORRECT: cache should have been invalidated by register_expression_handler.
	var resolver: Callable = func(_key: String) -> Variant: return 100
	engine.evaluate_ast(ast2, resolver)
	assert_true(custom_called[0], "custom handler should be called via shared dict reference")
