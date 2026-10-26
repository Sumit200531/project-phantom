class_name GameConst
## Shared constants: physics layers, render layers, team colours and tuning values.

# --- Physics layers (bit values) ---
const LAYER_WORLD := 1            # static level geometry, props
const LAYER_UNITS := 2            # character bodies (player + bots)
const LAYER_HITBOX := 4           # head/torso/leg hit areas
const LAYER_BARRIER_T0 := 8       # energy barrier owned by team 0 (blocks team 1 bullets)
const LAYER_BARRIER_T1 := 16      # energy barrier owned by team 1 (blocks team 0 bullets)
const LAYER_SPAWN_WALL := 32      # spawn barriers during the preparation phase
const LAYER_DEVICE := 64          # dropped objective device

const UNIT_MOVE_MASK := LAYER_WORLD | LAYER_UNITS | LAYER_SPAWN_WALL

# --- Render layers ---
const VIS_WORLD := 1
const VIS_VIEWMODEL := 2          # first-person arms/weapon, drawn by the overlay camera
const VIS_WORLD_ONLY_MASK := 0xFFFFF & ~2

# --- Teams ---
const TEAM_A := 0                 # the human player's team
const TEAM_B := 1

const COLOR_ALLY := Color(0.2, 0.86, 0.8)
const COLOR_ENEMY := Color(1.0, 0.36, 0.26)
const COLOR_AMBER := Color(1.0, 0.71, 0.28)
const COLOR_CYAN := Color(0.33, 0.9, 1.0)
const COLOR_GRAPHITE := Color(0.06, 0.075, 0.09)
const COLOR_TEXT := Color(0.93, 0.95, 0.96)
const COLOR_DIM := Color(0.6, 0.66, 0.7)

# --- Match tuning ---
const PREP_TIME := 12.0
const ROUND_TIME := 105.0
const DEVICE_TIME := 40.0
const PLANT_TIME := 4.0
const DEFUSE_TIME := 7.0
const ROUND_END_TIME := 5.5
const TEAM_SIZE := 5
const DEVICE_BLAST_RADIUS := 14.0

static func team_color(team: int, viewer_team: int) -> Color:
	return COLOR_ALLY if team == viewer_team else COLOR_ENEMY

static func barrier_layer(team: int) -> int:
	return LAYER_BARRIER_T0 if team == 0 else LAYER_BARRIER_T1

## Bullet mask for a shooter on `team`: world + hitboxes + the OTHER team's barriers.
static func bullet_mask(team: int) -> int:
	return LAYER_WORLD | LAYER_HITBOX | barrier_layer(1 - team)
