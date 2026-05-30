extends GutTest


func test_dedup_suppresses_repeat_messages() -> void:
	var emitted: Array[String] = []
	var bus := ChronicleWarningBus.new(func(msg: String) -> void: emitted.append(msg))
	bus.warn("test message")
	bus.warn("test message")
	assert_eq(emitted.size(), 1, "Duplicate message should be suppressed")

func test_different_messages_both_fire() -> void:
	var emitted: Array[String] = []
	var bus := ChronicleWarningBus.new(func(msg: String) -> void: emitted.append(msg))
	bus.warn("message A")
	bus.warn("message B")
	assert_eq(emitted.size(), 2, "Both unique messages should be emitted")

func test_clear_resets_dedup() -> void:
	var emitted: Array[String] = []
	var bus := ChronicleWarningBus.new(func(msg: String) -> void: emitted.append(msg))
	bus.warn("cleared message")
	assert_eq(emitted.size(), 1)
	bus.clear()
	bus.warn("cleared message")
	assert_eq(emitted.size(), 2, "Message should fire again after clear")

func test_cap_prevents_unbounded_growth() -> void:
	var bus := ChronicleWarningBus.new()
	for i in range(600):
		bus.warn("msg_%d" % i)
	assert_eq(bus._dedup.size(), 500, "Dedup dict should be capped at 500")


func test_suppressed_count_tracks_after_cap() -> void:
	var bus := ChronicleWarningBus.new()
	for i: int in range(600):
		bus.warn("msg_%d" % i)
	assert_eq(bus._suppressed_count, 100, "600 distinct warnings past the 500-entry dedup cap → 100 suppressed")


func test_clear_resets_suppressed_count() -> void:
	var bus := ChronicleWarningBus.new()
	for i: int in range(550):
		bus.warn("msg_%d" % i)
	assert_eq(bus._suppressed_count, 50, "550 distinct warnings past the 500-entry dedup cap → 50 suppressed")
	bus.clear()
	assert_eq(bus._suppressed_count, 0, "clear() resets the suppressed counter to 0")


# Warning bus deduplicates identical messages
func test_warning_bus_dedup() -> void:
	var output: Array[String] = []
	var bus := ChronicleWarningBus.new(func(msg: String) -> void: output.append(msg))
	bus.warn("same message")
	bus.warn("same message")
	bus.warn("same message")
	assert_eq(output.size(), 1, "Duplicate warnings should be suppressed")
	assert_string_contains(output[0], "same message", "First warning should pass through")
