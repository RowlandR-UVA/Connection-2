extends Node

""" 
----------------------------------------------------------------------------------------------
Purpose: This script interfaces with Steam's Multiplayer Interface and streamlines the process for Godot Usage
	It basically makes it easier to use Steam's Multiplayer Features in Godot

@Author: MadMelon999 (Rowland Halsey Robinson), Hazard Studios LLC, 9/2/24

Documentation Style:
	Any function indicated with _func() (the underscore part) should NOT be accessed outside of the Connection.gd script. As in, Don't use them. They are meant for internal use only

----------------------------------------------------------------------------------------------
Virtual Callbacks to use in the Current_Scene:
	Lobby Creation, Joining, and Matchmaking
		func _on_Lobby_Created(success:bool):
		func _on_Lobby_Joined(success:bool, msg:String):
		func _on_Handshake_Timeout(was_host:bool):
		func _on_Lobby_Match_List(lobby_data:Dictionary, headers:Array):
		func _on_Received_Trust_Test(Packet:Connection.Packet_Class):
		func _on_Trust_Test_Results(passed:bool):
	
	Updates, Operational, Leaving:
		func _on_Get_Lobby_Members():
		func _on_Lobby_Left(quit:bool, steam_id:int):
		func _on_Get_Inputs():
		func _on_Check_Inputs(inputs:Dictionary, steam_id:int) -> bool:
	
	NOTE: If these Callbacks are not present, and they are called, an error will be thrown (but not a fatal one)

Packets - Reading and Sending from the Current_Scene:
	In _ready(), call the function:
		setup_callable(callable_id:String, obj:Node, do_print:bool=false):
	
	In var Control:Dictionary, add the functions and stages of that function you would like to use
		Example for the "clock" Packet:
			var CONTROL:Dictionary = {"clock": [
				Send_Scheme.new(false, Steam.P2P_SEND_UNRELIABLE, false),
				Control_Details.new(READER.Sender, "send my time to the host", null),
				Control_Details.new(READER.Host, "include my time in the packet return", TYPE_FLOAT),
				Control_Details.new(READER.Sender, "use those times to determine the latency", [TYPE_FLOAT, TYPE_FLOAT])
				]
			}
			
		This example indicates, firstly, that all Packets should follow a certain Send_Scheme (see class in "Internal: Vars" for more details)
		Secondly, each stage of the function is described by: WHO can access it, its description, and the Valid Types it can accept (NOTE: Valid_Types are not necessary, but useful)
	
	To create a Packet, do:
		Packet_Class.new(callable_id, function, sender, data, stage)
		
		NOTE:
			The stage, by default, should always start at 0. If you need to start in the middle of a Packet instead, it is recommended that you use another function entirely
			If data does not abide by valid_types (specified in Control_Details in CONTROL), then an error will be thrown (unless valid_types == null)
			The Sender should be the next recipient of the Packet. If the Packet is being sent to multiple members, and you are initializing the Packet, just set it to yourself (steam_id)
	
	To Read a packet:
		Whenever a Packet is read (either when the Packet is initalized with Packet_Class.new() or when the Packet is received by another user), this function will be called in the respective callable_id:
			_CONTROL_func_name(Packet:Packet_Class)
		
		Example of a _CONTROL function:
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
		
		NOTE:
			Do not call a _CONTROL function directly. ALWAYS use Packets to access them (since Packets will also throw errors if there is one)
			The Packet's data will automatically be checked in its initialization against valid_types, so you can assume that the TYPE of data will be valid (assuming valid_types != null)
	
	To Send a Packet:
		Use Packet.send(data, steam_ids), where data is the data you want to send
		
		NOTE:
			steam_ids only works with READER.Members, and can be left unused if necessary.
			When a packet is sent, it is nt destroyed nor corrupted, meaning, you can reuse the packet as many times as necessary without worry of self-interference
				This is particularly useful for _on_Received_Trust_Test(Packet:Connection.Packet_Class), as the Packet can easily be reused to repeatedly send passwords

----------------------------------------------------------------------------------------------
Steam Multiplayer - Oddities:
	
	Reliability: Depending on how you chose to send a Packet, a Packet can have a garenteed chance of recieving the end-user
		You can also specifiy it as unreliable, which decreases the chance of it making across, but can be sent faster (maximum data size of 2kb)
	
	Joining:
		When you are a Host: _on_Lobby_Created is called, and then _on_Lobby_Joined is called. This is done automatically by steam, and not by this script (the consecutive calling)
		When you are a Client: _on_Lobby_Joined is called

	Packet Bunching: Occurs when several Packets are received within the same frame. For example, if you send 100 Packets with deltaX between each, and the network lags just a bit, they can all be recieved on the same frame

Dev Testing:
	If you receive a non-fatal error in red in the console when debugging, this does not necessarilt mean there was a critical error, but rather, it could be a planned statement.
		For example, if yiu receive an error that begins with 0.0.7, that just means that a packet was excluded from processing since it was already accessed in a later time frame, so it is discarded
			Sometimes, however, the error could be fatal. In that case, either check your own code, or try to debug this script
		These errors are thrown from _dev_print(), and are meant to be used internally

----------------------------------------------------------------------------------------------
Bugs and Updates for Next Version:
	Add in a setting that makes it so kicked players have to go through more checks in order to become trusted and join
		And also check for a pre-verification method
		Give the Host a blacklist list they can keep members on and off from?
	
	Make Error throws more descriptive, and include less of them if they are non-critical errors
	
	Implement Command Line Joining:
		## Check Command Line
		# Get the Arguments
		var args: Array = OS.get_cmdline_args()
		
		# If Valid
		if (args.size() > 1) and (args[0] == "+connect_lobby") and (int(args[1]) > 0):
			
			# Join the Lobby
			var lobby_id = int(args[1])
			join_lobby(lobby_id)
	
	Allow for games where the host of a lobby can change without crash
		Maybe a button that specifically indicates changing the host?
----------------------------------------------------------------------------------------------
"""


""" External: Variables """
# Game ID
@export var GAME_ID:String = "SCRIPT Connection" ## This is the ID for which lobbies will be searched for. Make it Unique to the Script

# Scenes
@export var MAIN_SCENE:String = "res://Scenes and Scripts/Main/main.tscn" ## The True "Main_Scene" that runs after this script finishes its _ready() script
@export var PIRATING_SCENE:String = "res://Steam/Scenes and Scripts/Pirating Scene.tscn" ## The scene to which the user is sent if they are a pirate

# Pirate Handling
@export var PIRATES_ALLOWED:bool = true ## If true, the game sends to Pirating Scene, if false, Pirates are tolerated
@export var FORCE_TEST_PIRATE:bool = false ## If true, pirate trigger goes off. If false, then pirate forcing does not happen


