extends ChronicleTestSuite

const Parser := preload("res://addons/chronicle/core/expression/parser.gd")
const Lexer := preload("res://addons/chronicle/core/expression/lexer.gd")


# register_type succeeds with valid callables
func test_register_type_success() -> void:
	var result: bool = _chronicle.register_type(TYPE_RID, "TestRID",
		func(v: Variant) -> Dictionary: return {"_chronicle_type": "TestRID", "val": 0},
		func(d: Dictionary) -> Variant: return RID())
	assert_true(result)
	_chronicle.unregister_type(TYPE_RID)


# register_migration callable is invoked on deserialize
func test_register_migration_invoked() -> void:
	var migrated := [false]
	_chronicle.register_migration(0, func(data: Dictionary) -> Dictionary:
		data["version"] = 1
		migrated[0] = true
		return data)
	var old_data := {"version": 0, "facts": {}, "timeline": [], "expiring_facts": {}}
	var ok: bool = _chronicle.deserialize(old_data)
	assert_true(ok)
	assert_true(migrated[0])


# A custom keyword registered via the facade is usable in evaluate()
func test_register_keyword_usable() -> void:
	var node_type := "is_positive"
	var token := Lexer.FIRST_CUSTOM_TOKEN_TYPE
	# Keyword "POSITIVE" produces an AST node whose handler checks the operand > 0.
	var parse_fn := func(_state: Parser.ParseState, operand: Dictionary, negated: bool) -> Variant:
		return {node_type = node_type, operand = operand, negated = negated}
	# Evaluator: truthy when the resolved operand value is a number > 0.
	var eval_fn := func(ast: Dictionary, resolver: Callable) -> bool:
		var v: Variant = resolver.call(ast.operand.value)
		return (v is int or v is float) and v > 0
	var keys_fn := func(ast: Dictionary, keys: Array[String]) -> void:
		keys.append(ast.operand.value)
	var walk_fn := func(_ast: Dictionary, _leaf_fn: Callable) -> void: pass

	assert_true(_chronicle.register_keyword("POSITIVE", token, parse_fn, false),
		"register_keyword should succeed for a fresh keyword")
	assert_true(_chronicle.register_expression_handler(node_type, eval_fn, keys_fn, walk_fn),
		"register_expression_handler should succeed for the custom node type")

	_chronicle.set_fact("score", 5)
	assert_true(_chronicle.evaluate("score POSITIVE"),
		"custom POSITIVE keyword evaluates true for a positive value")

	_chronicle.set_fact("score", -1)
	assert_false(_chronicle.evaluate("score POSITIVE"),
		"custom POSITIVE keyword evaluates false for a non-positive value")

	# Clean up so the static-ish keyword registration does not leak into other tests.
	_chronicle.unregister_keyword("POSITIVE")
	_chronicle.unregister_expression_handler(node_type)


# Unregistering something never registered returns false (idempotent, no error)
func test_unregister_nonexistent_expression_handler_returns_false() -> void:
	assert_false(_chronicle.unregister_expression_handler("never_registered_node"),
		"unregistering a non-existent expression handler returns false")


func test_unregister_nonexistent_keyword_returns_false() -> void:
	assert_false(_chronicle.unregister_keyword("NEVERREGISTEREDKEYWORD"),
		"unregistering a non-existent keyword returns false")


# ── Registration introspection ──

# is_type_registered tracks registration; unregister_type returns true then false
func test_is_type_registered_and_unregister_type() -> void:
	assert_false(_chronicle.is_type_registered(TYPE_RID), "TYPE_RID not registered initially")
	_chronicle.register_type(TYPE_RID, "TestRID2",
		func(_v: Variant) -> Dictionary: return {"_chronicle_type": "TestRID2"},
		func(_d: Dictionary) -> Variant: return RID())
	assert_true(_chronicle.is_type_registered(TYPE_RID), "registered after register_type")
	assert_true(_chronicle.unregister_type(TYPE_RID), "unregister_type returns true when it existed")
	assert_false(_chronicle.is_type_registered(TYPE_RID), "gone after unregister_type")
	assert_false(_chronicle.unregister_type(TYPE_RID), "unregister_type returns false when already gone")


