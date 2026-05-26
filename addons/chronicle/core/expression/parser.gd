## Parses tokenized expressions into a Dictionary-based AST.

const Lexer := preload("res://addons/chronicle/core/expression/lexer.gd")

const NODE_OR := "or"
const NODE_AND := "and"
const NODE_NOT := "not"
const NODE_COMPARE := "compare"
const NODE_TRUTHY := "truthy"
const NODE_IN := "in"
const NODE_BETWEEN := "between"
const NODE_MATCHES := "matches"

const MAX_DEPTH: int = 64

const COMP_OPS: Dictionary[int, bool] = {
	Lexer.TokenType.OP_EQ: true, Lexer.TokenType.OP_NEQ: true,
	Lexer.TokenType.OP_GT: true, Lexer.TokenType.OP_LT: true,
	Lexer.TokenType.OP_GTE: true, Lexer.TokenType.OP_LTE: true,
}


class ParseState extends RefCounted:
	var tokens: Array[Dictionary]
	var pos: int = 0
	var depth: int = 0


class KeywordEntry extends RefCounted:
	var fn: Callable
	var negatable: bool
	func _init(p_fn: Callable, p_negatable: bool) -> void:
		fn = p_fn
		negatable = p_negatable


# -- AST node factory functions --------------------------------------------------

static func _make_compare(left: Dictionary, op: int, right: Dictionary) -> Dictionary:
	return {node_type = NODE_COMPARE, left = left, op = op, right = right}


static func _make_logical(type: String, children: Array) -> Dictionary:
	return {node_type = type, children = children}


static func _make_unary(type: String, operand: Dictionary) -> Dictionary:
	return {node_type = type, operand = operand}


static func _make_truthy(key: String) -> Dictionary:
	return {node_type = NODE_TRUTHY, key = key}


static func _make_in(operand: Dictionary, rhs: Dictionary, negated: bool) -> Dictionary:
	return {node_type = NODE_IN, operand = operand, rhs = rhs, negated = negated}


static func _make_between(operand: Dictionary, low: Variant, high: Variant, negated: bool) -> Dictionary:
	return {node_type = NODE_BETWEEN, operand = operand, low = low, high = high, negated = negated}


static func _make_matches(operand: Dictionary, pattern: String, compiled_regex: RegEx, negated: bool) -> Dictionary:
	return {node_type = NODE_MATCHES, operand = operand, pattern = pattern, compiled_regex = compiled_regex, negated = negated}


static func parse_or_with(state: ParseState, keyword_entries: Dictionary) -> Variant:
	var left: Variant = _parse_and_with(state, keyword_entries)
	if left == null:
		return null
	return _parse_binary_chain(state, left, Lexer.TokenType.OR, NODE_OR, func(s: ParseState) -> Variant: return _parse_and_with(s, keyword_entries))


static func current_token(state: ParseState) -> Dictionary:
	return state.tokens[state.pos]


static func _advance(state: ParseState) -> Dictionary:
	var tok: Dictionary = state.tokens[state.pos]
	state.pos += 1
	return tok


static func _parse_binary_chain(state: ParseState, left: Variant, token_type: int, node_type: String, sub_fn: Callable) -> Variant:
	var children: Array[Variant] = [left]
	while current_token(state).type == token_type:
		_advance(state)
		var right: Variant = sub_fn.call(state)
		if right == null:
			return null
		children.append(right)
	return children[0] if children.size() == 1 else _make_logical(node_type, children)


static func _parse_and_with(state: ParseState, keyword_entries: Dictionary) -> Variant:
	var left: Variant = _parse_unary_with(state, keyword_entries)
	if left == null:
		return null
	return _parse_binary_chain(state, left, Lexer.TokenType.AND, NODE_AND, func(s: ParseState) -> Variant: return _parse_unary_with(s, keyword_entries))


