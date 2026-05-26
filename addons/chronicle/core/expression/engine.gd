## Each Chronicle owns its own engine.
class_name ChronicleExpressionEngine
extends RefCounted

const Lexer := preload("res://addons/chronicle/core/expression/lexer.gd")
const Parser := preload("res://addons/chronicle/core/expression/parser.gd")
const Evaluator := preload("res://addons/chronicle/core/expression/evaluator.gd")
var _custom_keywords: Dictionary[String, int] = {}
var _negative_start_types: Dictionary[int, bool] = {}
var _keyword_entries: Dictionary[int, RefCounted] = {}
var _ast_cache: ChronicleRingCache
static var _PARSE_FAILED: RefCounted = RefCounted.new()
var _handlers: Dictionary[String, Dictionary] = {}
var _builtin_handler_types: Dictionary[String, bool] = {}
var _regex_cache: ChronicleRingCache
var _truthy_fn_resolver: Callable


func _init(truthy_fn_resolver: Callable = Callable()) -> void:
	_truthy_fn_resolver = truthy_fn_resolver
	_ast_cache = ChronicleRingCache.new(256)
	_regex_cache = ChronicleRingCache.new(512)
	_init_negative_start_types()
	_init_builtin_keyword_entries()
	_init_builtin_handlers()


func parse(source: String) -> Variant:
	var cached: Variant = _ast_cache.get_or_null(source)
	if cached != null:
		return null if is_same(cached, _PARSE_FAILED) else _deep_copy_ast(cached)
	var tokens: Array[Dictionary] = Lexer.tokenize_with(source, _custom_keywords, _negative_start_types)
	if tokens.is_empty():
		_ast_cache.put(source, _PARSE_FAILED)
		return null
	if tokens.size() == 1 and tokens[0].type == Lexer.TokenType.EOF:
		_ast_cache.put(source, _PARSE_FAILED)
		return null
	var state := Parser.ParseState.new()
	state.tokens = tokens
	var ast: Variant = Parser.parse_or_with(state, _keyword_entries)
	if ast == null:
		_ast_cache.put(source, _PARSE_FAILED)
		return null
	if Parser.current_token(state).type != Lexer.TokenType.EOF:
		push_error("[Chronicle] Expression parse error at col %d: unexpected token '%s' after expression." % [Parser.current_token(state).pos, str(Parser.current_token(state).value)])
		_ast_cache.put(source, _PARSE_FAILED)
		return null
	_ast_cache.put(source, ast)
	return _deep_copy_ast(ast)


func evaluate_ast(ast: Variant, resolver: Callable) -> bool:
	return Evaluator.evaluate_ast_with(ast, resolver, _handlers, _regex_cache, _truthy_fn_resolver)


func extract_keys(ast: Variant) -> Array[String]:
	return Evaluator.extract_keys_with(ast, _handlers)


func walk_ast(node: Variant, leaf_fn: Callable) -> void:
	Evaluator.walk_ast_with(node, leaf_fn, _handlers)


func register_keyword(keyword: String, token_type: int, parse_fn: Callable, negatable: bool) -> bool:
	if token_type < Lexer.FIRST_CUSTOM_TOKEN_TYPE:
		push_error("[Chronicle] register_keyword: token_type %d is below FIRST_CUSTOM_TOKEN_TYPE (%d)." % [token_type, Lexer.FIRST_CUSTOM_TOKEN_TYPE])
		return false
	if not parse_fn.is_valid():
		push_error("[Chronicle] register_keyword(): parse_fn must be a valid Callable.")
		return false
	var upper: String = keyword.to_upper()
	if upper in Lexer._BUILTIN_KEYWORDS:
		push_warning("[Chronicle] Keyword \"%s\" is a built-in keyword — cannot override." % upper)
		return false
	if upper in _custom_keywords:
		var old_token: int = _custom_keywords[upper]
		_negative_start_types.erase(old_token)
		_keyword_entries.erase(old_token)
		_custom_keywords.erase(upper)
		push_warning("[Chronicle] Custom keyword \"%s\" already registered — overwriting." % upper)
	if token_type in _keyword_entries:
		push_error("[Chronicle] register_keyword: token_type %d already registered." % token_type)
		return false
	_custom_keywords[upper] = token_type
	_negative_start_types[token_type] = true
	_keyword_entries[token_type] = Parser.KeywordEntry.new(parse_fn, negatable)
	_ast_cache.clear()
	return true


func unregister_keyword(keyword: String) -> bool:
	var upper: String = keyword.to_upper()
	if upper not in _custom_keywords:
		return false
	var token_type: int = _custom_keywords[upper]
	_negative_start_types.erase(token_type)
	_keyword_entries.erase(token_type)
	_custom_keywords.erase(upper)
	_ast_cache.clear()
	return true


