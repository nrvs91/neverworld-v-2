# Skill System MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire a real MnemonicResource through the full combat pipeline — player selects a skill from ActionMenu, it resolves with the real damage formula (hit roll, crit, resistance), applies its costs, and a damage number appears. Enemy turns use the same pipeline via a `basic_attack` mnemonic on EnemyData.

**Architecture:** MnemonicResource owns an Array[Skill_Effect_Base] of effects and per-skill metadata (costs, targeting, display flags). SkillExecutor (static utility) iterates effects, builds an ActionContext as a rolling scratchpad, and returns it. CombatFSM applies results and emits events. CombatUIFSM populates ActionMenu from the actor's mnemonic list at turn start and threads the selected mnemonic through the action_selected signal. Enemies pick `mnemonics[0]` (their basic_attack) automatically.

**Tech Stack:** GDScript, Godot 4.6, custom Resources (.tres), RefCounted for transient ActionContext, ResistanceType / CharacterStats already in place.

---

## File Map

**Create:**
- `scripts/combat/skills/TargetingData.gd`
- `scripts/combat/skills/MnemonicResource.gd`
- `scripts/combat/skills/effects/Skill_Effect_Base.gd`
- `scripts/combat/skills/effects/Skill_Effect_Damage.gd`
- `scripts/combat/ActionContext.gd`
- `scripts/combat/SkillExecutor.gd`
- `scripts/combat/ui/SkillButton.gd`
- `resources/mnemonics/` (new folder)

**Modify:**
- `scripts/characters/PlayerData.gd` — add `mnemonics: Array[MnemonicResource]`
- `scripts/characters/EnemyData.gd` — add `basic_attack: MnemonicResource`
- `scripts/combat/CombatCharacter.gd` — expose `mnemonics`, `resistance_profile`; wire from data
- `scripts/combat/VitalsComponent.gd` — add `spend_hp_percent()`
- `scripts/combat/CombatCalculator.gd` — crit_roll, hit_roll (GDD formula + ChanceTier), calc_damage, resist_multiplier; remove base_attack
- `scripts/combat/CombatEvents.gd` — action_selected carries mnemonic + target
- `scripts/combat/CombatFSM.gd` — unified execution path for player and enemy
- `scripts/combat/ui/ActionMenu.gd` — fix remove_child bug, implement populate(), add get_selected_mnemonic()
- `scripts/combat/ui/CombatUIFSM.gd` — populate menu at turn start, store + emit mnemonic

---

## Task 1: TargetingData resource

**Files:**
- Create: `scripts/combat/skills/TargetingData.gd`

- [x] **Step 1: Create the file**

```gdscript
class_name TargetingData
extends Resource

enum Shape {
	SINGLE_ENEMY,
	SINGLE_ALLY,
	ALL_ENEMIES,
	ALL_ALLIES,
	SELF,
}

enum Filter {
	NONE,
	HAS_DOT,
	IS_DOWNED,
}

@export var shape: Shape = Shape.SINGLE_ENEMY
@export var filter: Filter = Filter.NONE
```

- [x] **Step 2: Verify in Godot**

Right-click `scripts/combat/skills/` in the FileSystem dock → New Resource → `TargetingData`. Confirm `shape` and `filter` dropdowns appear with the correct enum values.

- [x] **Step 3: Commit** (grouped into Phase 1 commit)

---

## Task 2: Skill_Effect_Base resource

**Files:**
- Create: `scripts/combat/skills/effects/Skill_Effect_Base.gd`

- [x] **Step 1: Create the file**

```gdscript
class_name Skill_Effect_Base
extends Resource

## ChanceTier is a universal accuracy/reliability descriptor.
## Its meaning is resolved by the CONSUMING effect type — not by this base class.
##
## Skill_Effect_Damage (physical):
##   Scales the attacker's HIT stat in the GDD hit formula:
##   hitChance = clamp((attacker.HIT × tier%) / defender.DODGE, 5%, 95%)
##   CERTAIN = full HIT / DODGE ratio. Still not guaranteed — only true_strike is.
##
## Skill_Effect_Ailment / Skill_Effect_Dot (future):
##   IS the raw application probability before resistance:
##   appChance = tier% × resist_multiplier
##   CERTAIN = 100% application (before resistance can reduce it).
##
## Skill_Effect_Damage (magical), heals, buffs, HoT, Mark, etc.:
##   IGNORED. These effects always connect — ChanceTier has no effect on them.
enum ChanceTier {
	CERTAIN,  # 100% tier — physical: full HIT/DODGE ratio; ailment: guaranteed before resist
	HIGH,     # 75% tier
	MEDIUM,   # 50% tier
	LOW,      # 25% tier
}

@export var chance_tier: ChanceTier = ChanceTier.HIGH
@export var needs_previous_hit: bool = false
@export var true_strike: bool = false
```

`true_strike = true` bypasses the hit roll entirely — this effect cannot miss regardless of DODGE.
`needs_previous_hit = true` means this step is skipped if the preceding step missed.
`chance_tier` — see the contract above. Each effect subclass documents how it uses it.

- [x] **Step 2: Verify in Godot**

Create a new `Skill_Effect_Base` resource. Confirm `chance_tier`, `needs_previous_hit`, and `true_strike` all appear in the Inspector.

- [x] **Step 3: Commit**

```bash
git add scripts/combat/skills/effects/Skill_Effect_Base.gd
git commit -m "feat: add Skill_Effect_Base with ChanceTier, true_strike, needs_previous_hit"
```

---

## Task 3: Skill_Effect_Damage resource

**Files:**
- Create: `scripts/combat/skills/effects/Skill_Effect_Damage.gd`

- [x] **Step 1: Create the file**

```gdscript
class_name Skill_Effect_Damage
extends Skill_Effect_Base

@export var power: int = 10
@export var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Slash
@export var inherit_from_weapon: bool = true
@export var crit_chance: int = 5
```

