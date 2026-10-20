extends RefCounted
# The belt and the pockets, along the bottom, with the six keys that reach them.
#
# The numerals on it are key names, not measurements: docs/01 clause 4 bans a UI that collapses
# uncertainty into a number, and "press 3" collapses nothing. The stack tally beside a name is
# allowed for docs/10's reason -- counting discrete objects is not uncertainty being collapsed --
# and is the only other digit here.
#
# What the strip is *for* is the pinning this overhaul deleted. A pouch on your front was
# reachable mid-fight because its window could be pinned to the screen; now the six things on your
# belt and in your pockets are on screen always, and a number key spends one.

const Chrome = preload("res://ui/chrome.gd")
const Locker = preload("res://ui/locker.gd")
const UiText = preload("res://ui/text.gd")
const Motion = preload("res://ui/motion.gd")
const Appearance = preload("res://presentation/appearance.gd")
const ItemPicture = preload("res://ui/item_picture.gd")

const SLOTS: int = 6
const LEAD: String = "belt and pockets"
# The widest a slot grows: the width that keeps a name beside a 32 px picture. A strip too narrow
# for six of these shrinks them all evenly (`slot_boxes`) and the name gives up the difference.
const SLOT_W: float = 246.0
const SLOT_H: float = 62.0
const GAP: float = 12.0
const KEY_SIZE: int = 20
const NAME_SIZE: int = 25
# The picture's box in a slot: wide enough for the pack's 32 px icon at the world's 2x, lying flat
# when it is a long thing, so the strip and the bag draw one object at one size. It sits between the
# key's numeral and the name; on a slot too narrow to keep the name beside it, the picture goes.
const PICTURE: float = 72.0
const PICTURE_GAP: float = 6.0
# Where a slot's contents start: past the key's numeral in the well's corner.
const KEY_W: float = 22.0
# The least room a name keeps beside a picture at 2x; under it the picture drops to the art's size.
const NAME_ROOM: float = 120.0
# The strip's own inset from the rect's left and right, and around its lead.
const SIDE: float = 24.0