static func _parse_unary_with(state: ParseState, keyword_entries: Dictionary) -> Variant:
	if current_token(state).type == Lexer.TokenType.NOT:
		if state.depth >= MAX_DEPTH:
			push_error("[Chronicle] Expression parse error: max nesting depth (%d) exceeded." % MAX_DEPTH)
			return null
		state.depth += 1
		_advance(state)
		var operand: Variant = _parse_unary_with(state, keyword_entries)
		state.depth -= 1
		if operand == null:
			return null
		return _make_unary(NODE_NOT, operand)
	return _parse_primary_with(state, keyword_entries)


static func _parse_primary_with(state: ParseState, keyword_entries: Dictionary) -> Variant:
	var tok: Dictionary = current_token(state)
	if tok.type == Lexer.TokenType.TRUE:
		_advance(state)
		return _make_compare({op_type = "bool", value = true}, Lexer.TokenType.OP_EQ, {op_type = "bool", value = true})
	if tok.type == Lexer.TokenType.FALSE:
		_advance(state)
		return _make_compare({op_type = "bool", value = false}, Lexer.TokenType.OP_EQ, {op_type = "bool", value = true})
	if tok.type == Lexer.TokenType.LPAREN:
		if state.depth >= MAX_DEPTH:
			push_error("[Chronicle] Expression parse error: max nesting depth (%d) exceeded." % MAX_DEPTH)
			return null
		state.depth += 1
		_advance(state)
		var expr: Variant = parse_or_with(state, keyword_entries)
		state.depth -= 1
		if expr == null:
			return null
		if current_token(state).type != Lexer.TokenType.RPAREN:
			push_error("[Chronicle] Expression parse error at col %d: expected ')' but got '%s'." % [current_token(state).pos, str(current_token(state).value)])
			return null
		_advance(state)
		return expr
	if tok.type == Lexer.TokenType.KEY:
		_advance(state)
		var next: Dictionary = current_token(state)
		var operand: Dictionary = {op_type = "key", value = tok.value}
		if next.type == Lexer.TokenType.NOT:
			var peek_pos: int = state.pos + 1
			if peek_pos < state.tokens.size():
				var peek_type: int = state.tokens[peek_pos].type
				if peek_type in keyword_entries and keyword_entries[peek_type].negatable:
					_advance(state)
					_advance(state)
					return keyword_entries[peek_type].fn.call(state, operand, true)
		if next.type in keyword_entries:
			_advance(state)
			return keyword_entries[next.type].fn.call(state, operand, false)
		if _is_comp_op(next.type):
			var op: int = next.type
			_advance(state)
			var rhs: Variant = _parse_value(state)
			if rhs == null:
				push_error("[Chronicle] Expression parse error at col %d: expected value after comparison operator." % current_token(state).pos)
				return null
			return _make_compare(operand, op, rhs)
		return _make_truthy(tok.value)
	push_error("[Chronicle] Expression parse error at col %d: unexpected token '%s'." % [tok.pos, str(tok.value)])
	return null


static func _parse_value(state: ParseState) -> Variant:
	var tok: Dictionary = current_token(state)
	if tok.type == Lexer.TokenType.STRING:
		_advance(state); return {op_type = "string", value = tok.value}
	if tok.type == Lexer.TokenType.NUMBER:
		_advance(state); return {op_type = "number", value = tok.value}
	if tok.type == Lexer.TokenType.TRUE:
		_advance(state); return {op_type = "bool", value = true}
	if tok.type == Lexer.TokenType.FALSE:
		_advance(state); return {op_type = "bool", value = false}
	if tok.type == Lexer.TokenType.KEY:
		_advance(state); return {op_type = "key", value = tok.value}
	return null


