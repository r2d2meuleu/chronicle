## Unit tests for the expression parser: tokenizer output, AST structure, key extraction, and evaluator API.
extends GutTest

const Parser := preload("res://addons/chronicle/core/expression/parser.gd")
const Lexer := preload("res://addons/chronicle/core/expression/lexer.gd")

var _engine: ChronicleExpressionEngine


func before_each() -> void:
	_engine = ChronicleExpressionEngine.new()


func _run_expr(expr: String, facts: Dictionary) -> bool:
	return ExpressionTestHelpers.run_expr(_engine, expr, facts)


# ── Tokenizer ──

func test_tokenizer_simple_key() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("player.gold")
	assert_eq(tokens.size(), 2, "simple key token count")
	assert_eq(tokens[0].type, T.KEY, "simple key type")
	assert_eq(tokens[0].value as String, "player.gold", "simple key value")
	assert_eq(tokens[0].pos, 0, "simple key pos is 0")
	assert_eq(tokens[1].type, T.EOF, "EOF at end")
	assert_eq(tokens[1].pos, 11, "EOF pos is end of string")


func test_tokenizer_compound_expression() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("player.hp > 5 AND quest.done")
	assert_eq(tokens[0].type, T.KEY, "key before op type")
	assert_eq(tokens[0].value as String, "player.hp", "key before op value")
	assert_eq(tokens[0].pos, 0, "first key pos")
	assert_eq(tokens[1].type, T.OP_GT, "greater than")
	assert_eq(tokens[1].pos, 10, "greater than pos")
	assert_eq(tokens[2].type, T.NUMBER, "number literal type")
	assert_eq(tokens[2].value, 5.0, "number literal value")
	assert_eq(tokens[2].pos, 12, "number pos")
	assert_eq(tokens[3].type, T.AND, "AND keyword")
	assert_eq(tokens[3].pos, 14, "AND pos")
	assert_eq(tokens[4].type, T.KEY, "key after AND type")
	assert_eq(tokens[4].value as String, "quest.done", "key after AND value")
	assert_eq(tokens[4].pos, 18, "key after AND pos")


func test_tokenizer_dotted_reserved_words_are_key() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("and.or.not")
	assert_eq(tokens[0].type, T.KEY, "dotted reserved words type")
	assert_eq(tokens[0].value as String, "and.or.not", "dotted reserved words value")


func test_tokenizer_string_literal() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize('status == "completed"')
	assert_eq(tokens[0].type, T.KEY, "key before ==")
	assert_eq(tokens[1].type, T.OP_EQ, "equals op")
	assert_eq(tokens[2].type, T.STRING, "string literal type")
	assert_eq(tokens[2].value as String, "completed", "string literal value")


func test_tokenizer_parens_and_not() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("NOT (a.b OR c.d)")
	assert_eq(tokens[0].type, T.NOT, "NOT keyword")
	assert_eq(tokens[1].type, T.LPAREN, "left paren")
	assert_eq(tokens[2].type, T.KEY, "key inside parens")
	assert_eq(tokens[3].type, T.OR, "OR keyword")
	assert_eq(tokens[4].type, T.KEY, "second key inside parens")
	assert_eq(tokens[5].type, T.RPAREN, "right paren")


func test_tokenizer_all_comparison_operators() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("a == b != c >= d <= e > f < g")
	assert_eq(tokens[1].type, T.OP_EQ, "== op")
	assert_eq(tokens[3].type, T.OP_NEQ, "!= op")
	assert_eq(tokens[5].type, T.OP_GTE, ">= op")
	assert_eq(tokens[7].type, T.OP_LTE, "<= op")
	assert_eq(tokens[9].type, T.OP_GT, "> op")
	assert_eq(tokens[11].type, T.OP_LT, "< op")


func test_tokenizer_true_false_keywords() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("flag == TRUE")
	assert_eq(tokens[2].type, T.TRUE, "TRUE keyword")
	tokens = Lexer.tokenize("flag == FALSE")
	assert_eq(tokens[2].type, T.FALSE, "FALSE keyword")


func test_tokenizer_negative_number() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("hp >= -5")
	assert_eq(tokens[2].type, T.NUMBER, "negative number type")
	assert_eq(tokens[2].value, -5.0, "negative number value")


func test_tokenizer_float_literal() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("val > 3.14")
	assert_eq(tokens[2].type, T.NUMBER, "float literal type")
	assert_eq(tokens[2].value, 3.14, "float literal value")