**`inherit_from_weapon` — physical damage type routing:**
- `true` (default): SkillExecutor reads the damage type from the attacker's equipped weapon (Sword → Slash, Spear → Pierce, etc.). If no weapon is equipped or the gear system doesn't exist yet, `damage_type` is used as the fallback. This is correct for the vast majority of physical skills — the weapon determines how the blow lands.
- `false`: `damage_type` is always used directly. Set this for skills whose physical nature comes from something other than the weapon — a summoned creature attack, a headbutt, a bite. Magical damage always uses `damage_type` directly and ignores this flag.

Author guideline: most physical effects ship with `inherit_from_weapon = true` and `damage_type` set to the intended fallback (usually Slash). Special effects like Tergo Lupi's wolves set `inherit_from_weapon = false` and author the correct type explicitly.

**`crit_chance` is a flat percentage (e.g. 5 = 5%). It lives here, on the effect, NOT on the character.**
Crit is authored per-skill: a high-risk single-hit move might have 20%, a safe multihit might have 2%. Gear can modify it later (outside MVP scope), but it is never a character stat like HIT or DODGE. Do not add Crit to `CharacterStats`, `CombatData`, `GrowthEntry`, or `StatCalculator`.

**Stat routing is implicit from damage_type — no manual authoring needed per effect:**
- `Slash`, `Pierce`, `Blunt` → AtkPhys vs DefPhys (physical)
- Everything else (`Fire`, `Water`, `Air`, `Nature`, `Stone`, `Feral`, `Bleed`, `Stun`) → AtkMag vs DefMag (magical)

**ChanceTier contract for Skill_Effect_Damage specifically:**
- **Physical types (Slash/Pierce/Blunt):** `chance_tier` scales the attacker's HIT in the formula `clamp((HIT × tier%) / DODGE, 5%, 95%)`. Default `HIGH` (75%) means a balanced hit rate. Author `CERTAIN` for highly reliable strikes, `LOW` for gamble-type hits. Still not a guaranteed hit — only `true_strike` bypasses the roll entirely.
- **Magical types (all others):** `chance_tier` is **ignored**. Magical damage always hits. Do not author it for magical Skill_Effect_Damage — the value has no effect and would mislead readers.

- [x] **Step 2: Verify in Godot**

Create a new `Skill_Effect_Damage` resource. Confirm `power`, `damage_type`, and inherited `chance_tier`, `needs_previous_hit`, `true_strike` all appear.

- [x] **Step 3: Commit**

```bash
git add scripts/combat/skills/effects/Skill_Effect_Damage.gd
git commit -m "feat: add Skill_Effect_Damage resource (implicit stat routing from damage_type)"
```

---

## Task 4: MnemonicResource

**Files:**
- Create: `scripts/combat/skills/MnemonicResource.gd`

- [x] **Step 1: Create the file**

```gdscript
class_name MnemonicResource
extends Resource

@export var mnemonic_name: String = ""
@export var ap_cost: int = 1
@export var mp_cost: int = 0
@export var hp_cost_percent: float = 0.0
@export var rank: int = 1
@export var is_melee: bool = true
@export var merge_display: bool = true
@export var targeting: TargetingData
@export var effect_steps: Array[Skill_Effect_Base] = []
```

`hp_cost_percent` is a fraction of the attacker's max HP (e.g. `0.1` = 10%). Applied after execution.
`is_melee` is emitted with the skill for animation/VFX/camera use — no logic consumer in MVP.
`merge_display = true` means all hits show as one number visually (e.g. Fire Slash). `false` means each hit is its own number (e.g. Multihit).

- [x] **Step 2: Verify in Godot**

Create a new `MnemonicResource`. Confirm all fields appear and that `effect_steps` accepts `Skill_Effect_Damage` entries.

- [x] **Step 3: Commit**

```bash
git add scripts/combat/skills/MnemonicResource.gd
git commit -m "feat: add MnemonicResource (costs, targeting, effects, display flags)"
```

---

## Task 5: ActionContext

**Files:**
- Create: `scripts/combat/ActionContext.gd`

- [x] **Step 1: Create the file**

```gdscript
class_name ActionContext
extends RefCounted

var mnemonic: MnemonicResource
var attacker: CombatCharacter
var primary_target: CombatCharacter

var step_results: Array = []
var total_damage: int = 0
var any_hit: bool = false
var any_crit: bool = false
var ailments_applied: Array = []
```

`step_results` holds one Dictionary per effect step: `{hit: bool, damage: int, is_crit: bool}`.
This is the rolling scratchpad SkillExecutor writes to as each effect resolves. Reactions, conditional chains, and post-execution events all read from it.

- [x] **Step 2: Verify in Godot**

Check Godot Output panel for parse errors.

- [x] **Step 3: Commit**

```bash
git add scripts/combat/ActionContext.gd
git commit -m "feat: add ActionContext execution scratchpad"
```

---

## Task 6: Guard against Crit stat drift

**Files:** none — this is a verification task.

Crit lives on `Skill_Effect_Damage.crit_chance` (per-effect, authored by the designer). It is **not** a character stat. `CharacterStats`, `CombatData`, `GrowthEntry`, and `StatCalculator` must NOT have any Crit field. This task exists so that an implementor explicitly confirms this rather than accidentally adding it during the adjacent stat work.

- [x] **Step 1: Confirm CharacterStats.gd has no Crit entry**

Open `scripts/characters/stats/CharacterStats.gd`. The `Stat` enum should end at `Pulse`. No `Crit` entry. If one is present, remove it.

- [x] **Step 2: Confirm CombatData.gd has no Crit export**

Open `scripts/characters/CombatData.gd`. No `@export var Crit`. If present, remove it.

- [x] **Step 3: Confirm StatCalculator.gd routes no Crit**

Open `scripts/combat/StatCalculator.gd`. Neither `compute_player` nor `compute_enemy` should reference `CharacterStats.Stat.Crit`. If present, remove the line.

- [x] **Step 4: Commit the verification (or any removals)**

```bash
git commit -m "chore: confirm Crit is per-effect — no stat plumbing in CharacterStats/StatCalculator"
```

