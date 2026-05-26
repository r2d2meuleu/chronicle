extends CanvasLayer

# This file contains 5 inner tab classes. If a new tab is added,
# consider extracting tab classes to separate files in debug/.

## Runtime debug panel for Chronicle. Toggled by F9 (or the
## "chronicle_toggle_debug" InputMap action). Compiled out in release
## builds unless [code]chronicle/debug/enabled_in_release[/code] is [code]true[/code]
## or the "CHRONICLE_DEBUG" feature flag is set.

const TAB_INSPECTOR := 1
const TAB_GATES := 2
const TAB_REACTORS := 3

const PERF_INTERVAL: float = 1.0

var _panel: PanelContainer
var _tabs: TabContainer
var _chronicle: ChronicleEngine = null

var _feed: _FactFeedTab
var _inspector: _FactInspectorTab
var _gates: _GateStatusTab
var _reactors: _ReactorLogTab
var _perf: _PerfMonitorTab
var _perf_timer: Timer
var _registered_hotkey: bool = false


func _ready() -> void:
	if not OS.is_debug_build() and not OS.has_feature("CHRONICLE_DEBUG") and not ProjectSettings.get_setting("chronicle/debug/enabled_in_release", false):
		queue_free()
		return

	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

	var parent_node := get_parent()
	if parent_node != null and parent_node is ChronicleEngine:
		_chronicle = parent_node
	else:
		_chronicle = get_node_or_null(ChronicleNodeUtils.AUTOLOAD_PATH)
	if _chronicle == null:
		push_warning("[Chronicle] Debug overlay: no Chronicle autoload found.")
		queue_free()
		return

	if not InputMap.has_action("chronicle_toggle_debug"):
		InputMap.add_action("chronicle_toggle_debug")
		var key_name: String = "F9"
		if ProjectSettings.has_setting("chronicle/debug/overlay_hotkey"):
			key_name = str(ProjectSettings.get_setting("chronicle/debug/overlay_hotkey", "F9"))
		var event := InputEventKey.new()
		var resolved_keycode: Key = OS.find_keycode_from_string(key_name)
		if resolved_keycode == KEY_NONE:
			push_warning("[Chronicle] Invalid overlay hotkey \"%s\" — falling back to F9." % key_name)
			resolved_keycode = KEY_F9
		event.keycode = resolved_keycode
		InputMap.action_add_event("chronicle_toggle_debug", event)
		_registered_hotkey = true

	_build_ui()
	_connect_signals()
	_start_perf_timer()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "ChronicleDebugPanel"

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.85)
	_panel.add_theme_stylebox_override("panel", style)

	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.size_flags_horizontal = Control.SIZE_FILL

	_panel.set_anchor(SIDE_LEFT, 0.65)
	_panel.set_anchor(SIDE_RIGHT, 1.0)
	_panel.set_anchor(SIDE_TOP, 0.0)
	_panel.set_anchor(SIDE_BOTTOM, 1.0)
	_panel.set_offset(SIDE_LEFT, 0.0)
	_panel.set_offset(SIDE_RIGHT, 0.0)
	_panel.set_offset(SIDE_TOP, 0.0)
	_panel.set_offset(SIDE_BOTTOM, 0.0)

	add_child(_panel)
	_panel.visible = false

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(_tabs)

	_tabs.tab_changed.connect(_on_tab_changed)

	_feed = _FactFeedTab.new()
	_feed.build(_tabs)

	_inspector = _FactInspectorTab.new()
	_inspector.build(_tabs)

	_gates = _GateStatusTab.new()
	_gates.build(_tabs)

	_reactors = _ReactorLogTab.new()
	_reactors.build(_tabs)

	_perf = _PerfMonitorTab.new()
	_perf.build(_tabs)


func _unhandled_input(event: InputEvent) -> void:
	if _panel == null:
		return
	if event.is_action_pressed("chronicle_toggle_debug"):
		_panel.visible = not _panel.visible
		if _perf_timer != null:
			if _panel.visible:
				_perf_timer.start()
			else:
				_perf_timer.stop()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if is_instance_valid(_chronicle) and _chronicle.fact_changed.is_connected(_on_fact_changed):
		_chronicle.fact_changed.disconnect(_on_fact_changed)
	if _reactors != null:
		_reactors.disconnect_all()
	if _registered_hotkey and InputMap.has_action("chronicle_toggle_debug"):
		InputMap.erase_action("chronicle_toggle_debug")


func _connect_signals() -> void:
	if _chronicle == null:
		return
	_chronicle.fact_changed.connect(_on_fact_changed)


func _start_perf_timer() -> void:
	_perf_timer = Timer.new()
	_perf_timer.wait_time = PERF_INTERVAL
	_perf_timer.autostart = false
	_perf_timer.timeout.connect(_update_perf)
	add_child(_perf_timer)


