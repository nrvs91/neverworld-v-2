# Stat Scaling & Character Ownership — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace integer `power` on damage tokens with multi-stat `StatScaling` resources (float multipliers on named stats). Add `character_owner` field to mnemonic resources with equip-time filtering in CombatCharacter.

**Architecture:** New `StatScaling` Resource holds a `stat: String` and `scaling: float`. Damage tokens carry `Array[StatScaling]` instead of `int power`. `CombatCalculator` sums `stat_value × scaling` across all entries to produce the attack value fed into the existing damage formula. `character_owner: Array[String]` on `MnemonicResource` gates which characters can equip a mnemonic — empty array = anyone. `CombatCharacter.initialize_player()` filters `data.mnemonics` by owner.

**Tech Stack:** Godot 4.6, GDScript, `.tres` Resource files

**Scope note:** This plan covers only the int→float Power refactor and character_owner gating. Gear-based mnemonic slots, RESONANCE economy, and rank progression are separate plans.

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `scripts/combat/stats/StatScaling.gd` | **Create** | Resource: `{stat: String, scaling: float}` |
| `scripts/combat/CombatCalculator.gd` | Modify | Accept `Array[StatScaling]`, sum attack from multiple stats |
| `scripts/combat/tokens/RuntimeToken_Damage.gd` | Modify | `power: int` → `stat_scalings: Array[StatScaling]` |
| `scripts/combat/tokens/RuntimeToken_Envenom.gd` | Modify | `power_per_token: int` → `scaling_per_token: float` |
| `scripts/combat/tokens/RuntimeToken_Counter.gd` | Modify | Same as Damage |
| `scripts/combat/tokens/RuntimeToken_Vigil.gd` | Modify | Same as Damage |
| `scripts/combat/skills/MnemonicResource.gd` | Modify | Add `character_owner: Array[String]` |
| `scripts/combat/CombatCharacter.gd` | Modify | Filter mnemonics by owner in `initialize_player()` |
| `resources/mnemonics/basic_attack/basic_attack.tres` | Modify | Update sub-resource |
| `resources/mnemonics/uskrav/uskrav_tergo_lupi.tres` | Modify | Update sub-resource + character_owner |
| `resources/mnemonics/viper_strike/viper_strike.tres` | Modify | Update sub-resource + character_owner |
| `resources/mnemonics/strike/enemy_basic_strike.tres` | Modify | Update sub-resource |
| `resources/mnemonics/envenom/envenom.tres` | Modify | Update sub-resource + character_owner |
| `resources/mnemonics/counter_stance/counter_stance.tres` | Modify | Update sub-resource + character_owner |
| `resources/mnemonics/vigil_stance/vigil_stance.tres` | Modify | Update sub-resource + character_owner |

---

### Task 1: Create StatScaling Resource

**Files:**
- Create: `scripts/combat/stats/StatScaling.gd`

- [ ] **Step 1: Write StatScaling.gd**

```gdscript
class_name StatScaling
extends Resource

@export var stat: String = ""
@export var scaling: float = 1.0
```

- [ ] **Step 2: Commit**

```bash
git add scripts/combat/stats/StatScaling.gd
git commit -m "feat: add StatScaling resource (stat + scaling multiplier)"
```

---

### Task 2: Update CombatCalculator for stat_scalings

**Files:**
- Modify: `scripts/combat/CombatCalculator.gd`

- [ ] **Step 1: Replace `calc_damage` to accept stat_scalings array**

Change the signature and body — old:
```gdscript
static func calc_damage(power: int, atk: int, def_val: int) -> int:
	var variance: float = randf_range(0.85, 1.0)
	return max(1, int(power * atk / (def_val + 10.0) * variance))
```

New:
```gdscript
static func calc_damage(stat_scalings: Array, stats: StatsComponent, def_val: int) -> int:
	var total_atk: float = 0.0
	for entry in stat_scalings:
		var stat_key: CharacterStats.Stat = _stat_from_string(entry.stat)
		var stat_val: int = stats.stat(stat_key)
		total_atk += stat_val * entry.scaling

	var variance: float = randf_range(0.85, 1.0)
	return max(1, int(total_atk / (def_val + 10.0) * variance))
```

