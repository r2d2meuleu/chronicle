extends BenchSuite




# 1. Gate eval simple — single key truthy
func test_bench_gate_eval_simple() -> void:
	_chronicle.set_fact("player.alive", true)
	var target: Node2D = add_gate("player.alive")
	guard(target.visible, "gate_eval_simple: gate open while player.alive is true")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		_chronicle.set_fact("player.alive", false)
		_chronicle.set_fact("player.alive", true)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_companion", "gate_eval_simple", 1, "simple", "us/op", stats, samples)
	BenchHelper.print_table("macro/companion :: gate_eval_simple", [{scale_label = "simple", stats = stats}], "toggle player.alive — gate re-evaluates")


# 2. Gate eval complex — multi-key expression
func test_bench_gate_eval_complex() -> void:
	_chronicle.set_fact("player.level", 10)
	_chronicle.set_fact("player.alive", true)
	_chronicle.set_fact("quest.active", true)
	var target: Node2D = add_gate("player.level > 5 AND player.alive AND quest.active")
	guard(target.visible, "gate_eval_complex: gate open when all 3 conditions true")
	# Alternate the level each iteration (10/11 — both keep level > 5 true) so the
	# write genuinely changes and the gate re-evaluates; an unchanged write is a no-op.
	var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("player.level", 10 + (i % 2))
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_companion", "gate_eval_complex", 1, "complex", "us/op", stats, samples)
	BenchHelper.print_table("macro/companion :: gate_eval_complex", [{scale_label = "complex", stats = stats}], "3-key AND expression")


# 3. 10 gates on same fact
func test_bench_gates_10_simultaneous() -> void:
	_chronicle.set_fact("player.health", 100)
	var last_target: Node2D = null
	for i: int in range(10):
		last_target = add_gate("player.health > %d" % (i * 10))
	guard(last_target.visible, "gates_10_simultaneous: gates open at health 100")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		_chronicle.set_fact("player.health", 50)
		_chronicle.set_fact("player.health", 100)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_companion", "gates_10_simultaneous", 10, "10 gates", "us/op", stats, samples)
	BenchHelper.print_table("macro/companion :: gates_10_simultaneous", [{scale_label = "10 gates", stats = stats}])


# 4. 50 gates with varied expressions
func test_bench_gates_50_mixed() -> void:
	for i: int in range(50):
		_chronicle.set_fact("flag_%d" % i, true)
	var flag0_target: Node2D = null
	for i: int in range(50):
		var t: Node2D = add_gate("flag_%d" % i)
		if i == 0:
			flag0_target = t
	guard(flag0_target.visible, "gates_50_mixed: flag_0 gate open while flag_0 true")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		_chronicle.set_fact("flag_0", false)
		_chronicle.set_fact("flag_0", true)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_companion", "gates_50_mixed", 50, "50 gates", "us/op", stats, samples)
	BenchHelper.print_table("macro/companion :: gates_50_mixed", [{scale_label = "50 gates", stats = stats}], "only 1 gate watches flag_0, others are idle")


# 5. Reactor dispatch — 5 reactors on same pattern
func test_bench_reactor_dispatch() -> void:
	_chronicle.set_fact("event.trigger", 0)
	var a_reactor: Node = null
	for _i: int in range(5):
		a_reactor = add_reactor({watch_pattern = "event.trigger", target_method = "on_fact"})
	_chronicle.set_fact("event.trigger", 1)
	guard(a_reactor.get_parent().calls.size() == 1, "reactor_dispatch: reactor fired exactly once on event.trigger")
	var samples: Array[float] = BenchHelper.measure_each(func(i: int) -> void:
		_chronicle.set_fact("event.trigger", i)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_companion", "reactor_dispatch", 5, "5 react", "us/op", stats, samples)
	BenchHelper.print_table("macro/companion :: reactor_dispatch", [{scale_label = "5 react", stats = stats}])


# 6. Reactor with CREATION filter
func test_bench_reactor_creation_filter() -> void:
	var a_reactor: Node = null
	for i: int in range(10):
		a_reactor = add_reactor({watch_pattern = "spawn.*", target_method = "on_fact", react_to = CompanionFactory.ReactTo.CREATION})
	_chronicle.set_fact("spawn.guard_probe", true)
	guard(a_reactor.get_parent().calls.size() == 1, "reactor_creation_filter: reactor fired exactly once on new spawn.* key")
	var counter: Array = [0]
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		counter[0] += 1
		_chronicle.set_fact("spawn.unit_%d" % counter[0], true)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_companion", "reactor_creation_filter", 10, "10 react", "us/op", stats, samples)
	BenchHelper.print_table("macro/companion :: reactor_creation_filter", [{scale_label = "10 react", stats = stats}], "CREATION filter — new keys only")


# 7. Recorder signal → fact pipeline
func test_bench_recorder_signal_to_fact() -> void:
	var parent: Node = add_recorder({trigger_signal = "triggered", fact_key = "record.count", value = true, record_mode = CompanionFactory.RecordMode.ALWAYS})
	parent.emit_signal("triggered")
	guard(_chronicle.has_fact("record.count"), "recorder_signal_to_fact: signal recorded record.count")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		parent.emit_signal("triggered")
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_companion", "recorder_signal_to_fact", 1, "1 rec", "us/op", stats, samples)
	BenchHelper.print_table("macro/companion :: recorder_signal_to_fact", [{scale_label = "1 rec", stats = stats}])


# 8. Mixed companions — realistic scene
func test_bench_mixed_companions() -> void:
	_chronicle.set_fact("player.alive", true)
	_chronicle.set_fact("player.health", 100)
	for i: int in range(10):
		add_gate("player.health > %d" % (i * 10))
	for i: int in range(5):
		add_reactor({watch_pattern = "player.*", target_method = "on_fact"})
	for i: int in range(3):
		var parent: Node = add_recorder({trigger_signal = "tick", fact_key = "tick.count_%d" % i, value = true, record_mode = CompanionFactory.RecordMode.ALWAYS})
		parent.emit_signal("tick")
	guard(_chronicle.has_fact("tick.count_0"), "mixed_companions: recorder wrote tick.count_0")
	var samples: Array[float] = BenchHelper.measure(func() -> void:
		_chronicle.set_fact("player.health", 75)
		_chronicle.set_fact("player.health", 100)
	)
	var stats: Dictionary = BenchHelper.compute_stats(samples)
	BenchResults.record("macro", "bench_companion", "mixed_companions", 18, "10g+5r+3c", "us/op", stats, samples)
	BenchHelper.print_table("macro/companion :: mixed_companions", [{scale_label = "10g+5r+3c", stats = stats}], "10 gates + 5 reactors + 3 recorders")
