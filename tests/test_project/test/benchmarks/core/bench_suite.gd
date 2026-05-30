## Base class for all benchmarks. Hoists the common benchmark lifecycle so
## individual bench files don't repeat preloads, the after_all flush, or the
## shared _engine/_noop members. Benchmarks measure performance; correctness is
## checked via cheap guards (see guard()), NOT GUT assertions in hot loops.
class_name BenchSuite
extends ChronicleTestSuite

const BenchHelper := preload("res://test/benchmarks/core/bench_helper.gd")
const BenchResults := preload("res://test/benchmarks/core/bench_results.gd")

## No-op watcher callback reused across watcher benches (avoids per-test lambda alloc).
var _noop: Callable = func(_k: String, _v: Variant, _o: Variant) -> void: pass
## Expression engine for benches that parse/evaluate expressions.
var _engine: ChronicleExpressionEngine


func before_each() -> void:
	super.before_each()
	_engine = ChronicleExpressionEngine.new()


func after_all() -> void:
	BenchResults.flush()


## Correctness guard: assert the timed operation actually worked. Call ONCE after
## setup, BEFORE the measure loop. (Used in a later task; define it now.)
func guard(condition: bool, message: String) -> void:
	assert_true(condition, "[bench guard] %s" % message)


## Populates entity_count entities × props_per facts: "<prefix>_<e>.prop_<p>" = e*props_per+p.
func populate_entities(entity_count: int, props_per: int, prefix: String = "entity") -> void:
	for e: int in range(entity_count):
		for p: int in range(props_per):
			_chronicle.set_fact("%s_%d.prop_%d" % [prefix, e, p], e * props_per + p)
