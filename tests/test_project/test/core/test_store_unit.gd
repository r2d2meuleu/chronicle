extends GutTest

const KeyCodec := preload("res://addons/chronicle/core/key_codec.gd")
const ChronicleStore := preload("res://addons/chronicle/core/store.gd")


# Without copy_fn, _copy falls back to value.duplicate() (a shallow copy), so
# mutating the returned TOP-LEVEL container does not affect the store.
func test_set_get_isolation_via_get_copy() -> void:
	var store := ChronicleStore.new()
	store.set_value("key", [1, 2, 3])
	var retrieved: Array = store.get_value("key")
	retrieved.append(4)
	assert_eq((store.get_value("key") as Array).size(), 3,
		"mutating the returned top-level array must not affect the store (shallow copy)")


# get_value returns a fresh top-level container each call (shallow duplicate).
func test_get_returns_copy() -> void:
	var store := ChronicleStore.new()
	store.set_value("key", [1, 2, 3])
	var a: Array = store.get_value("key")
	a.clear()
	assert_eq((store.get_value("key") as Array).size(), 3,
		"clearing the returned array must not affect the store (shallow copy)")


# set_value copies its INPUT, so mutating the caller's container after the write
# does not leak into the store (input-side defensive copy).
func test_set_value_copies_input() -> void:
	var store := ChronicleStore.new()
	var arr := [1, 2, 3]
	store.set_value("k", arr)
	arr.append(4)
	assert_eq((store.get_value("k") as Array).size(), 3,
		"set_value must copy its input")


# Null value handling
func test_null_handling() -> void:
	var store := ChronicleStore.new()
	assert_eq(store.get_value("missing"), null, "Missing key returns null")
	assert_eq(store.get_value("missing", 42), 42, "Missing key returns default")


# PackedArray — get_value returns a deep copy (requires copy_fn)
func test_packed_array_duplication() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy)
	store.set_value("packed", PackedInt32Array([1, 2, 3]))
	var a: Variant = store.get_value("packed")
	a.append(4)
	var b: Variant = store.get_value("packed")
	assert_eq(b.size(), 3, "Packed array get_value should return independent copy")


# Without copy_fn, the returned Dictionary is a shallow duplicate: adding a
# top-level key does not affect the store (nested isolation needs a copy_fn — see
# test_copy_fallback_shallow_nested_dict_mutation_leaks).
func test_dictionary_shallow_copy() -> void:
	var store := ChronicleStore.new()
	store.set_value("dict", {"inner": [1, 2]})
	var a: Dictionary = store.get_value("dict")
	a["added"] = true
	assert_does_not_have(store.get_value("dict"), "added",
		"adding a top-level key to the returned dict must not affect the store")


# erase removes key
func test_erase_removes_key() -> void:
	var store := ChronicleStore.new()
	store.set_value("key", "val")
	assert_true(store.has("key"), "key present after set")  # meta-allow:has-membership
	store.erase_value("key")
	assert_false(store.has("key"), "key gone after erase")  # meta-allow:has-membership


# clear removes all
func test_clear_removes_all() -> void:
	var store := ChronicleStore.new()
	store.set_value("a", 1)
	store.set_value("b", 2)
	assert_eq(store.size(), 2)
	store.clear()
	assert_eq(store.size(), 0)


# keys returns all stored keys
func test_keys_returns_all() -> void:
	var store := ChronicleStore.new()
	store.set_value("a", 1)
	store.set_value("b", 2)
	var keys: Array[String] = store.get_keys()
	keys.sort()
	assert_eq(keys, ["a", "b"] as Array[String])


# Value types (Vector2, Color) pass through correctly
func test_value_types_pass_through() -> void:
	var store := ChronicleStore.new()
	store.set_value("vec", Vector2(1.0, 2.0))
	store.set_value("col", Color(1, 0, 0, 1))
	assert_eq(store.get_value("vec"), Vector2(1.0, 2.0))
	assert_eq(store.get_value("col"), Color(1, 0, 0, 1))


