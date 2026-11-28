class_name Style
extends RefCounted

## Palettes and materials for both looks (Look.style; CLAUDE.md sections 20 and 24).
## Every model is authored in the seven Mac Studio colours, three values each (21 swatches).
## - Studio Vinyl shows those swatches as they are: two-band cel shading, a crisp vinyl
##   highlight and a soft rim.
## - Illustrated Ink maps each swatch to its illustration counterpart: same family and value,
##   richer hue (Bondi blue -> denim, coral -> vermilion, mint -> olive, silver -> cool white...).
##   It draws them with shaders/illustrated.gdshader: crisp terminator, cool shadows, warm rim,
##   hatching in the shadows.
## Either way every surface colour snaps to a swatch, so nothing off-palette can appear.

const BASE := {
	"silver": Color("#E5E7EB"), "space_gray": Color("#2C2E33"), "cream": Color("#F5F2EB"),
	"bondi_blue": Color("#4A90E2"), "coral": Color("#FF5F56"), "amber": Color("#FFBD2E"), "mint": Color("#27C93F"),
}
const LIGHT := 0.42   # Vinyl light value: mix toward white
const SHADE := 0.32   # Vinyl shade value: darken

## Illustrated counterparts, [base, light, shade] per family. Hand-mixed: lights lean warm and
## shades lean cool, like an illustrator's paints.
const ILL := {
	"silver": ["#CDD1DC", "#F2F1ED", "#8C92A9"],
	"space_gray": ["#2C3149", "#5A6079", "#191C2D"],
	"cream": ["#EFE2CA", "#FBF5E8", "#C4AF91"],
	"bondi_blue": ["#6E8DD3", "#A9BEEB", "#465BA0"],
	"coral": ["#E2583E", "#F39B7F", "#A3363A"],
	"amber": ["#EDB23B", "#F8D87D", "#B5762D"],
	"mint": ["#93A845", "#C4CF7F", "#5B7233"],
}
const VALUES := {"base": 0, "light": 1, "shade": 2}

## Hatching per kind of surface (Illustrated Ink). hatch = shadow strokes, texture = strokes on lit
## areas, stroke = typical stroke length in metres.
const KINDS := {
	"character": {"hatch": 1.0, "texture": 0.35, "stroke": 0.04, "snow": 0.3},
	"prop": {"hatch": 0.9, "texture": 0.15, "stroke": 0.06, "snow": 0.9},
	"set": {"hatch": 0.8, "texture": 0.0, "stroke": 0.12, "snow": 1.0},
	"flat": {"hatch": 0.45, "texture": 0.0, "stroke": 0.16, "snow": 1.0},
}

static var _vinyl: Array = []
static var _ill: Array = []
static var _shaders := {}

static func _vinyl_list() -> Array:
	if _vinyl.is_empty():
		for k in BASE:
			var c: Color = BASE[k]
			_vinyl.append(c)
			_vinyl.append(c.lerp(Color.WHITE, LIGHT))
			_vinyl.append(c.darkened(SHADE))
	return _vinyl

static func _ill_list() -> Array:
	if _ill.is_empty():
		for k in BASE:
			for hexc: String in ILL[k]:
				_ill.append(Color(hexc))
	return _ill

## The current look's 21 swatches (the same order in both looks: family by family, base / light / shade).
static func swatches() -> Array:
	return _ill_list() if Look.illustrated() else _vinyl_list()

## A palette swatch by name and value: swatch("coral"), swatch("mint", "light"), swatch("bondi_blue", "shade").
static func swatch(name: String, value := "base") -> Color:
	return swatches()[BASE.keys().find(name) * 3 + int(VALUES.get(value, 0))]

static func _dist(c: Color, s: Color) -> float:
	var rm := (c.r + s.r) * 0.5
	var dr := c.r - s.r
	var dg := c.g - s.g
	var db := c.b - s.b
	return (2.0 + rm) * dr * dr + 4.0 * dg * dg + (3.0 - rm) * db * db

## Nearest swatch (perceptual "redmean" distance), shown in the current look. Alpha is kept.
## Illustrated Ink also recognises its own swatches, so snapping twice changes nothing.
static func snap(c: Color) -> Color:
	var lists := [_vinyl_list()]
	if Look.illustrated():
		lists.append(_ill_list())
	var best := 0
	var best_d := INF
	for arr: Array in lists:
		for i in arr.size():
			var d := _dist(c, arr[i])
			if d < best_d:
				best_d = d
				best = i
	var s: Color = swatches()[best]
	return Color(s.r, s.g, s.b, c.a)