- [ ] **Step 2: Add `_stat_from_string` helper**

Append this static function to CombatCalculator (after `_tier_multiplier` at line 72):

```gdscript
static func _stat_from_string(stat_name: String) -> CharacterStats.Stat:
	match stat_name:
		"Phys.Atk": return CharacterStats.Stat.AtkPhys
		"Magic.Atk": return CharacterStats.Stat.AtkMag
		"MaxHP": return CharacterStats.Stat.MaxHP
		"PULSE": return CharacterStats.Stat.Pulse
		_:
			Log.warn("unknown stat in StatScaling", stat_name, "defaulting to Phys.Atk")
			return CharacterStats.Stat.AtkPhys
```

- [ ] **Step 3: Update `resolve_hit` signature**

Change `power: int` parameter to `stat_scalings: Array`. Old signature:
```gdscript
static func resolve_hit(
		power: int,
		damage_type: ResistanceType.DamageType,
		crit_chance: int,
		chance_tier: SkillEffectBase.ChanceTier,
		source: CombatCharacter,
		target: CombatCharacter,
		true_strike: bool = false
) -> Dictionary:
```

New signature (only the first param changes, body stays mostly same):
```gdscript
static func resolve_hit(
		stat_scalings: Array,
		damage_type: ResistanceType.DamageType,
		crit_chance: int,
		chance_tier: SkillEffectBase.ChanceTier,
		source: CombatCharacter,
		target: CombatCharacter,
		true_strike: bool = false
) -> Dictionary:
```

- [ ] **Step 4: Update `calc_damage` call in `resolve_hit`**

Old (line 59):
```gdscript
	var raw := calc_damage(power, source.stats.stat(atk_stat), target.stats.stat(def_stat))
```

Replace lines 57–59 — old:
```gdscript
	var atk_stat := CharacterStats.Stat.AtkPhys if phys else CharacterStats.Stat.AtkMag
	var def_stat := CharacterStats.Stat.DefPhys if phys else CharacterStats.Stat.DefMag
	var raw := calc_damage(power, source.stats.stat(atk_stat), target.stats.stat(def_stat))
```

New:
```gdscript
	var def_stat := CharacterStats.Stat.DefPhys if phys else CharacterStats.Stat.DefMag
	var raw := calc_damage(stat_scalings, source.stats, target.stats.stat(def_stat))
```

Note: `atk_stat` is no longer needed — the stat is determined per-entry in `StatScaling.stat`. Defense still uses damage type.

- [ ] **Step 5: Commit**

```bash
git add scripts/combat/CombatCalculator.gd
git commit -m "feat: CombatCalculator uses StatScaling array, sums multi-stat attack"
```

---

### Task 3: Update RuntimeToken_Damage

**Files:**
- Modify: `scripts/combat/tokens/RuntimeToken_Damage.gd`

- [ ] **Step 1: Replace `power: int` with `stat_scalings: Array[StatScaling]`**

Old (line 6):
```gdscript
@export var power: int = 10
```

New:
```gdscript
@export var stat_scalings: Array[StatScaling] = []
```

Add a preload for StatScaling at the top (after line 4):
```gdscript
const StatScalingRes = preload("res://scripts/combat/stats/StatScaling.gd")
```

- [ ] **Step 2: Auto-populate default stat_scalings in `_init`**

Since exported `Array[StatScaling]` starts empty but needs a sensible default, override `_init` to inject a default `{Phys.Atk, 1.0}` entry when the array is empty in the editor. Actually, Godot's `@export` with `Array[Resource]` handles this — just leave the default as `[]` and let the `.tres` files provide entries. Remove the old `power` field entirely.

The `_init` currently sets `token_type` and `trigger`. Leave those. No default stat_scalings needed — each `.tres` will author its own.

- [ ] **Step 3: Update `fire()` to pass `stat_scalings`**

Old (line 22):
```gdscript
	var result := CombatCalculator.resolve_hit(power, effective_type, crit_chance, chance_tier, source, owner, true_strike)
```

