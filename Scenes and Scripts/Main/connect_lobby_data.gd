extends HBoxContainer

""" Setup """
func setup(lobby_id:int, lobby_data:Dictionary):
	""" Setup """
	
	# Game Key
	$Game_Key.text = str(lobby_id)
	
	# Lobby Name
	$Lobby_Name.text = lobby_data["name"]
	
	# Occupancy
	$Occupancy.text = str(lobby_data["current_size"]) + "/" + str(lobby_data["max_size"])
	$Occupancy.modulate = [Color(1,1,1), Color(1,0,0)][int(lobby_data["current_size"] == lobby_data["max_size"])]
	
	# Password Expected
	$Expect_Password.text = ["FALSE", "TRUE"][int(lobby_data["expect_password"])]
	$Expect_Password.modulate = [Color(1,1,0), Color(0,1,0)][int(lobby_data["expect_password"])]
	
	# Set Join Active
	set_join_active()

""" Triggers """
func _on_join_pressed():
	
	# Tell Main that a button was pressed
	get_tree().get_current_scene()._on_connect_join_pressed(int($Game_Key.text))

func set_join_active(active=!Connection.in_online_lobby()):
	""" Set Join Active """
	
	$Join.disabled = !active