func register_expression_handler(node_type: String, eval_fn: Callable, keys_fn: Callable, walk_fn: Callable, force: bool = false) -> bool:
	if not eval_fn.is_valid() or not keys_fn.is_valid() or not walk_fn.is_valid():
		push_error("[Chronicle] register_expression_handler('%s'): all three callables must be valid." % node_type)
		return false
	if node_type in _builtin_handler_types:
		if not force:
			push_error("[Chronicle] register_expression_handler: '%s' is a built-in handler — pass force=true to override." % node_type)
			return false
		push_warning("[Chronicle] register_expression_handler: force-overriding built-in handler '%s'." % node_type)
	elif node_type in _handlers:
		push_warning("[Chronicle] register_expression_handler: overriding existing handler for '%s'." % node_type)
	_handlers[node_type] = {eval = eval_fn, keys = keys_fn, walk = walk_fn}
	_ast_cache.clear()
	return true


func is_expression_handler_registered(node_type: String) -> bool:
	return node_type in _handlers and node_type not in _builtin_handler_types


func unregister_expression_handler(node_type: String) -> bool:
	if node_type in _builtin_handler_types:
		push_error("[Chronicle] Cannot unregister built-in handler: %s" % node_type)
		return false
	if node_type not in _handlers:
		return false
	_handlers.erase(node_type)
	_ast_cache.clear()
	return true


func clear_custom_handlers() -> void:
	for key: String in _handlers.keys():
		if key not in _builtin_handler_types:
			_handlers.erase(key)
	_ast_cache.clear()
	_regex_cache.clear()


func _clear_all() -> void:
	_handlers.clear()
	_ast_cache.clear()
	_regex_cache.clear()


func get_custom_token_type(keyword: String) -> Variant:
	return _custom_keywords.get(keyword.to_upper(), null)


func _init_negative_start_types() -> void:
	var T := Lexer.TokenType
	_negative_start_types = {
		T.LPAREN: true, T.LBRACKET: true, T.COMMA: true,
		T.AND: true, T.OR: true, T.NOT: true,
		T.BETWEEN: true, T.IN: true, T.MATCHES: true,
		T.OP_EQ: true, T.OP_NEQ: true, T.OP_LT: true,
		T.OP_LTE: true, T.OP_GT: true, T.OP_GTE: true,
	}


func _init_builtin_keyword_entries() -> void:
	var T := Lexer.TokenType
	_keyword_entries[T.IN] = Parser.KeywordEntry.new(Parser.parse_in_rhs, true)
	_keyword_entries[T.BETWEEN] = Parser.KeywordEntry.new(Parser.parse_between, true)
	_keyword_entries[T.MATCHES] = Parser.KeywordEntry.new(Parser.parse_matches_pattern, true)


func _init_builtin_handlers() -> void:
	var h: Dictionary = _handlers
	var rc: ChronicleRingCache = _regex_cache
	var tfr: Callable = _truthy_fn_resolver
	_register(Parser.NODE_OR, Evaluator._make_eval_or(h, rc, tfr), _make_keys_structural(h), Evaluator._make_walk_children(h))
	_register(Parser.NODE_AND, Evaluator._make_eval_and(h, rc, tfr), _make_keys_structural(h), Evaluator._make_walk_children(h))
	_register(Parser.NODE_NOT, Evaluator._make_eval_not(h, rc, tfr), _make_keys_not(h), Evaluator._make_walk_unary(h))
	_register(Parser.NODE_COMPARE, Evaluator._eval_compare, Evaluator._keys_compare, Evaluator._walk_leaf)
	_register(Parser.NODE_TRUTHY, Evaluator._make_eval_truthy(tfr), Evaluator._keys_truthy, Evaluator._walk_leaf)
	_register(Parser.NODE_IN, Evaluator._eval_in, Evaluator._keys_in, Evaluator._walk_leaf)
	_register(Parser.NODE_BETWEEN, Evaluator._eval_between, Evaluator._keys_between, Evaluator._walk_leaf)
	_register(Parser.NODE_MATCHES, Evaluator._make_eval_matches(rc), Evaluator._keys_matches, Evaluator._walk_leaf)
	for key: String in _handlers:
		_builtin_handler_types[key] = true


func _register(node_type: String, eval_fn: Callable, keys_fn: Callable, walk_fn: Callable) -> void:
	_handlers[node_type] = {eval = eval_fn, keys = keys_fn, walk = walk_fn}


func _deep_copy_ast(ast: Variant) -> Variant:
	if ast is Dictionary:
		var copy: Dictionary = {}
		for key: Variant in ast:
			copy[key] = _deep_copy_ast(ast[key])
		return copy
	if ast is Array:
		var copy: Array = []
		for item: Variant in ast:
			copy.append(_deep_copy_ast(item))
		return copy
	return ast


static func _make_keys_structural(handlers: Dictionary) -> Callable:
	return func(ast: Dictionary, keys: Array[String]) -> void:
		for child: Variant in ast.children:
			Evaluator._collect_keys_dispatch_with(child, keys, handlers)


static func _make_keys_not(handlers: Dictionary) -> Callable:
	return func(ast: Dictionary, keys: Array[String]) -> void:
		Evaluator._collect_keys_dispatch_with(ast.operand, keys, handlers)


