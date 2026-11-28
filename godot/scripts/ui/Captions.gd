class_name Captions
extends Control

## Shorts / TikTok-style captions: bold yellow words with a dark outline, one to three words at a
## time, timed to the dialogue line. The chunks share the spoken time in proportion to their length
## (each at least MIN_CHUNK); the last one stays HOLD seconds after the line ends.
## What is on screen (which chunk, its pop-in scale) is a pure function of the clock passed to
## tick(): no Tweens, so a scrubbed second or a movie-export frame always shows the same caption.

const FONT := preload("res://assets/fonts/Poppins-ExtraBold.ttf")   # SIL OFL 1.1, see OFL-Poppins.txt
const FILL := Color("#FFD43B")
const OUTLINE := Color("#141018")
const SHADOW := Color("#00000080")
const SIZE_OF_HEIGHT := 0.054   # font size as a share of the viewport height (~58 px at 1080p)
const OUTLINE_OF_SIZE := 0.22
const SHADOW_OF_SIZE := 0.05
const WIDTH := 0.84             # text wraps inside this share of the viewport width
const Y_LANDSCAPE := 0.72       # vertical centre, as a share of the viewport height
const Y_PORTRAIT := 0.64
const MAX_WORDS := 3
const MAX_CHARS := 16
const MIN_CHUNK := 0.18         # seconds a chunk stays on screen, at least
const HOLD := 0.3               # the last chunk stays this long after the line ends
const POP := 0.14               # pop-in: 0.82 -> 1.06 -> 1.0 over this many seconds
const POP_PEAK := 0.6           # share of POP spent growing to the overshoot
const SENTENCE_END := ".!?…"
const SOFT_BREAK := ",;:—–"
const CLOSERS := "\"'”’)]"
const PUNCT := ".,!?;:…—–-\"'“”‘’()[]"

var label: Label
var line_text := ""             # the whole line being captioned ("" when none)
var _chunks: Array = []
var _starts: Array = []         # clock at which each chunk starts
var _end := 0.0
var _shown := -1

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_color_override("font_color", FILL)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_color_override("font_shadow_color", SHADOW)
	label.visible = false
	add_child(label)

func _ready() -> void:
	_layout()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()

## Font size, outline, shadow and placement follow the viewport size.
func _layout() -> void:
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var fs := maxi(8, roundi(vp.y * SIZE_OF_HEIGHT))
	var outline := maxi(1, roundi(fs * OUTLINE_OF_SIZE))
	label.add_theme_font_size_override("font_size", fs)
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_constant_override("shadow_outline_size", outline)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", maxi(1, roundi(fs * SHADOW_OF_SIZE)))
	# a box with room for several wrapped lines, centred on the caption line: the text sits in its
	# middle, so the pivot (the box centre) is also the text centre
	var box := Vector2(vp.x * WIDTH, fs * 6.0)
	var cy := vp.y * (Y_PORTRAIT if vp.y > vp.x else Y_LANDSCAPE)
	label.position = Vector2((vp.x - box.x) * 0.5, cy - box.y * 0.5)
	label.size = box
	label.pivot_offset = box * 0.5

## Captions `text` over [start_clock, end_clock]: the words are spoken until end_clock - HOLD.
func show_line(text: String, start_clock: float, end_clock: float) -> void:
	line_text = text
	_chunks = chunks(text)
	_starts = schedule(_chunks, start_clock, end_clock)
	_end = end_clock
	_shown = -1
	tick(start_clock)

## Shows the chunk for `clock`, popping in as it starts; nothing before the line or after its end.
func tick(clock: float) -> void:
	var i := chunk_at(clock)
	if i < 0:
		label.visible = false
		_shown = -1
		return
	if i != _shown:
		label.text = _chunks[i]
		_shown = i
	label.scale = Vector2.ONE * pop_scale(clock - float(_starts[i]))
	label.visible = true

func clear() -> void:
	line_text = ""
	_chunks = []
	_starts = []
	_shown = -1
	label.visible = false

func showing() -> bool:
	return label.visible

## The chunk on screen ("" when hidden).
func current() -> String:
	return label.text if label.visible else ""

## Index of the chunk for `clock`, or -1 (no line, before it starts, or after end_clock).
func chunk_at(clock: float) -> int:
	if _chunks.is_empty() or clock < float(_starts[0]) or clock > _end:
		return -1
	var i := _chunks.size() - 1
	while i > 0 and clock < float(_starts[i]):
		i -= 1
	return i