# is_valid_type: built-in storable types are valid; an unregistered Object is not
func test_is_valid_type_builtin_vs_object() -> void:
	assert_true(_chronicle.is_valid_type(42), "int is a valid storable type")
	assert_true(_chronicle.is_valid_type("text"), "String is valid")
	assert_true(_chronicle.is_valid_type(Vector2(1, 2)), "Vector2 is valid")
	assert_false(_chronicle.is_valid_type(RefCounted.new()),
		"an unregistered Object is not a valid storable type")


# is_keyword_registered reflects custom-keyword registration
func test_is_keyword_registered_reflects_registration() -> void:
	assert_false(_chronicle.is_keyword_registered("MYKW"), "MYKW not registered initially")
	var parse_fn := func(_state: Parser.ParseState, operand: Dictionary, negated: bool) -> Variant:
		return {node_type = "mykw_node", operand = operand, negated = negated}
	_chronicle.register_keyword("MYKW", Lexer.FIRST_CUSTOM_TOKEN_TYPE, parse_fn, false)
	assert_true(_chronicle.is_keyword_registered("MYKW"), "registered after register_keyword")
	_chronicle.unregister_keyword("MYKW")
	assert_false(_chronicle.is_keyword_registered("MYKW"), "gone after unregister_keyword")


# is_expression_handler_registered: true for custom handlers, false for built-in/unregistered
func test_is_expression_handler_registered_custom_vs_builtin() -> void:
	assert_false(_chronicle.is_expression_handler_registered("compare"),
		"a built-in handler is not reported as a custom handler")
	assert_false(_chronicle.is_expression_handler_registered("my_custom_node"),
		"an unregistered node type is not registered")
	var eval_fn := func(_ast: Dictionary, _resolver: Callable) -> bool: return true
	var keys_fn := func(_ast: Dictionary, _keys: Array[String]) -> void: pass
	var walk_fn := func(_ast: Dictionary, _leaf_fn: Callable) -> void: pass
	_chronicle.register_expression_handler("my_custom_node", eval_fn, keys_fn, walk_fn)
	assert_true(_chronicle.is_expression_handler_registered("my_custom_node"),
		"custom handler registered")
	_chronicle.unregister_expression_handler("my_custom_node")
	assert_false(_chronicle.is_expression_handler_registered("my_custom_node"),
		"gone after unregister_expression_handler")


# register_type rejects a duplicate tag without force, accepts with force=true
func test_register_type_duplicate_and_force_override() -> void:
	var pack := func(_v: Variant) -> Dictionary: return {"_chronicle_type": "DupRID"}
	var unpack := func(_d: Dictionary) -> Variant: return RID()
	assert_true(_chronicle.register_type(TYPE_RID, "DupRID", pack, unpack),
		"first registration succeeds")
	assert_false(_chronicle.register_type(TYPE_RID, "DupRID", pack, unpack),
		"duplicate registration without force is rejected")
	assert_true(_chronicle.register_type(TYPE_RID, "DupRID", pack, unpack, Callable(), [] as Array[String], Callable(), true),
		"force=true overrides an existing registration")
	_chronicle.unregister_type(TYPE_RID)


# register_simple_expression registers a handler under the keyword's node type
func test_register_simple_expression_registers_handler() -> void:
	var eval_fn := func(_key: String, _arg: Variant, _resolver: Callable) -> bool: return true
	assert_true(_chronicle.register_simple_expression("simplekw", eval_fn),
		"register_simple_expression succeeds for a fresh node type")
	assert_true(_chronicle.is_expression_handler_registered("simplekw"),
		"the handler is registered under the keyword's node type")
	_chronicle.unregister_expression_handler("simplekw")
	assert_false(_chronicle.is_expression_handler_registered("simplekw"), "gone after unregister")