func test_tokenizer_unterminated_string_returns_empty() -> void:
	var tokens := Lexer.tokenize('name == "oops')
	assert_eq(tokens.size(), 0)


func test_tokenizer_unexpected_char_returns_empty() -> void:
	var tokens := Lexer.tokenize("a & b")
	assert_eq(tokens.size(), 0)


func test_tokenizer_lowercase_not_is_keyword() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("not")
	assert_eq(tokens[0].type, T.NOT, "lowercase 'not' is keyword")
	assert_eq(tokens[0].value as String, "NOT", "lowercase 'not' normalised to 'NOT'")


func test_tokenizer_uppercase_not_is_keyword() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("NOT")
	assert_eq(tokens[0].type, T.NOT, "uppercase NOT is keyword")


func test_tokenizer_negative_at_start() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("-10")
	assert_eq(tokens[0].type, T.NUMBER, "negative at start type")
	assert_eq(tokens[0].value, -10.0, "negative at start value")


func test_tokenizer_empty_string_gives_eof() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("")
	assert_eq(tokens.size(), 1, "empty string token count")
	assert_eq(tokens[0].type, T.EOF, "empty string token type")


func test_tokenizer_underscore_key() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("player._private")
	assert_eq(tokens[0].type, T.KEY, "underscore key type")
	assert_eq(tokens[0].value as String, "player._private", "underscore key value")


func test_tokenizer_no_space_operators() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("a==b")
	assert_eq(tokens.size(), 4, "no-space op token count")
	assert_eq(tokens[0].type, T.KEY, "no-space left key type")
	assert_eq(tokens[0].value as String, "a", "no-space left key value")
	assert_eq(tokens[1].type, T.OP_EQ, "no-space equals")
	assert_eq(tokens[2].type, T.KEY, "no-space right key type")
	assert_eq(tokens[2].value as String, "b", "no-space right key value")


func test_tokenizer_digit_containing_key() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("zone1.flag")
	assert_eq(tokens[0].type, T.KEY, "digit-containing key type")
	assert_eq(tokens[0].value as String, "zone1.flag", "digit-containing key value")


func test_tokenizer_dotted_uppercase_is_key() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("TRUE.FALSE")
	assert_eq(tokens[0].type, T.KEY, "dotted uppercase type")
	assert_eq(tokens[0].value as String, "TRUE.FALSE", "dotted uppercase value")


func test_tokenizer_negative_after_true() -> void:
	var T := Lexer.TokenType
	var tokens := Lexer.tokenize("TRUE == -1")
	assert_eq(tokens[2].type, T.NUMBER, "negative after TRUE type")
	assert_eq(tokens[2].value, -1.0, "negative after TRUE value")


# ── Parser ──

func test_parser_bare_key() -> void:
	var ast: Variant = _engine.parse("player.alive")
	assert_not_null(ast)
	assert_eq(ast.node_type, "truthy", "bare key is truthy node")


func test_parser_comparison() -> void:
	var ast: Variant = _engine.parse("player.gold >= 100")
	assert_not_null(ast)
	assert_eq(ast.node_type, "compare", "comparison node type")


func test_parser_and() -> void:
	var ast: Variant = _engine.parse("a.b AND c.d")
	assert_not_null(ast)
	assert_eq(ast.node_type, "and", "AND node type")
	assert_eq(ast.children.size(), 2, "AND has 2 children")


func test_parser_or() -> void:
	var ast: Variant = _engine.parse("a.b OR c.d")
	assert_not_null(ast)
	assert_eq(ast.node_type, "or", "OR node type")


func test_parser_not() -> void:
	var ast: Variant = _engine.parse("NOT a.b")
	assert_not_null(ast)
	assert_eq(ast.node_type, "not", "NOT node type")


func test_parser_compound_precedence() -> void:
	var ast: Variant = _engine.parse("a.b AND c.d OR NOT e.f")
	assert_not_null(ast)
	assert_eq(ast.node_type, "or", "compound: OR is root (lowest precedence)")


func test_parser_parens_override_precedence() -> void:
	var ast: Variant = _engine.parse("(a.b OR c.d) AND NOT e.f")
	assert_not_null(ast)
	assert_eq(ast.node_type, "and", "parens: AND is root")


func test_parser_string_comparison() -> void:
	var ast: Variant = _engine.parse('status == "completed"')
	assert_not_null(ast)