""" External: Functions """
## Callable Setup
func setup_callable(callable_id:String, obj:Node, do_print:bool=false): ## Run to setup a callable. Use for any script intended to use Steam's Multiplayer Interface Directly
	
	# Check if obj has Control
	if !("CONTROL" in obj):
		_dev_print("3.0.0", callable_id)
		return
	
	## If the Callable ID does not already exist
	if !(callable_id in callable_objs):
		
		# Basic
		callable_objs[callable_id] = obj # Assign the Callable Obj
		callables[callable_id] = {} # Reset the Callable Assigned to that ID
		var control:Dictionary = callable_objs[callable_id].CONTROL.duplicate() # Get the Control # TODO: Check if callable has CONTROL var that is a dictionary
		
		# Add the Controls to Callables
		for function in control.keys():
			
			# Basic
			callables[callable_id][function] = [] # Setup Callable
			var current_send_scheme:Send_Scheme = Send_Scheme.new() # Saves the Current Scheme of Compression
			current_send_scheme.check()
			
			# For Each Piece of Data
			for data in control[function]:
				
				# Data is Send Scheme:
				if data is Send_Scheme:
					current_send_scheme = data
					current_send_scheme.check()
				
				# Usage: reader, description, valid_types
				elif data is Control_Details:
					
					# Control_Details, send_scheme, Prev_Dif_Stage, Next_Dif_Stage
					callables[callable_id][function].append([data, current_send_scheme, null, null, data.reader in [READER.Members]])
					data.check()
				
				else:
					Connection._dev_print("2.0.0", data)
					return
		
			# Assign Next and Prev Readers
			for stage in range(len(callables[callable_id][function])):
			
				# Previous Stage
				for i in range(stage): # NOTE: Prev_Dif_Stage can stay "null", if no stage is before it
					
					# If Readers are Different
					if callables[callable_id][function][stage][CALLABLES.Control_Details].reader != callables[callable_id][function][(stage - (i + 1))][CALLABLES.Control_Details].reader:
						callables[callable_id][function][stage][CALLABLES.Prev_Dif_Stage] = (stage - (i + 1))
						break
				
				# Next Stage
				for i in range(len(callables[callable_id][function]) - stage - 1): # NOTE: Next_Dif_Stage can stay "null", if no stage is after it
					
					# If Readers are Different
					if callables[callable_id][function][stage][CALLABLES.Control_Details].reader != callables[callable_id][function][(stage + (i + 1))][CALLABLES.Control_Details].reader:
						callables[callable_id][function][stage][CALLABLES.Next_Dif_Stage] = (stage + (i + 1))
						break
		
	## Print Callables
	if do_print:
		# For Each Function
		var result:String = ""
		for function in callables[callable_id].keys():
			result += "[" + callable_id + ", " + function + "]:\n"
			
			# For each Stage
			for stage in range(len(callables[callable_id][function])):
				
				# Basuc
				var hold = callables[callable_id][function][stage]
				result += str(stage) + ": "
				
				# Reader, Prev_Dif_Stage, Next_Dif_Stage, Description, Valid_Types, Send_Scheme
				for call_enum in CALLABLES.values():
					# Reader
					if call_enum == CALLABLES.Control_Details:
						result += str(hold[call_enum].get_id())
					
					# Send Scheme
					elif call_enum == CALLABLES.Send_Scheme:
						result += str(hold[call_enum].get_id())
					
					# Other
					else:
						result += str(hold[call_enum])
					
					# Add Comma or New Line
					result += [", ", "\n"][int(call_enum == (len(CALLABLES.values()) - 1))]
			
			result += "\n"
		
		# Print Result
		print(result)
	
	## Check Root_Wait Calls
	if callable_id in packet_log[PACKET_LOG.root_wait]:
		
		# Use a check
		_dev_print("loading: \"PACKET_LOG.root_wait\" Packets", packet_log[PACKET_LOG.root_wait], false)
		
		# Get the Function Priorities
		var priority:Array = []
		for function in packet_log[PACKET_LOG.root_wait][callable_id]:
			var idx:int = callables[callable_id].keys().find(function)
			if idx != -1:
				priority.append(idx)
			else:
				_dev_print("0.1.0", function)
		
		# Sort
		priority.sort()
		
		# For each Idx
		for idx in priority:
			
			# Get the Function
			var function:String = callables[callable_id].keys()[idx]
			
			# Call the Packet
			var stage:int = packet_log[PACKET_LOG.root_wait][callable_id][function][0]
			var data = packet_log[PACKET_LOG.root_wait][callable_id][function][1]
			Packet_Class.new(callable_id, function, HOST_STEAM_ID, data, stage)
		
		# Remove Callable ID
		packet_log[PACKET_LOG.root_wait].erase(callable_id)
	
	## Remove Callables that Do Not Exist
	_check_freed_callables()

## Lobbies: Host Only
func change_scene(scene_path:String): ## Change the Scene
	## NOTE: Locks the Lobby as well when changing the scene
	
	# TODO: Allow for Intermediate Phase to be used here
	
	# Send Packet
	Packet_Class.new("Connection", "change_scene", STEAM_ID, scene_path)

func create_lobby(new_lobby_name:String, new_lobby_type:Steam.LobbyType, new_lobby_size:int, new_lobby_joinable:int, new_lobby_password:String): ## Creates a Lobby (also works when Offline)
	
	# If not in a lobby, End
	if LOBBY_ID != 0:
		return
		
	# Basic
	lobby_name = new_lobby_name
	lobby_type = new_lobby_type
	lobby_size = new_lobby_size
	lobby_joinable = new_lobby_joinable
	lobby_password = new_lobby_password
	_reset()
	
	# Online
	if ONLINE:
		Steam.createLobby(lobby_type, lobby_size)
	
	# Offline
	else:
		_on_Lobby_Created(1, 1)
		_on_Lobby_Joined(1, 0, false, Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)

func kick_member(steam_id: int): ## Kick Member
	
	# Send the Packet to kick the member
	Packet_Class.new("Connection", "kick", HOST_STEAM_ID, steam_id)

func set_lobby_type(new_lobby_type:Steam.LobbyType): ## Set the lobby type (called when already inside of a lobby and when the host)
	
	# Can only access if online host # TODO: In next version, allow for other lobby_data to be edited WHILE INSIDE of a lobby (as host of course)
	if is_member_online_host():
		
		# Set the Lobby Type
		lobby_type = new_lobby_type
		Steam.setLobbyType(Connection.LOBBY_ID, lobby_type)
		
		# Update
		_update_lobby_data(true)

func set_lobby_joinable(new_lobby_joinable:bool): ## Set the lobby joinable
	
	# If Online Host
	if is_member_online_host():
	
		# Set Lobby Joinable
		lobby_joinable = new_lobby_joinable
		Steam.setLobbyJoinable(LOBBY_ID, lobby_joinable)
		
		# If lobby is no longer joinable, kick untrusted
		if !lobby_joinable:
			for steam_id in MEMBERS:
				if !(steam_id in TRUSTED):
					kick_member(steam_id)
		
		# Update
		_update_lobby_data(true)

## Lobbies: Host and Client
func join_lobby(lobby_id: int, new_lobby_password:String=""): ## Joins a lobby
	
	# Reset
	lobby_password = new_lobby_password
	_reset()
	
	# Join Lobby
	Steam.joinLobby(lobby_id)

func leave_lobby(handshake_timeout:bool=false): ## Called when leaving a lobby
	
	# Get if Was Host
	var was_host:bool = is_member_host()
	
	# Close p2p sessions
	for steam_id in MEMBERS.keys():
		if !is_member_me(steam_id):
			Steam.closeP2PSessionWithUser(steam_id)
	
	# Leave Lobby
	Steam.leaveLobby(LOBBY_ID)
	
	# Update Host
	_reset()
	
	# Lobby Left
	if !handshake_timeout:
		_call_current_scene("_on_Lobby_Left", [true, STEAM_ID])
	else:
		_call_current_scene("_on_Handshake_Timeout", [was_host])

func refresh_match_list(search_distance:Steam.LobbyDistanceFilter = Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE): ## Update list of lobbies that are visible
	
	# Change search distance
	Steam.addRequestLobbyListDistanceFilter(search_distance)
	
	# Request Lobbies
	Steam.requestLobbyList()

## File Management
func file_write(file_name:String): ## Write a Steam Cloud file
	
	# Get Packed Data
	var packed:PackedByteArray = var_to_bytes(file_data[file_name]).compress(FileAccess.COMPRESSION_GZIP)
	
	# Write Packed Data
	Steam.fileWriteAsync(file_name, packed, packed.size())

func file_batch_write(file_names:Array): ## Write multiple Steam Cloud files at once
	
	# beginFileWriteBatch
	if len(file_names) > 1:
		Steam.beginFileWriteBatch()
	
	# Write to Files
	for file_name in file_names:
		file_write(file_name)
		Steam.fileWrite(file_name, var_to_bytes(file_data[file_name]).compress(FileAccess.COMPRESSION_GZIP))
	
	# endFileWriteBatch
	if len(file_names) > 1:
		Steam.endFileWriteBatch()

func file_delete(file_name:String): ## Delete a Steam Cloud File
	Steam.fileDelete(file_name)

## Helpers: Complex
func get_avatar(steam_id:int, avatar_size:Steam.AvatarSizes = Steam.AVATAR_MEDIUM): ## Get the Avatar of a player
	# TODO Return default png for missing if avatar does not exist (in its different sizes as well)
	
	# No Avatar Loaded
	if !((steam_id in AVATARS) and (avatar_size in AVATARS[steam_id])):
		
		# Request Avatar from steam
		Steam.getPlayerAvatar(avatar_size, steam_id)
		
		# Return default avatar
		return DEFAULT_AVATARS[avatar_size]
		
	else:
		
		# Return Avatar
		return AVATARS[steam_id][avatar_size]

func get_input(steam_id:int, input_type:INPUT_TYPE): ## Get a user's inputs
	
	# If Steam_ID exists and so does the Input Type
	if (steam_id in inputs) and (input_type in inputs[steam_id]):
		return inputs[steam_id][input_type]

func get_any_input_pressed(steam_id:int) -> bool: ## Check if any input is being pressed
	
	# If Steam ID Exists
	if (steam_id in inputs) and (INPUT_TYPE.normal in inputs[steam_id]):
		
		# Pressed
		for pressed in inputs[steam_id][INPUT_TYPE.normal].values():
			if pressed:
				return true
	
	return false

func get_member_latency(steam_id:int) -> int:
	return int(Steam.getLobbyMemberData(LOBBY_ID, steam_id, "latency")) # NOTE: In Milli-seconds

## Helpers: Simple
func is_member_me(steam_id:int) -> int:
	return steam_id == STEAM_ID

func is_member_host(steam_id:int=STEAM_ID) -> int:
	return steam_id == HOST_STEAM_ID

func is_member_online_host(steam_id:int=STEAM_ID) -> bool:
	return is_member_host(steam_id) and in_online_lobby()

