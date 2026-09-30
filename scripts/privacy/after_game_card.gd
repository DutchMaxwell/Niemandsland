class_name AfterGameCard
extends CanvasLayer
## After-game card (PR B2): offers the last game for preview or local export. No send path:
## nothing is queued and no file is written unless Save locally runs. Dismissal = keep private.
## An in-viewport house-style panel (D98 a): its scrim owns the clicks, Esc / x / Keep private hide it.

const LAYER := 112
const WIDTH := 380
const COPY := {
	"en": {"card_title": "Share this game?", "keep_private": "Keep private", "preview": "Preview", "save_locally": "Save locally"},
	"de": {"card_title": "Diese Partie teilen?", "keep_private": "Privat behalten", "preview": "Vorschau", "save_locally": "Lokal speichern"},
}

var export_path := PrivacyMenu.LAST_GAME_EXPORT_PATH
var _menu: PrivacyMenu = null
var _keep_button: Button = null
var _status: Label = null


func _ready() -> void:
	layer = LAYER
	var parts := HouseStyle.overlay_sheet(_t("card_title"), WIDTH)
	(parts["close"] as Button).pressed.connect(hide)
	var box: VBoxContainer = parts["body"]
	_keep_button = _button(_t("keep_private"), "KeepPrivateButton", hide, HouseStyle.PRIMARY)
	box.add_child(_keep_button)
	box.add_child(_button(_t("preview"), "PreviewButton", _on_preview, HouseStyle.BUTTON))
	box.add_child(_button(_t("save_locally"), "SaveLocallyButton", _on_save_locally, HouseStyle.BUTTON))
	_status = HouseStyle.label("", HouseStyle.CAPTION)
	_status.name = "CardStatus"
	box.add_child(_status)
	add_child(parts["root"] as Control)


static func text_for(locale: String, key: String) -> String:
	var language := "de" if locale.to_lower().begins_with("de") else "en"
	return str((COPY[language] as Dictionary).get(key, ""))


func open_for(menu: PrivacyMenu) -> void:
	_menu = menu
	show()
	_keep_button.grab_focus()


func _on_preview() -> void:
	hide()
	if _menu != null: _menu.open_details()


func _on_save_locally() -> void:
	if _menu == null: return
	var saved: String = _menu.save_last_game_locally(export_path)
	if not saved.is_empty(): _status.text = _menu.localized_text("saved_last") % saved


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"): hide()


func _button(text: String, node_name: String, callback: Callable, variant: StringName) -> Button:
	var button := HouseStyle.button(text, variant, HouseStyle.H_ACTION)
	button.text = text
	button.name = node_name
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	return button


func _t(key: String) -> String:
	return text_for(TranslationServer.get_locale(), key)