func test_parser_error_missing_rhs() -> void:
	var ast: Variant = _engine.parse("a.b ==")
	assert_null(ast)


func test_parser_error_unmatched_paren() -> void:
	var ast: Variant = _engine.parse("(a.b AND c.d")
	assert_null(ast)


func test_parser_error_empty_string() -> void:
	var ast: Variant = _engine.parse("")
	assert_null(ast)


func test_parser_true_literal() -> void:
	var ast: Variant = _engine.parse("TRUE")
	assert_not_null(ast)


func test_parser_false_literal() -> void:
	var ast: Variant = _engine.parse("FALSE")
	assert_not_null(ast)


# ── Key Extraction ──

func test_key_extraction_two_keys() -> void:
	var ast: Variant = _engine.parse("player.gold >= 100 AND quest.done")
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 2, "extract 2 keys")
	assert_has(keys, "player.gold", "extracted player.gold")
	assert_has(keys, "quest.done", "extracted quest.done")


func test_key_extraction_three_keys() -> void:
	var ast: Variant = _engine.parse("(a.b OR c.d) AND NOT e.f")
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 3, "extract 3 keys from compound")
	assert_has(keys, "a.b", "a.b extracted")
	assert_has(keys, "c.d", "c.d extracted")
	assert_has(keys, "e.f", "e.f extracted")


func test_key_extraction_deduplicates() -> void:
	var ast: Variant = _engine.parse("a.b AND a.b")
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 1, "deduplicate keys")


func test_key_extraction_no_keys_from_literals() -> void:
	var ast: Variant = _engine.parse("TRUE AND FALSE")
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 0, "no keys from pure literals")


func test_key_extraction_comparison_with_string_literal() -> void:
	var ast: Variant = _engine.parse('status == "done"')
	var keys := _engine.extract_keys(ast)
	assert_eq(keys.size(), 1, "one key from comparison")
	assert_eq(keys[0] as String, "status", "key is status, not string literal")


func test_key_extraction_null_ast() -> void:
	var keys := _engine.extract_keys(null)
	assert_eq(keys.size(), 0, "null ast returns empty keys")


# ── Evaluator ──

func test_evaluator_comparison_true() -> void:
	assert_true(_run_expr("player.gold >= 100", {"player.gold": 150}))


func test_evaluator_comparison_false() -> void:
	assert_false(_run_expr("player.gold >= 200", {"player.gold": 150}))


func test_evaluator_truthy_true() -> void:
	assert_true(_run_expr("quest.done", {"quest.done": true}))


func test_evaluator_truthy_missing_key() -> void:
	assert_false(_run_expr("quest.missing", {}))


func test_evaluator_and_true() -> void:
	assert_true(_run_expr("player.gold >= 100 AND quest.done", {"player.gold": 150, "quest.done": true}))


func test_evaluator_and_short_circuit() -> void:
	assert_false(_run_expr("player.gold >= 200 AND quest.done", {"player.gold": 150, "quest.done": true}))


func test_evaluator_or_true() -> void:
	assert_true(_run_expr("player.gold >= 200 OR quest.done", {"player.gold": 150, "quest.done": true}))


func test_evaluator_not_missing() -> void:
	assert_true(_run_expr("NOT quest.missing", {}))


func test_evaluator_not_true() -> void:
	assert_false(_run_expr("NOT quest.done", {"quest.done": true}))


func test_evaluator_string_comparison_true() -> void:
	assert_true(_run_expr('status == "completed"', {"status": "completed"}))


func test_evaluator_string_comparison_false() -> void:
	assert_false(_run_expr('status == "pending"', {"status": "completed"}))


func test_evaluator_true_literal() -> void:
	assert_true(_run_expr("TRUE", {}))


func test_evaluator_false_literal() -> void:
	assert_false(_run_expr("FALSE", {}))


func test_evaluator_null_ast_returns_false() -> void:
	# null AST cannot be produced via parse(), so call evaluate_ast directly.
	var resolver: Callable = func(_key: String) -> Variant: return null
	assert_false(_engine.evaluate_ast(null, resolver) as bool)


func test_evaluator_convenience_method() -> void:
	assert_true(_run_expr("player.alive", {"player.alive": true}))


func test_lexer_escaped_quote() -> void:
	var tokens: Array[Dictionary] = Lexer.tokenize("key == \"say \\\"hi\\\"\"")
	var str_token: Dictionary = tokens[2]
	assert_eq(str_token.type, Lexer.TokenType.STRING)
	assert_eq(str_token.value, "say \"hi\"")