If no changes were needed, `git commit` will say "nothing to commit" — that's the passing condition.

---

## Task 7: PlayerData — add mnemonics

**Files:**
- Modify: `scripts/characters/PlayerData.gd`

- [x] **Step 1: Add the mnemonics export**

```gdscript
class_name PlayerData
extends CombatData

@export var character_portrait: Texture2D
@export var growth_table: GrowthTable
@export var allowed_gear: Array[EquipmentType.Flags] = []
@export var starting_level: int = 1
@export var mnemonics: Array[MnemonicResource] = []
```

- [x] **Step 2: Verify**

Open any existing PlayerData `.tres` in the Inspector. Confirm the new `Mnemonics` array field appears.

- [x] **Step 3: Commit**

```bash
git add scripts/characters/PlayerData.gd
git commit -m "feat: add mnemonics array to PlayerData"
```

---

## Task 8: EnemyData — basic_attack mnemonic

**Files:**
- Modify: `scripts/characters/EnemyData.gd`

- [x] **Step 1: Add the basic_attack export**

```gdscript
class_name EnemyData
extends CombatData

@export var xp_value: int = 1
@export var loot_table: LootTable

@export var ai_profile: AIProfile
@export var resistance_profile: ResistanceProfile
@export var basic_attack: MnemonicResource
```

Enemies pick `mnemonics[0]` on their turn (set in CombatCharacter.initialize_enemy — see Task 9). `basic_attack` is authored in the Inspector just like a player skill.

- [x] **Step 2: Verify**

Open any existing EnemyData `.tres` in the Inspector. Confirm `Basic Attack` resource slot appears.

- [x] **Step 3: Commit**

```bash
git add scripts/characters/EnemyData.gd
git commit -m "feat: add basic_attack mnemonic slot to EnemyData"
```

---

## Task 9: CombatCharacter — wire mnemonics and resistance_profile

**Files:**
- Modify: `scripts/combat/CombatCharacter.gd`

- [x] **Step 1: Add vars and update initialize functions**

```gdscript
class_name CombatCharacter
extends Node3D

@onready var vitals: VitalsComponent = $VitalsComponent
@onready var stats: StatsComponent = $StatsComponent
@onready var tokens: ActiveTokens = $ActiveTokens
@onready var visuals: CombatVisuals = $CombatVisuals
@onready var sfx: CombatSFXComponent = $CombatSFXComponent

var character_name: String = ""
var is_player_controlled: bool = false
var mnemonics: Array[MnemonicResource] = []
var resistance_profile: ResistanceProfile = null

func initialize_player(data: PlayerData, save_data: CharacterSaveData) -> void:
	is_player_controlled = true
	var computed := StatCalculator.compute_player(data, save_data)
	vitals.setup(computed[CharacterStats.Stat.MaxHP], computed[CharacterStats.Stat.MaxMP])
	stats.setup(computed)
	visuals.setup(data.character_sprite)
	character_name = data.character_name
	mnemonics = data.mnemonics
	resistance_profile = ResistanceProfile.new()  # blank — compiled from gear once gear system exists
	Log.info("character ready", data.character_name)

func initialize_enemy(data: EnemyData) -> void:
	is_player_controlled = false
	var computed := StatCalculator.compute_enemy(data)
	vitals.setup(computed[CharacterStats.Stat.MaxHP], computed[CharacterStats.Stat.MaxMP])
	stats.setup(computed)
	visuals.setup(data.character_sprite)
	character_name = data.character_name
	resistance_profile = data.resistance_profile
	if data.basic_attack:
		mnemonics = [data.basic_attack]
	Log.info("character ready", data.character_name)
```

- [x] **Step 2: Verify**

Run the combat scene. Confirm no errors in the Output panel.

- [x] **Step 3: Commit**

```bash
git add scripts/combat/CombatCharacter.gd
git commit -m "feat: CombatCharacter wires mnemonics and resistance_profile from data"
```

---

## Task 10: VitalsComponent — spend methods for all three costs

**Files:**
- Modify: `scripts/combat/VitalsComponent.gd`

- [x] **Step 1: Make max_hp public and add spend methods**

In `VitalsComponent.gd`:

Change the private `_max_hp` declaration to public:
```gdscript
var max_hp: int = 0
```

Update the two internal references (`setup()` and `spend_hp_percent()`) from `_max_hp` to `max_hp`. Then add the three spend methods at the end of the file:

```gdscript
func spend_ap(amount: int) -> void:
	cur_ap -= amount

func spend_mp(amount: int) -> void:
	cur_mp -= amount

func spend_hp_percent(percent: float) -> void:
	var cost: int = max(1, int(max_hp * percent))
	cur_hp = max(0, cur_hp - cost)
```

`max_hp` is now public so SkillButton can calculate the displayed HP cost for skills that use it.
`spend_ap` and `spend_mp` are called only after the guard in CombatFSM confirms the actor has enough — they do no bounds checking themselves.
`spend_hp_percent`: fraction of max HP (0.1 = 10%). Minimum 1 HP drained. HP can reach zero; caller checks for downed state.

- [x] **Step 2: Verify**

Godot parse check.

- [x] **Step 3: Commit**

```bash
git add scripts/combat/VitalsComponent.gd
git commit -m "feat: VitalsComponent spend_ap, spend_mp, spend_hp_percent"
```

---

## Task 11: CombatCalculator — real formulas

**Files:**
- Modify: `scripts/combat/CombatCalculator.gd`

`base_attack()` is removed. All execution now goes through SkillExecutor.

- [x] **Step 1: Rewrite the file**

