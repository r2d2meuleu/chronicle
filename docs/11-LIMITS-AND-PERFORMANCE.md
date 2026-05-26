# Chronicle — Limits and Performance

Concrete numbers for capacity planning. All defaults are configurable via Project Settings (`chronicle/storage/`).

---

## Default Limits

| Limit | Default | Range | Setting |
|-------|---------|-------|---------|
| Timeline capacity | 10,000 entries | 100 – 1,000,000 | `chronicle/storage/timeline_cap` |
| Serialize timeline cap | 1,000 entries | 100 – 100,000 | `chronicle/storage/serialize_timeline_cap` |
| Store hard cap | 0 (disabled) | 0 – 1,000,000 | `chronicle/storage/store_hard_cap` |
| Expression nesting depth | 64 levels | Fixed | Not configurable |
| AST expression cache | 256 entries | Fixed | Not configurable |
| Regex pattern cache | 512 entries | Fixed | Not configurable |
| Cascade depth (re-entrancy) | 8 levels inline | Fixed | Not configurable |
| Deferred write queue | 64 entries | Fixed | Not configurable |
| Drain iteration cap | 256 iterations | Fixed | Not configurable |
| Key segment cache (WatchBus) | 2,048 entries | Fixed | Not configurable |
| Key normalization cache | 2,048 entries (x2) | Fixed | Not configurable |
| Max key length | 256 characters | Fixed | Not configurable |
| Store warning threshold | 10,000 facts | Fixed | Not configurable |

**Store warning behavior:** The warning fires at 10,000 facts, then repeats every 5,000 (at 15,000, 20,000, etc.). Specifically, it fires whenever `store_size >= 10,000` and `store_size` is a multiple of 5,000.

**Store hard cap behavior:** New-key writes beyond the cap are rejected. A `push_error` is emitted and `set_fact()` returns `false`. Existing keys can still be updated — the guard only blocks writes that would create a new key.

---

## Runtime Configuration

```gdscript
# Increase timeline for games with frequent writes
Chronicle.set_timeline_cap(100_000)

# Limit total fact count (rejects new keys beyond this)
Chronicle.set_store_hard_cap(50_000)
```

---

## Performance Characteristics

### Write: set_fact()

- **Store write:** O(1) hash map insertion
- **Timeline append:** O(1) ring buffer write
- **Watcher dispatch:** O(exact_watchers + matching_glob_watchers)
- **Typical cost:** < 0.01ms per write with < 10 watchers on that key

### Read: get_fact()

- **Lookup:** O(1) hash map access
- **Deep copy:** O(value_size) for Arrays/Dicts; O(1) for primitives
- **Typical cost:** < 0.001ms

### Expression: evaluate()

- **First call:** Parse + evaluate (~0.05ms for simple expressions)
- **Cached call:** Evaluate only, AST cached (~0.01ms)
- **Complex expressions (10+ operators):** ~0.1ms

### Serialization: serialize()

- **5,000 facts:** ~25ms (serialize + deserialize roundtrip)
- **10,000 facts:** ~50ms (~5us per fact)
- **Timeline cap 1,000:** adds ~20ms

### Expiry: flush_expiry()

- **No facts due:** O(1) single float comparison (min-expiry guard)
- **N facts expiring:** O(N) iteration + O(N) erase + watcher dispatch

---

## Frame Budget Guidance

At 60fps you have **16.6ms per frame**. Typical Chronicle usage:

| Game size | Facts | Watchers | Chronicle overhead/frame |
|-----------|-------|----------|--------------------------|
| Small (indie) | 100-500 | 10-50 | < 0.1ms |
| Medium (RPG) | 1,000-5,000 | 50-200 | < 0.5ms |
| Large (open world) | 5,000-20,000 | 200-1,000 | 1-3ms |
| Extreme (stress test) | 50,000-100,000 | 1,000+ | 5-15ms |

### Safe rules of thumb

- **500 `set_fact()` calls per frame** is safe for any game under 200 watchers
- **Serialize under 5,000 facts** to keep save times under 200ms
- **Keep watcher count under 500** for zero-thought performance (< 0.5ms overhead per frame)
- **Timeline at 10,000** is enough for 3+ minutes of history at 60fps with 50 writes/sec

---

## Scaling Recommendations

### When to increase timeline cap

- You need deep rollback (> 30 seconds of history)
- You have temporal queries spanning long periods
- Default 10k supports ~10,000 seconds (~167 minutes) at 1 write/sec, ~1,000 seconds (~17 minutes) at 10 writes/sec

### When to use transient facts

- Per-frame state (positions, velocities) that shouldn't pollute saves
- Session-only state (UI open/closed, current menu)
- Temporary buffs: use `lifetime` parameter instead (auto-expires AND auto-marks transient)

### When to batch with set_facts()

- Loading initial state (level start, NPC spawning)
- Importing data from external sources
- Each key still dispatches individually, but avoids per-call overhead

### When to use store hard cap

- Dynamically generated keys (procedural games, MMO-style)
- Prevents memory growth from key leaks
- Set to 2-5x your expected maximum fact count

---

## Memory Estimates

| Item | Approximate size |
|------|-----------------|
| Per fact (primitive value) | ~200 bytes |
| Per fact (small Dict/Array) | ~400 bytes |
| Per timeline entry | ~300 bytes |
| Per watcher | ~150 bytes |
| 10,000 facts + 10,000 timeline | ~5 MB |

These are rough estimates. Actual usage depends on key lengths and value sizes.