func test_lexer_escape_sequences() -> void:
	var tokens: Array[Dictionary] = Lexer.tokenize("key == \"line1\\nline2\\ttab\\\\slash\"")
	var str_token: Dictionary = tokens[2]
	assert_eq(str_token.value, "line1\nline2\ttab\\slash")


func test_lexer_unknown_escape_passthrough() -> void:
	var tokens: Array[Dictionary] = Lexer.tokenize("key == \"hello\\xworld\"")
	var str_token: Dictionary = tokens[2]
	assert_eq(str_token.value, "hello\\xworld")


# ── Case-Insensitive Keywords ──

func test_case_insensitive_and() -> void:
	var ast: Variant = _engine.parse("player.hp > 0 and quest.started")
	assert_not_null(ast, "lowercase 'and' should parse")
	assert_eq(ast.node_type, Parser.NODE_AND)

func test_case_insensitive_or() -> void:
	var ast: Variant = _engine.parse("player.hp > 0 or quest.started")
	assert_not_null(ast, "lowercase 'or' should parse")
	assert_eq(ast.node_type, Parser.NODE_OR)

func test_case_insensitive_not() -> void:
	var ast: Variant = _engine.parse("not quest.started")
	assert_not_null(ast, "lowercase 'not' should parse")
	assert_eq(ast.node_type, Parser.NODE_NOT)

func test_case_insensitive_true_false() -> void:
	var ast_t: Variant = _engine.parse("true")
	assert_not_null(ast_t, "lowercase 'true' should parse")
	assert_eq(ast_t.node_type, Parser.NODE_COMPARE, "lowercase true produces compare node")
	var ast_f: Variant = _engine.parse("false")
	assert_not_null(ast_f, "lowercase 'false' should parse")
	assert_eq(ast_f.node_type, Parser.NODE_COMPARE, "lowercase false produces compare node")

func test_case_insensitive_in() -> void:
	var ast: Variant = _engine.parse("player.class in [\"warrior\", \"mage\"]")
	assert_not_null(ast, "lowercase 'in' should parse")
	assert_eq(ast.node_type, Parser.NODE_IN)

func test_case_insensitive_between() -> void:
	var ast: Variant = _engine.parse("player.level between 1 and 10")
	assert_not_null(ast, "lowercase 'between...and' should parse")
	assert_eq(ast.node_type, Parser.NODE_BETWEEN)

func test_case_insensitive_matches() -> void:
	var ast: Variant = _engine.parse("player.name matches \"hero.*\"")
	assert_not_null(ast, "lowercase 'matches' should parse")
	assert_eq(ast.node_type, Parser.NODE_MATCHES)

func test_case_insensitive_mixed_case() -> void:
	var ast: Variant = _engine.parse("player.hp > 0 And quest.started Or Not player.dead")
	assert_not_null(ast, "mixed case keywords should parse")
	assert_eq(ast.node_type, Parser.NODE_OR)

func test_not_between_parses() -> void:
	var ast: Variant = _engine.parse("player.level NOT BETWEEN 1 AND 5")
	assert_not_null(ast, "NOT BETWEEN should parse")
	assert_eq(ast.node_type, Parser.NODE_BETWEEN)
	assert_true(ast.get("negated", false), "NOT BETWEEN should have negated=true")

func test_not_between_case_insensitive() -> void:
	var ast: Variant = _engine.parse("player.level not between 1 and 5")
	assert_not_null(ast, "lowercase 'not between' should parse")
	assert_eq(ast.node_type, Parser.NODE_BETWEEN)
	assert_true(ast.get("negated", false), "lowercase not between should be negated")


# ── Keyword Registration ──

func test_custom_keyword_registration() -> void:
	var custom_token: int = 1000
	var engine := ChronicleExpressionEngine.new()
	# A parse_fn is required to register a keyword; use a no-op that returns null
	engine.register_keyword("CUSTOM", custom_token, func(_state: Variant, _operand: Variant, _negated: bool) -> Variant: return null, false)
	var tokens: Array[Dictionary] = Lexer.tokenize_with("CUSTOM", engine._custom_keywords, engine._negative_start_types)
	assert_eq(tokens[0].type, custom_token)
	assert_eq(tokens[0].value, "CUSTOM")
