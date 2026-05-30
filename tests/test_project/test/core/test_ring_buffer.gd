extends GutTest


func test_put_and_get() -> void:
	var cache := ChronicleRingCache.new(4)
	cache.put("a", 1)
	cache.put("b", 2)
	assert_eq(cache.get_or_null("a"), 1)
	assert_eq(cache.get_or_null("b"), 2)
	assert_eq(cache.get_or_null("c"), null)

func test_membership_via_get_or_null() -> void:
	var cache := ChronicleRingCache.new(4)
	cache.put("x", 10)
	assert_not_null(cache.get_or_null("x"), "existing key returns non-null")
	assert_null(cache.get_or_null("y"), "missing key returns null")

func test_eviction_at_cap() -> void:
	var cache := ChronicleRingCache.new(3)
	cache.put("a", 1)
	cache.put("b", 2)
	cache.put("c", 3)
	assert_eq(cache._cache.size(), 3)
	cache.put("d", 4)
	assert_eq(cache._cache.size(), 3)
	assert_eq(cache.get_or_null("a"), null, "oldest entry should be evicted")
	assert_eq(cache.get_or_null("d"), 4)

func test_duplicate_put_ignored() -> void:
	var cache := ChronicleRingCache.new(3)
	cache.put("a", 1)
	cache.put("a", 999)
	assert_eq(cache.get_or_null("a"), 1, "duplicate put should not overwrite")
	assert_eq(cache._cache.size(), 1)

func test_clear() -> void:
	var cache := ChronicleRingCache.new(4)
	cache.put("a", 1)
	cache.put("b", 2)
	cache.clear()
	assert_eq(cache._cache.size(), 0)
	assert_eq(cache.get_or_null("a"), null)

func test_wraparound_eviction() -> void:
	var cache := ChronicleRingCache.new(2)
	cache.put("a", 1)
	cache.put("b", 2)
	cache.put("c", 3)
	cache.put("d", 4)
	assert_eq(cache.get_or_null("a"), null)
	assert_eq(cache.get_or_null("b"), null)
	assert_eq(cache.get_or_null("c"), 3)
	assert_eq(cache.get_or_null("d"), 4)


# Ring cache put ignores value updates for existing keys
func test_ring_cache_put_ignores_updates() -> void:
	var cache := ChronicleRingCache.new(4)
	cache.put("key1", "old_value")
	cache.put("key1", "new_value")
	var result: Variant = cache.get_or_null("key1")
	# BUG: Returns "old_value" — the update is silently dropped.
	# For a pure normalization cache where keys map to a single canonical form,
	# this is intentional (same input always produces same output). But the API
	# name "put" implies upsert semantics, and the class is generic.
	assert_eq(result, "old_value",
		"put() should ignore updates (FIFO cache, not LRU)")


# Ring cache is FIFO, not LRU — access does not promote
func test_ring_cache_fifo_not_lru() -> void:
	var cache := ChronicleRingCache.new(3)
	cache.put("a", "1")
	cache.put("b", "2")
	cache.put("c", "3")
	# Access "a" — does NOT promote it in a FIFO cache
	var _val: Variant = cache.get_or_null("a")
	# Insert "d" — should evict "a" (oldest inserted), not "b"
	cache.put("d", "4")
	assert_null(cache.get_or_null("a"), "FIFO: oldest key 'a' evicted despite recent access")
	assert_eq(cache.get_or_null("b"), "2", "'b' should survive")
	assert_eq(cache.get_or_null("c"), "3", "'c' should survive")
	assert_eq(cache.get_or_null("d"), "4", "'d' should be present")


# Ring cache clear() + re-fill produces correct eviction despite stale _order entries
func test_ring_cache_clear_stale_order_entries_safe() -> void:
	var cache := ChronicleRingCache.new(2)

	# Fill and partially consume the ring:
	cache.put("old_a", "1")
	cache.put("old_b", "2")
	# Evict old_a by inserting old_c:
	cache.put("old_c", "3")  # old_a evicted; order = ["old_c", "old_b"], head=1

	cache.clear()
	# After clear: _fill=0, _head=0, but _order still has ["old_c","old_b"] (stale).

	# Re-fill with new keys:
	cache.put("new_x", "X")
	cache.put("new_y", "Y")
	# Both slots overwritten: _fill=2=cap.

	# Evict: should evict new_x (position 0, oldest inserted after clear).
	cache.put("new_z", "Z")

	assert_null(cache.get_or_null("new_x"),
		"new_x should be evicted (oldest after clear) despite stale order entries")
	assert_eq(cache.get_or_null("new_y"), "Y", "new_y must survive")
	assert_eq(cache.get_or_null("new_z"), "Z", "new_z must be present")
	# Old keys must not be accessible after clear:
	assert_null(cache.get_or_null("old_a"), "old_a must be gone after clear")
	assert_null(cache.get_or_null("old_b"), "old_b must be gone after clear")
	assert_null(cache.get_or_null("old_c"), "old_c must be gone after clear")
