const ExprParser := preload("res://addons/chronicle/core/expression/parser.gd")
const Lexer := preload("res://addons/chronicle/core/expression/lexer.gd")

const MAX_EVAL_DEPTH: int = 64


static func evaluate_ast_with(ast: Variant, resolver: Callable, handlers: Dictionary, regex_cache: ChronicleRingCache, truthy_fn_resolver: Callable, depth: int = MAX_EVAL_DEPTH) -> bool:
	if depth <= 0:
		push_error("[Chronicle] Expression evaluation exceeded max depth (%d)." % MAX_EVAL_DEPTH)
		return false
	if ast == null or ast is not Dictionary:
		return false
	var handler: Dictionary = handlers.get(ast.get("node_type", ""), {})
	if handler.is_empty():
		push_error("[Chronicle] Unknown AST node type: %s" % ast.get("node_type", ""))
		return false
	return handler.eval.call(ast, resolver)


static func extract_keys_with(ast: Variant, handlers: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	_collect_keys_dispatch_with(ast, keys, handlers)
	return keys


static func walk_ast_with(node: Variant, leaf_fn: Callable, handlers: Dictionary) -> void:
	if node == null or node is not Dictionary:
		return
	var node_type: String = node.get("node_type", "")
	var handler: Dictionary = handlers.get(node_type, {})
	if handler.is_empty():
		push_error("[Chronicle] walk_ast: unknown node_type '%s' — skipping." % node_type)
		return
	handler.walk.call(node, leaf_fn)


static func _collect_keys_dispatch_with(ast: Variant, keys: Array[String], handlers: Dictionary) -> void:
	if ast == null or ast is not Dictionary:
		return
	var handler: Dictionary = handlers.get(ast.get("node_type", ""), {})
	if not handler.is_empty():
		handler.keys.call(ast, keys)


static func _make_eval_or(handlers: Dictionary, regex_cache: ChronicleRingCache, truthy_fn_resolver: Callable) -> Callable:
	return func(ast: Dictionary, resolver: Callable) -> bool:
		for child: Variant in ast.children:
			if evaluate_ast_with(child, resolver, handlers, regex_cache, truthy_fn_resolver):
				return true
		return false


static func _make_eval_and(handlers: Dictionary, regex_cache: ChronicleRingCache, truthy_fn_resolver: Callable) -> Callable:
	return func(ast: Dictionary, resolver: Callable) -> bool:
		for child: Variant in ast.children:
			if not evaluate_ast_with(child, resolver, handlers, regex_cache, truthy_fn_resolver):
				return false
		return true


static func _make_eval_not(handlers: Dictionary, regex_cache: ChronicleRingCache, truthy_fn_resolver: Callable) -> Callable:
	return func(ast: Dictionary, resolver: Callable) -> bool:
		return not evaluate_ast_with(ast.operand, resolver, handlers, regex_cache, truthy_fn_resolver)


static func _eval_compare(ast: Dictionary, resolver: Callable) -> bool:
	var left_val: Variant = _resolve_operand(ast.left, resolver)
	var right_val: Variant = _resolve_operand(ast.right, resolver)
	return _apply_comparison(ast.op, left_val, right_val)


static func _make_eval_truthy(truthy_fn_resolver: Callable) -> Callable:
	return func(ast: Dictionary, resolver: Callable) -> bool:
		return ChronicleValueUtils.is_truthy(resolver.call(ast.key), truthy_fn_resolver)


static func _eval_in(ast: Dictionary, resolver: Callable) -> bool:
	var lhs_val: Variant = _resolve_operand(ast.operand, resolver)
	var rhs_result: Variant = _resolve_in_rhs(ast.rhs, resolver)
	if rhs_result == null:
		return false
	var found: bool = _check_membership(lhs_val, rhs_result, ast.rhs.get("rhs_type", ""), resolver)
	return not found if ast.get("negated", false) else found


static func _eval_between(ast: Dictionary, resolver: Callable) -> bool:
	var subject: Variant = _resolve_operand(ast.operand, resolver)
	var low: Variant = _resolve_operand(ast.low, resolver)
	var high: Variant = _resolve_operand(ast.high, resolver)
	var result: bool = _check_between(subject, low, high)
	return not result if ast.get("negated", false) else result


static func _make_eval_matches(regex_cache: ChronicleRingCache) -> Callable:
	return func(ast: Dictionary, resolver: Callable) -> bool:
		var val: Variant = _resolve_operand(ast.operand, resolver)
		return _check_matches_with(val, ast, ast.get("negated", false), regex_cache)


static func _keys_compare(ast: Dictionary, keys: Array[String]) -> void:
	_collect_key(ast.left, keys)
	_collect_key(ast.right, keys)


static func _keys_truthy(ast: Dictionary, keys: Array[String]) -> void:
	var key: String = ast.key
	if key not in keys:
		keys.append(key)


static func _keys_in(ast: Dictionary, keys: Array[String]) -> void:
	_collect_key(ast.operand, keys)
	if ast.rhs.get("rhs_type", "") == "key":
		var key: String = ast.rhs.value
		if key not in keys:
			keys.append(key)
	elif ast.rhs.get("rhs_type", "") == "array":
		for element: Dictionary in ast.rhs.get("elements", []):
			_collect_key(element, keys)


static func _keys_between(ast: Dictionary, keys: Array[String]) -> void:
	_collect_key(ast.operand, keys)
	_collect_key(ast.low, keys)
	_collect_key(ast.high, keys)


static func _keys_matches(ast: Dictionary, keys: Array[String]) -> void:
	_collect_key(ast.operand, keys)


static func _collect_key(operand: Dictionary, keys: Array[String]) -> void:
	if operand.get("op_type", "") == "key":
		var key: String = operand.value
		if key not in keys:
			keys.append(key)


static func _make_walk_children(handlers: Dictionary) -> Callable:
	return func(ast: Dictionary, leaf_fn: Callable) -> void:
		for child: Variant in ast.children:
			walk_ast_with(child, leaf_fn, handlers)


static func _make_walk_unary(handlers: Dictionary) -> Callable:
	return func(ast: Dictionary, leaf_fn: Callable) -> void:
		walk_ast_with(ast.operand, leaf_fn, handlers)


static func _walk_leaf(ast: Dictionary, leaf_fn: Callable) -> void:
	leaf_fn.call(ast)


## Cache for externally constructed NODE_MATCHES ASTs that omit compiled_regex.
## Parser-generated ASTs always embed compiled_regex, so this cache is a fallback only.
static func _get_regex_with(pattern: String, node: Dictionary, regex_cache: ChronicleRingCache) -> RegEx:
	var compiled: Variant = node.get("compiled_regex")
	if compiled is RegEx:
		return compiled
	var cached: Variant = regex_cache.get_or_null(pattern)
	if cached != null:
		return cached
	var regex := RegEx.new()
	var compile_err: Error = regex.compile("^(?:" + pattern + ")$")
	if compile_err != OK:
		push_error("[Chronicle] Expression eval: failed to compile cached regex pattern '%s'." % pattern)
		return regex
	regex_cache.put(pattern, regex)
	return regex


static func _resolve_operand(operand: Dictionary, resolver: Callable) -> Variant:
	var op_type: String = operand.get("op_type", "")
	if op_type == "key":
		return resolver.call(operand.value)
	return operand.value


static func _apply_comparison(op: int, left: Variant, right: Variant) -> bool:
	if left == null or right == null:
		if op == Lexer.TokenType.OP_EQ: return left == right
		if op == Lexer.TokenType.OP_NEQ: return left != right
		return false
	match op:
		Lexer.TokenType.OP_EQ:
			if typeof(left) != typeof(right) and not _comparable(left, right): return false
			return left == right
		Lexer.TokenType.OP_NEQ:
			if typeof(left) != typeof(right) and not _comparable(left, right): return true
			return left != right
		Lexer.TokenType.OP_GT:
			if _comparable(left, right): return left > right
		Lexer.TokenType.OP_LT:
			if _comparable(left, right): return left < right
		Lexer.TokenType.OP_GTE:
			if _comparable(left, right): return left >= right
		Lexer.TokenType.OP_LTE:
			if _comparable(left, right): return left <= right
	push_warning("[Chronicle] Expression eval: type mismatch in comparison — %s (%s) vs %s (%s)." % [str(left), type_string(typeof(left)), str(right), type_string(typeof(right))])
	return false


static func _comparable(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return true
	if a is String and b is String: return true
	return false


static func _resolve_in_rhs(rhs: Dictionary, resolver: Callable) -> Variant:
	if rhs.rhs_type == "array": return rhs.elements
	var resolved: Variant = resolver.call(rhs.value)
	if resolved == null:
		push_warning("[Chronicle] Expression eval: IN key '%s' is not set." % rhs.value); return null
	if resolved is not Array:
		push_warning("[Chronicle] Expression eval: IN key '%s' resolved to %s, expected Array." % [rhs.value, type_string(typeof(resolved))]); return null
	return resolved


static func _check_membership(value: Variant, rhs: Variant, rhs_type: String, resolver: Callable = Callable()) -> bool:
	if rhs_type == "array":
		for element: Dictionary in rhs:
			var resolved: Variant = _resolve_operand(element, resolver) if resolver.is_valid() else element.value
			if _values_equal(value, resolved): return true
		return false
	for element: Variant in rhs:
		if _values_equal(value, element): return true
	return false


static func _values_equal(a: Variant, b: Variant) -> bool:
	if a == null and b == null: return true
	if a == null or b == null: return false
	if typeof(a) != typeof(b):
		if _comparable(a, b): return a == b
		return false
	return a == b


static func _check_between(subject: Variant, low: Variant, high: Variant) -> bool:
	if subject == null:
		push_warning("[Chronicle] Expression eval: BETWEEN subject is null."); return false
	if low == null or high == null:
		push_warning("[Chronicle] Expression eval: BETWEEN bound is null (low=%s, high=%s)." % [str(low), str(high)]); return false
	if not _comparable(subject, low) or not _comparable(subject, high):
		push_warning("[Chronicle] Expression eval: BETWEEN type mismatch — subject %s (%s), low %s (%s), high %s (%s)." % [str(subject), type_string(typeof(subject)), str(low), type_string(typeof(low)), str(high), type_string(typeof(high))]); return false
	if not _comparable(low, high):
		push_warning("[Chronicle] Expression eval: BETWEEN bounds not comparable — %s (%s) vs %s (%s)." % [str(low), type_string(typeof(low)), str(high), type_string(typeof(high))]); return false
	if low > high:
		push_warning("[Chronicle] Expression eval: BETWEEN bounds inverted (%s > %s)." % [str(low), str(high)]); return false
	return subject >= low and subject <= high


static func _check_matches_with(val: Variant, node: Dictionary, negated: bool, regex_cache: ChronicleRingCache) -> bool:
	if val == null: return false
	if val is not String:
		push_warning("[Chronicle] Expression eval: MATCHES requires String, got %s (%s)." % [type_string(typeof(val)), str(val)]); return false
	var regex: RegEx = _get_regex_with(node.pattern, node, regex_cache)
	if not regex.is_valid(): return false
	var matched: bool = regex.search(val) != null
	return not matched if negated else matched
