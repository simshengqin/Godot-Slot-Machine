extends Node2D

const SlotTile := preload("res://scenes/SlotTile.tscn")
# Stores the SlotTile's SPIN_UP animation distance
const SPIN_UP_DISTANCE = 100.0
signal stopped

@export var pictures := [ # (Array, String)
	preload("res://sprites/TileIcons/cherry.png"),       # 0
	preload("res://sprites/TileIcons/strawberry.png"),   # 1
	preload("res://sprites/TileIcons/seven.png"),        # 2
	preload("res://sprites/TileIcons/lemon.png"),        # 3
	preload("res://sprites/TileIcons/banana.png"),       # 4
	preload("res://sprites/TileIcons/bell.png"),         # 5
	preload("res://sprites/TileIcons/watermelon.png"),   # 6
	preload("res://sprites/TileIcons/green_apple.png"),  # 7
	preload("res://sprites/TileIcons/clover.png"),       # 8
	preload("res://sprites/TileIcons/unknown.png"),      # 9 - hidden/unrevealed
	preload("res://sprites/TileIcons/rainbow.png"),      # 10 - wild
	# Color placeholders (TODO: add actual images)
	preload("res://sprites/TileIcons/unknown.png"),      # 11 - red placeholder 🔴
	preload("res://sprites/TileIcons/unknown.png"),      # 12 - yellow placeholder 🟡
	preload("res://sprites/TileIcons/unknown.png"),      # 13 - green placeholder 🟢
	#preload("res://sprites/TileIcons/bat.png"),
	#preload("res://sprites/TileIcons/cactus.png"),
	#preload("res://sprites/TileIcons/card-exchange.png"),
	#preload("res://sprites/TileIcons/card-joker.png"),
	#preload("res://sprites/TileIcons/chess-knight.png"),
	#preload("res://sprites/TileIcons/coffee-cup.png"),
	#preload("res://sprites/TileIcons/companion-cube.png"),
	#preload("res://sprites/TileIcons/cycling.png"),
	#preload("res://sprites/TileIcons/dandelion-flower.png"),
	#preload("res://sprites/TileIcons/eight-ball.png"),
	#preload("res://sprites/TileIcons/hummingbird.png"),
	#preload("res://sprites/TileIcons/kiwi-bird.png"),
	#preload("res://sprites/TileIcons/owl.png"),
	#preload("res://sprites/TileIcons/pc.png"),
	#preload("res://sprites/TileIcons/pie-slice.png"),
	#preload("res://sprites/TileIcons/plastic-duck.png"),
	#preload("res://sprites/TileIcons/raven.png"),
	#preload("res://sprites/TileIcons/rolling-dices.png"),
	#preload("res://sprites/TileIcons/skull-crossed-bones.png"),
	#preload("res://sprites/TileIcons/super-mushroom.png"),
	#preload("res://sprites/TileIcons/tic-tac-toe.png"),
	#preload("res://sprites/TileIcons/trojan-horse.png"),
	#preload("res://sprites/TileIcons/udder.png")
]

@export var reels := 5 # (int,1,20)
@export var tiles_per_reel := 3 # (int,1,20)
# Defines how long the reels are spinning
@export var runtime := 1.0 # (float,0,10)
# Defines how fast the reels are spinning
@export var speed := 5.0 # (float,0.1,10)
# Defines the start delay between each reel
@export var reel_delay := 0.2 # (float,0,2)

# Adjusts tile size to viewport
@onready var size := get_viewport_rect().size
@onready var tile_size := size / Vector2(reels, tiles_per_reel)
# Normalizes the speed for consistancy independent of the number of tiles
@onready var speed_norm := speed * tiles_per_reel
# Add additional tiles outside the viewport of each reel for smooth animation
# Add it twice for above and below the grid
@onready var extra_tiles := int(ceil(SPIN_UP_DISTANCE / tile_size.y) * 2)

# Stores the actual number of tiles
@onready var rows := tiles_per_reel + extra_tiles

enum State {OFF, ON, STOPPED}
var state = State.OFF
var result := {}

# Reference to GameBridge (set by Main.gd)
var game_bridge = null
# Latest snapshot from Python backend
var last_snapshot = {}

# Stores SlotTile instances
var tiles := []
# Stores the top left corner of each grid cell
var grid_pos := []

# 1/speed*runtime*reels times
# Stores the desured number of movements per reel
@onready var expected_runs :int = int(runtime * speed_norm)
# Stores the current number of movements per reel
var tiles_moved_per_reel := []
# Stores how many tiles have finished per reel
var tiles_stopped_per_reel := []
# When force stopped, stores the current number of movements
var runs_stopped := 0
# Store the runs independent of how they are achieved
var total_runs : int

func _ready():
	# Initializes grid of tiles
	for col in reels:
		grid_pos.append([])
		tiles_moved_per_reel.append(0)
		tiles_stopped_per_reel.append(0)
		for row in range(rows):
			# Position extra tiles above and below the viewport
			grid_pos[col].append(Vector2(col, row-0.5*extra_tiles) * tile_size)
			_add_tile(col, row)

# Stores and initializes a new tile at the given grid cell
func _add_tile(col :int, row :int) -> void:
	tiles.append(SlotTile.instantiate())
	var tile := get_tile(col, row)
	add_child(tile)
	tile.move_completed.connect(_on_tile_moved.bind(tile))
	tile.set_size(tile_size)
	tile.set_texture(_randomTexture())
	tile.position = grid_pos[col][row]
	tile.set_velocity(speed_norm)

# Returns the tile at the given grid cell
func get_tile(col :int, row :int) -> SlotTile:
	return tiles[(col * rows) + row]