New:
```gdscript
	var result := CombatCalculator.resolve_hit(stat_scalings, effective_type, crit_chance, chance_tier, source, owner, true_strike)
```

- [ ] **Step 4: Remove unused `power` references**

Remove the old `@export var power: int = 10` line. Done in step 1.

- [ ] **Step 5: Commit**

```bash
git add scripts/combat/tokens/RuntimeToken_Damage.gd
git commit -m "feat: RuntimeToken_Damage uses stat_scalings Array instead of int power"
```

---

### Task 4: Update RuntimeToken_Envenom

**Files:**
- Modify: `scripts/combat/tokens/RuntimeToken_Envenom.gd`

- [ ] **Step 1: Replace `power_per_token: int` with `scaling_per_token: float`**

Old (line 7):
```gdscript
@export var power_per_token: int = 30
```

New:
```gdscript
@export var scaling_per_token: float = 1.0
```

- [ ] **Step 2: Update `fire()` to build a StatScaling on the fly and pass array**

Envenom doesn't store stat_scalings as an exported array — it builds damage from `count × scaling_per_token`. The cleanest approach: create a temporary StatScaling at runtime with the accumulated value.

Old (lines 23–24):
```gdscript
	var result := CombatCalculator.resolve_hit(
		count * power_per_token, damage_type, crit_chance, chance_tier, source, owner)
```

New:
```gdscript
	var temp_scalings: Array[StatScaling] = []
	var temp: StatScaling = StatScaling.new()
	temp.stat = "Phys.Atk" if CombatCalculator.is_physical(damage_type) else "Magic.Atk"
	temp.scaling = count * scaling_per_token
	temp_scalings.append(temp)

	var result := CombatCalculator.resolve_hit(
		temp_scalings, damage_type, crit_chance, chance_tier, source, owner)
```

Add preload at top (after line 4):
```gdscript
const StatScalingRes = preload("res://scripts/combat/stats/StatScaling.gd")
```

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/tokens/RuntimeToken_Envenom.gd
git commit -m "feat: RuntimeToken_Envenom uses scaling_per_token float, builds temp StatScaling"
```

---

### Task 5: Update RuntimeToken_Counter

**Files:**
- Modify: `scripts/combat/tokens/RuntimeToken_Counter.gd`

- [ ] **Step 1: Replace `power: int` with `stat_scalings: Array[StatScaling]`**

Old (line 4):
```gdscript
@export var power: int = 15
```

New:
```gdscript
@export var stat_scalings: Array[StatScaling] = []
```

Add preload at top (after line 2):
```gdscript
const StatScalingRes = preload("res://scripts/combat/stats/StatScaling.gd")
```

_Note: extends RuntimeToken, which is on line 1. Preload after `extends`._

- [ ] **Step 2: Update `fire()` call**

Old (lines 15–19):
```gdscript
	var result := CombatCalculator.resolve_hit(
		power,
		ResistanceType.DamageType.Slash,
		5,
		Skill_Effect_Base.ChanceTier.HIGH,
		owner,
		attacker
	)
```

New:
```gdscript
	var result := CombatCalculator.resolve_hit(
		stat_scalings,
		ResistanceType.DamageType.Slash,
		5,
		Skill_Effect_Base.ChanceTier.HIGH,
		owner,
		attacker
	)
```

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/tokens/RuntimeToken_Counter.gd
git commit -m "feat: RuntimeToken_Counter uses stat_scalings Array instead of int power"
```

---

### Task 6: Update RuntimeToken_Vigil

**Files:**
- Modify: `scripts/combat/tokens/RuntimeToken_Vigil.gd`

- [ ] **Step 1: Replace `power: int` with `stat_scalings: Array[StatScaling]`**

Old (line 4):
```gdscript
@export var power: int = 15
```

New:
```gdscript
@export var stat_scalings: Array[StatScaling] = []
```

Add preload:
```gdscript
const StatScalingRes = preload("res://scripts/combat/stats/StatScaling.gd")
```

- [ ] **Step 2: Update `fire()` to use the new `calc_damage` signature**