func is_member_trusted(steam_id:int=STEAM_ID) -> bool:
	return (steam_id in TRUSTED)

func in_lobby() -> bool:
	return !(LOBBY_ID in [0])

func in_online_lobby() -> bool:
	return !(LOBBY_ID in [0,1])

func get_member_color(steam_id:int):
	
	# If the steam_id is a member
	if (steam_id in MEMBERS) and is_member_trusted(steam_id):
		if is_member_host(steam_id):
			return Color(0,1,1)
		else:
			return Color(0,1,0)
	return Color(1,0,0)

func get_member_name(steam_id:int) -> String:
	
	# If Member already exists
	if steam_id in MEMBERS:
		return MEMBERS[steam_id]
	
	# Not in-lobby member
	return Steam.getFriendPersonaName(steam_id)

## Achievements
func get_achievements() -> Array: ## Get the Achievements Currently Available
	""" Get Achievements """
	
	# Get all of the Achievements
	var arr:Array = []
	var i = 0
	while true:
		var ach = Steam.getAchievementName(i)
		if ach == "":
			break
		arr.append(ach)
		i += 1
	return arr

func set_achievement(achievement:String): ## Set an Achievement to have been achieved by oneself
	""" Set Achievement """
	
	# NOTE: These can only be set when steam is running, not the godot debugger for steam!
	if !(Steam.getAchievement(achievement)["achieved"]):
		Steam.setAchievement(achievement)


""" Internal: Vars """
## Steam Check
var OWNED:bool ## User Owns the Game
var PIRATE:bool ## User is a pirate. ARRRR MATEES
var ONLINE:bool ## User is Online or Offline
var STEAM_ID:int ## My steam_id
var STEAM_NAME:String ## My Steam Name

# Lobby Basics
var LOBBY_ID:int ## The lobby_id currently used. 0 is not in a lobby. 1 is in an offline lobby. Other is an actual lobby
var lobby_name:String ## The name of the lobby
var lobby_type:Steam.LobbyType ## The type of lobby (see LOBBY_TYPES for more info)
var lobby_size:int ## The maximum size of the lobby
var lobby_joinable:bool ## If the lobby is joinable or not
var lobby_password:String ## The password for the lobby (if an empty string [""], then no password is required)

# Steam ID Saving
var HOST_STEAM_ID:int ## The current HOST_STEAM_ID. If offline lobby, then automatically set to my steam_id
var MEMBERS: Dictionary ## Holds all steam_ids in lobby pointing to names (including untrusted members)
var TRUSTED:Array ## Holds all trusted steam_ids
var APPROVED:Array ## Holds all steam_ids that have assumed pre-approval for trust (happens when a player has already joined a lobby)
var KICKED:Array ## Holds all fot he steam_ids that have been kicked from the lobby (either good or bad standing)

## Virtual Enums
# Lobby Search
const LOBBY_TYPES:Dictionary = { ## The types of Lobbies that can be Started
	"Public": Steam.LOBBY_TYPE_PUBLIC,
	"Friends Only": Steam.LOBBY_TYPE_FRIENDS_ONLY,
	"Private": Steam.LOBBY_TYPE_PRIVATE,
	"Private Unique": Steam.LOBBY_TYPE_PRIVATE_UNIQUE,
	"Invisible": Steam.LOBBY_TYPE_INVISIBLE,
	}
const SEARCH_DISTANCES:Dictionary = { ## The types of Search Distances that can be used by a client
	"Worldwide": Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE,
	"Far": Steam.LOBBY_DISTANCE_FILTER_FAR,
	"Close": Steam.LOBBY_DISTANCE_FILTER_CLOSE
	}

# Compression
const COMPRESSION:Dictionary = { ## The types of Compression Available
	"brotli": FileAccess.COMPRESSION_BROTLI, ## NOTE: Only Decompression is Supported for this Type
	"DEFLATE": FileAccess.COMPRESSION_DEFLATE,
	"FastLZ": FileAccess.COMPRESSION_FASTLZ, ## NOTE: Does not work with decompress_dynamic
	"gzip": FileAccess.COMPRESSION_GZIP,
	"Zstandard": FileAccess.COMPRESSION_ZSTD, ## NOTE: Does not work with decompress_dynamic
	}
const ALLOWED_COMPRESSION:Array = [FileAccess.COMPRESSION_DEFLATE, FileAccess.COMPRESSION_GZIP] ## The Compression Modes that are permitted

# P2P Send
const P2P_SEND:Dictionary = { ## The types of Peer-to_Peer Sending Available
	"Reliable": Steam.P2P_SEND_RELIABLE,
	"Rel_w_Buf": Steam.P2P_SEND_RELIABLE_WITH_BUFFERING,
	"Unreliable": Steam.P2P_SEND_UNRELIABLE,
	"Unrel_No_Del": Steam.P2P_SEND_UNRELIABLE_NO_DELAY,
	}
const ALLOWED_P2P_SEND:Array = [Steam.P2P_SEND_RELIABLE, Steam.P2P_SEND_RELIABLE_WITH_BUFFERING, Steam.P2P_SEND_UNRELIABLE, Steam.P2P_SEND_UNRELIABLE_NO_DELAY] ## The P2P_Send Modes that are permitted

## Delta-Based Calls
# Basic
const TIME_BASED_TRIGGERS:Dictionary = {"CONTROL_clock": 0.06, "CONTROL_inputs": 0.06, "_on_Lobby_Data_Updated": 2.0} ## The total times at which certain triggers go off
var time_based_triggers:Dictionary ## The current times at which certain triggers go off
var allow_lobby_data_update:bool ## Set to true when the time_based_trigger (_on_Lobby_Data_Updated) goes off. Set to false when the function _on_Lobby_Data_Updated finally gets called

# Handshake
const HANDSHAKE_TRIGGER_DELTA:float = 2.0 ## The amount of seconds to wait until sending the next handshake
const HANDSHAKE_TRIGGER_TOTAL:float = 19.9 ## The total amount of time to wait for a handshake
var waiting_for_handshake:bool ## Checks if still waiting for a handshake

## File Management
const FILE_DATA = ["Test"] ## The files that will be loaded during initialization
const FILE_DATA_MIN_PING_TIME:float = 10.0 ## The minimum ping time for files until cancelling early is possible
const FILE_DATA_MAX_PING_TIME:float = 20.0 ## The maximum time until files are automatically overwritten # TODO: Check if this has bad side-effects
const FILE_DATA_INCR_TIME:float = 0.1 ## The time between each ping
var file_data:Dictionary ## The data held within each file. To access this data, just reference this dictionary, instead of calling for the data from Steam Servers
@onready var files_initialized:bool = false ## Boolean that indicates if the files have been initialized

## Avatars
const DEFAULT_AVATARS_PATH = "res://Steam/Assets/Default Avatars/"
@onready var DEFAULT_AVATARS:Dictionary = {
	Steam.AVATAR_SMALL: load(DEFAULT_AVATARS_PATH.path_join("AVATAR_SMALL.png")),
	Steam.AVATAR_MEDIUM: load(DEFAULT_AVATARS_PATH.path_join("AVATAR_MEDIUM.png")),
	Steam.AVATAR_LARGE: load(DEFAULT_AVATARS_PATH.path_join("AVATAR_LARGE.png"))
	}
var AVATARS: Dictionary ## The PNG AVATARS of every player, categorized by {steam_id: avatar_size: png}

## Clock
# Actual
var latency:float ## The latency it takes for two-way communication to the host. Value is in SECONDS and represents the time it takes to speak to host ONE-WAY
var client_clock:int ## The current time of the client_clock (this value is synced across users). Value is in SECONDS (with 3 digits worth of msec)

# Calculations
const LATENCY_PING_AMOUNT = 9 ## The amount of latency pings required until the latency is calaculated
var latency_array:Array ## The latency values stored until it is properly calculated
var delta_latency:float ## Internal, used for calculations
var decimal_collector:float ## Internal, used for calculations

## Inputs
enum INPUT_TYPE {normal, just_pressed, just_released, mouse} ## The types of inputs that can be stored
var inputs: Dictionary ## Inputs stored by {steam_id: input_type: input_name: boolean}. Access via get_input()

## Packet Class
# Basic
enum READER {Host, Sender, Members} ## The types of readers that can recieve a packet
const NON_LOBBY_ALLOWED = ["change_scene"] ## Within Connection.gd, functions that don't need to be trusted to be accessed: when outside of a lobby
const ALLOWED_UNTRUSTED_CONNECTION_PACKETS = ["handshake", "trust_update", "kick"] ## Within Connection.gd, functions that don't need to be trusted to be accessed: when untrusted
const IGNORE_CONNECTION_PACKETS = ["clock", "inputs"]

# Read
const PACKET_READ_LIMIT:int = 200 ## The amount of packets that can be read during _process()
enum PACKET_LOG {latest, root_wait} ## The different kinds of storage methods for packets.
var packet_log:Array ## The storage medium of different kinds of packets

