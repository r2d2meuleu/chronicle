extends GutTest

# Tests for ChronicleValueUtils (deep_copy, truthiness, value helpers).
# Moved out of test_key_codec.gd — these test ValueUtils, not the key codec.


# compute_clamp does not validate min <= max
func test_compute_clamp_inverted_range() -> void:
	# clampf(5.0, 10.0, 1.0) — min > max. Godot's clampf returns min (10.0).
	var result: Variant = ChronicleValueUtils.compute_clamp(5, 10.0, 1.0)
	# This silently clamps to the min value, which is arguably wrong
	assert_eq(result, 10,
		"Inverted range: Godot clampf returns min, but this is likely a user error")


# _as_int_if_whole precision edge case with large floats
func test_as_int_precision_large_float() -> void:
	# 0 + 2^53 is exactly representable in both float and int, so the increment
	# produces the precise integer value (no precision loss at this boundary).
	var large: float = pow(2.0, 53.0)
	var result: Variant = ChronicleValueUtils.compute_increment(0, large)
	assert_eq(result, 9007199254740992,
		"0 + 2^53 is exactly representable — increment yields the exact integer")


# deep_copy creates independent nested copies
func test_deep_copy_nested_independence() -> void:
	var inner: Array = [1, 2, 3]
	var outer: Array = [inner, {"nested": inner}]
	var copy: Variant = ChronicleValueUtils.deep_copy(outer)
	# Mutate the original inner array
	inner.append(4)
	assert_eq((copy[0] as Array).size(), 3,
		"deep_copy should be independent of original")
	assert_eq(((copy[1] as Dictionary)["nested"] as Array).size(), 3,
		"nested dict values should also be independent")


# compute_clamp rejects NaN current value
func test_compute_clamp_nan_current() -> void:
	var result: Variant = ChronicleValueUtils.compute_clamp(NAN, 0.0, 10.0)
	assert_null(result, "NaN current should return null")


# compute_increment with NaN amount
func test_compute_increment_nan_amount() -> void:
	var result: Variant = ChronicleValueUtils.compute_increment(5, NAN)
	assert_null(result, "NaN amount should produce null (NaN result detected)")


# safe_copy does not forward custom_copy_fn — nested custom objects alias
func test_safe_copy_does_not_forward_custom_copy_fn() -> void:
	# Simulate a custom mutable object as a Reference (RefCounted subclass).
	# deep_copy falls through to: if custom_copy_fn.is_valid(): return custom_copy_fn.call(value)
	# safe_copy calls deep_copy WITHOUT custom_copy_fn, so custom objects return as-is.
	var custom_obj := RefCounted.new()
	var arr: Array = [custom_obj]

	# safe_copy with a valid custom_copy_fn argument — not possible via safe_copy's API.
	# We call deep_copy directly with a copy fn to show what safe_copy SHOULD do:
	# Use an Array to capture by reference (GDScript lambdas capture primitives by value).
	var copy_count: Array[int] = [0]
	var custom_fn := func(_v: Variant) -> Variant:
		copy_count[0] += 1
		return RefCounted.new()  # New distinct instance

	# deep_copy WITH custom_copy_fn copies the object (count increments):
	ChronicleValueUtils.deep_copy(arr, 64, custom_fn)
	assert_eq(copy_count[0], 1,
		"deep_copy with custom_copy_fn should call it for the custom object")

	# safe_copy does NOT forward custom_copy_fn, so the object is aliased:
	copy_count[0] = 0
	var safe_result: Variant = ChronicleValueUtils.safe_copy(arr)
	assert_eq(copy_count[0], 0,
		"safe_copy does not forward custom_copy_fn — custom object is NOT copied")
	# The nested custom_obj is aliased: safe_result[0] is the same object as custom_obj.
	assert_eq((safe_result as Array)[0], custom_obj,
		"safe_copy returns a reference alias for the nested custom object — not a deep copy")


# compute_clamp preserves int type when already in range
func test_compute_clamp_preserves_int_when_in_range() -> void:
	var result: Variant = ChronicleValueUtils.compute_clamp(5, 0.0, 10.0)
	# 5 is already in [0, 10], so current is returned unchanged.
	assert_eq(result, 5, "in-range int should be returned unchanged")
	assert_true(result is int, "int identity must be preserved (not cast to float)")


# compute_clamp on an int that equals the boundary — still returns int
func test_compute_clamp_int_at_boundary() -> void:
	var result: Variant = ChronicleValueUtils.compute_clamp(10, 0.0, 10.0)
	# clampf(10.0, 0.0, 10.0) == 10.0 == float(10), so current (int 10) is returned.
	assert_eq(result, 10, "int at boundary should be returned unchanged")
	assert_true(result is int, "type must stay int at boundary")


# Beyond max_depth, deep_copy returns the nested value UNCOPIED (shared reference)
func test_deep_copy_beyond_max_depth_shares_refs() -> void:
	var v: Dictionary = {"a": {"b": {"c": 1}}}
	var copy: Dictionary = ChronicleValueUtils.deep_copy(v, 1)
	v["a"]["b"]["c"] = 999
	assert_eq(copy["a"]["b"]["c"], 999, "beyond max_depth, nested refs are shared, not deep-copied")


# compute_increment returns null when the result overflows to INF
func test_compute_increment_overflow_returns_null() -> void:
	assert_null(ChronicleValueUtils.compute_increment(1.7e308, 1.7e308),
		"increment overflowing to INF should return null")