Vigil calls `calc_damage` directly (not `resolve_hit`). Old (lines 16–17):
```gdscript
	var atk: int = owner.stats.stat(CharacterStats.Stat.AtkMag)
	var amount: int = CombatCalculator.calc_damage(power, atk, 0)
```

New — uses the `stat_scalings` array and `owner.stats`:
```gdscript
	var amount: int = CombatCalculator.calc_damage(stat_scalings, owner.stats, 0)
```

Remove the `var atk` line entirely.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/tokens/RuntimeToken_Vigil.gd
git commit -m "feat: RuntimeToken_Vigil uses stat_scalings Array instead of int power"
```

---

### Task 7: Add character_owner to MnemonicResource

**Files:**
- Modify: `scripts/combat/skills/MnemonicResource.gd`

- [ ] **Step 1: Add the field**

After `rank` line (line 14), insert:
```gdscript
@export var character_owner: Array[String] = []
```

The full field block becomes:
```gdscript
@export var mnemonic_name: String = ""
@export var ap_generates: int = 0
@export_range(0, 9) var ap_cost: int = 0
@export var ap_generation_bonuses: Dictionary = {}
@export var ap_reduction_conditions: Dictionary = {}
@export var mp_cost: int = 0
@export var hp_cost_percent: float = 0.0
@export var rank: int = 1
@export var character_owner: Array[String] = []
@export var is_melee: bool = true
@export var merge_display: bool = true
@export var targeting: TargetingDataScript
@export var effect_steps: Array[SkillEffectBase] = []
@export var requires_token_on_enemy: String = ""
```

Empty array = anyone can equip. Values are lowercase character names like `"skugge"`, `"vargi"`.

- [ ] **Step 2: Commit**

```bash
git add scripts/combat/skills/MnemonicResource.gd
git commit -m "feat: add character_owner field to MnemonicResource"
```

---

### Task 8: Filter mnemonics by character_owner in CombatCharacter

**Files:**
- Modify: `scripts/combat/CombatCharacter.gd`

- [ ] **Step 1: Add owner filtering in `initialize_player`**

Old (lines 25–27):
```gdscript
	var base_attack: MnemonicRes = BasicAttack.duplicate() as MnemonicRes
	mnemonics = [base_attack]
	mnemonics.append_array(data.mnemonics)
```

New:
```gdscript
	var base_attack: MnemonicRes = BasicAttack.duplicate() as MnemonicRes
	mnemonics = [base_attack]

	var char_id: String = data.character_name.to_lower()
	for mnemonic in data.mnemonics:
		if mnemonic.character_owner.is_empty():
			mnemonics.append(mnemonic)
			continue
		var owner_lowered: Array[String] = []
		for owner in mnemonic.character_owner:
			owner_lowered.append(owner.to_lower())
		if char_id in owner_lowered:
			mnemonics.append(mnemonic)
		else:
			Log.info("mnemonic owner mismatch", "%s not owned by %s" % [mnemonic.mnemonic_name, char_id])
```

- [ ] **Step 2: Commit**

```bash
git add scripts/combat/CombatCharacter.gd
git commit -m "feat: filter mnemonics by character_owner during player init"
```

---

### Task 9: Update .tres files — stat_scalings (damage tokens)

**Files:**
- `resources/mnemonics/basic_attack/basic_attack.tres`
- `resources/mnemonics/uskrav/uskrav_tergo_lupi.tres`
- `resources/mnemonics/viper_strike/viper_strike.tres`
- `resources/mnemonics/strike/enemy_basic_strike.tres`

**Power mapping (old int → new scaling × stat):**

| Mnemonic | Old Power | New Scaling | Stat |
|----------|-----------|-------------|------|
| basic_attack | 10 (default) | 1.0 | Phys.Atk |
| uskrav | 30 | 1.5 | Phys.Atk |
| viper_strike | 25 | 1.25 | Phys.Atk |
| enemy_basic_strike | 15 | 0.75 | Phys.Atk |

- [ ] **Step 1: Update `basic_attack.tres`**

The `[sub_resource type="Resource" id="Resource_dmg"]` block currently has:
```
script = ExtResource("3_damage")
```
No `power` line (uses default 10). Add stat_scalings:

Add a new ext_resource for StatScaling at the top of the file, then change the sub_resource. The final file:

```
[gd_resource type="Resource" script_class="MnemonicResource" format=3 uid="uid://t6tu3r7k0r70"]

