class_name MenuTicker
extends Label
## "Intel feed" quote ticker for the main menu: a mono line that types itself
## (typewriter on visible_characters), holds, fades and rotates to the next anti-war
## quote. Respects GraphicsSettings.reduce_motion (shows lines instantly).

# === Constants ===

const MONO_PATH := "res://assets/ui_glassmorphism/fonts/SourceCodePro.ttf"
const FONT_SIZE := 14
const PREFIX := "// "
const CHARS_PER_SECOND := 35.0
const HOLD_SECONDS := 20.0
const FADE_SECONDS := HudTokens.DUR_PANEL_OUT

## Anti-war quotes — the project's tone anchor (rotates while the menu is open).
const MENU_QUOTES: Array[String] = [
	"“Comrade, I did not want to kill you.” — Erich Maria Remarque · All Quiet on the Western Front (1929)",
	"“I see how peoples are set against one another, and in silence, unknowingly, foolishly, obediently, innocently slay one another.” — Erich Maria Remarque (1929)",
	"“We are forlorn like children, and experienced like old men; we are crude and sorrowful and superficial — I believe we are lost.” — Erich Maria Remarque (1929)",
	"“The dead only know one thing: it is better to be alive.” — Joker · Full Metal Jacket (1987)",
	"“Babies — infants who belong at their mothers' breasts. You feel ancient among all these kids.” — The Captain · Das Boot (1981)",
	"“We did not fight the enemy; we fought ourselves — and the enemy was in us.” — Chris Taylor · Platoon (1986)",
	"“The enemy is anybody who's going to get you killed, no matter which side he is on.” — Joseph Heller · Catch-22 (1961)",
	"“Patriotism is the last refuge of a scoundrel.” — Col. Dax · Paths of Glory (1957)",
	"“War don't ennoble men. It turns them into dogs — poisons the soul.” — Pvt. Witt · The Thin Red Line (1998)",
	"“The horror… the horror.” — Colonel Kurtz · Apocalypse Now (1979)",
]

# === Private variables ===

var _quote_index := -1
var _rng := RandomNumberGenerator.new()
var _tween: Tween = null

# === Lifecycle ===

func _ready() -> void:
	var mono := FontVariation.new()
	mono.base_font = load(MONO_PATH)
	add_theme_font_override("font", mono)
	add_theme_font_size_override("font_size", FONT_SIZE)
	# Brighter than TEXT_MUTED + a hard shadow: must stay readable over the bright
	# grass/fire areas of the diorama, not only over the scrim.
	add_theme_color_override("font_color", Color(HudTokens.TEXT.r, HudTokens.TEXT.g, HudTokens.TEXT.b, 0.92))
	add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 1)
	add_theme_constant_override("shadow_outline_size", 4)
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()  # presentation-only randomness

# === Public ===

## Starts (or restarts) the rotation. Split from _ready so the menu can delay the
## first line until the entrance choreography reaches the ticker beat.
func start() -> void:
	_show_next_quote()


## Pure rotation rule (unit-tested): picks the next index from a random draw,
## never repeating the current one.
static func next_index(current: int, count: int, rand: int) -> int:
	if count <= 1:
		return 0
	var idx := absi(rand) % count
	if idx == current:
		idx = (idx + 1) % count
	return idx

# === Private ===

func _show_next_quote() -> void:
	_quote_index = next_index(_quote_index, MENU_QUOTES.size(), _rng.randi())
	text = PREFIX + MENU_QUOTES[_quote_index]
	modulate.a = 1.0

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()

	if GraphicsSettings.reduce_motion:
		visible_characters = -1
		_tween.tween_interval(HOLD_SECONDS)
	else:
		visible_characters = 0
		var chars := text.length()
		_tween.tween_property(self, "visible_characters", chars, float(chars) / CHARS_PER_SECOND)
		_tween.tween_interval(HOLD_SECONDS)
		_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_callback(_show_next_quote)