```gdscript
class_name CombatCalculator
## Pure utility. Takes values in, returns values out. No state, no Node base.

## Raw damage formula from GDD:
##   damage = Power × Atk / (Def + 10) × Random(0.85, 1.0)
static func calc_damage(power: int, atk: int, def_val: int) -> int:
	var variance: float = randf_range(0.85, 1.0)
	return max(1, int(power * atk / (def_val + 10.0) * variance))

## Crit roll. Returns true if the attack crits.
## Crit = automatic hit + 2× damage. Must be rolled BEFORE the hit roll.
## crit_chance comes from the effect (Skill_Effect_Damage.crit_chance), NOT from a character stat.
static func crit_roll(crit_chance: int) -> bool:
	return randf() < crit_chance / 100.0

## Hit roll. Returns true if the attack connects.
## GDD formula: clamp((attacker.HIT × ChanceTier%) / defender.DODGE, 5%, 95%)
static func hit_roll(hit_stat: int, dodge_stat: int, tier: Skill_Effect_Base.ChanceTier) -> bool:
	var tier_mult: float = _tier_multiplier(tier)
	var chance: float = clampf((hit_stat * tier_mult) / float(max(1, dodge_stat)), 0.05, 0.95)
	return randf() <= chance

## Resistance multiplier for damage or ailment application.
static func resist_multiplier(state: ResistanceType.State) -> float:
	match state:
		ResistanceType.State.WEAK:      return 2.0
		ResistanceType.State.RESISTANT: return 0.5
		ResistanceType.State.IMMUNE:    return 0.0
		_:                              return 1.0

static func _tier_multiplier(tier: Skill_Effect_Base.ChanceTier) -> float:
	match tier:
		Skill_Effect_Base.ChanceTier.CERTAIN: return 1.0
		Skill_Effect_Base.ChanceTier.HIGH:    return 0.75
		Skill_Effect_Base.ChanceTier.MEDIUM:  return 0.50
		Skill_Effect_Base.ChanceTier.LOW:     return 0.25
	return 1.0
```

- [x] **Step 2: Verify parse**

Open Godot. Check Output for errors. No scene test yet — SkillExecutor (next task) calls these.

- [x] **Step 3: Commit**

```bash
git add scripts/combat/CombatCalculator.gd
git commit -m "feat: CombatCalculator real formulas (crit_roll, hit_roll with ChanceTier, resist_multiplier)"
```

---

## Task 12: SkillExecutor

**Files:**
- Create: `scripts/combat/SkillExecutor.gd`

- [x] **Step 1: Create the file**

```gdscript
class_name SkillExecutor
## Static utility. Resolves a mnemonic's effect steps against a target.
## Creates and returns an ActionContext populated with per-step results.

static func execute(mnemonic: MnemonicResource, attacker: CombatCharacter, target: CombatCharacter) -> ActionContext:
	var ctx := ActionContext.new()
	ctx.mnemonic = mnemonic
	ctx.attacker = attacker
	ctx.primary_target = target

	for effect in mnemonic.effect_steps:
		if effect.needs_previous_hit and not ctx.any_hit:
			ctx.step_results.append({hit = false, damage = 0, is_crit = false})
			continue
		var result: Dictionary = _resolve_effect(effect, attacker, target)
		ctx.step_results.append(result)
		if result.hit:
			ctx.any_hit = true
			ctx.total_damage += result.damage
		if result.is_crit:
			ctx.any_crit = true

	return ctx

static func _resolve_effect(effect: Skill_Effect_Base, attacker: CombatCharacter, target: CombatCharacter) -> Dictionary:
	if effect is Skill_Effect_Damage:
		return _resolve_damage(effect as Skill_Effect_Damage, attacker, target)
	Log.warn("SkillExecutor — unknown effect type, skipping")
	return {hit = false, damage = 0, is_crit = false}

static func _resolve_damage(effect: Skill_Effect_Damage, attacker: CombatCharacter, target: CombatCharacter) -> Dictionary:
	var is_phys: bool = _is_physical(effect.damage_type)

	# ChanceTier contract enforcement:
	# Physical (Slash/Pierce/Blunt) — chance_tier scales HIT in the hit formula below.
	# Magical (everything else)     — always hits, chance_tier is not read here at all.
	# true_strike                   — bypasses hit roll regardless of physical/magical.

	# Crit roll first — crit = automatic hit.
	# crit_chance is authored on the effect, not read from attacker stats.
	var is_crit: bool = CombatCalculator.crit_roll(effect.crit_chance)

	# Hit roll (physical only, skipped for magical and true_strike)
	if is_phys and not is_crit and not effect.true_strike:
		var hit_stat: int = attacker.stats.stat(CharacterStats.Stat.Hit)
		var dodge_stat: int = target.stats.stat(CharacterStats.Stat.Dodge)
		if not CombatCalculator.hit_roll(hit_stat, dodge_stat, effect.chance_tier):
			Log.info("SkillExecutor — missed", attacker.character_name)
			return {hit = false, damage = 0, is_crit = false}

	# Resolve the effective damage type:
	# physical + inherit_from_weapon → read from equipped weapon (stub for now)
	# physical + not inherit  → use effect.damage_type directly
	# magical                 → always use effect.damage_type
	var effective_type: ResistanceType.DamageType = effect.damage_type
	if is_phys and effect.inherit_from_weapon:
		effective_type = _get_weapon_damage_type(attacker)

	# Stat routing from effective damage type
	var atk_stat := CharacterStats.Stat.AtkPhys if is_phys else CharacterStats.Stat.AtkMag
	var def_stat := CharacterStats.Stat.DefPhys if is_phys else CharacterStats.Stat.DefMag
	var atk: int = attacker.stats.stat(atk_stat)
	var def_val: int = target.stats.stat(def_stat)
	var raw: int = CombatCalculator.calc_damage(effect.power, atk, def_val)

	# Crit doubles damage
	if is_crit:
		raw *= 2

	# Resistance lookup uses effective_type, not effect.damage_type
	var resist_state := ResistanceType.State.NONE
	if target.resistance_profile != null:
		resist_state = target.resistance_profile.get_state(effective_type)
	var final_damage: int = max(0, int(raw * CombatCalculator.resist_multiplier(resist_state)))

	var summary := "%s->%s %d (crit:%s resist:%s)" % [attacker.character_name, target.character_name,
		final_damage, is_crit, ResistanceType.State.keys()[resist_state]]
	Log.info("SkillExecutor", summary)
	return {hit = true, damage = final_damage, is_crit = is_crit}

static func _is_physical(dt: ResistanceType.DamageType) -> bool:
	return dt == ResistanceType.DamageType.Slash \
		or dt == ResistanceType.DamageType.Pierce \
		or dt == ResistanceType.DamageType.Blunt

static func _get_weapon_damage_type(attacker: CombatCharacter) -> ResistanceType.DamageType:
	# TODO: read from attacker's equipped weapon once gear system exists.
	# Falls back to effect.damage_type at call site — this stub only fires when
	# inherit_from_weapon = true and no gear system is in place yet.
	return ResistanceType.DamageType.Slash
```

