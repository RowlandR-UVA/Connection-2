extends Control

""" Scenes and Scripts """
@export var Connect_Lobby_Data_Scene = preload("res://Scenes and Scripts/Main/connect_lobby_data.tscn")
@export var Lobby_Player_Data_Scene = preload("res://Scenes and Scripts/Main/lobby_player_data.tscn")

""" Vars and Constants """
const DEFAULT_LOBBY_SIZE:int = 8
const PASSWORD_MAX_LENGTH:int = 20

# Slide
var slide:String

# Password
var password_Packet: Connection.Packet_Class

# Connect
enum CONNECT_OPERATION {Start_Game_Key, Typing_Game_Key, Checking_Game_Key, Failed_Join, Receiving_Password_Test, Start_Password, Typing_Password, Checking_Password, Failed_Password, Leaving_Lobby}
enum CONNECT_MSG {None, Offline, No_Lobbies_Found, Refreshing}
@onready var search_distance:Steam.LobbyDistanceFilter = Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE
const AUTO_REFRESH_TOTAL_TIME:float = 10.0
var auto_refresh_current_time:float = 0.0

# Lobby
var sync_basic_nodes:Dictionary

# Input Shield
const INPUT_SHIELD_DOT_TOTAL_TIME:float = 0.5
var input_shield_msg:String
var input_shield_current_time:float
var input_shield_dot_idx:int

# Control
var CONTROL:Dictionary = {} # NOTE: This gets autofilled with the Send_Scheme Controls (in _ready)

## Send Scheme
# Compression and p2p_send
enum SEND_SCHEME {Compression, P2P_Send}
enum COMPRESSION {DEFLATE, gzip}
enum P2P_SEND {Reliable, Rel_w_Buf}

# Mode
enum SS_MODE {Idle, Process, Transition, Done}
var ss_mode:SS_MODE

# Results
enum SS_RESULTS {total_time, lossiness}
var ss_results:Array
var ss_temp_results:Dictionary

# Step Data
const SS_MAX_STEPS_PER_STEP = 20
var ss_send_scheme:Array
var ss_step:Array

# Time
const SS_TOTAL_PROCESS_TIME:float = SS_MAX_STEPS_PER_STEP*0.04*4*1.5
var ss_current_time:Array # Array of two float (current_process_time, total_time)

# Data Sizes
var SS_SIZE_MIN:int = 5000 # in bytes # NOTE: This should NOT be set lower than 32 bytes (see SS_EXTRA_DATA_BASIS)
var SS_SIZE_MAX:int  = 100000 # in bytes
var SS_EXTRA_DATA_AMOUNT:int = var_to_bytes([randi(), randf(), []]).size() - var_to_bytes([]).size() # NOTE: In addition to the data already being sent for the test, their is also auxilliary data that shpuld be overlooked for the test, +8 is also a given for any piece of data sent
var SS_STEPS:int = (SS_SIZE_MAX - SS_SIZE_MIN)/1000 # NOTE: This should not be lower than 2
var ss_data_sizes:Array
var ss_data:Array


""" Setup """
func _ready():
	## Basic
	# Randomize
	randomize()
	
	# Hide the Input Shield
	set_input_shield(null)
	
	# Defocus
	defocus()
	
	## Callables
	# Setup Control
	for compression in COMPRESSION.keys():
		for p2p_send in P2P_SEND.keys():
			CONTROL["SS_" + compression + "_" + p2p_send] = [
				Connection.Send_Scheme.new(false, Connection.P2P_SEND.values()[Connection.P2P_SEND.keys().find(p2p_send)], false, Connection.COMPRESSION.values()[Connection.COMPRESSION.keys().find(compression)]),
				Connection.Control_Details.new(Connection.READER.Sender, "snd1", [TYPE_NIL]),
				Connection.Control_Details.new(Connection.READER.Host, "rec1"),
				Connection.Control_Details.new(Connection.READER.Sender, "rec2"),
				]
	
	## Set the SS_Mode
	SS_change_mode(SS_MODE.Idle)
	
	## Slides
	# Host
	$Slides/Host/VBox/VBox/VBox/Lobby_Name/Lobby_Name.text = Connection.STEAM_NAME + "'s Lobby"
	$Slides/Host/VBox/VBox/VBox/Lobby_Size/Lobby_Size.text = str(DEFAULT_LOBBY_SIZE)
	$Slides/Host/VBox/VBox/VBox/Lobby_Type/Lobby_Type.selected = 0
	$Slides/Host/VBox/VBox/VBox/Password/Password_Check.button_pressed = false
	$Slides/Host/VBox/VBox/VBox/Password/Password.max_length = PASSWORD_MAX_LENGTH
	_on_password_check_pressed()
	
	# Connect
	$Slides/Connect/VBox/Middle/HBox/Search_Distance/Search_Distance.selected = Connection.SEARCH_DISTANCES.values().find(search_distance)
	$Slides/Connect/VBox/Bottom/VBox/Password/HBox/Password.max_length = PASSWORD_MAX_LENGTH
	
	# Set as Callable
	Connection.setup_callable("Main", self)
	
	# Set the Slide
	change_slide(["Start", "Lobby"][int(Connection.in_lobby())])

