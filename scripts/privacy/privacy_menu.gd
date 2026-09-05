class_name PrivacyMenu
extends Window
## Consent and byte-exact example preview. This milestone deliberately has no send
## path: the only write is the player's explicit local example export.

const FIXTURE_PATH := "res://assets/privacy/example_record.json"
const EXPORT_PATH := "user://shared_records/example.json"
const Builder := preload("res://scripts/privacy/shared_record_builder.gd")
const Store := preload("res://scripts/privacy/consent_store.gd")

const COPY := {
	"en": {
		"title": "Privacy & data",
		"heading": "Help improve the computer opponent",
		"question": "May Niemandsland share de-identified records of games you choose for evaluation?",
		"summary": "They can contain board setup, armies, actions, dice, result, and game/brain versions. They never contain player names, chat, room codes, account or device identifiers, or save files.",
		"review_exact": "Review the exact fields and an example of exactly what we would send",
		"no_thanks": "No thanks",
		"review": "Review details",
		"example": "EXAMPLE — not your last game",
		"allow_evaluation": "Allow evaluation sharing",
		"withdraw": "Withdraw evaluation sharing",
		"allow_training": "Allow use for training",
		"save": "Save example locally",
		"close": "Close",
		"settings_section": "PRIVACY & DATA:",
		"deletion_code": "Deletion code",
		"build_failed": "Could not build example data.",
		"create_failed": "Could not create %s",
		"write_failed": "Could not write %s",
		"saved": "Saved exact example bytes to %s",
		"fields": "Fields in the record:\n• payload_schema_version — payload format number\n• consent_schema_version — consent wording version\n• deletion_code — random installation deletion code\n• record_id — random record identifier\n• game_version and build_hash — public game build\n• core_abi and rules_epoch — rules-engine versions\n• training_use — whether separate training permission was given\n• brain.engine, brain.id and brain.hash — public opponent version, or Classic\n• game.system_id, mission_id and scoring_id — public rules identifiers\n• game.random_seed, layout_seed and dice_seed — game seeds when known\n• table.width_inches and height_inches — table size\n• table.terrain — type identifiers, coordinates and rotations\n• table.objectives — type identifiers, coordinates and owner numbers\n• armies — side, book and faction identifiers\n• armies.units — stable unit/profile identifiers, numeric quality, defense and model count, plus loadout/rule identifiers\n• actions — ordered index, round, side, stable unit/action/target identifiers, coordinates, observed dice faces and numeric score\n• rounds — completed round count\n• final.vp, objective_owners and outcome — final numeric score and result\n• payload_sha256 — integrity hash of all preceding fields",
		"never": "Never collected in this record:\nPlayer, army or unit display names; chat or battle-log prose; room codes; multiplayer identity tokens; account, platform, device or IP identifiers; save files; screenshots; timestamps; file paths; host names; hardware inventory; unrelated diagnostics.",
		"destination": "Destination: to be published by the maintainer",
		"controller": "Controller: to be published by the maintainer",
		"processor": "Processor and hosting region: to be published by the maintainer",
		"purposes": "Purposes: evaluation and blind-spot discovery; training only with the separate training permission",
		"recipients": "Recipients: to be published by the maintainer",
		"retention": "Retention: to be published by the maintainer",
		"withdrawal": "Withdrawal is available on this page at any time and stops future sharing immediately. Deletion-request route: to be published by the maintainer",
		"contact": "Contact, privacy notice and supervisory-authority route: to be published by the maintainer",
	},
	"de": {
		"title": "Datenschutz & Daten",
		"heading": "Computerspieler verbessern",
		"question": "Darf Niemandsland pseudonymisierte Daten aus Partien, die du auswählst, zur Auswertung bereitstellen?",
		"summary": "Enthalten sein können Spielfeldaufbau, Armeen, Aktionen, Würfel, Ergebnis sowie Spiel- und Gehirnversion. Niemals enthalten sind Spielernamen, Chat, Raumcodes, Konto-/Gerätekennungen oder Spielstände.",
		"review_exact": "Prüfe vor deiner Entscheidung alle Felder und ein Beispiel dessen, was genau gesendet würde",
		"no_thanks": "Nein, danke",
		"review": "Details prüfen",
		"example": "BEISPIEL — nicht deine letzte Partie",
		"allow_evaluation": "Auswertung erlauben",
		"withdraw": "Auswertung nicht mehr erlauben",
		"allow_training": "Nutzung fürs Training erlauben",
		"save": "Beispiel lokal speichern",
		"close": "Schließen",
		"settings_section": "DATENSCHUTZ & DATEN:",
		"deletion_code": "Löschcode",
		"build_failed": "Die Beispieldaten konnten nicht erstellt werden.",
		"create_failed": "%s konnte nicht angelegt werden",
		"write_failed": "%s konnte nicht geschrieben werden",
		"saved": "Die exakten Beispieldaten wurden unter %s gespeichert",
		"fields": "Felder im Datensatz:\n• payload_schema_version — Nummer des Datenformats\n• consent_schema_version — Version dieser Einwilligung\n• deletion_code — zufälliger Löschcode dieser Installation\n• record_id — zufällige Kennung des Datensatzes\n• game_version und build_hash — öffentliche Spielversion\n• core_abi und rules_epoch — Versionen der Regel-Engine\n• training_use — ob die getrennte Trainingsfreigabe erteilt wurde\n• brain.engine, brain.id und brain.hash — öffentliche Gegnerversion oder Classic\n• game.system_id, mission_id und scoring_id — öffentliche Regelkennungen\n• game.random_seed, layout_seed und dice_seed — bekannte Spiel-Zufallswerte\n• table.width_inches und height_inches — Tischgröße\n• table.terrain — Typkennungen, Koordinaten und Drehungen\n• table.objectives — Typkennungen, Koordinaten und Besitznummern\n• armies — Seite sowie Buch- und Fraktionskennungen\n• armies.units — stabile Einheiten-/Profilkennungen, Zahlenwerte und Ausrüstungs-/Regelkennungen\n• actions — Reihenfolge, Runde, Seite, stabile Aktions-/Einheiten-/Zielkennungen, Koordinaten, beobachtete Würfelaugen und Zahlenwert\n• rounds — Zahl abgeschlossener Runden\n• final.vp, objective_owners und outcome — Endstand und Ergebnis\n• payload_sha256 — Prüfsumme aller vorherigen Felder",
		"never": "Niemals in diesem Datensatz erhoben:\nAnzeige-Namen von Spielern, Armeen oder Einheiten; Chat oder Schlachtprosa; Raumcodes; Mehrspieler-Identitätsschlüssel; Konto-, Plattform-, Geräte- oder IP-Kennungen; Spielstände; Bildschirmfotos; Zeitstempel; Dateipfade; Rechnernamen; Hardwaredaten; sonstige Diagnosen.",
		"destination": "Ziel: wird vom Betreiber veröffentlicht",
		"controller": "Verantwortlicher: wird vom Betreiber veröffentlicht",
		"processor": "Auftragsverarbeiter und Hosting-Region: wird vom Betreiber veröffentlicht",
		"purposes": "Zwecke: Auswertung und Suche nach blinden Flecken; Training nur mit der getrennten Trainingsfreigabe",
		"recipients": "Empfänger: wird vom Betreiber veröffentlicht",
		"retention": "Speicherdauer: wird vom Betreiber veröffentlicht",
		"withdrawal": "Widerruf ist jederzeit auf dieser Seite möglich und stoppt künftige Freigaben sofort. Weg für Löschwünsche: wird vom Betreiber veröffentlicht",
		"contact": "Kontakt, Datenschutzhinweis und Aufsichtsbehörde: wird vom Betreiber veröffentlicht",
	},
}

