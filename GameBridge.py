"""
GameBridge - py4godot bridge between Godot and Python backend.

This file lives in the Godot project and imports the twin-hands backend.
It exposes GameManager functionality as a Godot Node.

Usage in Godot:
	1. Add GameBridge node to scene
	2. Call methods: $GameBridge.new_game(), $GameBridge.spin(), etc.
	3. Returns JSON strings - parse with JSON.parse_string()
"""

import sys
import json
from pathlib import Path

# Add twin-hands to Python path
# TODO: Update this path for production/distribution
TWIN_HANDS_PATH = "C:/Users/User/Documents/GitHub/twin-hands"
if TWIN_HANDS_PATH not in sys.path:
	sys.path.insert(0, TWIN_HANDS_PATH)

from py4godot.classes import gdclass
from py4godot.classes.Node import Node

# Use offline cache for fast startup (no network calls)
from src.utils.data.game_data_source import CacheFileDataSource
from src.utils.data.game_data_registry import GameDataRegistry

# Set cache path - try multiple locations for dev and export
CACHE_PATH = None
for path in [
	Path(__file__).parent / "cache",  # Next to GameBridge.py (works in export)
	Path("cache"),  # Relative to cwd
	Path("C:/Users/User/Documents/GitHub/Godot-Slot-Machine/cache"),  # Dev fallback
]:
	if path.exists():
		CACHE_PATH = path
		break

if CACHE_PATH:
	GameDataRegistry.set_data_source(CacheFileDataSource(str(CACHE_PATH)))
	print("[GameBridge] USING OFFLINE CACHE (fast)")
else:
	print("[GameBridge] WARNING: Cache not found, using Google Sheets (SLOW!)")

# Import backend (after setting data source)
from src.managers.system.game_manager import GameManager
from src.resources.poker_grid_config import PokerGridConfig
from src.api.game_adapter import build_snapshot


# Symbol name (Python) -> Picture index (Godot)
# Must match the order in SlotMachine.gd pictures array
SYMBOL_TO_INDEX = {
	"cherry": 0,
	"strawberry": 1,
	"seven": 2,
	"lemon": 3,
	"banana": 4,
	"bell": 5,
	"watermelon": 6,
	"green_apple": 7,
	"clover": 8,
	"unknown": 9,      # Null/placeholder in preview
	"rainbow": 10,     # Wild symbol
}

# Reverse mapping for debugging
INDEX_TO_SYMBOL = {v: k for k, v in SYMBOL_TO_INDEX.items()}


