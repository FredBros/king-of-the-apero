extends VBoxContainer

@onready var info_label: RichTextLabel = $InfoLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	update_text()

func update_text() -> void:
	var txt = "[center][b][color=#be4a2f]%s[/color][/b]\n" % tr("ROADMAP_ALPHA_VERSION")
	txt += "[i][color=#686e86]%s[/color][/i][/center]\n\n" % tr("ROADMAP_WARNING")
	
	txt += "[center][b][color=#e4a672]%s[/color][/b]\n" % tr("ROADMAP_TITLE")
	txt += "[color=#63c74d][V][/color] %s\n" % tr("ROADMAP_CORE")
	txt += "[color=#e4a672]->[/color] %s\n" % tr("ROADMAP_ONLINE")
	txt += "[color=#686e86][ ][/color] %s\n" % tr("ROADMAP_3D")
	txt += "[color=#686e86][ ][/color] %s[/center]" % tr("ROADMAP_LEGENDS")
	
	info_label.text = txt

# Permet de mettre à jour le texte instantanément si le joueur change la langue dans les options
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		if is_node_ready():
			update_text()