# `selected` is the inventory sheet's currently-picked item, so a belt or pocket slot that holds
# it wears the same ring the bag grid gives it -- what you clicked cannot look like two different
# things depending on which panel it is drawn in. -1 (the default) picks nothing.
#
# `ping` is `{item, frame}` for the thing the player last picked up, while the kit's item_ping is
# still playing; {} for none. The slot holding that item wears it; an item that went into a bag
# rather than onto the strip, or merged into a stack under another id, pings the strip's lead
# instead -- something went in, and the sheet says where.
#
# `world` is what a picture is resolved against: a filled slot draws the same picture the bag plate
# and the floor draw for that base -- the pack's icon, or its class's glyph where the pack has none --
# through `Appearance.item_look`. With no world a slot is words alone, as it was before the pictures.
static func draw_strip(ci: CanvasItem, rect: Rect2, rows: Array, alpha: float, selected: int = -1, ping: Dictionary = {}, world: Variant = null) -> void:
	Locker.panel(ci, rect, alpha)
	var font: Font = Chrome.font()
	var lead_y: float = floorf(rect.position.y + (rect.size.y - Chrome.line_height(KEY_SIZE)) / 2.0 + Chrome.ascent(KEY_SIZE))
	ci.draw_string(font, Vector2(rect.position.x + SIDE, lead_y), LEAD, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_SIZE, Locker._a(Locker.TEXT_DIM, alpha))
	var lead_w: float = lead_width(font)
	var boxes: Array[Rect2] = slot_boxes(font, rect)
	var y: float = rect.position.y + (rect.size.y - SLOT_H) / 2.0
	var ping_slot: int = ping_slot_of(rows, ping)
	if ping_slot == -1 and not ping.is_empty():
		_draw_ping(ci, Rect2(rect.position + Vector2(SIDE, y - rect.position.y), Vector2(lead_w, SLOT_H)), int(ping.get("frame", -1)))
	var mid: float = SLOT_H / 2.0 - Chrome.line_height(NAME_SIZE) / 2.0 + Chrome.ascent(NAME_SIZE)
	for i in SLOTS:
		var box: Rect2 = boxes[i]
		var picked: bool = selected != -1 and i < rows.size() and int((rows[i] as Dictionary).get("item", -1)) == selected
		Locker.well(ci, box, alpha)
		# The key's numeral, small and amber in the well's corner: a key name, not a measurement.
		ci.draw_string(font, box.position + Vector2(Locker.PX * 3.0, Locker.PX * 2.0 + Chrome.ascent(KEY_SIZE)), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_SIZE, Locker._a(Locker.ACCENT, alpha))
		var name_x: float = KEY_W
		var wide: float = box.size.x - KEY_W - Locker.PX * 4.0
		if i < rows.size():
			var d: Dictionary = rows[i] as Dictionary
			var text: String = String(d.get("name", ""))
			var count: int = int(d.get("count", 1))
			if world != null:
				# The same picture the bag plate draws, at the same 2x, wherever the slot is wide
				# enough to keep a few letters of the name beside it.
				# At the world's 2x where the name keeps room for a word beside it, the art's own size
				# where it does not: a narrow strip (1280) keeps "Kitchen Knife" readable rather than
				# trading it for a bigger knife. Never turned -- a strip slot is not a footprint.
				var look: Dictionary = Appearance.item_look(world, ItemPicture.base_of(world, int(d.get("item", -1))))
				var big: bool = wide - PICTURE - PICTURE_GAP >= NAME_ROOM
				var pw: float = PICTURE if big else PICTURE / 2.0
				ItemPicture.draw(ci, Rect2(box.position + Vector2(name_x, Locker.PX * 2.0), Vector2(pw, SLOT_H - Locker.PX * 4.0)), look, alpha, 2 if big else 1, false)
				name_x += pw + PICTURE_GAP
				wide -= pw + PICTURE_GAP
			if count > 1:
				var tally: String = "x%d" % count
				var tw: float = font.get_string_size(tally, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_SIZE).x
				Locker.text_shadowed(ci, box.end - Vector2(tw + Locker.PX * 3.0, Locker.PX * 3.0), tally, KEY_SIZE, Locker.ACCENT, alpha)
				wide -= tw + Locker.PX * 2.0
			ci.draw_string(font, box.position + Vector2(name_x, mid), UiText.fit(font, text, NAME_SIZE, maxf(wide, 1.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, Locker._a(Locker.TEXT, alpha))
		else:
			ci.draw_string(font, box.position + Vector2(name_x, mid), UiText.fit(font, "empty", NAME_SIZE, maxf(wide, 1.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, Locker._a(Locker.TEXT_FAINT, alpha))
		if picked:
			Locker.selected(ci, box, alpha)
		if i == ping_slot:
			_draw_ping(ci, box, int(ping.get("frame", -1)))


# The lead's width: the label the six slots sit to the right of.
static func lead_width(font: Font) -> float:
	return font.get_string_size(LEAD, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_SIZE).x


# The six slots' boxes inside `rect`: from the end of the lead to one inset short of the rect's right
# edge, `SLOT_W` wide where that fits and evenly narrower where it does not -- so at any width every
# slot lies wholly inside the strip, and the picture (a fixed 32 px, never resampled) keeps its
# place while the name is fitted to what is left. Whole pixels, so the boxes and the frames drawn
# on them agree. Pure, so the gate can ask it at any width without a canvas.
static func slot_boxes(font: Font, rect: Rect2) -> Array[Rect2]:
	var x0: float = rect.position.x + SIDE + lead_width(font) + SIDE
	var room: float = rect.end.x - SIDE - x0 - GAP * float(SLOTS - 1)
	var w: float = minf(SLOT_W, floorf(room / float(SLOTS)))
	var y: float = rect.position.y + (rect.size.y - SLOT_H) / 2.0
	var out: Array[Rect2] = []
	for i in SLOTS:
		out.append(Rect2(Vector2(x0 + (w + GAP) * float(i), y), Vector2(w, SLOT_H)))
	return out


# Which of the strip's slots holds the pinged item: -1 for no ping, or for an item not on the
# strip. Pure, so the gate can ask it without a canvas.
static func ping_slot_of(rows: Array, ping: Dictionary) -> int:
	if ping.is_empty():
		return -1
	var item: int = int(ping.get("item", -1))
	for i in mini(rows.size(), SLOTS):
		if int((rows[i] as Dictionary).get("item", -2)) == item:
			return i
	return -1


# The items `actor` picked up in one tick's drained events, in order: `sim/modules/inventory.gd`
# publishes `item.pickedUp` for every pick-up by anybody, and only the player's own reach a slot
# the player is looking at -- a colonist looting across the street is not your belt filling.
static func pickups_by(drained: Array, actor: int) -> Array[int]:
	var out: Array[int] = []
	for e in drained:
		if not (e is Dictionary):
			continue
		var ev: Dictionary = e as Dictionary
		if String(ev.get("type", "")) == "item.pickedUp" and int(ev.get("entity", -1)) == actor:
			out.append(int(ev.get("item", -1)))
	return out


# The ping's one frame, centred on `box` at native kit size (its 32 px doubled is taller than a
# slot).
static func _draw_ping(ci: CanvasItem, box: Rect2, frame: int) -> void:
	var tex: Texture2D = Motion.texture_of("item_ping", frame, 1)
	if tex == null:
		return
	ci.draw_texture(tex, (box.get_center() - tex.get_size() * 0.5).round())


# Where the strip sits: full width along the bottom, above the margin.
static func rect_for(view: Vector2, pad: float, height: float) -> Rect2:
	return Rect2(Vector2(pad, view.y - pad - height), Vector2(view.x - pad * 2.0, height))