""" Operational: Basic """
func _process(delta):
	""" Process """
	
	## Input Shield
	# If Input Shield is Active
	if $Input_Shield.visible:
		
		# Time Trigger
		input_shield_current_time += delta
		if input_shield_current_time >= INPUT_SHIELD_DOT_TOTAL_TIME:
			input_shield_current_time -= INPUT_SHIELD_DOT_TOTAL_TIME
			
			# Advance Dots
			update_input_shield()
	
	## Escape
	if Input.is_action_just_pressed("escape"):
		defocus()
	
	## Auto Refresh
	if slide == "Connect":
		
		# Time Trigger
		auto_refresh_current_time += delta
		if auto_refresh_current_time >= AUTO_REFRESH_TOTAL_TIME:
			auto_refresh_current_time -= AUTO_REFRESH_TOTAL_TIME
			
			# Refresh
			_on_refresh_pressed()
	
	## Lobby Sync
	elif slide == "Lobby":
		
		# Update Lobby Sync
		for steam_id in sync_basic_nodes.keys():
			
			# Latency
			sync_basic_nodes[steam_id]["Latency"].text = str(Connection.get_member_latency(steam_id))
			
			# Inputs Pressed
			var inputs_pressed:bool = Connection.get_any_input_pressed(steam_id)
			sync_basic_nodes[steam_id]["Inputs_Pressed"].text = ["FALSE", "TRUE"][int(inputs_pressed)]
			sync_basic_nodes[steam_id]["Inputs_Pressed"].modulate = [Color(1,0,0), Color(0,1,0)][int(inputs_pressed)]
	
	## Send Scheme
	_SS_process(delta)

func change_slide(new_slide:String):
	""" Change Slide """
	
	# Show the Target Slide
	slide = new_slide
	for child in $Slides.get_children():
		child.visible = (child.name == slide)
	
	# Slides
	if slide == "Host":
		$Slides/Host/VBox/VBox/Error_Msg.modulate.a = 0.0
	
	elif slide == "Connect":
		# Refresh
		auto_refresh_current_time = 0.0
		_on_refresh_pressed()
	
	elif slide == "Lobby":
		# Set the Current Tab
		$Slides/Lobby/VBox/TabContainer.current_tab = 0
		
		# Hide or Show Nodes
		var is_host:bool = Connection.is_member_host()
		$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/HBox/Lobby_Type.visible = is_host
		$Slides/Lobby/VBox/Buttons/Lock_Lobby.visible = is_host
	
	# Get Lobby Members
	_on_Get_Lobby_Members()

""" Operational: Connect """
func connect_operation(operation:CONNECT_OPERATION):
	""" Connect Operation """
	
	# Join Game Key Button and Game Key Dissabling
	var hold = operation in [CONNECT_OPERATION.Start_Game_Key, CONNECT_OPERATION.Typing_Game_Key, CONNECT_OPERATION.Failed_Join]
	$Slides/Connect/VBox/Bottom/VBox/Game_Key/HBox/Game_Key.editable = hold
	$Slides/Connect/VBox/Bottom/VBox/Game_Key/Join_Game_Key.visible = hold
	
	# Button Visibility
	hold = Connection.in_online_lobby() and (operation != CONNECT_OPERATION.Receiving_Password_Test)
	$Slides/Connect/VBox/Bottom/Buttons/Back_Connect.visible = !hold
	$Slides/Connect/VBox/Bottom/Buttons/Quit_Connect.visible = hold
	$Slides/Connect/VBox/Bottom/VBox/Password.visible = hold
	
	# Button Disabledness
	$Slides/Connect/VBox/Middle/HBox/Search_Distance/Search_Distance.disabled = hold
	$Slides/Connect/VBox/Middle/HBox/Refresh.disabled = hold
	get_tree().call_group("connect_lobby_data", "set_join_active")
	
	# Game Key Error Msg
	$Slides/Connect/VBox/Bottom/Error_Msg.modulate.a = [0.0, 1.0][int(operation in [CONNECT_OPERATION.Failed_Join, CONNECT_OPERATION.Failed_Password])]
	
	# Operations
	if operation == CONNECT_OPERATION.Start_Game_Key:
		$Slides/Connect/VBox/Bottom/VBox/Game_Key/HBox/Game_Key.text = str(0)
		set_input_shield(null)
		
	elif operation == CONNECT_OPERATION.Typing_Game_Key:
		pass
	
	elif operation == CONNECT_OPERATION.Checking_Game_Key:
		set_input_shield("Connecting (Checking_Game_Key)")
	
	elif operation == CONNECT_OPERATION.Failed_Join:
		set_input_shield(null)
	
	elif operation == CONNECT_OPERATION.Receiving_Password_Test:
		$Slides/Connect/VBox/Bottom/VBox/Game_Key/HBox/Game_Key.text = str(Connection.LOBBY_ID)
		$Slides/Connect/VBox/Bottom/VBox/Password/HBox/Password.text = ""
		set_input_shield("Joining (Handshaking)")
	
	elif operation == CONNECT_OPERATION.Start_Password:
		$Slides/Connect/VBox/Bottom/VBox/Password/HBox/Password.text = ""
		set_input_shield(null)
	
	elif operation == CONNECT_OPERATION.Typing_Password:
		pass
	
	elif operation == CONNECT_OPERATION.Checking_Password:
		set_input_shield("Joining (Answering Trust)")
	
	elif operation == CONNECT_OPERATION.Failed_Password:
		$Slides/Connect/VBox/Bottom/VBox/Password/HBox/Password.text = ""
		$Slides/Connect/VBox/Bottom/Error_Msg.text = "Incorrect Password"
		set_input_shield(null)
	
	elif operation == CONNECT_OPERATION.Leaving_Lobby:
		set_input_shield("Leaving Lobby")