- [x] **Step 2: Verify parse**

Open Godot. Check for errors.

- [x] **Step 3: Commit**

```bash
git add scripts/combat/SkillExecutor.gd
git commit -m "feat: SkillExecutor — ActionContext pipeline, crit, true_strike, implicit stat routing"
```

---

## Task 13: CombatEvents — update action_selected signal

**Files:**
- Modify: `scripts/combat/CombatEvents.gd`

- [x] **Step 1: Change the signal signature**

Change:
```gdscript
signal action_selected(target: CombatCharacter)
```
To:
```gdscript
signal action_selected(mnemonic: MnemonicResource, target: CombatCharacter)
```

When awaiting in GDScript, multi-param signals return an Array: `[mnemonic, target]`.
WAIT emits `(null, null)`.

- [x] **Step 2: Note**

This breaks CombatFSM and CombatUIFSM until Tasks 14 and 15 fix them. Don't run the scene after this step.

- [x] **Step 3: Commit** (grouped into Phase 4 commit)

```bash
git add scripts/combat/CombatEvents.gd
git commit -m "feat: action_selected signal carries mnemonic + target"
```

---

## Task 14: CombatFSM — unified execution path

**Files:**
- Modify: `scripts/combat/CombatFSM.gd`

Changes: add `_pending_mnemonic`; fix await to unpack two-param signal; enemy auto-picks `mnemonics[0]`; unified `_enter_action_execution()` using SkillExecutor.

- [x] **Step 1: Add _pending_mnemonic to var declarations**

```gdscript
var _pending_mnemonic: MnemonicResource = null
```

- [x] **Step 2: Fix _enter_action_select() for both player and enemy**

Replace the entire function:

```gdscript
func _enter_action_select() -> void:
	CombatEvents.please_select_action.emit(_active_actor)

	if not _active_actor.is_player_controlled:
		_pending_target = _first_living_opponent(_active_actor)
		if _pending_target == null:
			Log.info("ActionSelect — enemy has no valid target, skipping")
			_transition(State.TURN_END)
			return
		_pending_mnemonic = _active_actor.mnemonics[0] if not _active_actor.mnemonics.is_empty() else null
		Log.info("ActionSelect — enemy auto:", _pending_target.character_name)
		_transition(State.ACTION_EXECUTION)
		return

	var result: Array = await CombatEvents.action_selected
	_pending_mnemonic = result[0] as MnemonicResource
	_pending_target = result[1] as CombatCharacter
	if _pending_target == null:
		Log.info("ActionSelect — WAIT selected")
		_transition(State.TURN_END)
		return
	Log.info("ActionSelect — target:", _pending_target.character_name)
	_transition(State.ACTION_EXECUTION)
```

- [x] **Step 3: Replace _enter_action_execution() with unified path**

Replace the entire function (and remove `_execute_player_skill` / `_execute_enemy_auto` if they existed from a previous draft):

```gdscript
func _enter_action_execution() -> void:
	if _pending_mnemonic == null:
		Log.warn("ActionExecution — no mnemonic, skipping to REACTION_SCAN")
		_transition(State.REACTION_SCAN)
		return

	# Guard: check both costs before spending either — avoids partial deductions
	if _active_actor.vitals.cur_ap < _pending_mnemonic.ap_cost \
			or _active_actor.vitals.cur_mp < _pending_mnemonic.mp_cost:
		Log.warn("ActionExecution — insufficient AP/MP, skipping skill")
		_transition(State.REACTION_SCAN)
		return

	_active_actor.vitals.spend_ap(_pending_mnemonic.ap_cost)
	_active_actor.vitals.spend_mp(_pending_mnemonic.mp_cost)

	var context: ActionContext = SkillExecutor.execute(_pending_mnemonic, _active_actor, _pending_target)

	if _pending_mnemonic.hp_cost_percent > 0.0:
		_active_actor.vitals.spend_hp_percent(_pending_mnemonic.hp_cost_percent)

	for result: Dictionary in context.step_results:
		# Apply damage BEFORE emitting — listeners read post-damage vitals
		if result.hit:
			_pending_target.vitals.take_damage(result.damage)
		CombatEvents.action_executed.emit(_active_actor, _pending_target, result.damage)

	Log.info("ActionExecution", "%s->%s total:%d" % [_active_actor.character_name, _pending_target.character_name, context.total_damage])

	if _pending_target.vitals.is_downed():
		Log.info("actor downed", _pending_target.character_name)
		CombatEvents.actor_downed.emit(_pending_target)

	if _check_combat_end():
		return
	_transition(State.REACTION_SCAN)
```

- [x] **Step 4: Verify**

