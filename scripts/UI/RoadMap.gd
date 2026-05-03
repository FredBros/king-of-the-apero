extends VBoxContainer

@onready var info_label: RichTextLabel = $InfoLabel

func _ready() -> void:
	_update_text()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		if is_node_ready():
			_update_text()

func _update_text() -> void:
	if not info_label: return
	
	var text_content = """[center][b][color=#be4a2f]%s[/color][/b]
[i][color=#686e86]%s[/color][/i][/center]

[center][b][color=#e4a672]%s[/color][/b]
[color=#63c74d][V][/color] %s
[color=#e4a672]->[/color] %s
[color=#686e86][ ][/color] %s
[color=#686e86][ ][/color] %s[/center]"""
	
	info_label.text = text_content % [
		tr("ROADMAP_ALPHA_VERSION"),
		tr("ROADMAP_WARNING"),
		tr("ROADMAP_TITLE"),
		tr("ROADMAP_CORE"),
		tr("ROADMAP_ONLINE"),
		tr("ROADMAP_3D"),
		tr("ROADMAP_LEGENDS")
	]