class_name ScaleHelper
extends RefCounted

const SMALL := {facts = 1000, watchers = 100, timeline_cap = 10000}
const MEDIUM := {facts = 10000, watchers = 500, timeline_cap = 50000}
const LARGE := {facts = 50000, watchers = 1000, timeline_cap = 100000}
const EXTREME := {facts = 100000, watchers = 5000, timeline_cap = 500000}

const VALUE_TYPES := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]


static func generate_entity_facts(chronicle: Node, entity_count: int, keys_per_entity: int) -> int:
	var total := 0
	for e in entity_count:
		for k in keys_per_entity:
			var key := "entity_%d.key_%d" % [e, k]
			var value: Variant = _random_value(e * keys_per_entity + k)
			chronicle.set_fact(key, value)
			total += 1
	return total


static func generate_mixed_type_facts(chronicle: Node, count: int) -> int:
	for i in count:
		var key := "mixed_%d.fact" % i
		match i % 6:
			0: chronicle.set_fact(key, i % 2 == 0)
			1: chronicle.set_fact(key, i)
			2: chronicle.set_fact(key, float(i) * 0.1)
			3: chronicle.set_fact(key, "val_%d" % i)
			4: chronicle.set_fact(key, [i, i + 1, i + 2])
			5: chronicle.set_fact(key, {"n": i, "label": "item_%d" % i})
	return count


static func generate_nested_value(depth: int, width: int) -> Dictionary:
	if depth <= 0:
		return {"leaf": true, "val": 42}
	var result := {}
	for w in width:
		result["branch_%d" % w] = generate_nested_value(depth - 1, width)
	return result


static func generate_keyed_facts(chronicle: Node, prefix: String, count: int, value: Variant = true) -> void:
	for i in count:
		chronicle.set_fact("%s_%d" % [prefix, i], value)


static func time_callable(callable: Callable) -> float:
	var start := Time.get_ticks_usec()
	callable.call()
	return float(Time.get_ticks_usec() - start)


static func time_callable_runs(callable: Callable, runs: int) -> Dictionary:
	var samples: Array[float] = []
	for i in runs:
		samples.append(time_callable(callable))
	samples.sort()
	var total := 0.0
	for s in samples:
		total += s
	return {
		mean_us = total / samples.size(),
		min_us = samples[0],
		max_us = samples[-1],
		p50_us = samples[samples.size() / 2],
		p99_us = samples[int(samples.size() * 0.99)],
	}


static func setup_timeline_cap(chronicle: Node, cap: int) -> void:
	chronicle.set_timeline_cap(cap)


static func _random_value(seed_val: int) -> Variant:
	match seed_val % 4:
		0: return seed_val % 2 == 0
		1: return seed_val
		2: return float(seed_val) * 0.5
		_: return "val_%d" % seed_val
	return null
