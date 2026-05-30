extends BenchSuite

const SCALES: Array[int] = [1000, 10000, 50000]
const LABELS: Array[String] = ["1K", "10K", "50K"]


# 1. Light frame — platformer/puzzle game
func test_bench_light_frame() -> void:
	# Per-frame counter so position/state writes genuinely change each frame (a real
	# frame moves the player) — a constant write is short-circuited and measures a no-op.
	var f: Array[int] = [0]
	BenchHelper.run_scale_bench("macro", "bench_game_frame", "light_frame", "us/frame",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			populate_entities(scale / 10, 10)
			f[0] = 0,
		func() -> void:
			f[0] += 1
			_chronicle.set_fact("player.x", 100.0 + f[0])
			_chronicle.set_fact("player.y", 200.0 + f[0])
			_chronicle.set_fact("player.state", "running" if f[0] % 2 == 0 else "idle")
			var _a: Variant = _chronicle.get_fact("player.x")
			var _b: Variant = _chronicle.get_fact("player.y")
			var _c: Array = _chronicle.get_fact_keys("player.*")
			var _d: bool = _chronicle.is_marked("player.alive"),
		BenchHelper.TableKind.FRAME, 0, "",
		func(scale: int) -> void:
			guard(_chronicle.count_facts("*") == scale, "light_frame: scale populated to %d facts" % scale))


# 2. Medium frame — action RPG
func test_bench_medium_frame() -> void:
	# Per-frame counter so every per-frame field genuinely changes each frame — constant
	# writes are short-circuited and would measure no-ops instead of real frame cost.
	var f: Array[int] = [0]
	BenchHelper.run_scale_bench("macro", "bench_game_frame", "medium_frame", "us/frame",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			populate_entities(scale / 10, 10)
			_chronicle.set_fact("player.health", 100)
			f[0] = 0,
		func() -> void:
			f[0] += 1
			_chronicle.set_fact("player.x", 150.0 + f[0])
			_chronicle.set_fact("player.y", 250.0 + f[0])
			_chronicle.set_fact("player.state", "attacking" if f[0] % 2 == 0 else "blocking")
			_chronicle.set_fact("enemy_0.health", 50 + f[0])
			_chronicle.set_fact("enemy_0.state", "hit" if f[0] % 2 == 0 else "idle")
			_chronicle.set_fact("combat.active", f[0] % 2 == 0)
			_chronicle.set_fact("combat.round", f[0])
			_chronicle.set_fact("ui.dirty", f[0] % 2 == 0)
			var _a: Variant = _chronicle.get_fact("player.health")
			var _b: Variant = _chronicle.get_fact("player.x")
			var _c: Variant = _chronicle.get_fact("enemy_0.health")
			var _d: Variant = _chronicle.get_fact("combat.active")
			var _e: Variant = _chronicle.get_fact("ui.dirty")
			var _f: Array = _chronicle.get_fact_keys("enemy_0.*")
			var _g: Array = _chronicle.get_fact_keys("player.*")
			var _h: bool = _chronicle.is_marked("combat.active")
			var _i: bool = _chronicle.is_marked("player.alive")
			var _j: bool = _chronicle.is_marked("ui.dirty")
			_chronicle.increment_fact("player.score"),
		BenchHelper.TableKind.FRAME, 0, "",
		func(_scale: int) -> void:
			guard(_chronicle.get_fact("player.health") == 100, "medium_frame: setup wrote player.health"))


# 3. Heavy frame — complex strategy game
func test_bench_heavy_frame() -> void:
	# Per-frame counter so the 20 unit positions genuinely move each frame — constant
	# writes are short-circuited and would measure no-ops instead of real movement cost.
	var f: Array[int] = [0]
	BenchHelper.run_scale_bench("macro", "bench_game_frame", "heavy_frame", "us/frame",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			populate_entities(scale / 10, 10)
			_chronicle.set_game_time(10.0)
			f[0] = 0,
		func() -> void:
			f[0] += 1
			for i: int in range(20):
				_chronicle.set_fact("unit_%d.pos" % i, i * 10 + f[0])
			for i: int in range(10):
				var _v: Variant = _chronicle.get_fact("unit_%d.pos" % i)
			for i: int in range(5):
				var _r: Array = _chronicle.get_fact_keys("unit_%d.*" % i)
			var _all: Array = _chronicle.get_fact_keys("*")
			for i: int in range(5):
				var _m: bool = _chronicle.is_marked("unit_%d.alive" % i)
			_chronicle.increment_fact("turn.count")
			_chronicle.increment_fact("resources.gold", 5.0)
			_chronicle.increment_fact("resources.wood", 2.0)
			var _c: Array = _chronicle.get_changes_since(9.0),
		BenchHelper.TableKind.FRAME, 0, "",
		func(scale: int) -> void:
			guard(_chronicle.count_facts("*") == scale, "heavy_frame: scale populated to %d facts" % scale))