func start() -> void:
	# Only start if it is not running yet
	if state == State.OFF:
		state = State.ON
		total_runs = expected_runs
		# Reset stopped counters
		for i in range(reels):
			tiles_stopped_per_reel[i] = 0
		# Ask server for result
		_get_result()
		# Spins all reels
		for reel in reels:
			_spin_reel(reel)
			# Spins the next reel a little bit later
			if reel_delay > 0:
				await get_tree().create_timer(reel_delay).timeout

# Force the machine to stop before runtime ends
func stop():
	# Tells the machine to stop at the next possible moment
	state = State.STOPPED
	# Store the current runs of the first reel
	# Add runs to update the tiles to the result images
	runs_stopped = current_runs()
	total_runs = runs_stopped + tiles_per_reel + 1

# Is called when the animation stops
func _stop() -> void:
	for reel in reels:
		tiles_moved_per_reel[reel] = 0
		tiles_stopped_per_reel[reel] = 0
	state = State.OFF
	emit_signal("stopped")

# Starts moving all tiles of the given reel
func _spin_reel(reel :int) -> void:
	# Moves each tile of the reel
	for row in rows:
		_move_tile(get_tile(reel, row))

func _move_tile(tile :SlotTile) -> void:
	# Plays a spin up animation
	tile.spin_up()
	await tile.get_node("Animations").animation_finished
	# Moves reel by one tile at a time to avoid artifacts when going too fast
	tile.move_by(Vector2(0, tile_size.y))
	# The reel will move further through the _on_tile_moved function

func _on_tile_moved(tile: SlotTile) -> void:
	# Calculates the reel that the tile is on (use round to avoid floating point issues)
	var reel := int(round(tile.position.x / tile_size.x))

	# Count how many tiles moved per reel
	tiles_moved_per_reel[reel] += 1
	var reel_runs := current_runs(reel)

	# If tile moved out of the viewport, move it to the invisible row at the top
	if (tile.position.y > grid_pos[0][-1].y):
		tile.position.y = grid_pos[0][0].y
	# Set texture based on tile's visible row position
	var current_idx = total_runs - reel_runs
	if (current_idx < tiles_per_reel):
		# Use the tile's visible row position to determine which result texture to use
		var visible_row := int(round(tile.position.y / tile_size.y))
		if visible_row >= 0 and visible_row < tiles_per_reel:
			var result_texture = pictures[result.tiles[reel][visible_row]]
			tile.set_texture(result_texture)
		else:
			tile.set_texture(_randomTexture())
	else:
		tile.set_texture(_randomTexture())

	# Stop moving after the reel ran expected_runs times
	# Or if the player stopped it
	if (state != State.OFF && reel_runs != total_runs):
		tile.move_by(Vector2(0, tile_size.y))
	else: # stop moving this reel
		tile.spin_down()
		tiles_stopped_per_reel[reel] += 1
		# When ALL tiles in the last reel have stopped, machine is stopped
		if reel == reels - 1 and tiles_stopped_per_reel[reel] >= rows:
			_stop()

# Divide it by the number of tiles to know how often the whole reel moved
# Since this function is called by each tile, the number changes (e.g. for 6 tiles: 1/6, 2/6, ...)
# We use ceil, so that both 1/7, as well as 7/7 return that the reel ran 1 time
func current_runs(reel := 0) -> int:
	return int(ceil(float(tiles_moved_per_reel[reel]) / rows))

func _randomTexture() -> Texture2D:
	return pictures[randi() % pictures.size()]

func _get_result() -> void:
	if game_bridge:
		# Get result from Python backend
		var json_str = game_bridge.spin()
		last_snapshot = JSON.parse_string(json_str)

		if last_snapshot.has("error"):
			print("[SlotMachine] Error: ", last_snapshot.error)
			# Fallback to random
			_get_random_result()
		elif last_snapshot.has("grid_indices"):
			# Use grid from Python backend
			result = { "tiles": last_snapshot.grid_indices }
			print("[SlotMachine] Got result from Python backend")
		else:
			print("[SlotMachine] No grid_indices in snapshot, using random")
			_get_random_result()
	else:
		print("[SlotMachine] No bridge, using random result")
		_get_random_result()

func _get_random_result() -> void:
	# Fallback: generate random result (original behavior)
	var tiles_array := []
	for reel in reels:
		var reel_tiles := []
		for i in tiles_per_reel:
			reel_tiles.append(randi() % pictures.size())
		tiles_array.append(reel_tiles)
	result = { "tiles": tiles_array }

# Show preview grid (before spin) - displays locked/revealed symbols
func show_preview() -> void:
	if not game_bridge:
		print("[SlotMachine] No bridge for preview")
		return

	# Get current snapshot with preview_indices
	var json_str = game_bridge.get_snapshot()
	var snapshot = JSON.parse_string(json_str)

	if snapshot.has("error"):
		print("[SlotMachine] Preview error: ", snapshot.error)
		return

	if not snapshot.has("preview_indices"):
		print("[SlotMachine] No preview_indices in snapshot")
		return

	var preview = snapshot.preview_indices  # [col][row] format
	last_snapshot = snapshot

	# Set each visible tile to show preview
	# Visible rows start at extra_tiles/2
	var visible_start = int(extra_tiles / 2)

	for col in range(min(reels, preview.size())):
		var col_data = preview[col]
		for row in range(min(tiles_per_reel, col_data.size())):
			var tile_row = visible_start + row
			var tile = get_tile(col, tile_row)
			var pic_index = col_data[row]
			if pic_index >= 0 and pic_index < pictures.size():
				tile.set_texture(pictures[pic_index])
			else:
				tile.set_texture(pictures[9])  # unknown

	print("[SlotMachine] Preview shown")