[ext_resource type="Script" uid="uid://cctdg0o2mn235" path="res://scripts/combat/skills/effects/Skill_Effect_Base.gd" id="1_base"]
[ext_resource type="Script" uid="uid://drcvu0qn608jt" path="res://scripts/combat/skills/effects/Skill_Effect_Instant.gd" id="2_instant"]
[ext_resource type="Script" uid="uid://bqwo4712edpli" path="res://scripts/combat/tokens/RuntimeToken_Damage.gd" id="3_damage"]
[ext_resource type="Script" uid="uid://b237vbpqp01dw" path="res://scripts/combat/skills/MnemonicResource.gd" id="4_mnemonic"]
[ext_resource type="Resource" path="res://resources/mnemonics/targeting_single_enemy.tres" id="5_target"]
[ext_resource type="Script" path="res://scripts/combat/stats/StatScaling.gd" id="6_ss"]

[sub_resource type="Resource" id="Resource_scaling"]
script = ExtResource("6_ss")
stat = "Phys.Atk"
scaling = 1.0

[sub_resource type="Resource" id="Resource_dmg"]
script = ExtResource("3_damage")
stat_scalings = Array[ExtResource("6_ss")]([SubResource("Resource_scaling")])

[sub_resource type="Resource" id="Resource_effect"]
script = ExtResource("2_instant")
token = SubResource("Resource_dmg")

[resource]
script = ExtResource("4_mnemonic")
mnemonic_name = "Attack"
ap_generates = 1
targeting = ExtResource("5_target")
effect_steps = Array[ExtResource("1_base")]([SubResource("Resource_effect")])
```

- [ ] **Step 2: Update `uskrav_tergo_lupi.tres`**

Current `Resource_dmg` sub-resource has `power = 30`. Replace with stat_scalings. The full updated file:

```
[gd_resource type="Resource" script_class="MnemonicResource" format=3 uid="uid://cbkgtwihvevg2"]

[ext_resource type="Script" uid="uid://cctdg0o2mn235" path="res://scripts/combat/skills/effects/Skill_Effect_Base.gd" id="1_537wx"]
[ext_resource type="Script" uid="uid://drcvu0qn608jt" path="res://scripts/combat/skills/effects/Skill_Effect_Instant.gd" id="2_instant"]
[ext_resource type="Script" uid="uid://bqwo4712edpli" path="res://scripts/combat/tokens/RuntimeToken_Damage.gd" id="3_damage"]
[ext_resource type="Script" uid="uid://b237vbpqp01dw" path="res://scripts/combat/skills/MnemonicResource.gd" id="4_u5tj5"]
[ext_resource type="Script" uid="uid://c0nmnx3d2582y" path="res://scripts/combat/skills/TargetingData.gd" id="5_8gwnu"]
[ext_resource type="Script" path="res://scripts/combat/stats/StatScaling.gd" id="6_ss"]

[sub_resource type="Resource" id="Resource_scaling"]
script = ExtResource("6_ss")
stat = "Phys.Atk"
scaling = 1.5

[sub_resource type="Resource" id="Resource_dmg"]
script = ExtResource("3_damage")
stat_scalings = Array[ExtResource("6_ss")]([SubResource("Resource_scaling")])

[sub_resource type="Resource" id="Resource_effect"]
script = ExtResource("2_instant")
token = SubResource("Resource_dmg")

[sub_resource type="Resource" id="Resource_targeting"]
script = ExtResource("5_8gwnu")

[resource]
script = ExtResource("4_u5tj5")
mnemonic_name = "Uskrav"
ap_generates = 1
character_owner = Array[String](["skugge"])
targeting = SubResource("Resource_targeting")
effect_steps = Array[ExtResource("1_537wx")]([SubResource("Resource_effect")])
```

- [ ] **Step 3: Update `viper_strike.tres`**

Replace the entire file:

```
[gd_resource type="Resource" script_class="MnemonicResource" format=3 uid="uid://bevbhr88aabfj"]