## Callable
enum CALLABLES {Control_Details, Send_Scheme, Prev_Dif_Stage, Next_Dif_Stage} ## The kinds of data that can be accessed within a CONTROL Function
var callables:Dictionary ## The callables of a script, stored by {callable_id: function: stage: CALLABLES}
var callable_objs: Dictionary ## Callable_Ids pointing to Callable_Objs

## Control
var CONTROL:Dictionary = { ## The Controls that can be accessed within this script. NOTE: This should be implemented in every script that intends to use Steam
## Control_Details is used for each Stage
## Send_Scheme is used to CHANGE the current send_scheme being used. If not used, then the default vars in _init() within "class Send_Scheme" are used
	"handshake": [
		Control_Details.new(READER.Sender, "client forth", TYPE_NIL),
		Control_Details.new(READER.Host, "host back", TYPE_NIL),
		Control_Details.new(READER.Sender, "client request test", TYPE_NIL),
		Control_Details.new(READER.Host, "host tell client to autosend or not", TYPE_STRING),
		Control_Details.new(READER.Sender, "client answer test", TYPE_BOOL),
		Control_Details.new(READER.Host, "host check test answer", TYPE_STRING),
		Control_Details.new(READER.Sender, "client failed", TYPE_NIL),
		],
	"trust_update": [
		Control_Details.new(READER.Host, "tell clients the new trusted members", TYPE_INT),
		Control_Details.new(READER.Members, "update trusted", TYPE_ARRAY),
	],
	
	"kick": [
		Send_Scheme.new(false),
		Control_Details.new(READER.Host, "tell clients who to kick", TYPE_INT),
		Control_Details.new(READER.Members, "kick player", TYPE_INT),
	],
	
	"change_scene": [
		Control_Details.new(READER.Host, "tell clients the new scene", TYPE_STRING),
		Control_Details.new(READER.Members, "switch scene, and tell the clients who was Kicked", [TYPE_ARRAY, TYPE_STRING]),
	],
	
	"clock": [
		Send_Scheme.new(false, Steam.P2P_SEND_UNRELIABLE, false),
		Control_Details.new(READER.Sender, "send my time to the host", null),
		Control_Details.new(READER.Host, "include my time in the packet return", TYPE_FLOAT),
		Control_Details.new(READER.Sender, "use those times to determine the latency", [TYPE_FLOAT, TYPE_FLOAT]),
		],
	
	"inputs": [
		Control_Details.new(READER.Sender, "send my inputs to the host", TYPE_NIL),
		Control_Details.new(READER.Host, "check that their inputs are valid, then send to the clients", TYPE_DICTIONARY),
		Send_Scheme.new(false), # NOTE: This has to be false because the data included specifies the steam_id target, which cannot be analyzed by the "force_latest" condition
		Control_Details.new(READER.Members, "update the original sender's inputs", [TYPE_DICTIONARY, TYPE_INT]),
		],
	}

## Classes
class Packet_Class: ## This class allows the controlled sending and reading packets to be more stable and secure
	
	## Vars
	# Basic
	var callable_id:String
	var function:String
	var stage:int
	var data
	var sender:int
	
	# Temporary / Operational
	var control: Array # NOTE: This is a quick reference var for CONTROL for the function
	var time_stamp:float
	
	## Reading and Sending
	func _init(new_callable_id:String, new_function:String, new_sender:int, new_data=null, new_stage:int=0): ## Reads a packet
		
		## Basic
		# Assign Vars
		callable_id = new_callable_id
		function = new_function
		stage = new_stage
		data = new_data
		sender = new_sender
		time_stamp = Time.get_unix_time_from_system()
		
		## Checks
		
		# Check if root_wait is Needed
		if !(callable_id in Connection.callables):
			# NOTE: Assume that for root_wait, the stage is always 1, and the sender is always the host
			
			# Invalid Sender
			if !Connection.is_member_host(sender):
				Connection._dev_print("0.0.1", self)
				return
			
			# Add root_wait ID
			if !(callable_id in Connection.packet_log[Connection.PACKET_LOG.root_wait]):
				Connection.packet_log[Connection.PACKET_LOG.root_wait][callable_id] = {}
			Connection.packet_log[Connection.PACKET_LOG.root_wait][callable_id][function] = [stage, data] # NOTE: This automatically overwrites previous function calls, on-purpose
			
			# Return
			return
		
		# Function does not exist
		elif !(function in Connection.callables[callable_id]):
			Connection._dev_print("0.0.2", self)
			return
		
		# Set the Control
		control = Connection.callables[callable_id][function]
		
		# Check: Stage Too Far
		if !((stage >= 0) and (stage < len(control))):
			Connection._dev_print("0.0.3", self)
			return
		
		# (Valid Stage) and (Trusted) and (Sender Allowed to Send): # (Zeroeth Stage) OR ((Trusted) and (Previous Sender Good))
		if !sender_valid():
			if Connection._dev_print("0.0.4", self):
				Connection._dev_print("sender_valid", {"isn't a member": !(sender in Connection.MEMBERS), "is_sender_trusted": Connection.is_member_trusted(sender), "untrusted_allowed": untrusted_allowed(), "reader_valid": (control[stage][Connection.CALLABLES.Prev_Dif_Stage] == null or (sender in get_readers(control[stage][Connection.CALLABLES.Prev_Dif_Stage])))})
				Connection._dev_print("details", [Connection.MEMBERS, sender, Connection.TRUSTED, sender in Connection.TRUSTED])
				Connection._dev_print("", null)
			return
		
		# Can Access: (I can Read)
		elif !receiver_valid():
			if Connection._dev_print("0.0.5", self):
				Connection._dev_print("reader_valid", {"i_am_reader": (Connection.STEAM_ID in get_readers(stage)), "i_am_sender": (control[stage][Connection.CALLABLES.Control_Details].reader == Connection.READER.Sender)})
				Connection._dev_print("", null)
			return
		
		# Check Valid Types
		elif !Connection._check_valid_types(data, control[stage][Connection.CALLABLES.Control_Details].valid_types):
			Connection._dev_print("0.0.6", self)
			Connection._dev_print("", [data, control[stage][Connection.CALLABLES.Control_Details].valid_types])
			return
			
		# Packet Log: Latest
		if control[stage][Connection.CALLABLES.Send_Scheme].force_latest:
			
			# Basic
			var id:Array = [callable_id, function, stage, sender]
			
			# If (No Latest Exists) OR (Latest is greater than the previous Latest) # NOTE: If this if Runs, then the Packet will continue to run
			if !(id in Connection.packet_log[Connection.PACKET_LOG.latest]) or (time_stamp > Connection.packet_log[Connection.PACKET_LOG.latest][id]):
				Connection.packet_log[Connection.PACKET_LOG.latest][id] = time_stamp
			
			# Bad Packet (But not necessarily a malicious one)
			else:
				Connection._dev_print("0.0.7", self)
				return
		
		## General Print
		if (callable_id == "Connection") and !(function in IGNORE_CONNECTION_PACKETS):
			Connection._dev_print("read", self, false)
		
		## Read
		Connection._get_callable(callable_id).call("_CONTROL_" + function, self)
	
	func send(new_data=data, steam_ids:Array=[]): ## Sends a Packet
		
		# Can Access Check
		if !receiver_valid():
			Connection._dev_print("1.0.0", self)
			return
		
		# Set the Data
		data = new_data
		
		# Get Steam_Ids
		if steam_ids.is_empty():
			steam_ids = get_readers(stage + 1)
		
		# Set the Lobby Password # NOTE: THis is an extreme edge case, where we don't want the user to have to set the lobby_password when they attempt to asnwer it
		if [callable_id, function, stage] == ["Connection", "handshake", 4]:
			# TODO: Run a valid_types check
			Connection.lobby_password = data
		
		# Send packet
		Connection._send_packet(self, steam_ids, control[stage][Connection.CALLABLES.Send_Scheme])
	
	## Helpers and Checks
	func get_readers(temp_stage:int): ## Gets all of the steam_ids associated with a reader
		
		# Return None if out of bounds
		if !(temp_stage >= 0 and temp_stage < len(control)):
			return []
		
		# Get the Reader
		var reader = control[temp_stage][Connection.CALLABLES.Control_Details].reader
		if reader == READER.Host:
			return [Connection.HOST_STEAM_ID]
		
		elif reader == READER.Sender:
			return [sender]
		
		elif reader == READER.Members: # NOTE: "Members" Implies Trusted Members Only
			if untrusted_allowed():
				return Connection.MEMBERS.keys()
			else:
				return Connection.TRUSTED
	
	func sender_valid(): ## Checks if the sender is valid
		
		# Sender Exists
		if !(sender in Connection.MEMBERS): # TODO: Working: put this part in send_packet
			
			# Get Lobby Members in case they just joined, and check again
			Connection._get_lobby_members()
			
			# Member not joined
			if !(sender in Connection.MEMBERS):
				return false
		
		# Basic
		var trusted:bool = Connection.is_member_trusted(sender) or untrusted_allowed()
		var could_send:bool = control[stage][Connection.CALLABLES.Prev_Dif_Stage] == null or (sender in get_readers(control[stage][Connection.CALLABLES.Prev_Dif_Stage]))
		
		# Return
		return could_send and (trusted)
	
	func receiver_valid(): ## Checks if the receiver is valid
		
		# I am Reader
		var i_am_reader:bool = Connection.STEAM_ID in get_readers(stage)
		
		# I am a sender (all senders should be able to have access)
		var i_am_sender:bool = control[stage][Connection.CALLABLES.Control_Details].reader == Connection.READER.Sender
		
		# Return
		return i_am_reader or i_am_sender
	
	func untrusted_allowed(): ## Checks if untrusted users are allowed to access packets
		return ((callable_id == "Connection") and (function in ALLOWED_UNTRUSTED_CONNECTION_PACKETS + NON_LOBBY_ALLOWED))

	func get_id():
		
		# Gets the Unique ID of the Packet
		return [callable_id, function, stage, data]