func set_connect_msg(connect_msg:CONNECT_MSG):
	""" Set Connect Msg """
	
	# Autoset Msg
	if !Connection.ONLINE:
		connect_msg = CONNECT_MSG.Offline
	
	# Visibility
	$Slides/Connect/VBox/Middle/Scroll/Msg.visible = (connect_msg != CONNECT_MSG.None)
	$Slides/Connect/VBox/Middle/Scroll/Lobby_Data_Root.visible = (connect_msg == CONNECT_MSG.None)
	
	# Msg and Modulate
	if connect_msg == CONNECT_MSG.Offline:
		$Slides/Connect/VBox/Middle/Scroll/Msg/Msg.text = "Offline"
		$Slides/Connect/VBox/Middle/Scroll/Msg/Msg.modulate = Color(1,0,0)
	
	elif connect_msg == CONNECT_MSG.No_Lobbies_Found:
		$Slides/Connect/VBox/Middle/Scroll/Msg/Msg.text = "No Lobbies Found"
		$Slides/Connect/VBox/Middle/Scroll/Msg/Msg.modulate = Color(1,1,1)
	
	elif connect_msg == CONNECT_MSG.Refreshing: 
		$Slides/Connect/VBox/Middle/Scroll/Msg/Msg.text = "Refreshing..."
		$Slides/Connect/VBox/Middle/Scroll/Msg/Msg.modulate = Color(1,1,1)

""" Operational: Input Shield """
func set_input_shield(msg):
	""" Input Shield """
	
	# Show or Hide
	$Input_Shield.visible = (msg != null)
	
	# Defocus
	defocus()
	
	# Set the Msg
	if msg != null:
		
		# Basic
		input_shield_msg = str(msg)
		input_shield_current_time = 0
		input_shield_dot_idx = 0
		
		# Update Input Shield
		update_input_shield()

func update_input_shield():
	""" Update Input Shield """
	
	# Set the Dot Idx
	input_shield_dot_idx = (input_shield_dot_idx + 1)%4
	
	# Set the Msg
	$Input_Shield/Msg.text = input_shield_msg
	for i in range(input_shield_dot_idx):
		$Input_Shield/Msg.text += "."


""" Callables: Lobby Connection """
func _on_Lobby_Created(success:bool):
	""" Lobby Created """ # TODO: Check Success Failure
	
	# Failre
	if !success:
		
		# Show the Error Msg
		$Slides/Host/VBox/VBox/Error_Msg.modulate.a = 1.0
		$Slides/Host/VBox/VBox/Error_Msg.text = "Failed to Create Lobby (likely a network timeout)"
	
	# Hide Input Shield
	set_input_shield(null)

func _on_Lobby_Joined(success:bool, msg:String):
	""" Lobby Joined """
	
	# Success
	if success:
		
		# Host (on slide create_lobby, so just join)
		if Connection.is_member_host():
			set_input_shield("Joining (Handshaking)...")
		
		# Client
		else:
			connect_operation(CONNECT_OPERATION.Receiving_Password_Test)
	
	# Failure
	else:
		$Slides/Connect/VBox/Bottom/Error_Msg.text = msg
		connect_operation(CONNECT_OPERATION.Failed_Join)

func _on_Handshake_Timeout(was_host:bool):
	
	# Host Failed to Create Lobby
	var msg:String
	if was_host:
		
		# Show the Error Msg
		$Slides/Host/VBox/VBox/Error_Msg.modulate.a = 1.0
		$Slides/Host/VBox/VBox/Error_Msg.text = "Handshake Timed Out"
	
	# Client Failed to Join lobby
	else:
		
		# Show the Error Msg
		$Slides/Connect/VBox/Bottom/Error_Msg.text = "Handshake Timed Out"
		connect_operation(CONNECT_OPERATION.Failed_Join)
	
	# Hide Input Shield
	set_input_shield(null)

