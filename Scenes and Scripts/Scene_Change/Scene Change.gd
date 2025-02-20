extends Control


""" Vars """
var CONTROL = {
	"color_change": [
		Connection.Control_Details.new(Connection.READER.Sender, "tell host to change color", TYPE_NIL),
		Connection.Control_Details.new(Connection.READER.Host, "tell clients the new color", TYPE_NIL),
		Connection.Control_Details.new(Connection.READER.Members, "use the new color", TYPE_COLOR),
	]
	}


""" Setup """
func _ready():
	
	# Randomize
	randomize()
	
	# Back to Main Visibility
	$HBox/Back_to_Main.visible = Connection.is_member_host()
	
	# Setup Callable
	Connection.setup_callable("Scene_Change", self)
	
	# Run a Color Change
	if Connection.is_member_host():
		_on_color_change_pressed()


""" CONTROL """
func _CONTROL_color_change(Packet:Connection.Packet_Class):
	
	# Tell Host to Change color
	if Packet.stage == 0:
		Packet.send(null)
	
	# tell clients the new color
	elif Packet.stage == 1:
		Packet.send(Color(randf_range(0, 1), randf_range(0, 1), randf_range(0, 1)))
	
	# Receive the new color
	elif Packet.stage == 2:
		$Color_Change/HBox/ColorRect.color = Packet.data


""" Buttons """
func _on_quit_pressed():
	Connection.leave_lobby()

func _on_back_to_main_pressed():
	Connection.change_scene("res://Scenes and Scripts/Main/main.tscn")

func _on_color_change_pressed():
	Connection.Packet_Class.new("Scene_Change", "color_change", Connection.HOST_STEAM_ID)


""" Callables """
func _on_Get_Lobby_Members():
	""" Get Lobby Members """
	
	pass

func _on_Lobby_Left(quit:bool, steam_id:int):
	
	# Quit
	if quit:
		Connection.change_scene("res://Scenes and Scripts/Main/main.tscn")

func _on_Get_Inputs():
	
	# Inputs
	var inputs = {
		Connection.INPUT_TYPE.normal: {
			"space": Input.is_action_pressed("space")
			}
		}
	# Return
	return inputs

func _on_Check_Inputs(inputs:Dictionary, steam_id:int) -> bool:
	return true