@gdclass
class GameBridge(Node):
	"""
	Bridge node that wraps the Python GameManager for Godot.

	All methods return JSON strings for safe data transfer.
	Parse in GDScript with: JSON.parse_string(result)
	"""

	def _ready(self):
		"""Called when node enters scene tree."""
		self.game = None
		self.pending_bet = 0
		print("[GameBridge] Ready")

	# ==================== GAME LIFECYCLE ====================

	def new_game(self, seed: int = 0):
		"""
		Start a new game.

		Args:
			seed: RNG seed (0 = random)

		Returns:
			JSON string with game snapshot
		"""
		config = PokerGridConfig()
		self.game = GameManager(config, seed=seed if seed != 0 else None)
		self.pending_bet = 0

		snapshot = build_snapshot(self.game, pending_bet=0)
		snapshot["seed"] = self.game.rng.seed
		return json.dumps(snapshot)

	def start_round(self):
		"""Start a new round. Returns JSON snapshot."""
		if not self.game:
			return json.dumps({"error": "no_game"})

		self.game.start_round()
		self.pending_bet = 0
		return json.dumps(build_snapshot(self.game, pending_bet=0))

	def end_round(self):
		"""End current round. Returns JSON snapshot."""
		if not self.game:
			return json.dumps({"error": "no_game"})

		self.game.end_round()
		self.pending_bet = 0
		return json.dumps(build_snapshot(self.game, pending_bet=0))

	# ==================== CORE LOOP ====================

	def insert_token(self):
		"""
		Insert one token into pending bet.
		Returns JSON snapshot.
		"""
		if not self.game:
			return json.dumps({"error": "no_game"})

		max_bet = self.game.state_manager.get_resource_stat("max_bet")
		effective_tokens = self.game.state.tokens - self.pending_bet

		if self.pending_bet >= max_bet:
			snapshot = build_snapshot(self.game, pending_bet=self.pending_bet)
			snapshot["error"] = "max_bet_reached"
			return json.dumps(snapshot)

		if effective_tokens <= 0:
			snapshot = build_snapshot(self.game, pending_bet=self.pending_bet)
			snapshot["error"] = "no_tokens"
			return json.dumps(snapshot)

		self.pending_bet += 1
		return json.dumps(build_snapshot(self.game, pending_bet=self.pending_bet))

	def remove_token(self):
		"""
		Remove one token from pending bet.
		Returns JSON snapshot.
		"""
		if not self.game:
			return json.dumps({"error": "no_game"})

		if self.pending_bet <= 0:
			snapshot = build_snapshot(self.game, pending_bet=self.pending_bet)
			snapshot["error"] = "no_bet_to_remove"
			return json.dumps(snapshot)

		self.pending_bet -= 1
		return json.dumps(build_snapshot(self.game, pending_bet=self.pending_bet))

	def spin(self):
		"""
		Execute spin with pending bet.
		Returns JSON snapshot with scoring data for animation.
		"""
		if not self.game:
			return json.dumps({"error": "no_game"})

		# Place pending bet
		if self.pending_bet > 0:
			result = self.game.place_bet(self.pending_bet)
			if not result.get("success"):
				snapshot = build_snapshot(self.game, pending_bet=self.pending_bet)
				snapshot["error"] = result.get("error", "bet_failed")
				return json.dumps(snapshot)

		# Execute spin
		scoring_result = self.game.spin()
		self.pending_bet = 0

		snapshot = build_snapshot(self.game, scoring_result=scoring_result, pending_bet=0)

		# Add grid as indices for Godot (for slot animation)
		snapshot["grid_indices"] = self._grid_to_indices()

		return json.dumps(snapshot)

	def get_snapshot(self):
		"""Get current game state as JSON snapshot."""
		if not self.game:
			return json.dumps({"error": "no_game"})

		snapshot = build_snapshot(self.game, pending_bet=self.pending_bet)
		snapshot["grid_indices"] = self._grid_to_indices()
		return json.dumps(snapshot)

	# ==================== SHOP ====================

	def enter_shop(self):
		"""Enter shop phase. Returns JSON snapshot."""
		if not self.game:
			return json.dumps({"error": "no_game"})

		self.game.enter_shop()
		return json.dumps(build_snapshot(self.game, pending_bet=0))

	def leave_shop(self):
		"""Leave shop phase. Returns JSON snapshot."""
		if not self.game:
			return json.dumps({"error": "no_game"})

		self.game.leave_shop()
		return json.dumps(build_snapshot(self.game, pending_bet=0))

	def buy_offer(self, index: int):
		"""Buy shop offer at index. Returns JSON snapshot."""
		if not self.game:
			return json.dumps({"error": "no_game"})

		result = self.game.buy_face_up_offer(index)
		snapshot = build_snapshot(self.game, pending_bet=0)
		if not result.get("success"):
			snapshot["error"] = result.get("error_key", "buy_failed")
		return json.dumps(snapshot)

	def open_pack(self, index: int):
		"""Open pack at index. Returns JSON snapshot."""
		if not self.game:
			return json.dumps({"error": "no_game"})

		result = self.game.open_pack(index)
		snapshot = build_snapshot(self.game, pending_bet=0)
		if not result.get("success"):
			snapshot["error"] = result.get("error", "pack_failed")
		return json.dumps(snapshot)

	def pick_from_pack(self, index: int):
		"""Pick item from open pack. Returns JSON snapshot."""
		if not self.game:
			return json.dumps({"error": "no_game"})

		result = self.game.pick_pack_item(index)
		snapshot = build_snapshot(self.game, pending_bet=0)
		if not result.get("success"):
			snapshot["error"] = result.get("error", "pick_failed")
		return json.dumps(snapshot)

	def skip_pack(self):
		"""Skip remaining pack picks. Returns JSON snapshot."""
		if not self.game:
			return json.dumps({"error": "no_game"})

		self.game.skip_pack()
		return json.dumps(build_snapshot(self.game, pending_bet=0))

	def refresh_shop(self):
		"""Refresh shop offers. Returns JSON snapshot."""
		if not self.game:
			return json.dumps({"error": "no_game"})

		result = self.game.refresh_shop()
		snapshot = build_snapshot(self.game, pending_bet=0)
		if not result.get("success"):
			snapshot["error"] = result.get("error", "refresh_failed")
		return json.dumps(snapshot)

	# ==================== HELPERS ====================

	def _grid_to_indices(self):
		"""
		Convert grid symbols to Godot picture indices.
		Returns 2D array [col][row] matching SlotMachine.gd format.
		"""
		if not self.game or not self.game.state.grid:
			return []

		# Grid is [row][col] in Python, SlotMachine wants [col][row]
		rows = len(self.game.state.grid)
		cols = len(self.game.state.grid[0]) if rows > 0 else 0

		result = []
		for col in range(cols):
			col_tiles = []
			for row in range(rows):
				cell = self.game.state.grid[row][col]
				if cell is None:
					col_tiles.append(9)  # Default to unknown (question mark)
				else:
					symbol_name = cell.name if hasattr(cell, 'name') else str(cell)
					col_tiles.append(SYMBOL_TO_INDEX.get(symbol_name, 9))
			result.append(col_tiles)

		return result

	def get_symbol_index(self, symbol_name: str):
		"""Get Godot picture index for a symbol name."""
		return SYMBOL_TO_INDEX.get(symbol_name, 0)

	def get_symbol_name(self, index: int):
		"""Get symbol name for a Godot picture index."""
		return INDEX_TO_SYMBOL.get(index, "cherry")