func _on_Lobby_Match_List(lobby_data:Dictionary, headers:Array):
	""" Lobby Match List """
	
	# Update Match List
	$Slides/Connect/VBox/Middle/HBox/Lobbies.text = "Lobbies: " + str(lobby_data.size())
	
	# Update Lobbies
	if slide == "Connect":
		
		# For Each Lobby Id
		for lobby_id in lobby_data.keys():
			
			# Get The Local lobbby Data
			var local:Dictionary = {}
			for i in range(len(headers)):
				local[headers[i]] = lobby_data[lobby_id][i]
			
			# Set up the Obj
			var obj = Connect_Lobby_Data_Scene.instantiate()
			obj.setup(lobby_id, local)
			$Slides/Connect/VBox/Middle/Scroll/Lobby_Data_Root.add_child(obj)
		
		# Set Connect Msg
		set_connect_msg([CONNECT_MSG.None, CONNECT_MSG.No_Lobbies_Found][int(lobby_data.size() == 0)])

func _on_Received_Trust_Test(Packet:Connection.Packet_Class):
	""" Received Trust Test """
	
	# Save Password Packet
	password_Packet = Packet
	connect_operation(CONNECT_OPERATION.Start_Password)

func _on_Trust_Test_Results(passed:bool):
	""" Failed Trust Test """
	
	# Passed
	if passed:
		
		# Set the Slide
		set_input_shield(null)
		change_slide("Lobby")
	
	# Failed
	else:
		
		# Failed Password
		connect_operation(CONNECT_OPERATION.Failed_Password)


""" Callables: Operational """
func _on_Get_Lobby_Members():
	""" Get Lobby Members """
	
	# Only Continue if Slide is Lobby
	if slide != "Lobby":
		return
		
	## Lobby_Data
	# Basic
	var label_ref = Label.new()
	
	# Lobby Name
	var hold = Connection.ONLINE
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/HBox/Lobby_Name.text = "Lobby Name: " + ["none", Steam.getLobbyData(Connection.LOBBY_ID, "name")][int(hold)]
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/HBox/Lobby_Name.modulate = [Color(1,1,0), Color(1,1,1)][int(hold)]
	
	# Lobby Type
	hold = Connection.is_member_online_host()
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/HBox/Lobby_Type/Lobby_Type.selected = Connection.LOBBY_TYPES.values().find(Connection.lobby_type)
	
	# Online
	hold = Connection.ONLINE
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/HBox/HBox/Online.text = ["False", "True"][int(hold)]
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/HBox/HBox/Online.modulate = [Color(1,0,0), Color(0,1,0)][int(hold)]
	
	# Game Key and Password
	hold = Connection.ONLINE
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/VBox/Game_Key/Game_Key.text = "Game Key: " + ["none", str(Connection.LOBBY_ID)][int(hold)]
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/VBox/Password.text = "Password: " + ["null", Connection.lobby_password][int(Connection.lobby_password != "")]
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/VBox/Password.modulate = [Color(1,1,0), Color(1,1,1)][int(Connection.lobby_password != "")]
	
	# Lobby Size
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/VBox2/Lobby_Size/Trusted.text = str(len(Connection.TRUSTED)) + " Trusted"
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/VBox2/Lobby_Size/Untrusted.text = str(len(Connection.MEMBERS.keys()) - len(Connection.TRUSTED)) + " Untrusted"
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/VBox2/Lobby_Size/Total.text = str(Connection.lobby_size) + " Total"
	
	# Kicked
	hold = []
	for steam_id in Connection.KICKED:
		hold.append(Connection.get_member_name(steam_id))
	hold = ", ".join(hold)
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/VBox2/Kicked.text = "Kicked: " + [hold, "null"][int(Connection.KICKED.is_empty())]
	$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/VBox2/Kicked.modulate = [Color(1,1,0), Color(1,1,1)][int(Connection.KICKED.is_empty())]
	
	# Lock_Lobby
	$Slides/Lobby/VBox/Buttons/Lock_Lobby.button_pressed = !Connection.lobby_joinable
	
	## Trusted / Members
	# Remove Children
	hold = $Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/VBox2/HBox/Player_Data_Root
	for child in hold.get_children():
		child.queue_free()
	
	# Add Children
	label_ref.add_theme_font_size_override("font_size", 30)
	for steam_id in Connection.MEMBERS.keys():
		
		# Basic
		var obj:HBoxContainer = Lobby_Player_Data_Scene.instantiate()
		obj.setup(steam_id)
		hold.add_child(obj)
	
	## Sync Basic
	# Remove Old Data
	sync_basic_nodes.clear()
	for type in ["Names", "Latency", "Inputs_Pressed"]:
		for child in get_node("Slides/Lobby/VBox/TabContainer/Sync/HBox/" + type + "/Root").get_children():
			child.queue_free()
	
	# For each Member
	label_ref.add_theme_font_size_override("font_size", 20)
	for steam_id in Connection.MEMBERS.keys():
		# Name
		var obj:Label = label_ref.duplicate()
		obj.name = str(steam_id)
		obj.text = Connection.MEMBERS[steam_id]
		obj.modulate = Connection.get_member_color(steam_id)
		get_node("Slides/Lobby/VBox/TabContainer/Sync/HBox/Names/Root").add_child(obj)
		
		sync_basic_nodes[steam_id] = {}
	
		# Latency, Inputs_Pressed
		for type in ["Latency", "Inputs_Pressed"]:
			obj = label_ref.duplicate()
			obj.name = str(steam_id)
			obj.text = ""
			get_node("Slides/Lobby/VBox/TabContainer/Sync/HBox/" + type + "/Root").add_child(obj)
			sync_basic_nodes[steam_id][type] = obj

