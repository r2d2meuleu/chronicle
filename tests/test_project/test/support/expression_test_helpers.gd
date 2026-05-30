class_name ExpressionTestHelpers
extends RefCounted

## Parse + evaluate an expression against a facts dict. Returns false if parse fails.
static func run_expr(engine: ChronicleExpressionEngine, expr: String, facts: Dictionary) -> bool:
	var resolver := func(key: String) -> Variant: return facts.get(key, null)
	var ast: Variant = engine.parse(expr)
	if ast == null:
		return false
	return engine.evaluate_ast(ast, resolver)