# 4. Dialogue frame — NPC dialogue tick with gate evaluations
func test_bench_dialogue_frame() -> void:
	var conditions: Array[String] = [
		"player.reputation > 50",
		"quest.intro_done AND player.level > 3",
		"npc.mood IN [1, 2, 3]",
	]
	var asts: Array = []
	for cond: String in conditions:
		asts.append(_engine.parse(cond))
	var resolver: Callable = func(key: String) -> Variant:
		return _chronicle.get_fact(key, null)
	# Per-frame counter so the dialogue line advances each frame — a constant write is
	# short-circuited and would measure a no-op instead of the real per-frame write.
	var f: Array[int] = [0]
	BenchHelper.run_scale_bench("macro", "bench_game_frame", "dialogue_frame", "us/frame",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			populate_entities(scale / 10, 10)
			_chronicle.set_fact("player.reputation", 75)
			_chronicle.set_fact("quest.intro_done", true)
			_chronicle.set_fact("player.level", 5)
			_chronicle.set_fact("npc.mood", 2)
			f[0] = 0,
		func() -> void:
			f[0] += 1
			_chronicle.set_fact("dialogue.line", f[0])
			var _a: bool = _chronicle.is_marked("quest.intro_done")
			var _b: bool = _chronicle.is_marked("player.alive")
			var _c: bool = _chronicle.is_marked("npc.available")
			var _d: bool = _chronicle.is_marked("dialogue.active")
			var _e: bool = _chronicle.is_marked("player.in_range")
			for ast: Variant in asts:
				var _r: bool = _engine.evaluate_ast(ast, resolver),
		BenchHelper.TableKind.FRAME, 0, "",
		func(_scale: int) -> void:
			guard(_chronicle.get_fact("player.reputation") == 75, "dialogue_frame: setup wrote player.reputation"))


# 5. Combat frame — high-frequency with cascades
func test_bench_combat_frame() -> void:
	var noop: Callable = func(_k: String, _v: Variant, _o: Variant) -> void: pass
	# Monotonic frame counter so the cascade source (combat.dmg_dealt) changes every
	# frame — a constant write is short-circuited and the 3-deep cascade never fires.
	var dmg_counter: Array = [0]
	var actions: Array[String] = ["strike", "block", "dodge"]
	BenchHelper.run_scale_bench("macro", "bench_game_frame", "combat_frame", "us/frame",
		SCALES, LABELS,
		func(scale: int) -> void:
			_chronicle.clear()
			populate_entities(scale / 10, 10)
			_chronicle.set_fact("combat.dmg_dealt", 0)
			_chronicle.watch("combat.dmg_dealt", func(_k: String, _v: Variant, _o: Variant) -> void:
				_chronicle.set_fact("combat.total_dmg", _v))
			_chronicle.watch("combat.total_dmg", func(_k: String, _v: Variant, _o: Variant) -> void:
				_chronicle.set_fact("ui.dmg_display", _v))
			_chronicle.watch("ui.dmg_display", noop),
		func() -> void:
			dmg_counter[0] += 1
			# Cycle each attacker's action every frame (real games vary actions) — a
			# constant action write is short-circuited and would measure a no-op.
			for i: int in range(10):
				_chronicle.set_fact("attacker_%d.action" % i, actions[(i + dmg_counter[0]) % actions.size()])
			for i: int in range(5):
				_chronicle.increment_fact("attacker_%d.hits" % i)
			# Transient per-frame temps: write them so the end-of-frame erase does real
			# index/timeline work (previously these keys were never set — erase was a no-op).
			_chronicle.set_fact("combat.temp_0", true)
			_chronicle.set_fact("combat.temp_1", true)
			_chronicle.erase_fact("combat.temp_0")
			_chronicle.erase_fact("combat.temp_1")
			for i: int in range(10):
				var _v: Variant = _chronicle.get_fact("attacker_%d.action" % i)
			_chronicle.set_fact("combat.dmg_dealt", 25 + dmg_counter[0]),
		BenchHelper.TableKind.FRAME, 0, "",
		func(_scale: int) -> void:
			guard(_chronicle.has_fact("combat.dmg_dealt"), "combat_frame: cascade source combat.dmg_dealt set up"))