func _on_Lobby_Left(quit:bool, steam_id:int):
	""" Lobby Left """
	
	# If is me leaving
	if quit:
	
		# End the SS Mode
		SS_change_mode(SS_MODE.Idle)
		
		# Change Slide to Start
		change_slide("Start")
		set_input_shield(null)

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


""" Send Scheme: Basic """
func SS_start(start:bool=false):
	""" Setup or Continue SS """
	
	## Start
	if start:
		
		## Basic
		ss_send_scheme = [0, 0] # compression, p2p_send
		ss_data.clear()
		ss_data_sizes.clear()
		
		## Get all of the data sizes
		var count:float = -1
		while count < SS_STEPS:
			while true:
			
				# Check End Condition
				count += 1
				if count >= SS_STEPS:
					break
				
				# Get the SS_Data
				ss_data = create_junk(int(lerp(SS_SIZE_MIN, SS_SIZE_MAX, count/(SS_STEPS - 1)) - SS_EXTRA_DATA_AMOUNT), ss_data)
				
				# Check if it is valud
				if len(ss_data_sizes) == 0 or (var_to_bytes(ss_data).size() != ss_data_sizes[-1]):
					ss_data_sizes.append(var_to_bytes(ss_data).size())
					break
		
		## Setup Results
		ss_results.clear()
		for result in SS_RESULTS.values():
			ss_results.append([])
			
			for compression in COMPRESSION.values():
				ss_results[-1].append([])
				
				for p2p_send in P2P_SEND.values():
					ss_results[-1][-1].append([])
		
	## Process All of the Comps and P2P_Sends Results
	else:
		
		# Basic
		var compression:COMPRESSION = ss_send_scheme[0]
		var p2p_send:P2P_SEND = ss_send_scheme[1]
		
		# For Each Temp Result
		for i in range(len(ss_data_sizes)):
			
			# Total Time
			if ss_temp_results["received"][i] != 0:
				ss_results[SS_RESULTS.total_time][compression][p2p_send].append(int(round(float(ss_temp_results["total_time"][i]) / ss_temp_results["received"][i])))
			else:
				ss_results[SS_RESULTS.total_time][compression][p2p_send].append(null)
			
			# Lossiness
			if ss_temp_results["sent"][i] != 0:
				ss_results[SS_RESULTS.lossiness][compression][p2p_send].append(int(round(float(ss_temp_results["received"][i]) / ss_temp_results["sent"][i])))
			else:
				ss_results[SS_RESULTS.lossiness][compression][p2p_send].append(null)
		
		# Increment P2p
		ss_send_scheme[1] += 1
		
		# P2P Too Big
		if ss_send_scheme[1] == P2P_SEND.size():
			ss_send_scheme[1] = 0
			ss_send_scheme[0] += 1
		
		# Done (Compression too Big)
		if ss_send_scheme[0] == COMPRESSION.size():
			SS_change_mode(SS_MODE.Done)
			return
		
	# Mode
	SS_reset(true)

func SS_reset(start:bool=false):
	""" SS Reset """
	
	# Reset SS Step
	if start:
		ss_step = [0, 0]
		ss_data.clear()
		ss_temp_results = { "total_time": [], "sent": [], "received": []}
	else:
		ss_step[0] += 1
	
	# Basic
	ss_step[1] = 0
	ss_current_time = [0, 0]
	
	# Reset Remp Results
	ss_temp_results["total_time"].append(0)
	ss_temp_results["sent"].append(0)
	ss_temp_results["received"].append(0)
	
	# Set the SS_Data
	ss_data = create_junk(ss_data_sizes[ss_step[0]], ss_data)
	
	# Set Mode to Process
	SS_change_mode(SS_MODE.Process)

func SS_change_mode(temp_ss_mode:SS_MODE):
	""" SS Change Mode """
	
	# Chaneg the SS_Mode
	ss_mode = temp_ss_mode

	# Button Text
	$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Buttons/SS_Test.text = ({SS_MODE.Idle: "Start", SS_MODE.Process: "Cancel", SS_MODE.Transition: "Cancel", SS_MODE.Done: "Redo"}[ss_mode] + " Test")
	
	# Visibility
	$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Buttons/Copy_SS_CSV.visible = (ss_mode == SS_MODE.Done)
	for node in ["Data1", "Data2", "Data3"]:
		$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox.get_node(node).visible = !(ss_mode in [SS_MODE.Idle, SS_MODE.Done])
	
	# Copy Csv
	if ss_mode == SS_MODE.Done:
		_on_copy_ss_csv_pressed
	
	# Update Nodes
	SS_update_nodes()

