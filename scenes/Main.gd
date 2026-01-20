extends Node2D

@onready var slot = $SubViewportContainer/SubViewport/SlotMachine
@onready var bridge = $GameBridge

# Score overlay (center top)
@onready var score_label = $UI/ScoreOverlay/ScoreLabel

# Pay Table overlay (left side)
@onready var pay_row_0 = $UI/PayTableOverlay/PayRow0
@onready var pay_row_1 = $UI/PayTableOverlay/PayRow1
@onready var pay_row_2 = $UI/PayTableOverlay/PayRow2

# Round overlay (right side)
@onready var round_label = $UI/RoundOverlay/RoundLabel
@onready var quota_label = $UI/RoundOverlay/QuotaLabel
@onready var deadline_label = $UI/RoundOverlay/DeadlineLabel

# Jokers and Tarots (top row)
@onready var jokers_container = $UI/JokersContainer
@onready var tarots_container = $UI/TarotsContainer
@onready var tooltip = $UI/Tooltip
@onready var tooltip_name = $UI/Tooltip/TooltipName
@onready var tooltip_desc = $UI/Tooltip/TooltipDesc

# Bottom Panel - Resources
@onready var tokens_label = $BottomPanel/TokensLabel
@onready var bet_label = $BottomPanel/BetLabel
@onready var money_label = $BottomPanel/MoneyLabel

# Info Panel
@onready var info_panel = $UI/InfoPanel
@onready var info_content = $UI/InfoPanel/InfoContent

# Store latest snapshot for UI updates
var current_snapshot = {}

# Called whenever snapshot changes - refreshes ALL UI
func _on_snapshot_changed():
	_update_ui()
	_update_pay_table()
	_update_jokers_tarots()

func _ready():
	slot.connect("stopped", Callable(self, "_on_slot_machine_stopped"))

	# Initialize game via Python backend
	_init_game()

func _set_snapshot(json_str: String):
	"""Helper to update snapshot and refresh all UI."""
	var parsed = JSON.parse_string(json_str)
	if parsed == null:
		print("[Main] Failed to parse JSON: ", json_str.substr(0, 100))
		return false
	current_snapshot = parsed
	_on_snapshot_changed()
	return true

func _init_game():
	# Start new game with random seed
	var json_str = bridge.new_game(0)
	_set_snapshot(json_str)
	print("[Main] Game initialized, seed: ", current_snapshot.get("seed", "unknown"))

	# Give SlotMachine access to bridge (before calling show_preview)
	slot.game_bridge = bridge

	# Start the first round (generates preview)
	json_str = bridge.start_round()
	_set_snapshot(json_str)
	print("[Main] Round started")

	# Show preview on the slot machine
	slot.show_preview()

func _on_Roll_button_down():
	if $Roll.text == "Roll":
		# Prevent spinning with zero bet
		var state = current_snapshot.get("state", {})
		var pending_bet = int(state.get("pending_bet", 0))
		if pending_bet <= 0:
			print("[Main] Cannot spin with 0 bet!")
			return
		slot.start()
		$Roll.text = "Stop"
	else:
		slot.stop()

func _on_slot_machine_stopped():
	$Roll.text = "Roll"

	# Get the snapshot from spin result (SlotMachine stored it)
	current_snapshot = slot.last_snapshot
	_on_snapshot_changed()  # Refresh all UI

	# Result stays visible - preview shown when user inserts first token