func _on_fact_changed(key: String, value: Variant, old_value: Variant, _erase_source: Variant) -> void:
	if old_value == null:
		_feed.push_entry("[%.2f] %s = %s" % [_get_game_time(), key, str(value)])
	elif value == null:
		_feed.push_entry("[%.2f] %s %s → [erased]" % [_get_game_time(), key, str(old_value)])
	else:
		_feed.push_entry("[%.2f] %s %s → %s" % [_get_game_time(), key, str(old_value), str(value)])


func _on_tab_changed(tab: int) -> void:
	if not is_instance_valid(_chronicle):
		return
	if tab == TAB_INSPECTOR:
		_inspector.populate(_chronicle)
	elif tab == TAB_GATES:
		_gates.populate(get_tree())
	elif tab == TAB_REACTORS:
		_reactors.connect_reactors(get_tree(), _get_game_time)


func _update_perf() -> void:
	if not is_instance_valid(_chronicle) or not _panel.visible:
		return
	_perf.update(_chronicle, get_tree())


func _get_game_time() -> float:
	if is_instance_valid(_chronicle):
		return _chronicle.get_game_time()
	return 0.0


class _RingBufferTextTab extends RefCounted:
	var _label: RichTextLabel
	var _entries: PackedStringArray = PackedStringArray()
	var _head: int = 0
	var _count: int = 0
	var _dirty: bool = false
	var _cap: int

	func _init(cap: int = 200) -> void:
		_cap = cap

	func _build_label(parent: TabContainer, tab_name: String) -> void:
		var container := VBoxContainer.new()
		container.name = tab_name
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		parent.add_child(container)

		_label = RichTextLabel.new()
		_label.bbcode_enabled = true
		_label.scroll_following = true
		_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_child(_label)

	func _append_entry(entry: String) -> void:
		if _entries.size() < _cap:
			_entries.append(entry)
			_count += 1
		else:
			_entries[_head] = entry
			_head = (_head + 1) % _cap
			_count = _cap
		if not _dirty:
			_dirty = true
			_rebuild_text.call_deferred()

	func _rebuild_text() -> void:
		if not is_instance_valid(_label):
			return
		_dirty = false
		var lines: PackedStringArray = PackedStringArray()
		for i: int in range(_count):
			lines.append(_entries[(_head + i) % _entries.size()])
		_label.text = "\n".join(lines)


class _FactFeedTab extends _RingBufferTextTab:
	func build(parent: TabContainer) -> void:
		_build_label(parent, "Fact Feed")

	func push_entry(text: String) -> void:
		_append_entry(text)


class _FactInspectorTab extends RefCounted:
	var _tree: Tree
	var _search: LineEdit
	var _chronicle_ref: Node = null

	func build(parent: TabContainer) -> void:
		var container := VBoxContainer.new()
		container.name = "Fact Inspector"
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		parent.add_child(container)

		_search = LineEdit.new()
		_search.placeholder_text = "Search facts…"
		_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_child(_search)
		_search.text_changed.connect(_on_search_changed)

		_tree = Tree.new()
		_tree.columns = 2
		_tree.column_titles_visible = true
		_tree.set_column_title(0, "Key")
		_tree.set_column_title(1, "Value")
		_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_child(_tree)

	func populate(chronicle: Node) -> void:
		if chronicle == null:
			return
		_chronicle_ref = chronicle
		_tree.clear()
		var root: TreeItem = _tree.create_item()
		root.set_text(0, "Facts")

		var filter: String = _search.text.to_lower() if _search != null else ""
		var facts: Dictionary = chronicle.get_facts()

		var keys: Array = facts.keys()
		keys.sort()
		for display_key: String in keys:
			if not filter.is_empty() and filter not in display_key.to_lower():
				continue
			var item: TreeItem = _tree.create_item(root)
			item.set_text(0, display_key)
			var fv: Variant = facts[display_key]
			item.set_text(1, "[null]" if fv == null else str(fv))

	func _on_search_changed(_text: String) -> void:
		if is_instance_valid(_chronicle_ref):
			populate(_chronicle_ref)