func SS_update_nodes():
	""" SS Update Nodes """
	
	# Discontinue
	if ss_mode in [SS_MODE.Idle, SS_MODE.Done]:
		return
	
	# Data 1
	$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data1/Compression.text = "Compression (" + str(ss_send_scheme[0]) + "/"  + str(COMPRESSION.size() - 1) + "): " + COMPRESSION.keys()[ss_send_scheme[0]]
	$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data1/P2P_Send.text = "P2P_Send (" + str(ss_send_scheme[1]) + "/"  + str(P2P_SEND.size() - 1) + "): " + P2P_SEND.keys()[ss_send_scheme[1]]
	
	# Data 2
	$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data2/Step.text = "Step (" + str(ss_step[0]) + "/" + str(len(ss_data_sizes)) + "): " + str(round(1000 * float(ss_step[0]) / len(ss_data_sizes)) / 10.0) + "%"
	$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data2/Size.text = "Size: " + str(ss_data_sizes[ss_step[0]] + SS_EXTRA_DATA_AMOUNT)
	
	# Data 3
	if ss_step[0] != 0:
		
		# Total Time
		var idx:int = (ss_step[0] - 1)
		if ss_temp_results["received"][idx] != 0:
			$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Total_Time.text = "Time: " + str(int(round(float(ss_temp_results["total_time"][idx]) / ss_temp_results["received"][idx])))
			$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Total_Time.modulate = Color(1,1,1)
		else:
			$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Total_Time.text = "Time: nan"
			$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Total_Time.modulate = Color(1,1,0)
		
		# Lossiness
		if ss_temp_results["sent"][idx] != 0:
			$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Lossiness.text = "Lossiness: " + str(int(round(100 * (1 - (ss_temp_results["received"][idx] / ss_temp_results["sent"][idx]))))) + "%"
			if ss_temp_results["received"][idx] != ss_temp_results["sent"][idx]:
				$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Lossiness.modulate = Color(1,0,0)
			else:
				$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Lossiness.modulate = Color(1,1,1)
		else:
			$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Lossiness.text = "Lossiness: nan"
			$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Lossiness.modulate = Color(1,1,0)
	
	# Data cannot yet be processed
	else:
		
		# Set Total Time Loading
		$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Total_Time.text = "Time: loading..."
		$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Total_Time.modulate = Color(1,0,1)
		
		# Set Lossiness Loading
		$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Lossiness.text = "Lossiness: loading..."
		$Slides/Lobby/VBox/TabContainer/Send_Scheme_Test/VBox/Data3/Lossiness.modulate = Color(1,0,1)

func _SS_process(delta:float):
	""" SS Process """
	
	## End
	if ss_mode in [SS_MODE.Idle, SS_MODE.Done]:
		return
	
	## Incr Time
	var trigger_time:float = max(delta, 4*Connection.latency) # in seconds ()
	for i in range(2):
		ss_current_time[i] += delta # total_time, trigger_time
	
	## Mode: Process
	if ss_mode == SS_MODE.Process:
		
		## Send Packet Trigger
		if (ss_step[1] == 0) or ss_current_time[1] >= trigger_time:
			
			# Change Current Time and Step
			ss_current_time[1] -= trigger_time
			ss_step[1] += 1
			ss_temp_results["sent"][ss_step[0]] += 1
			
			# Send the Compression and P2P Combo
			Connection.Packet_Class.new("Main", "SS_" + COMPRESSION.keys()[ss_send_scheme[0]] + "_" + P2P_SEND.keys()[ss_send_scheme[1]], Connection.HOST_STEAM_ID)
		
		## Next Step Trigger
		if ss_current_time[0] >= SS_TOTAL_PROCESS_TIME or ss_step[1] >= SS_MAX_STEPS_PER_STEP:
			
			## Next Process Trugger
			if (ss_step[0] + 1) < len(ss_data_sizes):
				SS_reset()
			
			## Transition Trigger
			else:
				SS_change_mode(SS_MODE.Transition)
				
	
	## Mode: Wait
	elif ss_mode == SS_MODE.Transition:
		
		# Save Data Trigger
		if ss_current_time[1] >= trigger_time:
			SS_start()
			return

func _SS_control_packet(Packet:Connection.Packet_Class):
	""" SS Received (called from an SS Control) """
	
	# Snd1
	if Packet.stage == 0:
		Packet.send([ss_step[0], Time.get_unix_time_from_system()*1000, ss_data])
	
	else:
		
		# Get Compression and P2P_Send (NOTE: Id does actually have to be this complicated)
		var compression:COMPRESSION = COMPRESSION[Connection.COMPRESSION.keys()[Connection.COMPRESSION.values().find(Packet.control[Packet.stage][Connection.CALLABLES.Send_Scheme].compression)]]
		var p2p_send:P2P_SEND = P2P_SEND[Connection.P2P_SEND.keys()[Connection.P2P_SEND.values().find(Packet.control[Packet.stage][Connection.CALLABLES.Send_Scheme].p2p_send)]]
	
		# End Early (packet did not get past wait period)
		if ss_send_scheme != [compression, p2p_send]:
			return
		
		# Rec1
		elif Packet.stage == 1:
			Packet.send()
		
		# Rec2
		elif Packet.stage == 2:
		
		# Set Data
			ss_temp_results["total_time"][Packet.data[0]] += 0.5*(Time.get_unix_time_from_system()*1000 - Packet.data[1])
			ss_temp_results["received"][Packet.data[0]] += 1
			
			# Update SS Nodes
			if Packet.data[0] != ss_step[0]:
				SS_update_nodes()


