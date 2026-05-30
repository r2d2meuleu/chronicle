extends ChronicleTestSuite


# Zero lifetime removes expiry
func test_zero_removes_expiry() -> void:
	_chronicle.set_fact("buff", true, false, 10.0)
	assert_has_expiry("buff")
	_chronicle.set_expiry("buff", 0.0)
	assert_no_expiry("buff")


# Nonexistent key is a no-op
func test_nonexistent_key_no_op() -> void:
	_chronicle.set_expiry("ghost", 5.0)
	assert_no_fact("ghost")


# Changes remaining time
func test_changes_remaining_time() -> void:
	_chronicle.set_fact("buff", true, false, 10.0)
	_chronicle.set_expiry("buff", 20.0)
	# set_expiry resets the timer to 20.0 from the current clock (0.0).
	assert_almost_eq(_chronicle.get_expiry_remaining("buff"), 20.0, 0.01)


# Negative lifetime is rejected
func test_negative_lifetime_rejected() -> void:
	_chronicle.set_fact("buff", true, false, 10.0)
	_chronicle.set_expiry("buff", -5.0)
	assert_has_expiry("buff")
	# The original 10.0s timer must be preserved — the rejected call is a no-op.
	assert_almost_eq(_chronicle.get_expiry_remaining("buff"), 10.0, 0.01,
		"rejected negative lifetime must not alter the existing timer")


# Adds expiry to a permanent fact
func test_adds_to_permanent_fact() -> void:
	_chronicle.set_fact("perm", true)
	assert_no_expiry("perm")
	_chronicle.set_expiry("perm", 5.0)
	assert_has_expiry("perm")


# set_expiry followed by rollback reverts the expiry
func test_set_expiry_rollback_reverts() -> void:
	set_time(1.0)
	_chronicle.set_fact("item", "sword")
	set_time(2.0)
	_chronicle.set_expiry("item", 5.0)
	assert_has_expiry("item")
	_chronicle.rollback_to(1.5)
	assert_no_expiry("item")


# set_expiry with same lifetime is a no-op (no new timeline entry)
func test_set_expiry_same_lifetime_noop() -> void:
	set_time(1.0)
	_chronicle.set_fact("item", "sword")
	_chronicle.set_expiry("item", 5.0)
	var history_before: Array = _chronicle.get_fact_history("item")
	_chronicle.set_expiry("item", 5.0)
	var history_after: Array = _chronicle.get_fact_history("item")
	assert_eq(history_before.size(), history_after.size(), "No new timeline entry for same expiry")


# set_expiry rejects an INF/NaN lifetime (returns false, emits push_error)
func test_set_expiry_inf_lifetime_returns_false() -> void:
	_chronicle.set_fact("inf.fact", 1)
	assert_false(_chronicle.set_expiry("inf.fact", INF), "INF lifetime is rejected")
	assert_no_expiry("inf.fact")


# set_expiry on a nonexistent fact returns false
func test_set_expiry_nonexistent_fact_returns_false() -> void:
	assert_false(_chronicle.set_expiry("nonexistent.fact", 5.0),
		"set_expiry on a fact that does not exist returns false")
