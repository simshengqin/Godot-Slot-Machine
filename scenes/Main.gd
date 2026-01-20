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

	# Start the first round
	json_str = bridge.start_round()
	current_snapshot = JSON.parse_string(json_str)
	print("[Main] Round started")

	# Give SlotMachine access to bridge
	slot.game_bridge = bridge

func _on_Roll_button_down():
	if $Roll.text == "Roll":
		slot.start()
		$Roll.text = "Stop"
	else:
		slot.stop()

func _on_slot_machine_stopped():
	$Roll.text = "Roll"

	# Update UI with latest snapshot
	_update_ui()

func _update_ui():
	# TODO: Update score, tokens, money display
	if current_snapshot.has("state"):
		var state = current_snapshot.state
		print("[Main] Score: ", state.get("score", 0))
		print("[Main] Tokens: ", state.get("tokens", 0))
		print("[Main] Money: ", state.get("money", 0))
