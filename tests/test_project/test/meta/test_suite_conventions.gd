extends GutTest

## Self-policing convention enforcement. Scans every test/*.gd file and FAILS on any
## reintroduced anti-pattern. Sanctioned exceptions: a trailing "# meta-allow:<rule>"
## comment on the offending line.
##
## Rules: true-tautology | has-membership | ordering | null-compare | audit-prefix | bench-guard
##
## The assert-argument rules use a real first-argument ANALYZER (not a fragile regex):
## extract the assert's first argument (paren/bracket/string-balanced), strip string
## literals (so an operator INSIDE a string like _run_expr("x > 4") cannot trigger a
## false positive), skip compound predicates (and/or/is — a conjunction cannot collapse
## to a single dedicated assertion), then classify what remains. This catches digit-led
## (`1 > 0`) and indexed (`arr[0] > b`) comparisons the old regex missed, with zero
## string/compound false positives by construction.

const SCAN_ROOT := "res://test"

# ── File walking ─────────────────────────────────────────────────────────────

func _gd_files(root: String, out: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var nm := dir.get_next()
	while nm != "":
		var path := root + "/" + nm
		if dir.current_is_dir():
			if not nm.begins_with("."):
				_gd_files(path, out)
		elif nm.ends_with(".gd") and path != get_script().resource_path:
			out.append(path)
		nm = dir.get_next()
	dir.list_dir_end()

func _all_files() -> Array:
	var files: Array = []
	_gd_files(SCAN_ROOT, files)
	return files

func _lines(path: String) -> PackedStringArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedStringArray()
	return f.get_as_text().split("\n")

# ── First-argument analyzer ──────────────────────────────────────────────────

## Returns the first argument of the first `assert_true(`/`assert_false(` call on the
## line (balanced over () [] {} and string literals, up to the top-level comma), or the
## "<NONE>" sentinel when the line has no such call.
func _assert_first_arg(line: String) -> String:
	var marker := "assert_true("
	var idx := line.find(marker)
	if idx < 0:
		marker = "assert_false("
		idx = line.find(marker)
	if idx < 0:
		return "<NONE>"
	var i := idx + marker.length()
	var depth := 0
	var arg := ""
	var in_str := false
	var quote := ""
	while i < line.length():
		var ch := line[i]
		if in_str:
			arg += ch
			if ch == quote and line[i - 1] != "\\":
				in_str = false
		elif ch == "\"" or ch == "'":
			in_str = true
			quote = ch
			arg += ch
		elif ch == "(" or ch == "[" or ch == "{":
			depth += 1
			arg += ch
		elif ch == ")" or ch == "]" or ch == "}":
			if ch == ")" and depth == 0:
				break
			depth -= 1
			arg += ch
		elif ch == "," and depth == 0:
			break
		else:
			arg += ch
		i += 1
	return arg.strip_edges()

## Remove string-literal contents from an expression, so operators/keywords inside
## strings can't be mistaken for code.
func _strip_strings(s: String) -> String:
	var out := ""
	var in_str := false
	var quote := ""
	var i := 0
	while i < s.length():
		var ch := s[i]
		if in_str:
			if ch == quote and (i == 0 or s[i - 1] != "\\"):
				in_str = false
		elif ch == "\"" or ch == "'":
			in_str = true
			quote = ch
		else:
			out += ch
		i += 1
	return out

## Reduce an expression to its TOP-LEVEL tokens: drop everything nested inside ()/[]/{}
## (keeping the outermost bracket pair as empty markers). An operator nested inside a
## function-call argument or lambda is part of THAT call's logic, not the assertion's
## shape — so only top-level operators indicate an anti-pattern. This is what makes
## `h.size() > 0` (top-level `>`) a hit while `.all(func(v): return v != null)` (nested
## `!= null`) and `evaluate_ast(ast, func() -> Variant: ...)` (nested `->`) are not.
func _top_level(s: String) -> String:
	var out := ""
	var depth := 0
	for i in range(s.length()):
		var ch := s[i]
		if ch == "(" or ch == "[" or ch == "{":
			if depth == 0:
				out += ch
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth -= 1
			if depth == 0:
				out += ch
		elif depth == 0:
			out += ch
	return out

## A compound predicate (boolean conjunction / type test) cannot collapse to one
## dedicated assertion, so it is never an anti-pattern.
func _is_compound(stripped: String) -> bool:
	return stripped.contains(" and ") or stripped.contains(" or ") or stripped.contains(" is ")

func _is_comment(line: String) -> bool:
	return line.strip_edges().begins_with("#")

## Scan all files, applying classify(stripped_arg) -> bool to the analyzed first
## argument of each assert_true/false. Honors "# meta-allow:<rule>".
func _scan_arg(rule: String, classify: Callable) -> Array:
	var hits: Array = []
	for path in _all_files():
		var lines := _lines(path)
		for i in range(lines.size()):
			var line: String = lines[i]
			if _is_comment(line) or line.contains("# meta-allow:" + rule):
				continue
			var arg := _assert_first_arg(line)
			if arg == "<NONE>":
				continue
			# string-strip → top-level reduce → drop lambda arrows, then classify
			var reduced := _top_level(_strip_strings(arg)).replace("->", " ").strip_edges()
			if classify.call(reduced):
				hits.append("%s:%d  %s" % [path, i + 1, line.strip_edges()])
	return hits

# ── Rules ────────────────────────────────────────────────────────────────────

func test_no_assert_true_literal() -> void:
	var hits := _scan_arg("true-tautology", func(s: String) -> bool: return s == "true")
	assert_eq(hits.size(), 0, "assert_true(true) is a tautology — use pass_test(\"why\"):\n%s" % "\n".join(hits))

func test_no_membership_via_assert_true() -> void:
	# `<ident-or-indexed>.has(` in the analyzed arg. Object-method .has() on a RefCounted
	# (ChronicleStore/ChronicleExpiry/etc.) is exempt via "# meta-allow:has-membership".
	var re := RegEx.new()
	re.compile("[A-Za-z_][A-Za-z0-9_.\\[\\]]*\\.has\\(")
	var hits := _scan_arg("has-membership", func(s: String) -> bool:
		return not _is_compound(s) and (re.search(s) != null or (" " + s + " ").contains(" in ")))
	assert_eq(hits.size(), 0, "use assert_has/assert_does_not_have for Dict/Array membership — via `.has()` OR the `in` operator (legitimate String containment may use `# meta-allow:has-membership`):\n%s" % "\n".join(hits))

func test_no_ordering_via_assert_true() -> void:
	# A relational operator surviving in the (string-stripped, non-compound) first arg.
	var re := RegEx.new()
	re.compile("(>=|<=|[<>])")
	var hits := _scan_arg("ordering", func(s: String) -> bool:
		return not _is_compound(s) and re.search(s) != null)
	assert_eq(hits.size(), 0, "use assert_gt/gte/lt/lte/between for ordering:\n%s" % "\n".join(hits))

func test_no_null_compare_via_assert_true() -> void:
	var re := RegEx.new()
	re.compile("(!=|==)\\s*null|null\\s*(!=|==)")
	var hits := _scan_arg("null-compare", func(s: String) -> bool:
		return not _is_compound(s) and re.search(s) != null)
	assert_eq(hits.size(), 0, "use assert_not_null/assert_null:\n%s" % "\n".join(hits))

func test_no_audit_prefix_names() -> void:
	var re := RegEx.new()
	re.compile("func (test_(bug[0-9]|edge[0-9]|a[0-9]+_|x[0-9]+_|h[0-9]+_|e[0-9]+_|tc[0-9]|r[0-9]+_))")
	var hits: Array = []
	for path in _all_files():
		var lines := _lines(path)
		for i in range(lines.size()):
			if lines[i].contains("# meta-allow:audit-prefix"):
				continue
			var m := re.search(lines[i])
			if m != null:
				hits.append("%s:%d  %s" % [path, i + 1, m.get_string(1)])
	assert_eq(hits.size(), 0, "audit-code prefixes are banned — use descriptive names:\n%s" % "\n".join(hits))

func test_every_bench_function_is_guarded() -> void:
	var files: Array = []
	_gd_files("res://test/benchmarks", files)
	var unguarded: Array = []
	for path in files:
		if not path.get_file().begins_with("bench_"):
			continue
		var lines := _lines(path)
		var i := 0
		while i < lines.size():
			var stripped := lines[i].strip_edges()
			if stripped.begins_with("func test_"):
				var body := ""
				var j := i + 1
				while j < lines.size() and not lines[j].begins_with("func "):
					body += lines[j] + "\n"
					j += 1
				if not (body.contains("guard(") or body.contains("run_scale_bench(")):
					unguarded.append("%s:%d  %s" % [path, i + 1, stripped])
				i = j
			else:
				i += 1
	assert_eq(unguarded.size(), 0, "every benchmark must prove its workload (guard()/run_scale_bench()):\n%s" % "\n".join(unguarded))