# ── R16-A4 store audit ───────────────────


# Sorting the returned keys array should not corrupt the cache.
func test_keys_sort_does_not_corrupt_cache() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	store.set_value("_global.b", 2)
	store.set_value("_global.a", 1)

	# First call populates the cache.
	var keys1: Array[String] = store.get_keys()
	# Caller sorts (e.g. for display). If keys() returns a reference,
	# this mutates the internal _cached_keys.
	keys1.sort()

	# Second call should return the original order from the Dictionary,
	# not the sorted order imposed by the caller.
	var keys2: Array[String] = store.get_keys()

	# BUG: If keys() returns a reference, keys2 is the same array as keys1,
	# already sorted. The cache is corrupted.
	# We cannot predict Dictionary key order, but we CAN verify that
	# mutating keys1 after the fact does not affect keys2.
	keys1.append("injected")
	assert_does_not_have(keys2, "injected",
		"Mutating a previously returned keys() array should not affect subsequent calls — " +
		"keys() must return a copy, not an internal reference")


# Appending to the returned keys array should not make the store report a phantom key.
func test_keys_append_does_not_create_phantom_key() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	store.set_value("_global.real", 1)

	var keys: Array[String] = store.get_keys()
	keys.append("_global.phantom")

	# If keys() returned a reference, _cached_keys now contains "phantom".
	# Since _keys_dirty is false, the next keys() call returns the corrupted cache.
	var keys2: Array[String] = store.get_keys()
	assert_does_not_have(keys2, "_global.phantom",
		"Appending to returned keys() should not create phantom entries in cache")
	assert_eq(keys2.size(), 1,
		"keys() should report exactly 1 key, not 2")


# Mutating the returned entity keys array should not corrupt the index.
func test_entity_keys_mutation_does_not_corrupt_index() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	store.set_value("player.hp", 100)
	store.set_value("player.mp", 50)

	var entity_keys: Array = store.get_keys_for_entity("player")
	assert_eq(entity_keys.size(), 2, "player entity should have 2 keys")

	# Caller mutates the returned array (e.g. filters, removes, appends).
	entity_keys.clear()

	# If get_keys_for_entity returned the live internal array,
	# the entity index is now empty for "player".
	var entity_keys2: Array = store.get_keys_for_entity("player")
	assert_eq(entity_keys2.size(), 2,
		"Clearing a returned entity keys array should not corrupt the internal entity index")


# Setting transient on a missing key — documents current behavior.
func test_transient_on_nonexistent_key() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)

	# Set transient on a key that does not exist.
	store.set_transient("_global.ghost", true)

	# The key does not exist in the store.
	assert_false(store.has("_global.ghost"),  # meta-allow:has-membership
		"The key should not exist in the store")

	# Current behavior: is_transient reports true even for non-existent keys.
	# The coordinator guards against this in practice, but the store API is permissive.
	assert_true(store.is_transient("_global.ghost"),
		"Current behavior: is_transient returns true even when key does not exist in store")


# Entity index must not accumulate duplicates on erase+re-set.
func test_entity_index_no_duplicates_on_reset() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	store.set_value("player.hp", 100)
	store.erase_value("player.hp")
	store.set_value("player.hp", 200)

	var entity_keys: Array = store.get_keys_for_entity("player")
	assert_eq(entity_keys.size(), 1,
		"Entity index should have exactly 1 entry after erase+re-set, not 2")
	assert_has(entity_keys, "player.hp")


# Erasing all keys for an entity should remove the entity from the index.
func test_entity_index_cleanup_on_full_erase() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	store.set_value("npc.hp", 50)
	store.set_value("npc.name", "goblin")
	store.erase_value("npc.hp")
	store.erase_value("npc.name")

	var entity_keys: Array = store.get_keys_for_entity("npc")
	assert_eq(entity_keys.size(), 0,
		"Entity index should be empty after erasing all keys for an entity")