[ext_resource type="Script" uid="uid://cctdg0o2mn235" path="res://scripts/combat/skills/effects/Skill_Effect_Base.gd" id="1_n4wrn"]
[ext_resource type="Script" uid="uid://drcvu0qn608jt" path="res://scripts/combat/skills/effects/Skill_Effect_Instant.gd" id="2_instant"]
[ext_resource type="Script" uid="uid://bqwo4712edpli" path="res://scripts/combat/tokens/RuntimeToken_Damage.gd" id="3_damage"]
[ext_resource type="Script" uid="uid://buh8rpxl1kj84" path="res://scripts/combat/skills/effects/Skill_Effect_Grant.gd" id="4_grant"]
[ext_resource type="Script" uid="uid://dhdkuku3cjs5b" path="res://scripts/combat/tokens/RuntimeToken_Poison.gd" id="5_poison"]
[ext_resource type="Script" uid="uid://b237vbpqp01dw" path="res://scripts/combat/skills/MnemonicResource.gd" id="6_wtefk"]
[ext_resource type="Resource" path="res://resources/mnemonics/targeting_single_enemy.tres" id="7_target"]
[ext_resource type="Script" path="res://scripts/combat/stats/StatScaling.gd" id="8_ss"]

[sub_resource type="Resource" id="Resource_scaling"]
script = ExtResource("8_ss")
stat = "Phys.Atk"
scaling = 1.25

[sub_resource type="Resource" id="Resource_dmg"]
script = ExtResource("3_damage")
stat_scalings = Array[ExtResource("8_ss")]([SubResource("Resource_scaling")])
damage_type = 1
inherit_from_weapon = false

[sub_resource type="Resource" id="Resource_instant"]
script = ExtResource("2_instant")
token = SubResource("Resource_dmg")

[sub_resource type="Resource" id="Resource_poison"]
script = ExtResource("5_poison")

[sub_resource type="Resource" id="Resource_grant"]
script = ExtResource("4_grant")
token = SubResource("Resource_poison")
amount = 3
needs_previous_hit = true

[resource]
script = ExtResource("6_wtefk")
mnemonic_name = "Viper Strike"
ap_generates = 1
character_owner = Array[String](["skugge"])
targeting = ExtResource("7_target")
effect_steps = Array[ExtResource("1_n4wrn")]([SubResource("Resource_instant"), SubResource("Resource_grant")])
```

- [ ] **Step 4: Update `enemy_basic_strike.tres`**

Replace the entire file:

```
[gd_resource type="Resource" script_class="MnemonicResource" format=3]

[ext_resource type="Script" path="res://scripts/combat/skills/effects/Skill_Effect_Base.gd" id="1_0v4da"]
[ext_resource type="Script" path="res://scripts/combat/skills/effects/Skill_Effect_Instant.gd" id="2_instant"]
[ext_resource type="Script" path="res://scripts/combat/tokens/RuntimeToken_Damage.gd" id="3_damage"]
[ext_resource type="Script" path="res://scripts/combat/skills/MnemonicResource.gd" id="4_gmsnc"]
[ext_resource type="Script" path="res://scripts/combat/skills/TargetingData.gd" id="5_pxevm"]
[ext_resource type="Script" path="res://scripts/combat/stats/StatScaling.gd" id="6_ss"]

[sub_resource type="Resource" id="Resource_scaling"]
script = ExtResource("6_ss")
stat = "Phys.Atk"
scaling = 0.75

[sub_resource type="Resource" id="Resource_dmg"]
script = ExtResource("3_damage")
stat_scalings = Array[ExtResource("6_ss")]([SubResource("Resource_scaling")])
damage_type = 2
inherit_from_weapon = false
crit_chance = 3

[sub_resource type="Resource" id="Resource_effect"]
script = ExtResource("2_instant")
token = SubResource("Resource_dmg")

[sub_resource type="Resource" id="Resource_targeting"]
script = ExtResource("5_pxevm")

