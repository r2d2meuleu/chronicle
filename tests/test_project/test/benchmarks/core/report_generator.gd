extends SceneTree

## Benchmark report generator (NOT a test — a standalone headless tool).
##
## Reads bench_results/*.json, keeps only the freshest run per (tier, suite, name,
## scale_label) among files whose meta.timestamp is on the LATEST date present, emits
## committed dark-mode-safe SVG line charts to test/bench_charts/, and injects a
## Markdown "Results" section between the BENCH:GENERATED markers in test/README.md.
##
## Run headless:
##   godot --headless -s res://test/benchmarks/core/report_generator.gd
##
## Naming: this file has NO `test_` prefix (GUT's default) and NO `bench_` prefix (the
## bench-tier prefix), so neither a core run nor a `-gprefix=bench_` run picks it up. It
## also defines no `func test_*` and no assert_true/false, so the meta convention scanner
## finds nothing to flag.

const RESULTS_DIR := "res://bench_results"
const CHARTS_DIR := "res://test/bench_charts"
const README_PATH := "res://test/README.md"
const MARK_START := "<!-- BENCH:GENERATED:START -->"
const MARK_END := "<!-- BENCH:GENERATED:END -->"

# Delimiter for composite group keys. The "|" char does not appear in any tier / suite /
# name (all are lowercase identifiers with underscores), so split() is unambiguous.
const SEP := "|"

# SVG geometry
const SVG_W := 560
const SVG_H := 320
const PAD_L := 64
const PAD_R := 20
const PAD_T := 44
const PAD_B := 56

# Dark-mode-safe palette: transparent bg, mid-gray axes/text readable on both themes,
# a distinct blue accent for the data series.
const COL_AXIS := "#888"
const COL_TEXT := "#888"
const COL_ACCENT := "#3b82f6"
const COL_BAND := "#3b82f6"

# Curated "headline" benches that get a chart (others appear as tables only). These
# cover the distinct performance dimensions without 50 charts of scroll: read/write/erase
# at store scale, watcher dispatch + registration scaling, timeline append/scan/bisect/
# rollback at depth, and entity-query scaling. Keys are "tier|suite|name".
const CHART_ALLOWLIST: Array[String] = [
	"micro|bench_watcher|dispatch_exact_scaling",
	"micro|bench_fact_write|overwrite_with_watchers",
	"stress|bench_scale_facts|insert_at_scale",
	"stress|bench_scale_facts|get_at_scale",
	"stress|bench_scale_facts|erase_at_scale",
	"stress|bench_scale_watchers|registration_at_scale",
	"stress|bench_scale_timeline|append_at_depth",
	"stress|bench_scale_timeline|changes_since_full_scan",
	"stress|bench_scale_timeline|changes_since_bisect",
	"stress|bench_scale_timeline|rollback_at_depth",
	"stress|bench_scale_entities|find_glob_entity_count",
	"stress|bench_scale_entities|find_wildcard_vs_entities",
]


func _is_charted(gkey: String) -> bool:
	return CHART_ALLOWLIST.has(gkey)


func _initialize() -> void:
	var summary := _run()
	print(summary)
	quit()


