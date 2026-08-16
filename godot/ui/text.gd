extends RefCounted
# Fitting text to a box without lying about it.
#
# The panels used to trim with substr(0, 9), which turns "Kitchen Knife" into "Kitchen K" --
# a cut that depends on nothing about the actual box and reads as a bug. Measuring against
# the font uses the whole box when the string fits and marks the cut when it does not.

const ELLIPSIS: String = "…"


# The longest prefix of `text` that fits in `max_width`, with an ellipsis when trimmed.
static func fit(font: Font, text: String, font_size: int, max_width: float) -> String:
	if font == null or text.is_empty() or max_width <= 0.0:
		return text
	if _width(font, text, font_size) <= max_width:
		return text
	var trimmed: String = text
	while trimmed.length() > 1:
		trimmed = trimmed.substr(0, trimmed.length() - 1)
		if _width(font, trimmed + ELLIPSIS, font_size) <= max_width:
			return trimmed.strip_edges(false, true) + ELLIPSIS
	return ELLIPSIS


static func _width(font: Font, text: String, font_size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