[resource]
script = ExtResource("4_gmsnc")
mnemonic_name = "Strike"
ap_generates = 0
targeting = SubResource("Resource_targeting")
effect_steps = Array[ExtResource("1_0v4da")]([SubResource("Resource_effect")])
```

- [ ] **Step 5: Commit**

```bash
git add resources/mnemonics/basic_attack/basic_attack.tres resources/mnemonics/uskrav/uskrav_tergo_lupi.tres resources/mnemonics/viper_strike/viper_strike.tres resources/mnemonics/strike/enemy_basic_strike.tres
git commit -m "feat: update damage token .tres files from int power to StatScaling array"
```

---

### Task 10: Update .tres files — stat_scalings (non-damage tokens) + character_owner

**Files:**
- `resources/mnemonics/envenom/envenom.tres`
- `resources/mnemonics/counter_stance/counter_stance.tres`
- `resources/mnemonics/vigil_stance/vigil_stance.tres`

- [ ] **Step 1: Update `envenom.tres`**

Replace the entire file:

```
[gd_resource type="Resource" script_class="MnemonicResource" format=3 uid="uid://cta281r5h2bh3"]

[ext_resource type="Script" uid="uid://cctdg0o2mn235" path="res://scripts/combat/skills/effects/Skill_Effect_Base.gd" id="1_base"]
[ext_resource type="Script" uid="uid://drcvu0qn608jt" path="res://scripts/combat/skills/effects/Skill_Effect_Instant.gd" id="2_instant"]
[ext_resource type="Script" uid="uid://ccalyaim6eaoh" path="res://scripts/combat/tokens/RuntimeToken_Envenom.gd" id="3_envenom"]
[ext_resource type="Script" uid="uid://b237vbpqp01dw" path="res://scripts/combat/skills/MnemonicResource.gd" id="4_mnemonic"]
[ext_resource type="Resource" path="res://resources/mnemonics/targeting_single_enemy.tres" id="5_target"]

[sub_resource type="Resource" id="Resource_envenom"]
script = ExtResource("3_envenom")
scaling_per_token = 1.0

[sub_resource type="Resource" id="Resource_instant"]
script = ExtResource("2_instant")
token = SubResource("Resource_envenom")

[resource]
script = ExtResource("4_mnemonic")
mnemonic_name = "Envenom"
ap_cost = 3
ap_reduction_conditions = {
"POISON": 2
}
character_owner = Array[String](["skugge"])
targeting = ExtResource("5_target")
effect_steps = Array[ExtResource("1_base")]([SubResource("Resource_instant")])
requires_token_on_enemy = "POISON"
```

- [ ] **Step 2: Update `counter_stance.tres`**

Replace the entire file:

```
[gd_resource type="Resource" script_class="MnemonicResource" format=3 uid="uid://cp5soyo7q7xj8"]

[ext_resource type="Script" uid="uid://cctdg0o2mn235" path="res://scripts/combat/skills/effects/Skill_Effect_Base.gd" id="1_base"]
[ext_resource type="Script" uid="uid://buh8rpxl1kj84" path="res://scripts/combat/skills/effects/Skill_Effect_Grant.gd" id="2_grant"]
[ext_resource type="Script" uid="uid://wc1i308m1wur" path="res://scripts/combat/tokens/RuntimeToken_Counter.gd" id="3_counter"]
[ext_resource type="Script" uid="uid://b237vbpqp01dw" path="res://scripts/combat/skills/MnemonicResource.gd" id="4_mnemonic"]
[ext_resource type="Script" uid="uid://c0nmnx3d2582y" path="res://scripts/combat/skills/TargetingData.gd" id="5_qgfp7"]
[ext_resource type="Script" path="res://scripts/combat/stats/StatScaling.gd" id="6_ss"]

[sub_resource type="Resource" id="Resource_counter_scaling"]
script = ExtResource("6_ss")
stat = "Phys.Atk"
scaling = 0.75

[sub_resource type="Resource" id="Resource_xh22d"]
script = ExtResource("3_counter")
stat_scalings = Array[ExtResource("6_ss")]([SubResource("Resource_counter_scaling")])
metadata/_custom_type_script = "uid://wc1i308m1wur"