## The illustrated surface shader, with back faces and/or transparency when asked.
static func _shader(variant: String) -> Shader:
	if _shaders.has(variant):
		return _shaders[variant]
	var base := load("res://shaders/illustrated.gdshader") as Shader
	var sh := base
	if variant != "":
		var code := base.code
		if variant.contains("double"):
			code = code.replace("render_mode cull_back;", "render_mode cull_disabled;")
		if variant.contains("alpha"):
			code = code.replace("//VARIANT", "#define USE_ALPHA")
		sh = Shader.new()
		sh.code = code
	_shaders[variant] = sh
	return sh

## Lit material in a palette colour. vertex = true uses (snapped) vertex or MultiMesh instance colours.
## opts: kind ("character" / "prop" / "set" / "flat"), double (no back-face culling), alpha, gloss,
## hatch, texture, stroke, seed.
static func toon(color := Color.WHITE, vertex := false, opts := {}) -> Material:
	var c := snap(color) if not vertex else Color.WHITE
	var clear := opts.has("alpha")
	if clear:
		c.a = float(opts["alpha"])
	var m: Material
	if Look.illustrated():
		var k: Dictionary = KINDS.get(String(opts.get("kind", "prop")), KINDS["prop"])
		var sm := ShaderMaterial.new()
		sm.shader = _shader(("double" if opts.get("double", false) else "") + ("alpha" if clear else ""))
		sm.set_shader_parameter("albedo", c)
		sm.set_shader_parameter("use_vcol", vertex)
		sm.set_shader_parameter("hatch_amt", float(opts.get("hatch", k["hatch"])))
		sm.set_shader_parameter("texture_amt", float(opts.get("texture", k["texture"])))
		sm.set_shader_parameter("stroke_len", float(opts.get("stroke", k["stroke"])))
		sm.set_shader_parameter("snow_amt", float(opts.get("snow", k["snow"])))
		var gloss := 0.5 if (not vertex and c.get_luminance() < 0.22) else 0.0
		sm.set_shader_parameter("gloss", float(opts.get("gloss", gloss)))
		sm.set_shader_parameter("stroke_seed", float(opts.get("seed", fmod(c.r * 13.0 + c.g * 7.0 + c.b * 3.0, 10.0))))
		# leaves sway (set and prop surfaces: green vertices, or a green surface colour)
		var outdoorsy := String(opts.get("kind", "prop")) in ["set", "prop"]
		var leafy := vertex or InkStroke.leafiness(c) > 0.5
		sm.set_shader_parameter("wind_amt", float(opts.get("wind", 1.0 if outdoorsy and leafy else 0.0)))
		m = sm
	else:
		var s := StandardMaterial3D.new()
		s.albedo_color = c
		s.vertex_color_use_as_albedo = vertex
		s.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		s.specular_mode = BaseMaterial3D.SPECULAR_TOON
		s.roughness = 0.38
		s.metallic_specular = 0.35
		s.rim_enabled = true
		s.rim = 0.12
		s.rim_tint = 0.65
		if opts.get("double", false):
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
		if clear:
			s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m = s
	m.set_meta("color", c)
	if clear:
		m.set_meta("clear", true)
	return m

## Glowing (emissive, unshaded) material in a palette colour. Illustrated Ink pushes it past
## white so it blooms.
static func glow(color: Color, energy := 1.6) -> StandardMaterial3D:
	var c := snap(color)
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if Look.illustrated():
		var k := 1.0 + 0.35 * energy
		m.albedo_color = Color(c.r * k, c.g * k, c.b * k, c.a)
	m.set_meta("glow", true)
	m.set_meta("color", c)
	return m

## The palette colour a material was made with.
static func color_of(m: Material) -> Color:
	if m == null:
		return Color.WHITE
	if m.has_meta("color"):
		return m.get_meta("color")
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	return Color.WHITE

static func is_glow(m: Material) -> bool:
	if m == null:
		return false
	if m.has_meta("glow"):
		return true
	return m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled

static func is_clear(m: Material) -> bool:
	if m == null:
		return false
	if m.has_meta("clear"):
		return true
	return m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED

## Re-dresses an imported model in the current look, swatch by swatch. Glowing parts stay glowing;
## glass stays see-through. kind sets the hatching ("character", "prop", "set"); map pieces named
## Flat_* (floors) and Prop_* pick their own kind.
static func restyle(n: Node, kind := "prop") -> void:
	var k := kind
	var nm := String(n.name)
	if nm.begins_with("Flat"):
		k = "flat"
	elif nm.begins_with("Prop_"):
		k = "prop"
	for c in n.get_children():
		restyle(c, k)
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s) as BaseMaterial3D
		var m: Material
		if src == null:
			m = toon(swatch("silver"), false, {"kind": k})
		elif src.emission_enabled:
			m = glow(src.emission if src.emission != Color.BLACK else src.albedo_color)
		elif src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			m = toon(src.albedo_color, false, {"kind": k, "alpha": src.albedo_color.a})
		else:
			m = toon(src.albedo_color, false, {"kind": k})
		mi.set_surface_override_material(s, m)
