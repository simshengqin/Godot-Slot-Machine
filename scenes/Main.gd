extends Node2D

@onready var slot = $SubViewportContainer/SubViewport/SlotMachine
@onready var bridge = $GameBridge

# Store latest snapshot for UI updates
var current_snapshot = {}

func _ready():
	slot.connect("stopped", Callable(self, "_on_slot_machine_stopped"))

	# Initialize game via Python backend
	_init_game()

func _init_game():
	# Start new game with random seed
	var json_str = bridge.new_game(0)
	current_snapshot = JSON.parse_string(json_str)
	print("[Main] Game initialized, seed: ", current_snapshot.get("seed", "unknown"))

	# Give SlotMachine access to bridge (before calling show_preview)
	slot.game_bridge = bridge

	# Start the first round (generates preview)
	json_str = bridge.start_round()
	current_snapshot = JSON.parse_string(json_str)
	print("[Main] Round started")

	# Show preview on the slot machine
	slot.show_preview()

func _on_Roll_button_down():
	if $Roll.text == "Roll":
		slot.start()
		$Roll.text = "Stop"
	else:
		slot.stop()

func _on_slot_machine_stopped():
	$Roll.text = "Roll"

	# Get the snapshot from spin result (SlotMachine stored it)
	current_snapshot = slot.last_snapshot

	# Update UI with latest snapshot
	_update_ui()

	# Result stays visible - preview shown when user inserts first token

func _update_ui():
	# TODO: Update score, tokens, money display from current_snapshot
	if current_snapshot.has("state"):
		var state = current_snapshot.state
		print("[Main] Score: ", state.get("score", 0))
		print("[Main] Tokens: ", state.get("tokens", 0))
		print("[Main] Money: ", state.get("money", 0))
		print("[Main] Pending bet: ", state.get("pending_bet", 0))

# ==================== BETTING ====================

func insert_token():
	"""Insert one token into pending bet. Shows preview on first token."""
	var json_str = bridge.insert_token()
	var prev_bet = current_snapshot.get("state", {}).get("pending_bet", 0)
	current_snapshot = JSON.parse_string(json_str)

	if current_snapshot.has("error"):
		print("[Main] Insert token error: ", current_snapshot.error)
		return

	var new_bet = current_snapshot.get("state", {}).get("pending_bet", 0)
	print("[Main] Bet: ", prev_bet, " -> ", new_bet)

	# Show preview when first token inserted (transition from result to preview)
	if prev_bet == 0 and new_bet > 0:
		slot.show_preview()

func remove_token():
	"""Remove one token from pending bet."""
	var json_str = bridge.remove_token()
	current_snapshot = JSON.parse_string(json_str)

	if current_snapshot.has("error"):
		print("[Main] Remove token error: ", current_snapshot.error)
		return

	print("[Main] Bet now: ", current_snapshot.get("state", {}).get("pending_bet", 0))

# Keyboard shortcuts for betting
func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP, KEY_EQUAL:  # Up arrow or + key
				insert_token()
			KEY_DOWN, KEY_MINUS:  # Down arrow or - key
				remove_token()