[sub_resource type="Resource" id="Resource_grant"]
script = ExtResource("2_grant")
token = SubResource("Resource_xh22d")
amount = 2

[sub_resource type="Resource" id="Resource_2k065"]
script = ExtResource("5_qgfp7")
shape = 1
filter = 1
metadata/_custom_type_script = "uid://c0nmnx3d2582y"

[resource]
script = ExtResource("4_mnemonic")
mnemonic_name = "Counter Stance"
character_owner = Array[String](["vargi"])
targeting = SubResource("Resource_2k065")
effect_steps = Array[ExtResource("1_base")]([SubResource("Resource_grant")])
```

- [ ] **Step 3: Update `vigil_stance.tres`**

Replace the entire file:

```
[gd_resource type="Resource" script_class="MnemonicResource" format=3 uid="uid://bei7u38wuqejm"]

[ext_resource type="Script" uid="uid://cctdg0o2mn235" path="res://scripts/combat/skills/effects/Skill_Effect_Base.gd" id="1_base"]
[ext_resource type="Script" uid="uid://buh8rpxl1kj84" path="res://scripts/combat/skills/effects/Skill_Effect_Grant.gd" id="2_grant"]
[ext_resource type="Script" uid="uid://cyp68t16p77gp" path="res://scripts/combat/tokens/RuntimeToken_Vigil.gd" id="3_vigil"]
[ext_resource type="Script" uid="uid://b237vbpqp01dw" path="res://scripts/combat/skills/MnemonicResource.gd" id="4_mnemonic"]
[ext_resource type="Resource" uid="uid://bsauqqvhcjq0x" path="res://resources/mnemonics/targeting_self.tres" id="5_self"]
[ext_resource type="Script" path="res://scripts/combat/stats/StatScaling.gd" id="6_ss"]

[sub_resource type="Resource" id="Resource_vigil_scaling"]
script = ExtResource("6_ss")
stat = "Magic.Atk"
scaling = 0.75

[sub_resource type="Resource" id="Resource_vigil"]
script = ExtResource("3_vigil")
stat_scalings = Array[ExtResource("6_ss")]([SubResource("Resource_vigil_scaling")])

[sub_resource type="Resource" id="Resource_grant"]
script = ExtResource("2_grant")
token = SubResource("Resource_vigil")
amount = 2

[resource]
script = ExtResource("4_mnemonic")
mnemonic_name = "Vigil Stance"
character_owner = Array[String](["vargi"])
targeting = ExtResource("5_self")
effect_steps = Array[ExtResource("1_base")]([SubResource("Resource_grant")])
```

- [ ] **Step 4: Commit**

```bash
git add resources/mnemonics/envenom/envenom.tres resources/mnemonics/counter_stance/counter_stance.tres resources/mnemonics/vigil_stance/vigil_stance.tres
git commit -m "feat: update envenom/counter/vigil .tres for stat_scalings and character_owner"
```

---

### Task 11: Run and verify

- [ ] **Step 1: Launch the game**

```bash
godot --path /home/bart/Projects/neverworld-v-2
```

- [ ] **Step 2: Trigger a combat encounter and verify:**
  - Basic Attack deals ~AtkPhys × 1.0 damage (unchanged feel from old Power=10 default)
  - Uskrav deals more than Basic Attack (1.5× scaling) and generates +1 AP
  - Envenom consumes POISON stacks and deals `count × 1.0 × AtkPhys` damage
  - Counter stance retaliates for 0.75× scaling
  - Vigil heals for 0.75× Magic.Atk scaling
  - No console errors (check Godot Output panel for any type mismatch or null dereference)

- [ ] **Step 3: Check Outp ut for log entries:**
  - `"character ready"` — characters should initialize without errors
  - `"mnemonic owner mismatch"` — should NOT appear for any mnemonic equipped on the right character. If Skugge has viper_strike, it should load. If any mnemonic is silently filtered due to owner mismatch, the log will tell you.
  - `"RuntimeToken_Damage"` — damage numbers should appear, confirming the pipeline works end-to-end