""" Slide Triggers: Start """
func _on_host_pressed():
	change_slide("Host")

func _on_connect_pressed():
	connect_operation(CONNECT_OPERATION.Start_Game_Key)
	change_slide("Connect")

func _on_quit_pressed():
	get_tree().quit()

""" Slide Triggers: Host """
func _on_password_check_pressed():
	$Slides/Host/VBox/VBox/VBox/Password/Password.visible = $Slides/Host/VBox/VBox/VBox/Password/Password_Check.button_pressed
	if $Slides/Host/VBox/VBox/VBox/Password/Password.visible:
		$Slides/Host/VBox/VBox/VBox/Password/Password.text = str(randi()%int(pow(10, PASSWORD_MAX_LENGTH)))

func _on_start_host_pressed():
	""" Create Lobby """
	
	# Input Shield
	set_input_shield("Hosting (Creating Lobby)")
	
	# Set the Password
	var lobby_password = ""
	if $Slides/Host/VBox/VBox/VBox/Password/Password_Check.button_pressed:
		lobby_password = str($Slides/Host/VBox/VBox/VBox/Password/Password.text)
	
	# Hide the Error Msg
	$Slides/Host/VBox/VBox/Error_Msg.modulate.a = 0.0
	
	# Lobby Name
	var lobby_name = str($Slides/Host/VBox/VBox/VBox/Lobby_Name/Lobby_Name.text)
	var lobby_type = Connection.LOBBY_TYPES.values()[$Slides/Host/VBox/VBox/VBox/Lobby_Type/Lobby_Type.selected]
	var lobby_size = int($Slides/Host/VBox/VBox/VBox/Lobby_Size/Lobby_Size.text)
	Connection.create_lobby(lobby_name, lobby_type, lobby_size, true, lobby_password)

func _on_back_host_pressed():
	change_slide("Start")

""" Slide Triggers: Connect """
func _on_search_distance_item_selected(index):
	search_distance = Connection.SEARCH_DISTANCES.values()[$Slides/Connect/VBox/Middle/HBox/Search_Distance/Search_Distance.selected]
	_on_refresh_pressed()

func _on_refresh_pressed():
	""" Refresh """
	
	# Allow if Not in Lobby
	if !Connection.in_online_lobby():
		
		# Clear Lobby Amount
		$Slides/Connect/VBox/Middle/HBox/Lobbies.text = "Lobbies: "
		
		# Reset Auto Refresh
		auto_refresh_current_time = 0.0
		
		# Connect Msg
		set_connect_msg(CONNECT_MSG.Refreshing)
		
		# Remove Previous Lobby_Data
		for child in $Slides/Connect/VBox/Middle/Scroll/Lobby_Data_Root.get_children():
			child.queue_free()
		
		# Refresh Match Lsit
		Connection.refresh_match_list(search_distance)

func _on_connect_join_pressed(game_key:int):
	connect_operation(CONNECT_OPERATION.Checking_Game_Key)
	Connection.join_lobby(game_key)

func _on_join_game_key_pressed():
	_on_connect_join_pressed(int($Slides/Connect/VBox/Bottom/VBox/Game_Key/HBox/Game_Key.text))

func _on_game_key_text_changed(_new_text):
	connect_operation(CONNECT_OPERATION.Typing_Game_Key)

func _on_enter_password_pressed():
	
	# Set Connect Operation
	connect_operation(CONNECT_OPERATION.Checking_Password)
	
	# Guess Password
	var lobby_password:String = str($Slides/Connect/VBox/Bottom/VBox/Password/HBox/Password.text)
	password_Packet.send(lobby_password)

func _on_password_text_changed(_new_text):
	connect_operation(CONNECT_OPERATION.Typing_Password)

func _on_back_connect_pressed():
	change_slide("Start")

func _on_quit_connect_pressed():
	connect_operation(CONNECT_OPERATION.Leaving_Lobby)
	Connection.leave_lobby()
	connect_operation(CONNECT_OPERATION.Start_Game_Key)

""" Slide Triggers: Lobby """
## Lobby_Data
func _on_lobby_type_item_selected(_index):
	Connection.set_lobby_type(Connection.LOBBY_TYPES.values()[$Slides/Lobby/VBox/TabContainer/Lobby_Data/VBox/HBox/Lobby_Type/Lobby_Type.selected])

func _on_copy_pressed():
	
	# No Password
	if Connection.lobby_password == "":
		DisplayServer.clipboard_set("Key: " + str(Connection.LOBBY_ID))
	else:
		DisplayServer.clipboard_set("Key: " + str(Connection.LOBBY_ID) + "\nPassword: " + str(Connection.lobby_password))

func _on_copy_password_pressed():
	DisplayServer.clipboard_set(Connection.lobby_password)

func _on_quit_lobby_pressed():
	Connection.leave_lobby()