var _store: ConsentStore
var _content: VBoxContainer
var _training_toggle: CheckButton
var _allow_button: Button
var _status: Label
var _preview: TextEdit


func _ready() -> void:
	transient = true
	exclusive = true
	close_requested.connect(hide)
	_store = Store.new()
	_store.load_from_disk()
	_build_shell()
	_show_overview()


static func text_for(locale: String, key: String) -> String:
	var language := "de" if locale.to_lower().begins_with("de") else "en"
	return str((COPY[language] as Dictionary).get(key, ""))


func set_store_path_for_tests(path: String) -> void:
	_store = Store.new(path)
	_store.load_from_disk()


func open_settings() -> void:
	_show_overview()
	popup_centered()


func localized_text(key: String) -> String:
	return _t(key)


func maybe_prompt_after_completed_game() -> bool:
	if not _store.should_prompt_after_completed_game():
		return false
	# Seeing or dismissing the prompt is enough: never ask again automatically.
	_store.mark_prompt_seen()
	open_settings()
	return true


func example_bytes() -> PackedByteArray:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	if parsed is not Dictionary:
		return PackedByteArray()
	var record := (parsed as Dictionary).duplicate(true)
	record["deletion_code"] = _store.deletion_code
	record["training_use"] = _store.training_use
	return Builder.build(record)


