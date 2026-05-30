class_name FrameSimulator
extends RefCounted


static func simulate_frames(chronicle: Node, count: int, delta: float = 0.016) -> Dictionary:
	var start := Time.get_ticks_usec()
	for i in count:
		chronicle.advance_game_time(delta)
		chronicle.flush_expiry()
	var elapsed := Time.get_ticks_usec() - start
	return {elapsed_us = elapsed, frames_run = count}


static func simulate_seconds(chronicle: Node, seconds: float, fps: float = 60.0) -> Dictionary:
	var frame_count := int(seconds * fps)
	var delta := 1.0 / fps
	return simulate_frames(chronicle, frame_count, delta)