## Pop-in scale `age` seconds into a chunk: 0.82 -> 1.06 (easing out) -> 1.0 (settling) over POP.
static func pop_scale(age: float) -> float:
	var k := clampf(age / POP, 0.0, 1.0)
	if k < POP_PEAK:
		return lerpf(0.82, 1.06, sin(k / POP_PEAK * PI * 0.5))
	return lerpf(1.06, 1.0, smoothstep(POP_PEAK, 1.0, k))

## Clock at which each chunk starts. Each chunk gets a share of [start, end - HOLD] in proportion
## to its character count, but at least MIN_CHUNK. A line too short even for that is squeezed
## evenly into [start, end], so every chunk still shows.
static func schedule(list: Array, start: float, end: float) -> Array:
	var n := list.size()
	var weight: Array = list.map(func(c): return maxf(1.0, String(c).length()))
	var span := maxf(0.0, end - HOLD - start)
	var dur: Array = []
	dur.resize(n)
	dur.fill(MIN_CHUNK)
	var pinned: Array = []
	pinned.resize(n)
	pinned.fill(false)
	var again := true
	while again:   # pin chunks whose share is under MIN_CHUNK, then share the rest again
		again = false
		var free_span := span
		var free_weight := 0.0
		for i in n:
			if pinned[i]:
				free_span -= MIN_CHUNK
			else:
				free_weight += weight[i]
		for i in n:
			if pinned[i]:
				continue
			dur[i] = free_span * weight[i] / free_weight
			if dur[i] < MIN_CHUNK:
				dur[i] = MIN_CHUNK
				pinned[i] = true
				again = true
	var total := 0.0
	for d in dur:
		total += d
	var squeeze := minf(1.0, maxf(0.0, end - start) / total) if total > 0.0 else 1.0
	var starts: Array = []
	var t := start
	for d in dur:
		starts.append(t)
		t += d * squeeze
	return starts

## Caption chunks of 1-3 words and at most about MAX_CHARS characters (a longer word stands alone).
## Punctuation stays on its word, and a chunk never runs across a sentence end (. ! ?). Inside a
## sentence the split is the most even one (2 + 2 rather than 3 + 1) and prefers to break after a
## comma.
static func chunks(text: String) -> Array:
	var out: Array = []
	var sentence := PackedStringArray()
	for w in _words(text):
		sentence.append(w)
		if _ends_sentence(w):
			out.append_array(_split(sentence))
			sentence = PackedStringArray()
	out.append_array(_split(sentence))
	return out

## Words split on spaces. A token of punctuation only (a spaced dash, "...") joins the word before
## it, or the next word when it follows a sentence end.
static func _words(text: String) -> PackedStringArray:
	var words := PackedStringArray()
	var lead := ""
	for tok in text.replace("\n", " ").replace("\t", " ").split(" ", false):
		if _is_punct(tok):
			if words.is_empty() or _ends_sentence(words[words.size() - 1]):
				lead += tok + " "
			else:
				words[words.size() - 1] += " " + tok
			continue
		words.append(lead + tok)
		lead = ""
	if lead != "":
		if words.is_empty():
			words.append(lead.strip_edges())
		else:
			words[words.size() - 1] += " " + lead.strip_edges()
	return words

static func _is_punct(tok: String) -> bool:
	for c in tok:
		if not PUNCT.contains(c):
			return false
	return true

static func _ends_sentence(w: String) -> bool:
	var s := w
	while s.length() > 1 and CLOSERS.contains(s[s.length() - 1]):
		s = s.left(-1)
	return s != "" and SENTENCE_END.contains(s[s.length() - 1])

## The best split of one sentence: fewest chunks, then the most even, breaking after commas.
static func _split(words: PackedStringArray) -> Array:
	var n := words.size()
	var cost: Array = [0.0]
	var prev: Array = [0]
	for i in range(1, n + 1):
		cost.append(INF)
		prev.append(i - 1)
		for k in range(1, mini(MAX_WORDS, i) + 1):
			var part := words.slice(i - k, i)
			if k > 1 and " ".join(part).length() > MAX_CHARS:
				break
			var c: float = cost[i - k] + _cost(part)
			if c <= cost[i]:   # ties go to the longer last chunk
				cost[i] = c
				prev[i] = i - k
	var out: Array = []
	var at := n
	while at > 0:
		out.push_front(" ".join(words.slice(prev[at], at)))
		at = prev[at]
	return out

static func _cost(part: PackedStringArray) -> float:
	var c := 1.0 + 0.15 * pow(MAX_WORDS - part.size(), 2)
	for j in part.size() - 1:
		var w := part[j]
		if SOFT_BREAK.contains(w[w.length() - 1]):
			c += 0.4   # a comma inside a chunk reads better as a break
	return c