static func parse_in_rhs(state: ParseState, operand: Dictionary, negated: bool) -> Variant:
	var tok: Dictionary = current_token(state)
	if tok.type == Lexer.TokenType.LBRACKET:
		_advance(state)
		var elements: Array[Variant] = []
		if current_token(state).type != Lexer.TokenType.RBRACKET:
			var first: Variant = _parse_value(state)
			if first == null:
				push_error("[Chronicle] Expression parse error at col %d: expected value in array." % current_token(state).pos); return null
			elements.append(first)
			while current_token(state).type == Lexer.TokenType.COMMA:
				_advance(state)
				var elem: Variant = _parse_value(state)
				if elem == null:
					push_error("[Chronicle] Expression parse error at col %d: expected value after ',' in array." % current_token(state).pos); return null
				elements.append(elem)
		if current_token(state).type != Lexer.TokenType.RBRACKET:
			push_error("[Chronicle] Expression parse error at col %d: expected ']' to close array." % current_token(state).pos); return null
		_advance(state)
		return _make_in(operand, {rhs_type = "array", elements = elements}, negated)
	if tok.type == Lexer.TokenType.KEY:
		_advance(state)
		return _make_in(operand, {rhs_type = "key", value = tok.value}, negated)
	push_error("[Chronicle] Expression parse error at col %d: expected '[' or key after %s." % [tok.pos, "NOT IN" if negated else "IN"]); return null


static func parse_between(state: ParseState, operand: Dictionary, negated: bool) -> Variant:
	var low: Variant = _parse_bound(state)
	if low == null:
		push_error("[Chronicle] Expression parse error at col %d: expected value after BETWEEN." % current_token(state).pos); return null
	if current_token(state).type != Lexer.TokenType.AND:
		push_error("[Chronicle] Expression parse error at col %d: expected 'AND' in BETWEEN expression." % current_token(state).pos); return null
	_advance(state)
	var high: Variant = _parse_bound(state)
	if high == null:
		push_error("[Chronicle] Expression parse error at col %d: expected value after AND in BETWEEN." % current_token(state).pos); return null
	return _make_between(operand, low, high, negated)


static func _parse_bound(state: ParseState) -> Variant:
	var result: Variant = _parse_value(state)
	if result != null and result.get("op_type", "") == "bool":
		push_error("[Chronicle] Expression parse error at col %d: BETWEEN bounds cannot be boolean literals." % current_token(state).pos); return null
	return result


static func parse_matches_pattern(state: ParseState, operand: Dictionary, negated: bool) -> Variant:
	var tok: Dictionary = current_token(state)
	if tok.type != Lexer.TokenType.STRING:
		push_error("[Chronicle] Expression parse error at col %d: MATCHES requires a string literal pattern." % tok.pos); return null
	_advance(state)
	var raw_pattern: String = tok.value
	if raw_pattern.length() > 256:
		push_error("[Chronicle] Expression parse error at col %d: regex pattern exceeds 256 char limit." % tok.pos); return null
	for pi: int in range(raw_pattern.length()):
		var ch: String = raw_pattern[pi]
		if pi > 0 and (raw_pattern[pi - 1] == ")" or raw_pattern[pi - 1] == "]"):
			var backslash_count: int = 0
			var bi: int = pi - 2
			while bi >= 0 and raw_pattern[bi] == "\\":
				backslash_count += 1
				bi -= 1
			if backslash_count % 2 == 1:
				continue
			if ch in ["+", "*", "?", "{"]:
				if raw_pattern[pi - 1] == ")":
					push_error("[Chronicle] ReDoS risk: quantifier '%s' after group close in pattern." % ch); return null
				var bracket_open: int = pi - 2
				while bracket_open >= 0 and raw_pattern[bracket_open] != "[":
					bracket_open -= 1
				if bracket_open > 0 and raw_pattern[bracket_open - 1] in ["+", "*", "?", "}"]:
					push_error("[Chronicle] ReDoS risk: quantifier '%s' after adjacent quantified character class in pattern." % ch); return null
	var wrapped: String = "^(?:" + raw_pattern + ")$"
	var regex := RegEx.new()
	var err: Error = regex.compile(wrapped)
	if err != OK:
		push_error("[Chronicle] Expression parse error at col %d: invalid regex pattern '%s'." % [tok.pos, raw_pattern]); return null
	return _make_matches(operand, raw_pattern, regex, negated)


static func _is_comp_op(type: int) -> bool:
	return type in COMP_OPS
