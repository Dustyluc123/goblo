class_name GameConfig
extends RefCounted
## Números do jogo num lugar só. O raio do planeta e a grade vêm do servidor
## (server/internal/world/world.go, DefaultConfig); aqui ficam os do cliente.

# --- Personagem -----------------------------------------------------------------------------
## Velocidade andando (unidades/s). SP → Pacaraima (~549 u) leva ~1 min 50 s andando.
const WALK_SPEED := 5.0
## Multiplicador com Shift. Correndo, SP → Pacaraima leva ~55 s.
const RUN_MULTIPLIER := 2.0
## Gravidade radial (unidades/s²).
const GRAVITY := 25.0
## Altura máxima do pulo (unidades). Sobe o degrau de colina (0,6), não um penhasco de montanha (1,6).
const JUMP_HEIGHT := 1.3
## Degraus até esta altura são subidos andando, sem pular (ex.: praia → campo).
const STEP_HEIGHT := 0.4
## Tempo depois de sair do chão em que ainda dá para pular.
const COYOTE_TIME := 0.12
## Tempo em que um Espaço apertado antes de pousar ainda vale.
const JUMP_BUFFER := 0.15

# --- Câmera ---------------------------------------------------------------------------------
const CAMERA_MIN_DISTANCE := 3.5
## Distância máxima acima da superfície, em raios do planeta (1,65 × 1000 = 1650).
const CAMERA_MAX_DISTANCE_RADII := 1.65
