extends BenchSuite

const Lexer := preload("res://addons/chronicle/core/expression/lexer.gd")

const SIMPLE_EXPR: String = "player.health > 50"
const COMPLEX_EXPR: String = "player.alive AND quest.active OR (player.level > 5 AND player.class IN [1, 2, 3])"


func _make_resolver() -> Callable:
	return func(key: String) -> Variant:
		return _chronicle.get_fact(key, null)


# 1. Tokenize simple expression
func test_bench_tokenize_simple() -> void:
	guard(Lexer.tokenize(SIMPLE_EXPR).size() > 0, "tokenize_simple: produced tokens")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _t: Array = Lexer.tokenize(SIMPLE_EXPR)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_expression", "tokenize_simple", 1, "simple", "us/op", stats, samples)
	BenchHelper.print_table("micro/expression :: tokenize_simple", [{scale_label = "simple", stats = stats}], SIMPLE_EXPR)


# 2. Tokenize complex expression
func test_bench_tokenize_complex() -> void:
	guard(Lexer.tokenize(COMPLEX_EXPR).size() > 0, "tokenize_complex: produced tokens")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _t: Array = Lexer.tokenize(COMPLEX_EXPR)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_expression", "tokenize_complex", 1, "complex", "us/op", stats, samples)
	BenchHelper.print_table("micro/expression :: tokenize_complex", [{scale_label = "complex", stats = stats}], COMPLEX_EXPR)


# 3. Parse simple — single comparison
func test_bench_parse_simple() -> void:
	guard(_engine.parse(SIMPLE_EXPR) != null, "parse_simple: AST produced")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _ast: Variant = _engine.parse(SIMPLE_EXPR)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_expression", "parse_simple", 1, "simple", "us/op", stats, samples)
	BenchHelper.print_table("micro/expression :: parse_simple", [{scale_label = "simple", stats = stats}])


# 4. Parse complex — nested AND/OR with 5 keys
func test_bench_parse_complex() -> void:
	guard(_engine.parse(COMPLEX_EXPR) != null, "parse_complex: AST produced")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _ast: Variant = _engine.parse(COMPLEX_EXPR)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_expression", "parse_complex", 1, "complex", "us/op", stats, samples)
	BenchHelper.print_table("micro/expression :: parse_complex", [{scale_label = "complex", stats = stats}])


# 5. Evaluate simple — 1 key lookup + 1 compare
func test_bench_evaluate_simple() -> void:
	_chronicle.set_fact("player.health", 75)
	var ast: Variant = _engine.parse(SIMPLE_EXPR)
	var resolver: Callable = _make_resolver()
	guard(_engine.evaluate_ast(ast, resolver) == true, "evaluate_simple: health 75 > 50 is true")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _r: bool = _engine.evaluate_ast(ast, resolver)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_expression", "evaluate_simple", 1, "simple", "us/op", stats, samples)
	BenchHelper.print_table("micro/expression :: evaluate_simple", [{scale_label = "simple", stats = stats}])


# 6. Evaluate complex — 5 key lookups + nested logic
func test_bench_evaluate_complex() -> void:
	_chronicle.set_fact("player.alive", true)
	_chronicle.set_fact("quest.active", false)
	_chronicle.set_fact("player.level", 10)
	_chronicle.set_fact("player.class", 2)
	var ast: Variant = _engine.parse(COMPLEX_EXPR)
	var resolver: Callable = _make_resolver()
	guard(_engine.evaluate_ast(ast, resolver) == true, "evaluate_complex: expression evaluates true")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _r: bool = _engine.evaluate_ast(ast, resolver)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_expression", "evaluate_complex", 1, "complex", "us/op", stats, samples)
	BenchHelper.print_table("micro/expression :: evaluate_complex", [{scale_label = "complex", stats = stats}])


# 7. Extract keys from complex AST
func test_bench_extract_keys() -> void:
	var ast: Variant = _engine.parse(COMPLEX_EXPR)
	guard(_engine.extract_keys(ast).size() > 0, "extract_keys: keys extracted from AST")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		var _keys: Array = _engine.extract_keys(ast)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("micro", "bench_expression", "extract_keys", 1, "complex", "us/op", stats, samples)
	BenchHelper.print_table("micro/expression :: extract_keys", [{scale_label = "complex", stats = stats}])