class _GateStatusTab extends RefCounted:
	var _tree: Tree

	func build(parent: TabContainer) -> void:
		var container := VBoxContainer.new()
		container.name = "Gate Status"
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		parent.add_child(container)

		_tree = Tree.new()
		_tree.columns = 2
		_tree.column_titles_visible = true
		_tree.set_column_title(0, "Gate")
		_tree.set_column_title(1, "Status")
		_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_child(_tree)

	func populate(scene_tree: SceneTree) -> void:
		_tree.clear()
		var root: TreeItem = _tree.create_item()
		root.set_text(0, "Gates")

		var open_root: TreeItem = _tree.create_item(root)
		open_root.set_text(0, "Open")

		var closed_root: TreeItem = _tree.create_item(root)
		closed_root.set_text(0, "Closed")

		var gates: Array[Node] = scene_tree.get_nodes_in_group(ChronicleNodeUtils.GROUP_GATES)
		for gate: Node in gates:
			var open: bool = false
			if gate is ChronicleGate:
				open = gate.is_open()

			var parent_node: TreeItem = open_root if open else closed_root
			var item: TreeItem = _tree.create_item(parent_node)
			item.set_text(0, gate.name)
			item.set_text(1, "Open" if open else "Closed")


class _ReactorLogTab extends _RingBufferTextTab:
	var _connected_paths: Dictionary[String, Dictionary] = {}  # node_path -> {cb: Callable, id: int}

	func build(parent: TabContainer) -> void:
		_build_label(parent, "Reactor Log")

	func connect_reactors(scene_tree: SceneTree, game_time_fn: Callable) -> void:
		# Evict freed reactors and paths reused by a different instance.
		for path: String in _connected_paths.keys():
			var node: Node = scene_tree.root.get_node_or_null(path)
			var entry: Dictionary = _connected_paths[path]
			if not is_instance_valid(node) or node.get_instance_id() != entry.id:
				_connected_paths.erase(path)

		var reactors: Array[Node] = scene_tree.get_nodes_in_group(ChronicleNodeUtils.GROUP_REACTORS)
		for reactor: Node in reactors:
			var path: String = str(reactor.get_path())
			if path in _connected_paths:
				continue
			if reactor is ChronicleReactor:
				var reactor_ref: WeakRef = weakref(reactor)
				var fn: Callable = game_time_fn
				var cb: Callable = func(key: String, value: Variant, _old: Variant) -> void:
					var r: Node = reactor_ref.get_ref()
					_on_reactor_matched(r.name if r else "<freed>", key, value, fn.call())
				reactor.fact_matched.connect(cb)
				_connected_paths[path] = {cb = cb, id = reactor.get_instance_id()}
				var captured_path: String = path
				reactor.tree_exiting.connect(func() -> void:
					_connected_paths.erase(captured_path), CONNECT_ONE_SHOT)

	func disconnect_all() -> void:
		for path: String in _connected_paths.keys():
			var node: Node = Engine.get_main_loop().root.get_node_or_null(path) if Engine.get_main_loop() else null
			if is_instance_valid(node) and node.has_signal("fact_matched"):
				var cb: Callable = _connected_paths[path].cb
				if node.fact_matched.is_connected(cb):
					node.fact_matched.disconnect(cb)
		_connected_paths.clear()

	func _on_reactor_matched(reactor_name: String, key: String, value: Variant, game_time: float) -> void:
		var time_str: String = "%.1f" % game_time
		var val_str: String = "[null]" if value == null else str(value)
		var entry: String = "[color=gray]%s[/color] [color=yellow]%s[/color] [color=cyan]%s[/color] = [color=white]%s[/color]" % [time_str, reactor_name, key, val_str]
		_append_entry(entry)


class _PerfMonitorTab extends RefCounted:
	var _fact_count: Label
	var _watcher_count: Label
	var _gate_count: Label
	var _reactor_count: Label

	func build(parent: TabContainer) -> void:
		var container := VBoxContainer.new()
		container.name = "Perf Monitor"
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		parent.add_child(container)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_top", 8)
		margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
		container.add_child(margin)

		var inner := VBoxContainer.new()
		margin.add_child(inner)

		_fact_count = _make_label("Facts: —")
		_watcher_count = _make_label("Watchers: —")
		_gate_count = _make_label("Gates: —")
		_reactor_count = _make_label("Reactors: —")

		inner.add_child(_fact_count)
		inner.add_child(_watcher_count)
		inner.add_child(_gate_count)
		inner.add_child(_reactor_count)

	func update(chronicle: Node, scene_tree: SceneTree) -> void:
		if chronicle == null:
			return
		var stats: Dictionary = chronicle.get_stats()
		_fact_count.text = "Facts: %d" % stats.fact_count
		_watcher_count.text = "Watchers: %d" % stats.watcher_count

		# Allocates a temporary array per call — acceptable for debug at 1-second intervals.
		_gate_count.text = "Gates: %d" % scene_tree.get_nodes_in_group(ChronicleNodeUtils.GROUP_GATES).size()
		_reactor_count.text = "Reactors: %d" % scene_tree.get_nodes_in_group(ChronicleNodeUtils.GROUP_REACTORS).size()

	static func _make_label(initial_text: String) -> Label:
		var lbl := Label.new()
		lbl.text = initial_text
		return lbl
