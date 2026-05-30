extends ChronicleTestSuite


# User-triggered erase fires fact_changed with EraseSource.USER
func test_user_erase_source() -> void:
	_chronicle.set_fact("x", 1)
	# collect_signal DROPS the 4th erase_source arg, so capture the raw tuple via
	# collect_any_signal to assert (key, value, old_value, erase_source).
	var c := collect_any_signal(_chronicle, "fact_changed")
	_chronicle.erase_fact("x")
	c.assert_emission_count(1)
	c.assert_emission_args(0, ["x", null, 1, Chronicle.EraseSource.USER])


# Rollback-triggered erase fires fact_changed with EraseSource.ROLLBACK
func test_rollback_erase_source() -> void:
	set_time(1.0)
	_chronicle.set_fact("x", 1)
	set_time(2.0)
	_chronicle.set_fact("x", 2)
	var c := collect_any_signal(_chronicle, "fact_changed")
	# rollback_to(1.0) reverts the t=2 write, restoring x=1 (from 2).
	_chronicle.rollback_to(1.0)
	c.assert_emission_count(1)
	c.assert_emission_args(0, ["x", 1, 2, Chronicle.EraseSource.ROLLBACK])
