# NEVERWORLD — Architecture

> This document describes how systems connect and talk to each other.
> It is not a design document — see GDD_V2.md for that.
> Update this as systems are built and flows are confirmed.

---

## Data Layer

Game data lives in Resources (`.tres` files). Nodes read from resources — they do not own the data.

### Character Data Hierarchy

```
CharacterData          ← identity only (name, ID, portrait, sprite)
  ├── CombatData       ← adds base stats (HP, MP, AtkPhys, etc.)
  │     ├── PlayerData ← adds growth table, allowed gear
  │     └── EnemyData  ← (future) adds loot table, AI profile, resistances
  └── NPCData          ← (future) adds dialogue, quest flags
```

### Supporting Resources

```
GrowthTable            ← array of GrowthEntry rows (one per level above 1)
GrowthEntry            ← per-level stat deltas for one level-up
CharacterSaveData      ← mutable per-character state (see Save Layer)
EquipmentType          ← flags enum for weapon/armor type constraints
```

---

## Save Layer

One `SaveFile` resource holds everything that persists to disk.

```
SaveFile
  ├── party_data: PartyData          ← active party slots, shared RESONANCE
  ├── character_saves: Dictionary    ← character_id → CharacterSaveData
  └── (future) world state, flags, etc.
```

### CharacterSaveData

Holds everything that changes over a playthrough for one character:

- `cur_hp`, `cur_mp` — current resources
- `character_level`, `cur_xp` — progression
- `equipped_weapon_id`, `equipped_armor_id`, `equipped_gear_ids` — gear slots
- `equipped_mnemonic_ids` — 4 mnemonic slots
- `choice_bonuses` — accumulated stat picks (Dictionary: stat → bonus)
- `stat_last_chosen_level` — cooldown tracking for choice growth

### Creating a new CharacterSaveData

When a character joins the party (game start or mid-story), a static factory function seeds a fresh `CharacterSaveData` from the character's `PlayerData` template:

```
CharacterSaveData.create_for(player_data: PlayerData) -> CharacterSaveData
```

---

## Stat Computation

Final stats are never stored — always computed on demand from two sources:

```
PlayerData (template)     +     CharacterSaveData (save state)
  └── base stats                  └── level, choice bonuses, gear IDs
  └── growth table
          ↓
     StatCalculator (static utility)
          ↓
     final stat block
```

`StatCalculator` is a pure utility — static functions, no state, no node. Called by UI to display stats, called by `CombatStart` state to initialize combat actors.

---

## Overworld

```
overworld_character.tscn
  ├── PlayerInputComponent / NPCBehaviorComponent   ← reads input or AI, emits direction_changed / run_toggled / interact_pressed
  ├── MovementComponent      ← listens to direction_changed, run_toggled — moves the character
  └── VisualComponent        ← listens to direction_changed, run_toggled — drives AnimatedSprite3D
```

- `overworld_character.gd` wires `controller` on both `MovementComponent` and `VisualComponent` at `_ready()`
- Also passes `character_data` to `VisualComponent` so it can assign the correct `SpriteFrames` to `AnimatedSprite3D`
- For NPCs, `PlayerInputComponent` is swapped for `NPCBehaviorComponent` — other components don't notice
- Camera is fixed — input is rotated 45° in `MovementComponent` to match isometric orientation

## Combat Characters

Overworld and combat are separate representations of the same character data. They share components where it makes sense but are distinct scenes with distinct purposes.

```
combat_character.tscn
  ├── VisualComponent        ← reused from overworld — same sprite, same animation logic
  ├── CombatInputComponent   ← waits for player menu input (replaces movement input)
  └── CombatComponent        ← owns runtime combat state: cur_hp, cur_mp, cur_ap, tokens, is_downed
```

- `VisualComponent` is the same component as overworld — reads `character_data.character_sprite`, drives `AnimatedSprite3D`
- `CombatComponent` is combat-only — handles HP/MP/AP tracking, token list, downed state
- All `combat_character` instances are identical in structure — what differs is the `CharacterData` resource attached
- Player instances seed from `PlayerData` + `CharacterSaveData` via `StatCalculator`
- Enemy instances seed from `EnemyData` directly — no save data involved

---

## Combat

Combat runs in a **dedicated battle scene** — separate from the overworld. The overworld freezes, the battle scene loads, the fight resolves, the player returns.

### Two FSMs in parallel

```
Logic FSM    ←→ (event bus) ←→    UI FSM
```

- Logic FSM owns game state — turn order, damage resolution, resource mutation
- UI FSM owns presentation — animations, floating numbers, bar updates
- They never touch each other directly — all communication through `CombatEvents` bus
- Logic FSM pauses at checkpoints and waits for `PresentationReady` from UI FSM

### Combat Actors

See **Combat Characters** section above. `combat_character.tscn` is the combat actor — same scene for players and enemies, different `CharacterData` resource attached to each.

### Combat Initialization Flow

```
CombatStart state
  ├── for each party member: pull PlayerData + CharacterSaveData → StatCalculator → spawn CombatActor
  ├── for each enemy: pull EnemyData → spawn CombatActor
  └── emit CombatStarted → UI FSM takes over presentation
```

---

## Event Buses

Cross-system communication uses domain-specific autoload event buses — signal declarations only, no logic.

| Bus | Domain |
|-----|--------|
| `CombatEvents` | Combat lifecycle signals |

Rules:
- Cache bus references in `_ready()`
- Always disconnect in `_exit_tree()`
- Use direct signals for parent↔child within the same scene
- Split buses by domain — never one mega-bus