func _run() -> String:
	var files := _list_result_files()
	if files.is_empty():
		return "[bench_report] No JSON files in %s — nothing to generate." % RESULTS_DIR

	var parsed := _parse_files(files)
	if parsed.is_empty():
		return "[bench_report] No parseable benchmark JSON found."

	var latest_date := _latest_date(parsed)
	var todays: Array = parsed.filter(func(p: Dictionary) -> bool:
		return String(p.meta.get("timestamp", "")).begins_with(latest_date))
	if todays.is_empty():
		return "[bench_report] No files for latest date %s." % latest_date

	# Overall-latest meta drives the README header.
	todays.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.meta.get("timestamp", "")) < String(b.meta.get("timestamp", "")))
	var latest_meta: Dictionary = todays[-1].meta

	# Merge: per (tier, suite, name, scale_label) keep the freshest measurement.
	var merged := _merge(todays)

	# Group merged entries by (tier, suite, name).
	var groups := _group(merged)

	if not DirAccess.dir_exists_absolute(CHARTS_DIR):
		DirAccess.make_dir_recursive_absolute(CHARTS_DIR)

	var charts_written := 0
	var benches_tabulated := 0

	var ordered_keys: Array = groups.keys()
	ordered_keys.sort_custom(func(a: String, b: String) -> bool: return a < b)

	for gkey: String in ordered_keys:
		var rows: Array = groups[gkey]
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			# Total order (tiebreak on label) so ties in int(scale) sort deterministically.
			if int(a.scale) != int(b.scale):
				return int(a.scale) < int(b.scale)
			return String(a.scale_label) < String(b.scale_label))
		benches_tabulated += 1
		if _distinct_labels(rows).size() >= 2 and _is_charted(gkey):
			var info: Dictionary = _key_parts(gkey)
			var stem := "%s__%s__%s" % [info.tier, info.suite, info.name]
			var svg_res := CHARTS_DIR + "/" + stem + ".svg"
			_write_text(svg_res, _build_svg(info, rows))
			# Rasterize to PNG so charts render in editors that block local SVG in
			# markdown preview (e.g. VS Code's built-in preview) AND on GitHub. PNG is
			# the committed artifact; if no rasterizer is available we keep the SVG.
			if _rasterize(svg_res, CHARTS_DIR + "/" + stem + ".png"):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(svg_res))
			charts_written += 1

	# Stale chart cleanup: remove SVGs that no longer correspond to a chartable bench
	# so re-runs are idempotent for the current data set.
	_prune_stale_charts(groups)

	# Build + inject the Markdown section.
	var section := _build_markdown(latest_meta, groups, ordered_keys)
	var inject_status := _inject_readme(section)

	return ("[bench_report] latest date: %s | files used: %d | charts written: %d | benches tabulated: %d\n"
		+ "[bench_report] README: %s") % [
			latest_date, todays.size(), charts_written, benches_tabulated, inject_status]


# ── Data loading ──────────────────────────────────────────────────────────────