class Control_Details:
	
	## Vars
	var reader:Connection.READER ## The reader (which points to steam_ids) that is allowed to access a packet
	var description:String ## The descriptions of what a packet does
	var valid_types ## The types of parameters that must be used when interacting with a packet
	
	## Functions
	func _init(new_reader:Connection.READER, new_description:String, new_valid_types=null): ## Init
		
		# Basic
		reader = new_reader
		description = new_description
		
		# Format Valid Types
		if new_valid_types == null:
			valid_types = null
		elif typeof(new_valid_types) != TYPE_ARRAY:
			valid_types = [new_valid_types]
		else:
			valid_types = new_valid_types
	
	func check(): ## Checks if there is an inherent error in the valid_types
		
		# Check Valid_Types
		if valid_types != null:
			for item in valid_types:
				if !((item == null) or (item is Variant.Type)):
					Connection._dev_print("4.0.0", self)
	
	func get_id(): ## Gets the Unique ID of Control_Details (used for debugging)
		return [
			Connection.READER.keys()[reader],
			description,
			valid_types
		]

class Send_Scheme:
	
	## Vars
	var force_latest:bool
	var p2p_send:Steam.P2PSend
	var compression:FileAccess.CompressionMode # NOTE: Compression is also the channel used for sending
	var allow_self_call:bool
	# TODO: Allow for thread_priorities
	
	## Functions
	func _init(new_force_latest:bool=true, new_p2p_send:Steam.P2PSend=Steam.P2P_SEND_RELIABLE, new_allow_self_call:bool=true, new_compression:FileAccess.CompressionMode=FileAccess.COMPRESSION_GZIP): ## Init
		
		# Basic
		force_latest = new_force_latest
		compression = new_compression
		p2p_send = new_p2p_send
		allow_self_call = new_allow_self_call
	
	func check(): ## Checks if there is an inherent error in the Packet
		
		# Not Allowed Compression
		if !(compression in ALLOWED_COMPRESSION):
			Connection._dev_print("4.0.0", self)
		
		# Not Allowed P2P Send
		if !(p2p_send in ALLOWED_P2P_SEND):
			Connection._dev_print("4.0.1", self)
		
	
	func get_id(): ## Gets the unique ID of a send_scheme (used for debugging)
		return [
			force_latest,
			Connection.COMPRESSION.keys()[Connection.COMPRESSION.values().find(compression)],
			Connection.P2P_SEND.keys()[Connection.P2P_SEND.values().find(p2p_send)],
			allow_self_call,
		]


""" Internal: Functions """
## Setup and Basic Check
func _ready():
	
	## Boot Check
	if !_steam_check():
		return
	
	## Connect Signals
	# Host
	Steam.connect("lobby_created", Callable(self, "_on_Lobby_Created"))
	
	# Client
	Steam.connect("join_requested", Callable(self, "_on_Lobby_Join_Requested"))
	Steam.connect("lobby_joined", Callable(self, "_on_Lobby_Joined"))
	
	# Host and Client
	Steam.connect("p2p_session_request", Callable(self, "_on_P2P_Session_Request"))
	Steam.connect("p2p_session_connect_fail", Callable(self, "_on_P2P_Session_Connect_Fail"))
	
	Steam.connect("lobby_chat_update", Callable(self, "_on_Lobby_Chat_Updated"))
	Steam.connect("lobby_data_update", Callable(self, "_on_Lobby_Data_Updated"))
	Steam.connect("persona_state_change", Callable(self, "_on_Persona_Change"))
	Steam.connect("avatar_loaded", Callable(self, "_on_Loaded_Avatar"))
	
	# Invite
	Steam.connect("lobby_match_list", Callable(self, "_on_Lobby_Match_List"))
	Steam.connect("lobby_message", Callable(self, "_on_Lobby_Message"))
	Steam.connect("lobby_invite", Callable(self, "_on_Lobby_Invite"))
	
	## Misc
	# Reset
	_reset()
	
	# Assign Self as Callable
	setup_callable("Connection", Connection, false)
	
	# Init Files
	_file_init()
	
	# Change Scene
	change_scene([MAIN_SCENE, PIRATING_SCENE][int(PIRATE)])

func _steam_check(): ## Checks bootup for Steam to see if game is playable
	
	# Steam App Open Check
	var INIT = Steam.steamInit()
	if INIT["status"] != 1:
		print("[Connection] Failed to initialize Steam. " + str(INIT["verbal"]) + " Shutting down...")
		get_tree().quit()
		return false
	
	# Basic
	OWNED = Steam.isSubscribed()
	PIRATE = !(OWNED or PIRATES_ALLOWED) or FORCE_TEST_PIRATE
	ONLINE = Steam.loggedOn()
	STEAM_ID = Steam.getSteamID()
	STEAM_NAME = Steam.getPersonaName()
	return true

func _reset(lobby_id:int=0): ## A General call to update and reset variables
	# NOTE: If lobby_id is 0 or 1, than that implies a special lobby type
	
	# Set the LOBBY_ID
	LOBBY_ID = lobby_id
	
	# Set the Host # NOTE: This is here (and not in _get_lobby_members()) so that when quitting the lobby, the HOST_STEAM_ID isn't accidentaly overwritten # TODO: In change_host future version, see if this is necessary
	if lobby_id == 0: # NOTE: This doesn;t actually do anything, its just helpful to have to make sure it stays a certain value
		HOST_STEAM_ID = STEAM_ID
	elif lobby_id == 1:
		HOST_STEAM_ID = STEAM_ID
	else:
		HOST_STEAM_ID = Steam.getLobbyOwner(LOBBY_ID)
	
	# Reset Handshake Waiting
	waiting_for_handshake = false
	
	# Reset Trusted, Approved, and Kicked
	TRUSTED.clear()
	APPROVED.clear()
	KICKED.clear()
	
	# Reset Packet Log
	packet_log.clear()
	for value in PACKET_LOG.values():
		packet_log.append({})
	
	# Reset Clock
	latency_array.clear()
	latency = 0
	delta_latency = 0
	client_clock = 0
	decimal_collector = 0.0
	
	# Reset Sync Inputs
	inputs.clear()
	for key in TIME_BASED_TRIGGERS.keys():
		time_based_triggers[key] = 0
	
	# Reset Lobby Data Trigger
	allow_lobby_data_update = false
	
	# Update Lobby Members
	_get_lobby_members()

func _file_init(file_names:Array=FILE_DATA) -> Array: ## Initialize the Steam Based Files. Returns the files that could not be initialized
	
	## Get the Files
	var not_ready:Array = file_names.duplicate()
	var overwritten:Array = []
	var current_time:float = 0.0
	while !not_ready.is_empty():
		
		# end_early
		var end_early:bool = (current_time >= FILE_DATA_MIN_PING_TIME) and Input.is_action_just_pressed("escape")
		if end_early:
			print("[STEAM] Ending Process Early: " + str(not_ready))
		
		# For Each not_ready file
		for file_name in file_names:
			if file_name in not_ready:
			
				# (File Exists) AND (continue searching) AND !(end_early)
				var check = null
				if Steam.fileExists(file_name) and (current_time <= FILE_DATA_MAX_PING_TIME) and !end_early:
					
					# Get the File Data
					var data = Steam.fileRead(file_name, Steam.getFileSize(file_name))
					
					# If Data has loaded
					if data != null and data["ret"] != 0:
						print("[STEAM] File Retrieved: " + file_name)
						file_data[file_name] = bytes_to_var(data["buf"].decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP))
						not_ready.erase(file_name)
				
				# File does not Exist
				else:
					print("[STEAM] File (" + file_name + ") Failed to Load. Initializing... ")
					file_data[file_name] = Time.get_unix_time_from_system()
					not_ready.erase(file_name)
					overwritten.append(file_name)
		
		# Print
		if !not_ready.is_empty():
			print("[STEAM] Failed to Retrieve (" + str(current_time) + "): " + str(not_ready))
		
		# Incr Current Time
		await get_tree().create_timer(FILE_DATA_INCR_TIME).timeout
		current_time += FILE_DATA_INCR_TIME
	
	## File Write Batch
	file_batch_write(overwritten)
	
	## Delete Files that shouldn't Exist
	var to_delete:Array = []
	for idx in Steam.getFileCount():
		
		# Get each file to delete
		var file_name = Steam.getFileNameAndSize(idx)["name"]
		if !(file_name in file_names) and file_name != "":
			to_delete.append(file_name)
	
	# Delete the files
	if !to_delete.is_empty():
		print("[STEAM] Deleting Extra Files: " + str(to_delete))
		for file_name in to_delete:
			file_delete(file_name)
	
	files_initialized = true
	
	# Return
	return not_ready

