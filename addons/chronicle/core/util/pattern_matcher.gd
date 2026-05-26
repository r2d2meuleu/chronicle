## Glob pattern matcher for Chronicle fact keys.
##
## Pattern semantics:
## - "*" matches any key
## - "prefix.*" (single trailing wildcard) matches any key at any depth under "prefix."
## - "a.*.c" (mid-position wildcard) matches exactly "a.<one-segment>.c"
## - Multiple wildcards: each "*" matches exactly one segment (no multi-level)
## Only a single trailing "*" has multi-level semantics.
class_name ChroniclePatternMatcher
extends RefCounted


static func validate(pattern: String) -> String:
	if pattern.is_empty():
		return "pattern is empty"
	if ".." in pattern or pattern.begins_with(".") or pattern.ends_with("."):
		return "malformed key structure"
	if "*" not in pattern:
		return ""
	if pattern == "*":
		return ""
	var segments: PackedStringArray = pattern.split(".")
	for seg: String in segments:
		if seg.is_empty():
			return "Empty segment in pattern \"%s\"." % pattern
		if seg == "*":
			continue
		if "*" in seg:
			return "Wildcard '*' must be an entire segment, not mixed: \"%s\"." % pattern
		for i: int in seg.length():
			var c: String = seg[i]
			if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
				return "Invalid character '%s' in pattern segment \"%s\". Use lowercase a-z, 0-9, underscore." % [c, seg]
	return ""


## Avoids re-splitting the key on every watcher check during glob dispatch.
static func matches_presplit_segs(pat_segs: PackedStringArray, key_segs: PackedStringArray) -> bool:
	if pat_segs.size() == 1 and pat_segs[0] == "*":
		return key_segs.size() > 0
	if pat_segs.size() != key_segs.size():
		return false
	for i: int in range(pat_segs.size()):
		if pat_segs[i] == "*":
			continue
		if pat_segs[i] != key_segs[i]:
			return false
	return true


static func matches(pattern: String, key: String) -> bool:
	if key.is_empty():
		return false
	if pattern == "*":
		return true
	if "*" not in pattern:
		return pattern == key
	if key.begins_with(".") or key.ends_with(".") or ".." in key:
		return false
	# Trailing wildcard: "entity.*" matches any depth beneath the prefix
	if pattern.ends_with(".*") and pattern.count("*") == 1:
		var prefix: String = pattern.substr(0, pattern.length() - 1)
		return key.begins_with(prefix) and key.length() > prefix.length()
	# Mid-segment or multi-wildcard: segment-by-segment, * matches exactly one segment
	var pat_segs: PackedStringArray = pattern.split(".")
	var key_segs: PackedStringArray = key.split(".")
	if pat_segs.size() != key_segs.size():
		return false
	for i: int in range(pat_segs.size()):
		if pat_segs[i] == "*":
			continue
		if pat_segs[i] != key_segs[i]:
			return false
	return true
