extends HBoxContainer

""" Vars and Constants """
var steam_id:int ## Steam ID of the player

""" Functions """
func setup(new_steam_id:int): ## Setup
	
	# Basic
	steam_id = new_steam_id
	
	# Avatar
	$Avatar.texture = Connection.get_avatar(steam_id, Steam.AVATAR_SMALL)
	
	# Kick Button: Show if (HOST and NOT_ME)
	$Kick.visible = (Connection.is_member_host() and !Connection.is_member_me(steam_id))
	
	# Label
	$Name.text = Connection.get_member_name(steam_id)
	$Name.modulate = Connection.get_member_color(steam_id)
	
func _on_kick_pressed():
	get_tree().get_current_scene()._player_kicked_pressed(steam_id)