## Process
func _process(delta):
	
	## Run Packet Callbacks
	Steam.run_callbacks()
	
	## Read Packets
	_read_RAW_packets() # NOTE: This is called when not even in lobby, in case the player left, and then recieved more data
	
	## Delta Based Call
	if is_member_trusted(STEAM_ID): # TODO: Check if in Lobby as Well?
		
		# Process Client Clock
		_process_client_clock(delta)
		
		# Time_Based Triggers
		for key in TIME_BASED_TRIGGERS.keys():
			
			# Time Trigger
			time_based_triggers[key] += delta
			if time_based_triggers[key] >= TIME_BASED_TRIGGERS[key]:
				time_based_triggers[key] = 0
				
				# Call Time Triggers
				if key == "CONTROL_clock":
					Packet_Class.new("Connection", "clock", HOST_STEAM_ID)
					
				elif key == "CONTROL_inputs":
					Packet_Class.new("Connection", "inputs", HOST_STEAM_ID)
				
				elif key == "_on_Lobby_Data_Updated":
					allow_lobby_data_update = true
	
	## If Goes Offline While in Online Lobby, Quit
	_steam_check()
	if in_online_lobby() and !ONLINE:
		leave_lobby(false)

## Lobby: Callables
func _on_Lobby_Created(connect_response:int, lobby_id:int): ## Called when lobby is created by host (called before _on_Lobby_Joined)
	
	# If Lobby is created
	if connect_response == 1:
		
		# Basic
		_reset(lobby_id) # NOTE: This is necessary here (not redundant for _on_Lobby_Joined()) for some functions to operate so as to recognize the host and lobby being active
		
		# Lobby Data
		set_lobby_joinable(lobby_joinable)
		_update_lobby_data(true)
	
	_call_current_scene("_on_Lobby_Created", [connect_response == 1])

func _on_Lobby_Joined(lobby_id:int, permissions:int, locked:bool, response:int): ## Called when lobby is joined (NOTE: this is called after _on_Lobby_Created())
	
	# Get the Fail Reason
	var msg: String
	match response:
		Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS: msg = "You have Successfuly Joined the Lobby"
		Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST: msg = "This lobby no longer exists."
		Steam.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED: msg = "You don't have permission to join this lobby."
		Steam.CHAT_ROOM_ENTER_RESPONSE_FULL: msg = "The lobby is now full."
		Steam.CHAT_ROOM_ENTER_RESPONSE_ERROR: msg = "Uh... something unexpected happened!"
		Steam.CHAT_ROOM_ENTER_RESPONSE_BANNED: msg = "You are banned from this lobby."
		Steam.CHAT_ROOM_ENTER_RESPONSE_LIMITED: msg = "You cannot join due to having a limited account."
		Steam.CHAT_ROOM_ENTER_RESPONSE_CLAN_DISABLED: msg = "This lobby is locked or disabled."
		Steam.CHAT_ROOM_ENTER_RESPONSE_COMMUNITY_BAN: msg = "This lobby is community locked."
		Steam.CHAT_ROOM_ENTER_RESPONSE_MEMBER_BLOCKED_YOU: msg = "A user in the lobby has blocked you from joining."
		Steam.CHAT_ROOM_ENTER_RESPONSE_YOU_BLOCKED_MEMBER: msg = "A user you have blocked is in the lobby."
	
	# Join: Success
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		
		# Basic
		_reset(lobby_id)
	
	# Run Callable
	_call_current_scene("_on_Lobby_Joined", [response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS, msg])
	
	# Handshake
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		Packet_Class.new("Connection", "handshake", HOST_STEAM_ID)

func _on_Lobby_Join_Requested(lobby_id: int, friend_steam_id: int): ## TODO: Next Version
	
	pass

func _on_Lobby_Match_List(lobby_id_list:Array): ## Returns the available lobbies to join (with the same steamapp_id)
	
	# Get the Lobbies with the Correct Game ID
	const HEADERS:Array = ["name", "current_size", "max_size", "expect_password"]
	var lobby_data:Dictionary = {}
	for lobby_id in lobby_id_list:
		
		# If the Lobby has the Correct Game ID
		if Steam.getLobbyData(lobby_id, "game_id") == GAME_ID:
			
			lobby_data[lobby_id] = [
				Steam.getLobbyData(lobby_id, "name"),
				int(Steam.getNumLobbyMembers(lobby_id)),
				int(Steam.getLobbyMemberLimit(lobby_id)),
				bool(int(Steam.getLobbyData(lobby_id, "expect_password"))),
			]
	
	# Run Callable
	_call_current_scene("_on_Lobby_Match_List", [lobby_data, HEADERS])

func _on_P2P_Session_Request(steam_id:int): ## Called when a user attempt to communicate with another user
	# NOTE: This is called every time another Steam_ID sends a packet to me
	
	# If player has not already been kicked
	if !(steam_id in KICKED): # TODO: good and bad kick standing check
		
		# Accept P2P Session
		Steam.acceptP2PSessionWithUser(steam_id)

func _on_P2P_Session_Connect_Fail(steam_id: int, session_error: int): ## Called during a p2p_session failure
	
	# Print the Msg
	var msg:String
	match session_error:
		0: msg = "[STEAM] WARNING: Session failure with "+str(steam_id)+" [no error given]."
		1: msg = "[STEAM] WARNING: Session failure with "+str(steam_id)+" [target user not running the same game]."
		2: msg = "[STEAM] WARNING: Session failure with "+str(steam_id)+" [local user doesn't own app / game]."
		3: msg = "[STEAM] WARNING: Session failure with "+str(steam_id)+" [target user isn't connected to Steam]."
		4: msg = "[STEAM] WARNING: Session failure with "+str(steam_id)+" [connection timed out]."
		5: msg = "[STEAM] WARNING: Session failure with "+str(steam_id)+" [unused]."
		_: msg = "[STEAM] WARNING: Session failure with "+str(steam_id)+" [unknown error "+str(session_error)+"]."
	print(msg)
	
	# If waiting for handshake
	if waiting_for_handshake:
		leave_lobby(true)

func _on_Lobby_Chat_Updated(lobby_id: int, steam_id: int, making_change_steam_id: int, chat_state: int): ## Called whenever a user joins, leaves, is banned, or etc in a lobby
	
	# Get the user who has made the lobby change
	var change_name: String = Steam.getFriendPersonaName(steam_id)
	
	# Get Status
	var msg: String
	match chat_state:
		1:msg = "[STEAM] " + str(change_name) + " has joined the lobby."
		2:msg = "[STEAM] " + str(change_name) + " has left the lobby."
		8:msg = "[STEAM] " + str(change_name) + " has been kicked from the lobby."
		16:msg = "[STEAM] " + str(change_name) + " has been banned from the lobby."
		_:msg = "[STEAM] " + str(change_name) + " did... something."
	print(msg)
	
	# Joined
	if chat_state == 1:
		
		"""  # TODO: good and bad kick standing check
		# If they are already kicked, kick them again
		if steam_id in KICKED:
			kick_member(steam_id)
		"""
	
	# Left
	else:
		
		# Host Left
		if is_member_host(steam_id):
			leave_lobby()
		
		# Other Left
		else:
			
			# If Member was kicked, make them removed from being kicked
			if steam_id in KICKED:
				KICKED.erase(steam_id) # TODO: Make two types of being kicked, good standing, and bad standing
			
			# Run Callable
			_get_lobby_members()
			_call_current_scene("_on_Lobby_Left", [is_member_me(steam_id) or is_member_host(steam_id), steam_id])

func _on_Lobby_Data_Updated(success, lobby_id:int, key): ## Data of Lobby has been updated
	
	# If (my lobby was updated) AND (time trigger for updating lobbies has elapsed) 
	if lobby_id == LOBBY_ID and allow_lobby_data_update:
		
		# Undo Trigger
		allow_lobby_data_update = false
		time_based_triggers["_on_Lobby_Data_Updated"] = 0
		
		# Update Lobby Data
		_update_lobby_data(false)