func _list_result_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(RESULTS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var nm := dir.get_next()
	while nm != "":
		if not dir.current_is_dir() and nm.ends_with(".json"):
			out.append(RESULTS_DIR + "/" + nm)
		nm = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _parse_files(paths: Array) -> Array:
	var out: Array = []
	for p: String in paths:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary and data.has("meta") and data.has("results"):
			out.append(data)
	return out


func _latest_date(parsed: Array) -> String:
	var latest := ""
	for d: Dictionary in parsed:
		var ts := String(d.meta.get("timestamp", ""))
		var date := ts.substr(0, 10)
		if date > latest:
			latest = date
	return latest


func _merge(todays: Array) -> Dictionary:
	# (tier|suite|name|scale_label) -> {ts, entry}; keep freshest per unique tuple.
	var best: Dictionary = {}
	for d: Dictionary in todays:
		var ts := String(d.meta.get("timestamp", ""))
		for r: Dictionary in d.results:
			var k := SEP.join([String(r.tier), String(r.suite), String(r.name), String(r.scale_label)])
			if not best.has(k) or ts >= best[k].ts:
				best[k] = {ts = ts, entry = r}
	var out: Dictionary = {}
	for k: String in best:
		out[k] = best[k].entry
	return out


func _group(merged: Dictionary) -> Dictionary:
	# "tier|suite|name" -> Array[entry]
	var groups: Dictionary = {}
	for k: String in merged:
		var r: Dictionary = merged[k]
		var gkey := SEP.join([String(r.tier), String(r.suite), String(r.name)])
		if not groups.has(gkey):
			groups[gkey] = []
		groups[gkey].append(r)
	return groups


func _key_parts(gkey: String) -> Dictionary:
	var parts := gkey.split(SEP)
	return {tier = parts[0], suite = parts[1], name = parts[2]}


func _distinct_labels(rows: Array) -> Array:
	var seen: Dictionary = {}
	for r: Dictionary in rows:
		seen[r.scale_label] = true
	return seen.keys()


# ── SVG chart ─────────────────────────────────────────────────────────────────

func _build_svg(info: Dictionary, rows: Array) -> String:
	var unit := String(rows[0].unit)
	var title := "%s · %s · %s" % [info.tier, info.suite, info.name]

	var n := rows.size()
	var medians: Array[float] = []
	var p25s: Array[float] = []
	var p75s: Array[float] = []
	var labels: Array[String] = []
	for r: Dictionary in rows:
		medians.append(float(r.stats.median))
		p25s.append(float(r.stats.get("p25", r.stats.median)))
		p75s.append(float(r.stats.get("p75", r.stats.median)))
		labels.append(String(r.scale_label))

	# y-range from the band so the p25–p75 fill stays inside the plot.
	var y_min := medians[0]
	var y_max := medians[0]
	for i in range(n):
		y_min = minf(y_min, minf(medians[i], p25s[i]))
		y_max = maxf(y_max, maxf(medians[i], p75s[i]))
	if y_max <= y_min:
		y_max = y_min + 1.0
	# Small headroom so points aren't glued to the frame.
	var span := y_max - y_min
	y_min = maxf(0.0, y_min - span * 0.08)
	y_max = y_max + span * 0.08

	var plot_w := SVG_W - PAD_L - PAD_R
	var plot_h := SVG_H - PAD_T - PAD_B

	var px := func(i: int) -> float:
		if n == 1:
			return PAD_L + plot_w * 0.5
		return PAD_L + plot_w * (float(i) / float(n - 1))
	var py := func(v: float) -> float:
		return PAD_T + plot_h * (1.0 - (v - y_min) / (y_max - y_min))

	var s := ""
	s += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\" font-family=\"sans-serif\">\n" % [SVG_W, SVG_H, SVG_W, SVG_H]
	s += "  <title>%s</title>\n" % _xml(title)

	# Title text
	s += "  <text x=\"%d\" y=\"22\" fill=\"%s\" font-size=\"13\" font-weight=\"bold\">%s</text>\n" % [PAD_L, COL_TEXT, _xml(title)]
	s += "  <text x=\"%d\" y=\"38\" fill=\"%s\" font-size=\"11\">median %s</text>\n" % [PAD_L, COL_TEXT, _xml(unit)]

	# Axes
	var x0 := PAD_L
	var x1 := SVG_W - PAD_R
	var yt := PAD_T
	var yb := SVG_H - PAD_B
	s += "  <line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"%s\" stroke-width=\"1\"/>\n" % [x0, yt, x0, yb, COL_AXIS]
	s += "  <line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"%s\" stroke-width=\"1\"/>\n" % [x0, yb, x1, yb, COL_AXIS]

	# y ticks: min and max
	s += "  <text x=\"%d\" y=\"%d\" fill=\"%s\" font-size=\"10\" text-anchor=\"end\">%s</text>\n" % [x0 - 6, yt + 4, COL_TEXT, _fmt(y_max)]
	s += "  <text x=\"%d\" y=\"%d\" fill=\"%s\" font-size=\"10\" text-anchor=\"end\">%s</text>\n" % [x0 - 6, yb + 4, COL_TEXT, _fmt(y_min)]

	# x tick labels
	for i in range(n):
		var tx: float = px.call(i)
		s += "  <text x=\"%s\" y=\"%d\" fill=\"%s\" font-size=\"10\" text-anchor=\"middle\">%s</text>\n" % [_num(tx), yb + 16, COL_TEXT, _xml(labels[i])]

	# p25–p75 band (a filled polygon: forward along p75, back along p25)
	if n >= 2:
		var pts := ""
		for i in range(n):
			pts += "%s,%s " % [_num(px.call(i)), _num(py.call(p75s[i]))]
		for i in range(n - 1, -1, -1):
			pts += "%s,%s " % [_num(px.call(i)), _num(py.call(p25s[i]))]
		s += "  <polygon points=\"%s\" fill=\"%s\" fill-opacity=\"0.12\" stroke=\"none\"/>\n" % [pts.strip_edges(), COL_BAND]

	# median polyline
	var line_pts := ""
	for i in range(n):
		line_pts += "%s,%s " % [_num(px.call(i)), _num(py.call(medians[i]))]
	s += "  <polyline points=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"2\"/>\n" % [line_pts.strip_edges(), COL_ACCENT]

	# point circles
	for i in range(n):
		s += "  <circle cx=\"%s\" cy=\"%s\" r=\"3\" fill=\"%s\"/>\n" % [_num(px.call(i)), _num(py.call(medians[i])), COL_ACCENT]

	# x-axis caption
	s += "  <text x=\"%d\" y=\"%d\" fill=\"%s\" font-size=\"10\" text-anchor=\"middle\">scale</text>\n" % [PAD_L + plot_w / 2, SVG_H - 6, COL_TEXT]

	s += "</svg>\n"
	return s


# ── Markdown ──────────────────────────────────────────────────────────────────

func _build_markdown(meta: Dictionary, groups: Dictionary, ordered_keys: Array) -> String:
	var ver := String(meta.get("godot_version", "?"))
	var os_name := String(meta.get("os", "?"))
	var iters := int(meta.get("iterations", 0))
	var warmup := int(meta.get("warmup", 0))
	var ts := String(meta.get("timestamp", "?"))
	var commit := String(meta.get("commit", "?"))

	var lines: Array[String] = []
	lines.append("Measured on Godot %s · %s · %d iters/%d warmup · snapshot %s (commit %s). Numbers are machine-specific; the meaningful signal is the SCALING SHAPE, not absolute µs." % [
		ver, os_name, iters, warmup, ts, commit])
	lines.append("")

	# Re-group by tier -> suite -> [gkey], preserving sorted order.
	var by_tier: Dictionary = {}
	for gkey: String in ordered_keys:
		var p := _key_parts(gkey)
		if not by_tier.has(p.tier):
			by_tier[p.tier] = {}
		if not by_tier[p.tier].has(p.suite):
			by_tier[p.tier][p.suite] = []
		by_tier[p.tier][p.suite].append(gkey)

	var tiers: Array = by_tier.keys()
	tiers.sort()
	for tier: String in tiers:
		lines.append("### Tier: %s" % tier)
		lines.append("")
		var suites: Array = by_tier[tier].keys()
		suites.sort()
		for suite: String in suites:
			lines.append("#### %s" % suite)
			lines.append("")
			# Charted "headline" benches render inline (chart + table). Everything else —
			# non-charted multi-scale benches and single-point benches — is collected into a
			# collapsed <details> block so the page stays short while keeping all the data.
			var detail: Array[String] = []
			var single_rows: Array = []
			var hidden := 0
			for gkey: String in by_tier[tier][suite]:
				var rows: Array = groups[gkey]
				rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
					return int(a.scale) < int(b.scale))
				var p := _key_parts(gkey)
				if _distinct_labels(rows).size() >= 2:
					if _is_charted(gkey):
						_append_bench_block(lines, gkey, p, rows)
					else:
						_append_bench_block(detail, gkey, p, rows)
						hidden += 1
				else:
					single_rows.append({parts = p, row = rows[0]})
			if not single_rows.is_empty():
				_append_single_table(detail, single_rows)
				hidden += single_rows.size()
			if not detail.is_empty():
				lines.append("<details>")
				lines.append("<summary>%d more %s benchmark%s — tables</summary>" % [
					hidden, suite, "" if hidden == 1 else "s"])
				lines.append("")  # blank line so GitHub renders the Markdown inside <details>
				lines.append_array(detail)
				lines.append("</details>")
				lines.append("")
	return "\n".join(lines)