# Erasing a key that doesn't exist should be a safe no-op.
func test_erase_nonexistent_key_is_noop() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	store.set_value("player.hp", 100)

	# Erase a key that was never set — should not crash or corrupt state.
	store.erase_value("player.nonexistent")

	assert_eq(store.size(), 1, "Store size should be unchanged")
	assert_true(store.has("player.hp"), "Existing key should still be present")  # meta-allow:has-membership
	var entity_keys: Array = store.get_keys_for_entity("player")
	assert_eq(entity_keys.size(), 1,
		"Entity index should be unchanged after erasing a nonexistent key")


# Keys cache must be invalidated by erase_value.
func test_keys_cache_invalidated_on_erase() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	store.set_value("_global.a", 1)
	store.set_value("_global.b", 2)

	# Populate cache.
	var before: Array[String] = store.get_keys()
	assert_eq(before.size(), 2, "Should have 2 keys before erase")

	store.erase_value("_global.a")

	var after: Array[String] = store.get_keys()
	assert_eq(after.size(), 1, "Should have 1 key after erase")
	assert_has(after, "_global.b")


# Keys cache must be invalidated by clear().
func test_keys_cache_invalidated_on_clear() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	store.set_value("_global.a", 1)

	# Populate cache.
	var _before: Array[String] = store.get_keys()

	store.clear()

	var after: Array[String] = store.get_keys()
	assert_eq(after.size(), 0, "Should have 0 keys after clear")


# Overwriting an existing key should NOT duplicate in entity index.
func test_overwrite_does_not_duplicate_entity_index() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	store.set_value("enemy.hp", 100)
	store.set_value("enemy.hp", 200)
	store.set_value("enemy.hp", 300)

	var entity_keys: Array = store.get_keys_for_entity("enemy")
	assert_eq(entity_keys.size(), 1,
		"Overwriting should not add duplicate entries to entity index")


# get_value_raw must not return a copy — caller gets the live reference.
func test_get_value_raw_returns_live_reference() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	var original: Array = [1, 2, 3]
	store.set_value("_global.arr", original)

	var raw: Variant = store.get_value_raw("_global.arr")
	# get_value_raw should return the stored reference (which is a copy of the original,
	# made during set_value). Mutating raw should affect the stored value.
	raw.append(4)

	var raw2: Variant = store.get_value_raw("_global.arr")
	assert_eq(raw2.size(), 4,
		"get_value_raw should return the live stored reference, not a copy")


# get_value must return a defensive copy — mutations must not affect the store.
func test_get_value_returns_defensive_copy() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	store.set_value("_global.arr", [1, 2, 3])

	var copy: Variant = store.get_value("_global.arr")
	copy.append(4)

	var stored: Variant = store.get_value("_global.arr")
	assert_eq(stored.size(), 3,
		"get_value should return a defensive copy — mutations must not affect the store")


# Entity index with no entity_fn should not build any index.
func test_no_entity_fn_skips_index() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy)
	store.set_value("player.hp", 100)

	var entity_keys: Array = store.get_keys_for_entity("player")
	assert_eq(entity_keys.size(), 0,
		"Without entity_fn, get_keys_for_entity should return empty")


# ── R17-A4 store audit ───────────────────


# Nested Array in Array — shallow duplicate shares inner arrays.
func test_copy_fallback_shallow_nested_array_mutation_leaks() -> void:
	# No copy_fn → _copy falls back to value.duplicate() (shallow).
	var store := ChronicleStore.new()
	store.set_value("_global.arr", [[1, 2], [3, 4]])

	var copy: Variant = store.get_value("_global.arr")
	assert_not_null(copy, "get_value should return a value")

	# Mutate a nested inner array through the returned copy.
	copy[0].append(99)

	# If _copy used deep_copy, the stored value would still be [[1,2],[3,4]].
	# With shallow duplicate, the inner array is shared: stored value is now [[1,2,99],[3,4]].
	var stored: Variant = store.get_value_raw("_global.arr")
	assert_eq(stored[0].size(), 3,
		"A4-1: _copy fallback is shallow — nested array mutation leaks into the store " +
		"(inner array is shared between copy and store). Use a copy_fn for deep isolation.")