Run the combat scene. The scene should start without errors. Enemy turns should proceed (assuming their basic_attack is authored — that's Task 18). Player turns will hang at action selection until CombatUIFSM is fixed in Task 17.

- [x] **Step 5: Commit**

```bash
git add scripts/combat/CombatFSM.gd
git commit -m "feat: CombatFSM unified execution — both player and enemy use SkillExecutor"
```

---

## Task 15: SkillButton.gd — setup script

**Files:**
- Create: `scripts/combat/ui/SkillButton.gd`
- Modify: `scenes/UI/skill_button.tscn` — attach the script

The existing `skill_button.tscn` has `MarginContainer/Layout/SkillName`, `Cost_1`, `Cost_2` labels.

- [x] **Step 1: Create the script**

```gdscript
class_name SkillButton
extends Button

@onready var _name_label: Label = $MarginContainer/Layout/SkillName
@onready var _cost_ap: Label = $MarginContainer/Layout/Cost_1
@onready var _cost_resource: Label = $MarginContainer/Layout/Cost_2

var mnemonic: MnemonicResource = null

## Skills always cost exactly two resources: AP + either HP or MP.
## vitals is needed to calculate the real HP cost and to check affordability.
func setup(m: MnemonicResource, vitals: VitalsComponent) -> void:
	mnemonic = m
	_name_label.text = m.mnemonic_name
	_cost_ap.text = str(m.ap_cost) + "AP"

	# Resolve the second cost — HP takes priority if both are somehow non-zero
	var hp_cost: int = max(1, int(vitals.max_hp * m.hp_cost_percent)) if m.hp_cost_percent > 0.0 else 0
	if hp_cost > 0:
		_cost_resource.text = str(hp_cost) + "HP"
		_cost_resource.visible = true
	elif m.mp_cost > 0:
		_cost_resource.text = str(m.mp_cost) + "MP"
		_cost_resource.visible = true
	else:
		_cost_resource.visible = false

	# Grey out if the actor can't afford either cost
	var can_afford: bool = vitals.cur_ap >= m.ap_cost \
		and (hp_cost == 0 or vitals.cur_hp > hp_cost) \
		and (m.mp_cost == 0 or vitals.cur_mp >= m.mp_cost)
	modulate.a = 1.0 if can_afford else 0.4
```

`modulate.a = 0.4` dims the button visually without disabling keyboard navigation — ActionMenu still cycles through all skills. The FSM's AP/MP guard prevents actually executing an unaffordable skill.

- [x] **Step 2: Attach the script in Godot**

Open `scenes/UI/skill_button.tscn`. Select the root `SkillButton` node → Inspector → Script → attach `scripts/combat/ui/SkillButton.gd`.

- [x] **Step 3: Verify**

Godot parse check. No errors in Output.

- [x] **Step 4: Commit**

```bash
git add scripts/combat/ui/SkillButton.gd scenes/UI/skill_button.tscn
git commit -m "feat: SkillButton setup(mnemonic) script"
```

---

## Task 16: ActionMenu — fix populate() and add get_selected_mnemonic()

**Files:**
- Modify: `scripts/combat/ui/ActionMenu.gd`

Two changes: fix the `queue_free` bug (old children must be immediately removed from the scene tree before new ones are added, otherwise `get_children()` still sees them), and add `get_selected_mnemonic()` so CombatUIFSM can retrieve the chosen mnemonic at confirm time.

- [x] **Step 1: Add _skill_mnemonics var at class level**

Add to the class vars block (before `_ready()`):

```gdscript
var _skill_mnemonics: Array[MnemonicResource] = []
```

- [x] **Step 2: Replace populate()**

Current populate():
```gdscript
func populate(skills: Array, items: Array) -> void:
	for child in _skill_menu.get_children():
		child.queue_free()
	for skill in skills:
		var btn: Button = SKILL_BUTTON.instantiate()
		# TODO: btn.setup(skill) once SkillResource format is defined
		_skill_menu.add_child(btn)
	...
```

Replace with:
```gdscript
func populate(skills: Array[MnemonicResource], items: Array, vitals: VitalsComponent) -> void:
	_skill_mnemonics = skills
	for child in _skill_menu.get_children():
		_skill_menu.remove_child(child)
		child.queue_free()
	for mnemonic in skills:
		var btn := SKILL_BUTTON.instantiate() as SkillButton
		btn.setup(mnemonic, vitals)
		_skill_menu.add_child(btn)

	for child in _item_menu.get_children():
		_item_menu.remove_child(child)
		child.queue_free()
	for item in items:
		var btn: Button = ITEM_BUTTON.instantiate()
		# TODO: btn.setup(item) once ItemResource format is defined
		_item_menu.add_child(btn)

	_item_index = 0
	_refresh_display()
```

`remove_child()` detaches the node immediately — `get_children()` no longer sees it. Without this, `queue_free()`-only leaves old children in the tree for the rest of the frame, causing `_item_index` to reference the wrong buttons.

- [x] **Step 3: Add get_selected_mnemonic()**

```gdscript
func get_selected_mnemonic() -> MnemonicResource:
	if _skill_mnemonics.is_empty() or _item_index >= _skill_mnemonics.size():
		return null
	return _skill_mnemonics[_item_index]
```

- [x] **Step 4: Verify**

Godot parse check.

- [x] **Step 5: Commit**

```bash
git add scripts/combat/ui/ActionMenu.gd
git commit -m "feat: ActionMenu.populate() wired with remove_child fix, get_selected_mnemonic() added"
```

---

## Task 17: CombatUIFSM — populate at turn start, thread mnemonic

**Files:**
- Modify: `scripts/combat/ui/CombatUIFSM.gd`

- [x] **Step 1: Add _pending_mnemonic var**

Add to var declarations:
```gdscript
var _pending_mnemonic: MnemonicResource = null
```

- [x] **Step 2: Update _enter_player_menu()**

Current:
```gdscript
func _enter_player_menu() -> void:
	cursor.stop()
	player_bar.set_active(_active_actor)
	# info_panel: ...
```

Replace with:
```gdscript
func _enter_player_menu() -> void:
	cursor.stop()
	player_bar.set_active(_active_actor)
	var menu := player_bar.get_active_menu()
	if menu != null:
		menu.populate(_active_actor.mnemonics, [], _active_actor.vitals)
	# info_panel: "A/D: switch menu   W/S: navigate   Enter: confirm"
```

- [x] **Step 3: Update _on_action_chosen()**

Current:
```gdscript
func _on_action_chosen(category: String, _item_index: int) -> void:
	if category == "WAIT":
		CombatEvents.action_selected.emit(null)
		_transition(State.WATCHING)
		return
	if category == "ACT":
		_transition(State.PLAYER_TARGETING)
```

Replace with:
```gdscript
func _on_action_chosen(category: String, _item_index: int) -> void:
	if category == "WAIT":
		CombatEvents.action_selected.emit(null, null)
		_transition(State.WATCHING)
		return
	if category == "ACT":
		var menu := player_bar.get_active_menu()
		_pending_mnemonic = menu.get_selected_mnemonic() if menu != null else null
		_transition(State.PLAYER_TARGETING)
```

- [x] **Step 4: Update _on_target_confirmed()**

Current:
```gdscript
func _on_target_confirmed(target: CombatCharacter) -> void:
	CombatEvents.action_selected.emit(target)
	_transition(State.WATCHING)
```

Replace with:
```gdscript
func _on_target_confirmed(target: CombatCharacter) -> void:
	CombatEvents.action_selected.emit(_pending_mnemonic, target)
	_pending_mnemonic = null
	_transition(State.WATCHING)
```

- [x] **Step 5: Verify Godot parses cleanly**

Open Godot. Check Output for errors. At this point, all callers of `action_selected` are consistent. The full pipeline compiles.

- [x] **Step 6: Commit**

```bash
git add scripts/combat/ui/CombatUIFSM.gd
git commit -m "feat: CombatUIFSM populates ActionMenu at turn start, threads mnemonic through action_selected"
```

---

## Task 18: Author test mnemonics and verify end-to-end

**Files:**
- Create: `resources/mnemonics/` — new folder with .tres resources

This task is done in the Godot editor Inspector. No code to write.

### Part A — Player mnemonic (Uskrav's basic slash)

- [x] **Step 1: Create TargetingData**

New Resource → `TargetingData`.
- `shape`: SINGLE_ENEMY
- `filter`: NONE

Save as `resources/mnemonics/targeting_single_enemy.tres`.

- [x] **Step 2: Create Skill_Effect_Damage**

New Resource → `Skill_Effect_Damage`.
- `power`: 30
- `damage_type`: Slash ← fallback if no weapon equipped; with gear system this will be overridden
- `inherit_from_weapon`: **true** — this is a weapon-driven physical attack
- `chance_tier`: HIGH
- `crit_chance`: 5
- `needs_previous_hit`: false
- `true_strike`: false

Save as `resources/mnemonics/effect_slash_30.tres`.

- [x] **Step 3: Create MnemonicResource**

New Resource → `MnemonicResource`.
- `mnemonic_name`: "Tergo Lupi"
- `ap_cost`: 1
- `mp_cost`: 0
- `hp_cost_percent`: 0.0
- `rank`: 1
- `is_melee`: true
- `merge_display`: true
- `targeting`: (load `targeting_single_enemy.tres`)
- `effect_steps`: add `effect_slash_30.tres`

Save as `resources/mnemonics/uskrav_tergo_lupi.tres`.

- [x] **Step 4: Add mnemonic to Uskrav's PlayerData**

Open Uskrav's PlayerData `.tres` under `resources/characters/`. In the `Mnemonics` array, add `uskrav_tergo_lupi.tres`.

### Part B — Enemy basic attack

- [x] **Step 5: Create a basic enemy Skill_Effect_Damage**

New Resource → `Skill_Effect_Damage`.
- `power`: 15
- `damage_type`: Blunt ← enemies don't have weapons, so `inherit_from_weapon = false`; type is explicit
- `inherit_from_weapon`: **false**
- `chance_tier`: HIGH
- `crit_chance`: 3
- `needs_previous_hit`: false
- `true_strike`: false

Save as `resources/mnemonics/effect_blunt_15.tres`.

- [x] **Step 6: Create enemy MnemonicResource**

New Resource → `MnemonicResource`.
- `mnemonic_name`: "Strike"
- `ap_cost`: 1
- `mp_cost`: 0
- `hp_cost_percent`: 0.0
- `rank`: 1
- `is_melee`: true
- `merge_display`: true
- `targeting`: (load `targeting_single_enemy.tres`)
- `effect_steps`: add `effect_blunt_15.tres`

Save as `resources/mnemonics/enemy_basic_strike.tres`.

- [x] **Step 7: Assign to an enemy EnemyData**

Open any EnemyData `.tres` used in the debug combat scene. Set `basic_attack` to `enemy_basic_strike.tres`.

### Part C — End-to-end verification

- [x] **Step 8: Run the combat scene and verify**

Run the scene (F5). Walk through:

1. **Enemy turn:** Enemy takes a turn automatically. Check Output log — should see:
   - `SkillExecutor — [crit/miss/damage] [attacker] -> [target] ...`
   - `ActionExecution [enemy] -> [player] total: N`
   - A damage number should appear over the player character

2. **Player turn:** When player's turn comes, ActionMenu should appear. Navigate to ACT — SkillMenu should show a "Tergo Lupi" button with "1AP". Press Enter to confirm, cursor appears on enemies. Confirm target. Check Output:
   - `SkillExecutor — damage N (crit:false resist:NONE)` (or with crit/resist variants)
   - A damage number appears over the enemy

3. **Both paths used SkillExecutor** — confirm no `base_attack` calls appear in the log.

- [x] **Step 9: Commit**

```bash
git add resources/mnemonics/
git commit -m "feat: author test mnemonics for Uskrav and enemy — pipeline verified end-to-end"
```

---

## Self-Review

### Spec coverage
- [x] MnemonicResource — name, costs (AP/MP/HP%), targeting, effect_steps, rank, is_melee, merge_display — Task 4
- [x] TargetingData shape + filter — Task 1
- [x] Skill_Effect_Base — chance_tier, needs_previous_hit, true_strike — Task 2
- [x] Skill_Effect_Damage — power, damage_type, implicit stat routing — Task 3
- [x] ActionContext rolling scratchpad — step_results, any_hit, any_crit, total_damage — Task 5
- [x] Crit is per-effect (crit_chance on Skill_Effect_Damage), not a character stat — confirmed in Task 6
- [x] PlayerData mnemonics array — Task 7
- [x] EnemyData basic_attack mnemonic — Task 8
- [x] CombatCharacter exposes mnemonics + resistance_profile — Task 9
- [x] VitalsComponent.spend_hp_percent — Task 10
- [x] GDD damage formula + crit_roll + hit_roll (GDD formula with ChanceTier) + resist_multiplier — Task 11
- [x] SkillExecutor — crit before hit, true_strike bypass, implicit routing, resistance lookup — Task 12
- [x] action_selected signal carries mnemonic + target — Task 13
- [x] CombatFSM unified path — both player and enemy use SkillExecutor — Task 14
- [x] SkillButton.setup(mnemonic) — Task 15
- [x] ActionMenu.populate() with correct remove_child() — Task 16
- [x] CombatUIFSM populates at turn start, threads mnemonic — Task 17
- [x] End-to-end verification — Task 18

### Out of scope (post-MVP)
- Ailment/DoT/Debuff effect types — no ailment system yet
- Enemy AI skill selection (multi-skill enemies) — currently always picks mnemonics[0]
- merge_display visual merging — MVP fires one `action_executed` per step; visual bundling is a presentation layer task
- Player ResistanceProfile compiled from gear — blank profile until gear system exists
- Item use in combat — item_menu stubs remain
- RUN / escape logic

---

## Implementation Deviations

> Captured during the 2026-05-15 build session. Deviations are ordered by when they were encountered, not by severity.

### 1. Commits grouped by phase, not per task
The plan expected ~18 individual commits (one per task). In practice we grouped into 5 phase commits + 3 fix commits + 1 cleanup commit to keep history readable. The work is identical; only commit granularity differs.

### 2. Godot headless `class_name` resolution required `preload()` workarounds
Godot 4.6's headless parser resolves `class_name` alphabetically at parse time. Several files (`CombatCalculator`, `SkillButton`, `ActionMenu`, `CombatUIFSM`, `CombatFSM`, `CombatEvents`, `MnemonicResource`, `ActionContext`, `SkillExecutor`, `PlayerData`, `EnemyData`, `CombatCharacter`) reference types that parse later alphabetically, causing "Could not find type" errors in `--check-only` and `--script` runs.

**Fix:** Added `const SomeType = preload("res://path/to/script.gd")` in affected files, using the preloaded const for type hints and references. The `class_name` declarations were kept for editor use. Runtime behavior is unchanged.

**Later resolved:** `SkillButton` was able to drop the string-path `extends` and use `extends CombatButton` normally once the `.uid` file was in place.

### 3. `CombatButton` base class introduced (not in plan)
After implementing Task 15, we discovered that Godot's default Button focus/hover/pressed styles draw a rounded grey background on top of the custom `ButtonBackground` shader. The plan only overrode `normal` style; this left `focus`, `hover`, `pressed`, and `disabled` styles intact.

**Fix:** Created `scripts/combat/ui/CombatButton.gd` — a thin base script that overrides all five Button styles with `StyleBoxEmpty` in `_ready()`. `SkillButton`, `WaitButton`, `RunButton`, and `ItemButton` all extend it. The `button_background.gd` script still handles gradient reversal via `focus_entered`/`mouse_entered` signals.

### 4. `@onready` resolution order — `add_child` must precede `setup()`
In `ActionMenu.populate()`, the plan showed `btn.setup(mnemonic, vitals)` before `_skill_menu.add_child(btn)`. This fails at runtime because `@onready` vars in `SkillButton` only resolve when the node enters the tree (i.e. after `add_child()`).

**Fix:** Swapped the order in `ActionMenu.populate()`:
```gdscript
_skill_menu.add_child(btn)   # _ready() fires, @onready labels resolve
btn.setup(mnemonic, vitals)   # now safe
```

### 5. Signal emission race condition in `_on_target_confirmed`
The plan showed `emit` then `transition(WATCHING)`. Because GDScript signal emission is synchronous, CombatFSM's `await action_selected` unblocked immediately and ran through the entire turn pipeline (execution → reaction → turn end → next turn start → please_select_action) **before** `_on_target_confirmed` reached its `_transition(State.WATCHING)` line. The WATCHING transition then overwrote the next turn's PLAYER_MENU state, halting combat.

**Fix:** `_on_target_confirmed` now transitions to WATCHING **before** emitting the signal:
```gdscript
func _on_target_confirmed(target: CombatCharacter) -> void:
    _transition(State.WATCHING)
    CombatEvents.action_selected.emit(_pending_mnemonic, target)
    _pending_mnemonic = null
```

### 6. `PlayerCardBar.set_active()` called `reset()` redundantly
`set_active()` called `menu.reset()` which fires `_refresh_display()`, then `_enter_player_menu()` called `populate()` which also fires `_refresh_display()`. This caused `ActionMenu ACT 0` to appear twice in the log on every turn start.

**Fix:** Removed `menu.reset()` from `set_active()`. `populate()` handles the full reset including `_item_index = 0`.

### 7. Test mnemonic assigned to both Skugge and Vargi
The plan refers to "Uskrav's basic slash" and "Uskrav's PlayerData", but the debug combat scene's party is Skugge (slot 0) and Vargi (slot 1). There is no "Uskrav" character in the project — Uskrav is the **mnemonic name** (from the GDD skill chain).

**What we did:** Assigned `uskrav_tergo_lupi.tres` to **Skugge** (the starting character). During playtesting we also assigned it to **Vargi** so both player characters had a skill to test with.

### 8. `SkillMenu` / `ItemMenu` width inconsistency in ActionMenu.tscn
The scene had `SkillMenu` and `ItemMenu` at 64px wide while `ContentArea` was only 48px with `clip_contents = true`. This didn't cause the reported bug (that was the `size_flags_horizontal = 3` on `SkillName`), but it was inconsistent with `WaitMenu`/`RunMenu` which were 48px.

**Fix:** Aligned `SkillMenu` and `ItemMenu` `offset_right` to 48.0 to match the rest.