func _update_ui():
	# All data is in "state" object
	if not current_snapshot.has("state"):
		return

	var state = current_snapshot.state

	# Resources (bottom panel)
	var tokens = int(state.get("tokens", 0))
	var money = int(state.get("money", 0))
	var pending_bet = int(state.get("pending_bet", 0))

	tokens_label.text = "Tokens: %d" % tokens
	money_label.text = "Money: $%d" % money
	bet_label.text = "Bet: %d" % pending_bet

	# Score (center top overlay)
	var score = int(state.get("score", 0))
	score_label.text = "SCORE: %06d" % score  # Padded like background

	# Round info (right overlay)
	var round_num = int(state.get("round", 1))
	var quota = int(state.get("quota", 0))
	var deadline = int(state.get("deadline", 1))
	var spins_used = int(state.get("spins_used", 0))

	round_label.text = "Round %d" % round_num
	quota_label.text = "%d" % quota
	deadline_label.text = "Deadline %d | Spins: %d" % [deadline, spins_used]

func _update_pay_table():
	# RULE 4.8: UI just renders what backend decides - no game logic here
	if not current_snapshot.has("state"):
		return

	var state = current_snapshot.state
	if not state.has("game_info"):
		return

	var game_info = state.game_info
	# RULE 4.8: Backend controls pay_table_display (empty = keep previous)
	# RULE 4.5: .get() OK at system boundary (JSON from Python backend)
	var symbols = game_info.get("pay_table_display", [])
	if symbols.size() == 0:
		return  # Backend says keep previous

	# Update top 3 rows (matching background layout)
	var pay_rows = [pay_row_0, pay_row_1, pay_row_2]

	for i in range(3):
		if i < symbols.size():
			var sym = symbols[i]
			var emoji = sym.get("emoji", "?")
			var value = int(sym.get("value", 0))

			# Use pre-formatted modifier from backend (e.g., "+3", "-1", "")
			var modifier = sym.get("modifier", "")

			# Format: emoji  🎲±N  💰value
			var dice_str = ""
			if modifier != "":
				dice_str = "🎲%s" % modifier
			else:
				dice_str = "    "

			# Format value (compact for large numbers)
			var value_str = ""
			if value >= 1000:
				value_str = "%.1fK" % (value / 1000.0)
			else:
				value_str = str(value)

			pay_rows[i].text = "%s  %s  💰%s" % [emoji, dice_str, value_str]
			print("[PayTable] Row %d: %s" % [i, pay_rows[i].text])  # Debug
		else:
			pay_rows[i].text = ""

func _update_jokers_tarots():
	# Clear existing joker buttons
	for child in jokers_container.get_children():
		child.queue_free()

	# Clear existing tarot buttons
	for child in tarots_container.get_children():
		child.queue_free()

	if not current_snapshot.has("state"):
		return

	var state = current_snapshot.state

	# Add joker buttons - jokers are directly in state
	var jokers = state.get("jokers", [])
	for i in range(jokers.size()):
		var joker = jokers[i]
		var btn = Button.new()
		var jname = joker.get("name", "?")
		btn.text = jname[0].to_upper() if jname.length() > 0 else "?"
		btn.custom_minimum_size = Vector2(45, 45)
		btn.add_theme_font_size_override("font_size", 20)
		btn.mouse_entered.connect(_on_joker_hover.bind(joker))
		btn.mouse_exited.connect(_on_item_hover_exit)
		jokers_container.add_child(btn)

	# Add tarot buttons - tarots are directly in state
	var tarots = state.get("tarots", [])
	for i in range(tarots.size()):
		var tarot = tarots[i]
		var btn = Button.new()
		var tname = tarot.get("name", "?")
		btn.text = tname[0].to_upper() if tname.length() > 0 else "?"
		btn.custom_minimum_size = Vector2(45, 45)
		btn.add_theme_font_size_override("font_size", 20)
		btn.mouse_entered.connect(_on_tarot_hover.bind(tarot))
		btn.mouse_exited.connect(_on_item_hover_exit)
		tarots_container.add_child(btn)

func _on_joker_hover(joker: Dictionary):
	tooltip_name.text = joker.get("name", "Unknown Joker")
	tooltip_desc.text = joker.get("description", "No description")
	tooltip.visible = true

func _on_tarot_hover(tarot: Dictionary):
	tooltip_name.text = tarot.get("name", "Unknown Tarot")
	tooltip_desc.text = tarot.get("description", "No description")
	tooltip.visible = true