func _on_lock_lobby_pressed():
	Connection.set_lobby_joinable(!$Slides/Lobby/VBox/Buttons/Lock_Lobby.button_pressed)

func _on_change_scene_pressed():
	""" Change Scene Pressed """
	
	Connection.change_scene("res://Scenes and Scripts/Scene_Change/Scene Change.tscn")

func _player_kicked_pressed(steam_id:int):
	Connection.kick_member(steam_id)

## Send Scheme
func _on_ss_test_pressed():
	
	# Start: Idle
	if ss_mode == SS_MODE.Idle:
		SS_start(true) # Start Test
	
	# Back to Idle: Done
	elif ss_mode == SS_MODE.Done:
		SS_change_mode(SS_MODE.Idle)
	
	# Stop: Process or Wait
	else:
		SS_change_mode(SS_MODE.Idle)

func _on_copy_ss_csv_pressed():
	""" Copy the SS CSV """
	
	## Header
	var array:Array = [["DATA_SIZE (B)"]]
	
	# Total Time
	for compression in COMPRESSION.keys():
		for p2p_send in P2P_SEND.keys():
			array[-1].append("Total_Time_" + compression + "_" + p2p_send)
	
	# Breakline
	array[-1].append("")
	
	# Lossiness
	for compression in COMPRESSION.keys():
		for p2p_send in P2P_SEND.keys():
			array[-1].append("Lossiness_" + compression + "_" + p2p_send)
	
	## Contents
	# For each stage
	for i in range(len(ss_data_sizes)):
		
		# Data Sizes
		var arr:Array = [ss_data_sizes[i] + SS_EXTRA_DATA_AMOUNT]
		
		# Total Time
		for compression in COMPRESSION.values():
			for p2p_send in P2P_SEND.values():
				if ss_results[SS_RESULTS.total_time][compression][p2p_send][i] == null:
					arr.append("")
				else:
					arr.append(ss_results[SS_RESULTS.total_time][compression][p2p_send][i])
				
		
		# Breakline
		arr.append("")
		
		# Lossiness
		for compression in COMPRESSION.values():
			for p2p_send in P2P_SEND.values():
				if ss_results[SS_RESULTS.lossiness][compression][p2p_send][i] == null:
					arr.append("")
				else:
					arr.append(ss_results[SS_RESULTS.lossiness][compression][p2p_send][i])
		
		# Add to Array
		array.append(arr)
	
	# Format the Array
	for i in range(len(array)):
		array[i] = ",".join(array[i])
	var results:String = "\n".join(array)
	DisplayServer.clipboard_set(results)
	print(results)


""" Misc """
func _line_edit_text_submitted(_new_text):
	""" Called by Every Line Edit that has had its text submitted """
	
	defocus()

func defocus():
	""" Release the Focus of all nodes that need to be"""
	
	# General Defocus
	for node in get_tree().get_nodes_in_group("defocus"):
		node.release_focus()
	
	# Forced Text
	$Slides/Host/VBox/VBox/VBox/Lobby_Size/Lobby_Size.text = str(max(int($Slides/Host/VBox/VBox/VBox/Lobby_Size/Lobby_Size.text), 2))
	$Slides/Connect/VBox/Bottom/VBox/Game_Key/HBox/Game_Key.text = str(max(int($Slides/Connect/VBox/Bottom/VBox/Game_Key/HBox/Game_Key.text), 0))

func create_junk(length:int, arr:Array = []):
	""" Create Junk """ # NOTE: Size of an int is 8 bytes
	
	# Add to Array
	var save:int = 0
	var save_incr:int = int(clamp((length + 8 - var_to_bytes(arr).size())/30.0, 0, 30))
	var i:int = 0
	while var_to_bytes(arr).size() < length:
		
		# Add to Arr
		var hold:int = randi()
		arr.append(hold)
		
		# Incr Save and i
		if i == 0:
			save = var_to_bytes(arr).size()
			i = save_incr
		else:
			i -= 1
	
	# Remove Excess from Array
	while (var_to_bytes(arr).size() - 8) > length:
		arr.pop_back()
	
	return arr




""" Send Scheme: CONTROL """
func _CONTROL_SS_DEFLATE_Reliable(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_DEFLATE_Rel_w_Buf(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_DEFLATE_Unreliable(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_DEFLATE_Unrel_No_Del(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)


func _CONTROL_SS_brotli_Reliable(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_brotli_Rel_w_Buf(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_brotli_Unreliable(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_brotli_Unrel_No_Del(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)


func _CONTROL_SS_FastLZ_Reliable(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_FastLZ_Rel_w_Buf(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_FastLZ_Unreliable(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_FastLZ_Unrel_No_Del(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)


func _CONTROL_SS_gzip_Reliable(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_gzip_Rel_w_Buf(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_gzip_Unreliable(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_gzip_Unrel_No_Del(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)


func _CONTROL_SS_Zstandard_Reliable(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_Zstandard_Rel_w_Buf(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_Zstandard_Unreliable(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)

func _CONTROL_SS_Zstandard_Unrel_No_Del(Packet:Connection.Packet_Class):
	_SS_control_packet(Packet)




















