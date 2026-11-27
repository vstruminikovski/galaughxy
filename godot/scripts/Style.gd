class_name Style
extends RefCounted

## "Studio Vinyl": the one look for every model and map (CLAUDE.md section 20).
## - Palette: the seven Mac Studio colours, each in three values (light / base / shade). Every
##   surface colour snaps to the nearest of these 21 swatches, so nothing off-palette can appear.
## - Shading: two-band cel (toon) diffuse, a crisp vinyl highlight and a soft rim, everywhere.
## - No speckle, noise or gradients: flat swatch areas separated by the boiling ink line.

const BASE := {
	"silver": Color("#E5E7EB"), "space_gray": Color("#2C2E33"), "cream": Color("#F5F2EB"),
	"bondi_blue": Color("#4A90E2"), "coral": Color("#FF5F56"), "amber": Color("#FFBD2E"), "mint": Color("#27C93F"),
}
const LIGHT := 0.42   # light value: mix toward white
const SHADE := 0.32   # shade value: darken

static var _swatches: Array = []

static func swatches() -> Array:
	if _swatches.is_empty():
		for k in BASE:
			var c: Color = BASE[k]
			_swatches.append(c)
			_swatches.append(c.lerp(Color.WHITE, LIGHT))
			_swatches.append(c.darkened(SHADE))
	return _swatches

## A palette swatch by name and value: swatch("coral"), swatch("mint", "light"), swatch("bondi_blue", "shade").
static func swatch(name: String, value := "base") -> Color:
	var c: Color = BASE[name]
	match value:
		"light": return c.lerp(Color.WHITE, LIGHT)
		"shade": return c.darkened(SHADE)
	return c

## Nearest swatch (perceptual "redmean" distance). Alpha is kept.
static func snap(c: Color) -> Color:
	var best: Color = swatches()[0]
	var best_d := INF
	for s: Color in swatches():
		var rm := (c.r + s.r) * 0.5
		var dr := c.r - s.r
		var dg := c.g - s.g
		var db := c.b - s.b
		var d := (2.0 + rm) * dr * dr + 4.0 * dg * dg + (3.0 - rm) * db * db
		if d < best_d:
			best_d = d
			best = s
	return Color(best.r, best.g, best.b, c.a)

## Cel-shaded vinyl material. vertex = true uses snapped vertex colours as albedo.
static func toon(color := Color.WHITE, vertex := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = snap(color) if not vertex else Color.WHITE
	m.vertex_color_use_as_albedo = vertex
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.38
	m.metallic_specular = 0.35
	m.rim_enabled = true
	m.rim = 0.12
	m.rim_tint = 0.65
	return m

## Glowing (emissive, unshaded) material in a palette colour.
static func glow(color: Color) -> StandardMaterial3D:
	var c := snap(color)
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

## Re-dresses an imported model: every material becomes Studio Vinyl in its nearest swatch.
## Glowing parts stay glowing; glass stays see-through.
static func restyle(n: Node) -> void:
	for c in n.get_children():
		restyle(c)
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s) as BaseMaterial3D
		if src == null:
			mi.set_surface_override_material(s, toon(swatch("silver")))
			continue
		var m: StandardMaterial3D
		if src.emission_enabled:
			m = glow(src.emission if src.emission != Color.BLACK else src.albedo_color)
		else:
			m = toon(src.albedo_color)
			if src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color.a = src.albedo_color.a
		mi.set_surface_override_material(s, m)