# Dictionary with Array value — shallow duplicate shares nested arrays.
func test_copy_fallback_shallow_nested_dict_mutation_leaks() -> void:
	var store := ChronicleStore.new()
	store.set_value("_global.d", {"items": [1, 2, 3]})

	var copy: Variant = store.get_value("_global.d")
	assert_not_null(copy, "get_value should return a value")

	# Mutate the nested array.
	copy["items"].append(99)

	# Shallow duplicate: the inner "items" Array is shared.
	var stored: Variant = store.get_value_raw("_global.d")
	assert_eq(stored["items"].size(), 4,
		"A4-1: _copy fallback is shallow — nested Dict array mutation leaks into the store " +
		"(inner array is shared). A copy_fn providing deep_copy is required for full isolation.")


# Entity key arrays always contain String values — type contract holds at runtime.
func test_entity_index_values_are_strings() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)
	store.set_value("player.hp", 100)
	store.set_value("player.mp", 50)
	store.set_value("enemy.hp", 30)

	var player_keys: Array[String] = store.get_keys_for_entity("player")
	var enemy_keys: Array[String] = store.get_keys_for_entity("enemy")

	# Runtime content check: all elements must be String.
	for k: Variant in player_keys:
		assert_true(k is String,
			("A4-2: entity key '%s' should be a String — type contract must hold even " +
			"though _entity_index is Dictionary[String, Array] (untyped)") % str(k))
	for k: Variant in enemy_keys:
		assert_true(k is String,
			"A4-2: entity key '%s' should be a String" % str(k))

	assert_eq(player_keys.size(), 2, "player should have 2 keys")
	assert_eq(enemy_keys.size(), 1, "enemy should have 1 key")


# set_value(key, null) — has() returns true but get_value returns null (ambiguous).
func test_set_null_value_has_returns_true_but_get_is_null() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)

	store.set_value("_global.ghost", null)

	# has() returns true — key exists in _store.
	assert_true(store.has("_global.ghost"),  # meta-allow:has-membership
		"A4-3: has() returns true after set_value(key, null)")

	# get_value returns null — indistinguishable from missing key.
	assert_null(store.get_value("_global.ghost"),
		"A4-3: get_value returns null for null-valued key (same as missing)")

	# get_value with a non-null default also returns null (not the default),
	# because the key IS found and _copy(null) → null is returned.
	assert_null(store.get_value("_global.ghost", 99),
		"A4-3: get_value ignores default for null-valued key — returns null, not default")


# set_value(key, null) — entity index includes the null-valued key.
func test_set_null_value_pollutes_entity_index() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)

	store.set_value("player.ghost", null)

	# Entity index tracks the key even though its value is null.
	var entity_keys: Array[String] = store.get_keys_for_entity("player")
	assert_has(entity_keys, "player.ghost",
		"A4-3: entity index contains null-valued key — _entity_index is polluted")

	# size() includes null-valued keys.
	assert_eq(store.size(), 1,
		"A4-3: size() counts null-valued keys as present")


# set_value then overwrite with null — entity index not duplicated.
func test_overwrite_with_null_does_not_duplicate_entity_index() -> void:
	var store := ChronicleStore.new(ChronicleValueUtils.deep_copy, KeyCodec.parse_entity)

	store.set_value("player.hp", 100)
	store.set_value("player.hp", null)  # Overwrite with null.

	var entity_keys: Array[String] = store.get_keys_for_entity("player")
	assert_eq(entity_keys.size(), 1,
		"A4-3: overwriting with null should not duplicate in entity index (key was already present)")
	assert_has(entity_keys, "player.hp",
		"A4-3: entity index still contains key after null overwrite")
