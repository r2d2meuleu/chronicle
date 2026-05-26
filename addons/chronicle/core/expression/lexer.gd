extends RefCounted


enum TokenType {
	KEY, NUMBER, STRING, AND, OR, NOT, TRUE, FALSE,
	IN, BETWEEN, MATCHES,
	OP_EQ, OP_NEQ, OP_GT, OP_LT, OP_GTE, OP_LTE,
	LPAREN, RPAREN, LBRACKET, RBRACKET, COMMA, EOF
}

const FIRST_CUSTOM_TOKEN_TYPE: int = 1000

const _BUILTIN_KEYWORDS: Dictionary[String, int] = {
	"AND": TokenType.AND, "OR": TokenType.OR, "NOT": TokenType.NOT,
	"TRUE": TokenType.TRUE, "FALSE": TokenType.FALSE,
	"IN": TokenType.IN, "BETWEEN": TokenType.BETWEEN, "MATCHES": TokenType.MATCHES,
}

const _DEFAULT_NEGATIVE_START_TYPES: Dictionary[int, bool] = {
	TokenType.LPAREN: true,
	TokenType.LBRACKET: true, TokenType.COMMA: true,
	TokenType.AND: true, TokenType.OR: true, TokenType.NOT: true,
	TokenType.BETWEEN: true, TokenType.IN: true, TokenType.MATCHES: true,
	TokenType.OP_EQ: true, TokenType.OP_NEQ: true, TokenType.OP_LT: true,
	TokenType.OP_LTE: true, TokenType.OP_GT: true, TokenType.OP_GTE: true,
}


## Convenience for tests that bypass ChronicleExpressionEngine.
static func tokenize(src: String) -> Array[Dictionary]:
	return tokenize_with(src, {}, _DEFAULT_NEGATIVE_START_TYPES)


static func tokenize_with(src: String, custom_keywords: Dictionary, negative_start_types: Dictionary) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	var i: int = 0
	var n: int = src.length()

	while i < n:
		var c: String = src[i]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
			continue
		if i + 1 < n:
			var pair: String = src.substr(i, 2)
			if pair == "==":
				tokens.append({type=TokenType.OP_EQ, value="==", pos=i}); i += 2; continue
			if pair == "!=":
				tokens.append({type=TokenType.OP_NEQ, value="!=", pos=i}); i += 2; continue
			if pair == ">=":
				tokens.append({type=TokenType.OP_GTE, value=">=", pos=i}); i += 2; continue
			if pair == "<=":
				tokens.append({type=TokenType.OP_LTE, value="<=", pos=i}); i += 2; continue
		if c == ">":
			tokens.append({type=TokenType.OP_GT, value=">", pos=i}); i += 1; continue
		if c == "<":
			tokens.append({type=TokenType.OP_LT, value="<", pos=i}); i += 1; continue
		if c == "(":
			tokens.append({type=TokenType.LPAREN, value="(", pos=i}); i += 1; continue
		if c == ")":
			tokens.append({type=TokenType.RPAREN, value=")", pos=i}); i += 1; continue
		if c == "[":
			tokens.append({type=TokenType.LBRACKET, value="[", pos=i}); i += 1; continue
		if c == "]":
			tokens.append({type=TokenType.RBRACKET, value="]", pos=i}); i += 1; continue
		if c == ",":
			tokens.append({type=TokenType.COMMA, value=",", pos=i}); i += 1; continue
		if c == "\"":
			var str_start: int = i
			i += 1
			var chars: PackedStringArray = []
			while i < n and src[i] != "\"":
				if src[i] == "\\" and i + 1 < n:
					i += 1
					match src[i]:
						"\"": chars.append("\"")
						"\\": chars.append("\\")
						"n": chars.append("\n")
						"t": chars.append("\t")
						_: chars.append("\\"); chars.append(src[i])
					i += 1
					continue
				chars.append(src[i])
				i += 1
			if i >= n:
				push_error("[Chronicle] Expression tokenizer: unterminated string at position %d." % str_start)
				return []
			tokens.append({type = TokenType.STRING, value = "".join(chars), pos = str_start})
			i += 1
			continue
		if c == "-" and not tokens.is_empty() and not _can_start_negative_with(tokens, negative_start_types):
			push_error("[Chronicle] Expression: unexpected '-' at col %d — subtraction is not supported." % i)
			return []
		if _is_digit(c) or (c == "-" and i + 1 < n and _is_digit(src[i + 1]) and _can_start_negative_with(tokens, negative_start_types)):
			var start: int = i
			if c == "-":
				i += 1
			while i < n and _is_digit(src[i]):
				i += 1
			if i < n and src[i] == "." and i + 1 < n and _is_digit(src[i + 1]):
				i += 1
				while i < n and _is_digit(src[i]):
					i += 1
			var raw_num: String = src.substr(start, i - start)
			var num_value: Variant = float(raw_num) if "." in raw_num else int(raw_num)
			tokens.append({type=TokenType.NUMBER, value=num_value, pos=start})
			continue
		if _is_ident_start(c):
			var start: int = i
			i += 1
			while i < n and (_is_ident_char(src[i]) or src[i] == "."):
				if src[i] == ".":
					if i + 1 < n and _is_ident_char(src[i + 1]):
						i += 1
					else:
						break
				i += 1
			var word: String = src.substr(start, i - start)
			var upper: String = word.to_upper()
			if "." not in word and upper in _BUILTIN_KEYWORDS:
				tokens.append({type=_BUILTIN_KEYWORDS[upper], value=upper, pos=start})
			elif "." not in word and upper in custom_keywords:
				tokens.append({type=custom_keywords[upper], value=upper, pos=start})
			else:
				tokens.append({type=TokenType.KEY, value=word, pos=start})
			continue
		push_error("[Chronicle] Expression tokenizer: unexpected character '%s' at position %d." % [c, i])
		return []

	tokens.append({type=TokenType.EOF, value="", pos=n})
	return tokens


static func _can_start_negative_with(tokens: Array[Dictionary], negative_start_types: Dictionary) -> bool:
	if tokens.is_empty():
		return true
	return tokens[-1].type in negative_start_types


static func _is_ident_start(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


static func _is_ident_char(c: String) -> bool:
	return _is_ident_start(c) or _is_digit(c)


static func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"
