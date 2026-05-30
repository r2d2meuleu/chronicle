## Covers acceptance test cases TC-42 through TC-45.
## Smoke tests for ChronicleDebugOverlay.
## Verifies the overlay instantiates without crashing and has the expected
## node structure. The UI is not tested headlessly — only instantiation and
## basic structure checks are performed.
extends ChronicleTestSuite

const DebugOverlay := preload("res://addons/chronicle/debug/debug_overlay.gd")


func _make_overlay() -> Node:
	var overlay: Node = autoqfree(DebugOverlay.new())
	_chronicle.add_child(overlay)
	return overlay


# Overlay is a CanvasLayer
func test_overlay_is_canvas_layer() -> void:
	var overlay := _make_overlay()
	assert_true(overlay is CanvasLayer, "overlay is a CanvasLayer")


# Overlay has a PanelContainer child
func test_overlay_has_panel() -> void:
	var overlay := _make_overlay()
	var panel: Node = null
	for child: Node in overlay.get_children():
		if child is PanelContainer:
			panel = child
			break
	assert_not_null(panel, "overlay has a PanelContainer child")


# Overlay has a TabContainer inside the panel
func test_overlay_has_tab_container() -> void:
	var overlay := _make_overlay()
	var tabs: Node = null
	for child: Node in overlay.get_children():
		if child is PanelContainer:
			for inner: Node in child.get_children():
				if inner is TabContainer:
					tabs = inner
					break
	assert_not_null(tabs, "overlay has a TabContainer")


# TabContainer has exactly 5 tabs
func test_overlay_has_five_tabs() -> void:
	var overlay := _make_overlay()
	var tabs: TabContainer = null
	for child: Node in overlay.get_children():
		if child is PanelContainer:
			for inner: Node in child.get_children():
				if inner is TabContainer:
					tabs = inner
					break
	assert_not_null(tabs, "five-tab check: TabContainer found")
	if tabs != null:
		assert_eq(tabs.get_tab_count(), 5, "TabContainer has 5 tabs")


# CanvasLayer layer is 128
func test_overlay_layer_is_128() -> void:
	var overlay := _make_overlay()
	assert_eq((overlay as CanvasLayer).layer, 128, "overlay layer == 128")


# process_mode is PROCESS_MODE_ALWAYS
func test_overlay_process_mode_always() -> void:
	var overlay := _make_overlay()
	assert_eq(overlay.process_mode, Node.PROCESS_MODE_ALWAYS, "overlay process_mode == PROCESS_MODE_ALWAYS")