func _on_Persona_Change(_steam_id:int, _flag:int): ## Someone's information has changed, Update the Lobby Members

	# Update the player list
	_get_lobby_members()

func _on_Loaded_Avatar(steam_id:int, size:int, buffer: PackedByteArray): ## Steam user's Avatar has been loaded, save it
	
	# End early
	if !(steam_id in MEMBERS):
		return
	
	# Create the image and get the Texture
	var image = Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, buffer)
	var image_texture: ImageTexture = ImageTexture.create_from_image(image)
	
	# Get Avatars
	if !(steam_id in AVATARS):
		AVATARS[steam_id] = {}
		
	# Set the Size
	var avatar_size:Steam.AvatarSizes = {32: Steam.AVATAR_SMALL, 64: Steam.AVATAR_MEDIUM, 184: Steam.AVATAR_LARGE}[size]
	AVATARS[steam_id][avatar_size] = image_texture
	
	# Get Lobby Members
	_get_lobby_members()

## Lobby: Internal
func _get_lobby_members(): ## Called when member data needs to be updated (very important function)
	
	## Not Actual Multiplayer
	if !in_online_lobby():
		MEMBERS = {STEAM_ID: STEAM_NAME}
	
	## Actual Multiplayer
	else:
		
		# Get Members
		MEMBERS.clear()
		for i in range(Steam.getNumLobbyMembers(LOBBY_ID)):
			
			# Get the Steam ID
			var steam_id = Steam.getLobbyMemberByIndex(LOBBY_ID, i)
			
			# If member is not Kicked
			if !(steam_id in KICKED):
				
				# Add to Members
				MEMBERS[steam_id] = Steam.getFriendPersonaName(steam_id) # TODO: Test out AVATARS
	
	## Unused Data Removal
	# Remove Excess Avatars
	for steam_id in AVATARS:
		if !(steam_id in MEMBERS):
			AVATARS.erase(steam_id)
	
	# Remove Excess Trusted
	for steam_id in TRUSTED:
		if !(steam_id in MEMBERS):
			TRUSTED.erase(steam_id)
	
	# Run Callable
	_call_current_scene("_on_Get_Lobby_Members", [])

func _update_lobby_data(for_host:bool): ## Force Update the Lobby Data as host or interpret the results as client
	
	# If Host
	if is_member_online_host():
		
		# Set Data
		if for_host:
			Steam.setLobbyData(LOBBY_ID, "game_id", GAME_ID)
			Steam.setLobbyData(LOBBY_ID, "name", lobby_name)
			Steam.setLobbyData(LOBBY_ID, "expect_password", ["0", "1"][int(lobby_password != "")])
	
	# If Client
	elif !is_member_host():
		
		# Set Data
		if !for_host:
			lobby_name = Steam.getLobbyData(LOBBY_ID, "name")
			lobby_size = int(Steam.getLobbyData(LOBBY_ID, "size"))
	
	# Get Lobby Members
	_get_lobby_members()

## Packets: Sending and Reading
func _send_packet(Packet:Packet_Class, steam_ids:Array, send_scheme:Send_Scheme): ## Send a P2P packet using the Packet_Class guidelines
	
	# Break Packet Apart
	var packet = Packet.get_id() # Order: [callable_id, function, stage, data]
	packet[2] += 1 # Incr Stage
	
	# Get the Compressed Data
	var COMPRESSED_DATA:PackedByteArray = var_to_bytes(packet).compress(send_scheme.compression)
	
	# Send to Each Steam ID
	for steam_id in steam_ids:
		
		# If Sending to Self
		# NOTE: Channel is the Compression Mode
		if is_member_me(steam_id) and send_scheme.allow_self_call:
			
			# Resend the Sender IF the next stage is not the stage + 1
			var sender:int = STEAM_ID
			if callables[packet[0]][packet[1]][packet[2] - 1][CALLABLES.Next_Dif_Stage] != packet[2]:
				sender = Packet.sender
			
			# Read Packet
			_read_packet(packet.duplicate(), sender)
		
		# If Sending to Other
		else: # TODO: Run Check to see if steam_id even exists
			Steam.sendP2PPacket(steam_id, COMPRESSED_DATA, send_scheme.p2p_send, send_scheme.compression)

func _read_RAW_packets(): ## Read Raw P2P Packets One at a time
	
	## Get Each Packet
	# For Each Used Channel
	var read_count:int = 0
	for channel in COMPRESSION.values():
		
		# While Read Count is Still Low
		while read_count < PACKET_READ_LIMIT and Steam.getAvailableP2PPacketSize(channel) > 0:
			
			# If the Packet Exists
			var packet_size:int = Steam.getAvailableP2PPacketSize(channel)
			if packet_size > 0:
				
				## Basic
				var raw_packet_data:Dictionary = Steam.readP2PPacket(packet_size, channel)
				var steam_id:int = raw_packet_data["steam_id_remote"]
				
				# TODO: check if steam_id exists within the lobby
				
				## Check: raw_packet_data["data"] is valid format (is_array of good length AND  is_compression_mode)
				if typeof(raw_packet_data["data"]) != TYPE_PACKED_BYTE_ARRAY:
					_dev_print("0.2.0", raw_packet_data)
					return
				
				## Get the Packet Data
				# Get and Check the Compression
				var compression: FileAccess.CompressionMode = channel # NOTE: Channel indicates the decompression method
				if !(compression in ALLOWED_COMPRESSION):
					_dev_print("0.2.1", COMPRESSION.keys()[COMPRESSION.values().find(compression)])
					return
				
				# Get the Packet
				var packet_data = bytes_to_var(raw_packet_data["data"].decompress_dynamic(-1, compression))
				
				## Check: packet_data is valid format
				if !((typeof(packet_data) == TYPE_ARRAY) and (len(packet_data) == 4)):
					_dev_print("0.2.2", str(COMPRESSION.keys()[channel]) + ", " + str(packet_data) + ", " + str(raw_packet_data["data"]))
					return
				
				# packet Order: callable_id, function, stage, data # NOTE: No Need to Check Data's validity
				elif !((typeof(packet_data[0]) == TYPE_STRING) and (typeof(packet_data[1]) == TYPE_STRING) and (typeof(packet_data[2]) == TYPE_INT) and packet_data[2] > 0): # Also check if Stage is NOT 0 or less
					_dev_print("0.2.3", str(channel) + ", " + str(packet_data))
					return
				
				## Read Packet
				_read_packet(packet_data, steam_id)

func _read_packet(packet:Array, steam_id:int): ## Read P2P Packet using Packet_Class guidelines
	
	# packet Order: callable_id, function, stage, data
	# Arg Order: callable_id, function, sender, data, stage
	Packet_Class.new(packet[0], packet[1], steam_id, packet[3], packet[2])

## Packets: Trust
func _CONTROL_handshake(Packet:Packet_Class): ## Handshake method for actually joining a lobby (requires pre-verification)
	
	## Back and Forth
	# Client
	if Packet.stage == 0:
		
		# Send Handshake
		waiting_for_handshake = true
		
		# Quit if Handshake is not processed
		var current_time:float = 0
		while waiting_for_handshake:
			
			# Total time elapsed
			if current_time >= HANDSHAKE_TRIGGER_TOTAL:
				
				# Leave Lobby # NOTE: This also stops any other handshake calls from getting through, since the user will no longer be recognizing the host in MEMBERS
				leave_lobby(true)
				break
			
			# Send packet
			Packet.send(null)
			
			# Wait and Repeat
			await get_tree().create_timer(HANDSHAKE_TRIGGER_DELTA).timeout
			current_time += HANDSHAKE_TRIGGER_DELTA
	
	# Host
	elif Packet.stage == 1:
		
		# Send Handshake right back
		Packet.send(null)
	
	## Trust Test
	# Client
	elif Packet.stage == 2:
		
		# If still waiting for a handshake
		if waiting_for_handshake:
			waiting_for_handshake = false
			
			# Send response (with the password)
			Packet.send(lobby_password)
	
	# Host
	elif Packet.stage == 3:
		# !(Password answered correctly or password_does_not_exist)
		var password_required:bool = !(_trust_test(Packet.sender, Packet.data) or (lobby_password == ""))
		
		# Send
		Packet.send(password_required)
	
	# Client
	elif Packet.stage == 4:
		
		# Password Required
		if Packet.data:
			_call_current_scene("_on_Received_Trust_Test", [Packet])
		
		# No Password Required
		else:
			Packet.send(lobby_password)
	
	# Host
	elif Packet.stage == 5:
		
		# Passed Test
		if _trust_test(Packet.sender, Packet.data):
			Packet_Class.new("Connection", "trust_update", HOST_STEAM_ID, Packet.sender)
		
		# Failed Test
		else:
			Packet.send(null)
	
	## Failure
	# Client
	elif Packet.stage == 6:
		_call_current_scene("_on_Trust_Test_Results", [false])