func _append_bench_block(lines: Array[String], gkey: String, parts: Dictionary, rows: Array) -> void:
	var unit := String(rows[0].unit)
	lines.append("**%s** (%s)" % [parts.name, unit])
	lines.append("")
	# Curated headline benches get a chart; all multi-scale benches get the table below.
	if _is_charted(gkey):
		var stem := "%s__%s__%s" % [parts.tier, parts.suite, parts.name]
		# Prefer the rasterized PNG (renders in VS Code preview + GitHub); fall back to SVG.
		var img := stem + (".png" if FileAccess.file_exists(CHARTS_DIR + "/" + stem + ".png") else ".svg")
		lines.append("![%s](bench_charts/%s)" % [parts.name, img])
		lines.append("")
	lines.append("| scale | median | p95 | vs prev |")
	lines.append("| --- | ---: | ---: | ---: |")
	var prev_median := 0.0
	var first := true
	for r: Dictionary in rows:
		var med := float(r.stats.median)
		var p95 := float(r.stats.get("p95", r.stats.median))
		var factor := "—"
		if not first and prev_median > 0.0:
			factor = "%.2f×" % (med / prev_median)
		lines.append("| %s | %s | %s | %s |" % [r.scale_label, _fmt(med), _fmt(p95), factor])
		prev_median = med
		first = false
	lines.append("")