func save_example_locally(path: String = EXPORT_PATH) -> String:
	var bytes := example_bytes()
	if bytes.is_empty():
		_set_status(_t("build_failed"))
		return ""
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if error != OK and error != ERR_ALREADY_EXISTS:
		_set_status(_t("create_failed") % path.get_base_dir())
		return ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status(_t("write_failed") % path)
		return ""
	file.store_buffer(bytes)
	file.close()
	_set_status(_t("saved") % path)
	return path


func _locale() -> String:
	return TranslationServer.get_locale()


func _t(key: String) -> String:
	return text_for(_locale(), key)


func _build_shell() -> void:
	title = _t("title")
	min_size = Vector2i(780, 680)
	size = Vector2i(780, 680)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	if has_node("/root/ThemeManager"):
		margin.theme = get_node("/root/ThemeManager").get_current_theme()


func _clear_content() -> void:
	for child in _content.get_children():
		# A pressed button still has feedback handlers to run on the same signal.
		child.hide()
		child.queue_free()


func _label(text: String, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if heading:
		label.add_theme_font_size_override("font_size", 20)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func _show_overview() -> void:
	if _content == null:
		return
	_clear_content()
	_content.add_child(_label(_t("heading"), true))
	_content.add_child(_label(_t("question")))
	_content.add_child(_label(_t("summary")))
	_content.add_child(_label(_t("review_exact")))
	var actions := HBoxContainer.new()
	actions.add_child(_button(_t("no_thanks"), _on_no_thanks))
	actions.add_child(_button(_t("review"), _show_details))
	_content.add_child(actions)


func _show_details() -> void:
	_store.mark_prompt_seen()
	_clear_content()
	_content.add_child(_label(_t("heading"), true))
	_content.add_child(_label(_t("fields")))
	_content.add_child(_label(_t("never")))
	_content.add_child(_label("%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s" % [
		_t("destination"), _t("controller"), _t("processor"), _t("purposes"),
		_t("recipients"), _t("retention"), _t("withdrawal"), _t("contact")]))
	_content.add_child(_label("%s: %s" % [_t("deletion_code"), _store.deletion_code]))
	_content.add_child(_label(_t("example"), true))
	_preview = TextEdit.new()
	_preview.name = "ExamplePreview"
	_preview.editable = false
	_preview.custom_minimum_size = Vector2(0, 240)
	_preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_preview.text = example_bytes().get_string_from_utf8()
	_content.add_child(_preview)
	_allow_button = _button("", _on_allow_or_withdraw)
	_allow_button.name = "AllowEvaluationButton"
	_content.add_child(_allow_button)
	_training_toggle = CheckButton.new()
	_training_toggle.name = "AllowTrainingToggle"
	_training_toggle.text = _t("allow_training")
	_training_toggle.button_pressed = _store.training_use
	_training_toggle.toggled.connect(_on_training_toggled)
	_content.add_child(_training_toggle)
	_content.add_child(_button(_t("save"), func() -> void: save_example_locally()))
	_content.add_child(_button(_t("close"), hide))
	_status = Label.new()
	_status.name = "ExportStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)
	_sync_consent_controls()


func _on_no_thanks() -> void:
	_store.set_consent(false, false)
	hide()


func _on_allow_or_withdraw() -> void:
	if _store.evaluation_sharing:
		_store.withdraw()
	else:
		_store.set_consent(true, _training_toggle.button_pressed)
	_sync_consent_controls()
	if _preview != null:
		_preview.text = example_bytes().get_string_from_utf8()


func _on_training_toggled(pressed: bool) -> void:
	if _store.evaluation_sharing:
		_store.set_consent(true, pressed)
		if _preview != null:
			_preview.text = example_bytes().get_string_from_utf8()


func _sync_consent_controls() -> void:
	_allow_button.text = _t("withdraw") if _store.evaluation_sharing else _t("allow_evaluation")
	_training_toggle.disabled = not _store.evaluation_sharing
	_training_toggle.set_pressed_no_signal(_store.training_use)


func _set_status(message: String) -> void:
	if _status != null:
		_status.text = message