func _on_item_hover_exit():
	tooltip.visible = false

# ==================== INFO PANEL ====================

func _on_info_button_pressed():
	info_panel.visible = true
	_populate_info_panel()

func _on_info_close_pressed():
	info_panel.visible = false

func _populate_info_panel():
	# Clear existing content
	for child in info_content.get_children():
		child.queue_free()

	if not current_snapshot.has("state"):
		return

	var state = current_snapshot.state

	# Section: SYMBOLS
	var section_label = Label.new()
	section_label.text = "SYMBOLS"
	section_label.add_theme_font_size_override("font_size", 22)
	info_content.add_child(section_label)

	# Header row
	var header = HBoxContainer.new()
	var h1 = Label.new()
	h1.text = "Symbol"
	h1.custom_minimum_size = Vector2(100, 0)
	header.add_child(h1)
	var h2 = Label.new()
	h2.text = "Value"
	h2.custom_minimum_size = Vector2(80, 0)
	header.add_child(h2)
	var h3 = Label.new()
	h3.text = "Prob"
	h3.custom_minimum_size = Vector2(80, 0)
	header.add_child(h3)
	var h4 = Label.new()
	h4.text = "Mod"
	header.add_child(h4)
	info_content.add_child(header)

	# Symbol rows
	if state.has("game_info"):
		var game_info = state.game_info
		var symbols = game_info.get("symbols", [])

		for sym in symbols:
			var row = HBoxContainer.new()

			var emoji_label = Label.new()
			emoji_label.text = sym.get("emoji", "?")
			emoji_label.custom_minimum_size = Vector2(100, 0)
			emoji_label.add_theme_font_size_override("font_size", 18)
			row.add_child(emoji_label)

			var value_label = Label.new()
			value_label.text = str(int(sym.get("value", 0)))
			value_label.custom_minimum_size = Vector2(80, 0)
			value_label.add_theme_font_size_override("font_size", 18)
			row.add_child(value_label)

			var prob_label = Label.new()
			prob_label.text = "%.1f%%" % sym.get("probability", 0)
			prob_label.custom_minimum_size = Vector2(80, 0)
			prob_label.add_theme_font_size_override("font_size", 18)
			row.add_child(prob_label)

			var mod_label = Label.new()
			var modifier = sym.get("modifier", "")
			mod_label.text = modifier if modifier != "" else "-"
			mod_label.add_theme_font_size_override("font_size", 18)
			row.add_child(mod_label)

			info_content.add_child(row)

# ==================== BETTING ====================

func insert_token():
	"""Insert one token into pending bet. Shows preview on first token."""
	var prev_bet = 0
	if current_snapshot.has("state"):
		prev_bet = int(current_snapshot.state.get("pending_bet", 0))

	var json_str = bridge.insert_token()
	if not _set_snapshot(json_str):
		return

	if current_snapshot.has("error"):
		print("[Main] Insert token error: ", current_snapshot.error)
		return

	var new_bet = 0
	if current_snapshot.has("state"):
		new_bet = int(current_snapshot.state.get("pending_bet", 0))

	# Show preview when first token inserted (transition from result to preview)
	if prev_bet == 0 and new_bet > 0:
		slot.show_preview()

func remove_token():
	"""Remove one token from pending bet."""
	var json_str = bridge.remove_token()
	if not _set_snapshot(json_str):
		return

	if current_snapshot.has("error"):
		print("[Main] Remove token error: ", current_snapshot.error)
		return

# Keyboard shortcuts for betting
func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP, KEY_EQUAL:  # Up arrow or + key
				insert_token()
			KEY_DOWN, KEY_MINUS:  # Down arrow or - key
				remove_token()
			KEY_I:  # Toggle info panel
				if info_panel.visible:
					_on_info_close_pressed()
				else:
					_on_info_button_pressed()