func _append_single_table(lines: Array[String], entries: Array) -> void:
	lines.append("| benchmark | scale | median | p95 | unit |")
	lines.append("| --- | --- | ---: | ---: | --- |")
	for e: Dictionary in entries:
		var r: Dictionary = e.row
		var med := float(r.stats.median)
		var p95 := float(r.stats.get("p95", r.stats.median))
		lines.append("| %s | %s | %s | %s | %s |" % [e.parts.name, r.scale_label, _fmt(med), _fmt(p95), r.unit])
	lines.append("")


func _inject_readme(section: String) -> String:
	var f := FileAccess.open(README_PATH, FileAccess.READ)
	if f == null:
		return "README missing at %s — section NOT injected." % README_PATH
	var text := f.get_as_text()
	f.close()

	var si := text.find(MARK_START)
	var ei := text.find(MARK_END)
	if si < 0 or ei < 0 or ei < si:
		return "Markers not found in README — section NOT injected."

	var before := text.substr(0, si + MARK_START.length())
	var after := text.substr(ei)
	var rebuilt := before + "\n\n" + section + "\n\n" + after
	_write_text(README_PATH, rebuilt)
	return "section injected between markers (%d bytes)." % section.length()


func _prune_stale_charts(groups: Dictionary) -> void:
	# Keep only charts (svg or png) for currently-allowlisted, still-chartable benches.
	var keep: Dictionary = {}
	for gkey: String in groups:
		var rows: Array = groups[gkey]
		if _distinct_labels(rows).size() >= 2 and _is_charted(gkey):
			var p := _key_parts(gkey)
			keep["%s__%s__%s" % [p.tier, p.suite, p.name]] = true
	var dir := DirAccess.open(CHARTS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var nm := dir.get_next()
	while nm != "":
		if not dir.current_is_dir() and (nm.ends_with(".svg") or nm.ends_with(".png")) and not keep.has(nm.get_basename()):
			dir.remove(nm)
		nm = dir.get_next()
	dir.list_dir_end()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[bench_report] cannot write %s" % path)
		return
	f.store_string(text)
	f.close()


## Rasterize an SVG to a 2x PNG (transparent bg preserved). Tries rsvg-convert, then
## ImageMagick. Returns true on success; on failure the caller keeps the SVG as a fallback.
func _rasterize(svg_res: String, png_res: String) -> bool:
	var svg_abs := ProjectSettings.globalize_path(svg_res)
	var png_abs := ProjectSettings.globalize_path(png_res)
	var out: Array = []
	if OS.execute("rsvg-convert", ["-z", "2", "-o", png_abs, svg_abs], out) == 0 and FileAccess.file_exists(png_abs):
		return true
	out = []
	if OS.execute("convert", ["-background", "none", "-density", "192", svg_abs, png_abs], out) == 0 and FileAccess.file_exists(png_abs):
		return true
	return false


func _xml(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


## Number formatting for axis/table values: compact, no spurious trailing zeros.
func _fmt(v: float) -> String:
	var a := absf(v)
	if a >= 1000.0:
		return "%.0f" % v
	if a >= 10.0:
		return "%.1f" % v
	if a >= 1.0:
		return "%.2f" % v
	return "%.3f" % v


## Coordinate formatting for the SVG: 2 decimals keeps files small + deterministic.
func _num(v: float) -> String:
	return "%.2f" % v