func _CONTROL_trust_update(Packet:Packet_Class): ## Update newly trusted members (called after the handshake CONTROL Packet)
	""" Control Update Trusted """
	
	# tell clients who is trusted
	if Packet.stage == 0:
		
		# Add to Approved
		var steam_id:int = Packet.data
		if !(steam_id in APPROVED):
			APPROVED.append(steam_id)
		
		# Send new Trusted
		Packet.send(TRUSTED + [Packet.data]) # TODO: Duplicate? Create an Auto-Duplicate Method?
	
	# clients understand trusted
	elif Packet.stage == 1:
		
		# Basic
		var given_trust:bool = !is_member_trusted() and (STEAM_ID in Packet.data)
		TRUSTED = Packet.data
		
		# Get Lobby Members
		_get_lobby_members()
		
		# Know that Trust has been given
		if given_trust:
			_call_current_scene("_on_Trust_Test_Results", [true])

func _trust_test(steam_id:int, test_lobby_password:String) -> bool: ## Check if Member is Trusted
	""" Trust Test """
	
	_get_lobby_members()
	return (steam_id in APPROVED) or (lobby_password == test_lobby_password) or (lobby_password == "")

## Packets: Change Scene and Kick
func _CONTROL_change_scene(Packet:Packet_Class): ## Changes the Scene
	
	if Packet.stage == 0:
		
		# Kick Untrusted Members
		set_lobby_joinable(false)
		
		# Send the Kicked and the New Scene
		Packet.send([KICKED, Packet.data])
	
	elif Packet.stage == 1:
		
		# Set Kicked and Update Lobby
		KICKED = Packet.data[0]
		_get_lobby_members()
		
		# Load the New Scene
		get_tree().call_deferred("change_scene_to_file", Packet.data[1]) # TODO: Add Check for Valid Scenes

func _CONTROL_kick(Packet:Packet_Class): ## Kicks a player
	
	# Tell members who is kicked
	if Packet.stage == 0:
		Packet.send()
	
	# Know I am kicked
	elif Packet.stage == 1:
		
		# Basic
		var steam_id:int = Packet.data
		
		# I am Kicked
		if is_member_me(steam_id):
			
			# Run Leave Lobby
			leave_lobby()
		
		# Other is Kicked
		else:
			
			# Add Member to Kicked
			if !(steam_id in KICKED):
				KICKED.append(steam_id)
			
			# Remove from Approved
			APPROVED.erase(steam_id)
			
			# Close Connection
			Steam.closeP2PSessionWithUser(steam_id)
			
			# Get Lobby Members
			_get_lobby_members()

## Packets: Clock and Inputs
func _CONTROL_clock(Packet:Packet_Class): ## Syncs the clock and determines the latency between users
	
	## User Send
	if Packet.stage == 0: # null
		Packet.send(Time.get_unix_time_from_system())
	
	## Host Send Back
	elif Packet.stage == 1:
		Packet.send([Packet.data, Time.get_unix_time_from_system()])
	
	## User Process
	elif Packet.stage == 2:
		
		# Basic
		var client_time = Packet.data[0] # 0: Client Sent
		var server_time = Packet.data[1] # 1: Server Sent
		var current_time = Time.get_unix_time_from_system() # 2: Client Recieved
		
		# Continue Loading Latency Array Until it is Saturated, then Clear It
		latency_array.append((current_time - client_time)/2.0)
		if len(latency_array) == LATENCY_PING_AMOUNT:
			
			# Sort and get the midpoint
			latency_array.sort()
			var mid_point = latency_array[len(latency_array)/2]
			
			# Get the Total Latency
			var total_latency = 0.0
			var count = 0.0
			for lat in latency_array:
				
				# Make sure the latency is not too high (in case a packet is lost, which increases latency too much)
				if !(lat > 2*mid_point and lat > 20):
					total_latency += lat
					count += 1
			
			# Get the delta and total latency
			delta_latency = total_latency/count - latency
			latency = total_latency/count
			
			# Clear the latency_array
			latency_array.clear()
			
			# Set the Client Clock
			client_clock = server_time + latency
			
			# Set Latency
			Steam.setLobbyMemberData(LOBBY_ID, "latency", str(int(latency*1000)))

func _process_client_clock(delta:float): ## Processed the Client Clock
	
	# Add the delta to the client clock
	client_clock += int(delta*1000) + delta_latency
	delta_latency = 0
	
	# Increase the Decimal Collector
	decimal_collector += (delta*1000) - int(delta*1000)
	
	# Add on another msec if delta collector is greater than 1
	if decimal_collector >= 1.0:
		decimal_collector -= 1.0
		client_clock += 1

func _CONTROL_inputs(Packet:Packet_Class): ## Controls how inputs are sent and processed
	
	if Packet.stage == 0: # client_send: Initiator
		
		# Get Inputs and Send
		var data = _call_current_scene("_on_Get_Inputs") # Should be a dictionary
		if data != null:
			Packet.send(data)
	
	elif Packet.stage == 1: # host_send: Host
		
		# Send Inputs if Check Passed
		var data = _call_current_scene("_on_Check_Inputs", [Packet.data[0], Packet.sender])
		if data != null:
			Packet.send([Packet.data, Packet.sender])
	
	elif Packet.stage == 2: # client_recieve: Initiator
		
		# Basic
		var data = Packet.data[0]
		var steam_id = Packet.data[1]
		
		# Initialize the Steam_Id
		if !(steam_id in inputs):
			inputs[steam_id] = {}
		
		# Add Input_types
		for input_type in data.keys():
			inputs[steam_id][input_type] = data[input_type]

## Callables
func _get_callable(id:String): ## Get the callable obj associated with a script
	
	# If the id exists
	if id in callable_objs:
		
		# Valid
		if is_instance_valid(callable_objs[id]):
			return callable_objs[id]
		
		# Check Free Callables
		_check_freed_callables()

func _call_current_scene(function:String, args:Array=[]): ## Runs a callable script
	
	# TODO: Check Valid Types
	
	# Get the Current Scene
	var current_scene:Node = get_tree().get_current_scene()
	
	# Scene has not Yet Loaded
	if !is_instance_valid(current_scene):
		return
	
	# Run Function
	if function in current_scene:
		return current_scene.callv(function, args)
	
	# Throw Error
	_dev_print("5.0.0", [current_scene, function])

func _check_freed_callables(): ## Check for free callable objs and remove them
	
	# For each callable_id
	for callable_id in callable_objs.keys():
		
		# If the obj is invalid
		if !is_instance_valid(callable_objs[callable_id]):
			callable_objs.erase(callable_id)
			callables.erase(callable_id)

func _check_valid_types(params, valid_types) -> bool: ## Check if the paramaters specified match the type's for that method 
	## NOTE: Recursive
	
	## End Early
	if valid_types == null:
		return true
	elif typeof(valid_types) != TYPE_ARRAY:
		_dev_print("7.0.0", valid_types)
		return false
	
	## Format Params
	# If (valid_types is an array of an array) AND params is also an array
	if (len(valid_types) == 1) and (valid_types[0] == TYPE_ARRAY) and (typeof(params) == TYPE_ARRAY):
		params = [params]
	
	# Turn Params into an Array
	elif typeof(params) != TYPE_ARRAY:
		params = [params]
	
	## Normal Check
	# Check Length
	if len(params) != len(valid_types):
		return false
	
	# Check Each type's validity
	for i in range(len(valid_types)):
		
		# If (valid_type_can_be_anything) OR (good_type)
		if !(valid_types[i] == null or valid_types[i] == typeof(params[i])):
			return false
	
	return true

""" Dev Testing """
func _dev_print(id, data=null, fatal:bool=true): ## A Dev Tool for Checking for Errors and if Connection is running properly
	""" Do Check """
	
	# Packet_Class Formatting
	if data is Packet_Class:
		
		# Ignore
		if (data.callable_id == "Connection") and (data.function in IGNORE_CONNECTION_PACKETS):
			return false
		
		# Get the Data
		data = [data.callable_id, data.function, data.stage, data.sender, data.data, Time.get_datetime_dict_from_unix_time(data.time_stamp)]
		
		# Steam_ID
		if data[3] in MEMBERS:
			data[3] = MEMBERS[data[3]]
		
		# Reformat the Time Stamp
		data[5] = str(data[5]["hour"]) + ":" + str(data[5]["minute"]) + ":" + str(data[5]["second"])
	
	# Control Details Formatting
	elif data is Control_Details:
		data = data.get_id()
	
	# Send Scheme Formatting
	elif data is Send_Scheme:
		data = data.get_id()
	
	# Print the result
	var result:String = str(id) + [": " + str(data), ""][int(data == null)]
	if fatal:
		printerr(result)
	else:
		print(result)
	
	return true





