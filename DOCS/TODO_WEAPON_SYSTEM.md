# TODO — Weapon System & Basic Attack Design

> Written after the enemy skill split (2026-06-07).
> Context: we just made enemy basic attacks inline on `EnemyData` (flat damage, authored per enemy).
> Player basic attacks are still a shared `MnemonicResource` file. This note captures why that
> needs to change and what a weapon system would need to resolve.

---

## 1. The Immediate Bug

`resources/mnemonics/basic_attack/basic_attack.tres` has `stat = 6` in its `StatScaling`.
After removing `MaxAP`/`CurAP` from the `CharacterStats` enum, index 6 is now `Hit`, not `AtkPhys`.

**Impact:** Player basic attacks scale off `Hit` instead of `AtkPhys`. They do garbage damage.

**Quick fix options:**
- A. Fix the `.tres` to `stat = 4` (AtkPhys) — one minute, but the file stays fragile.
- B. Generate player basic attack at runtime, same as enemies — no `.tres`, no enum drift.

**Recommendation:** B. The `.tres` adds nothing a runtime constructor can't do, and it's one
less file to accidentally break when the enum shifts again.

---

## 2. Weapon-Driven Damage Type

**Current state:** `RuntimeToken_Damage` has:

```gdscript
@export var inherit_from_weapon: bool = true

static func _get_weapon_damage_type() -> ResistanceType.DamageType:
    # TODO: read from attacker's equipped weapon once gear system exists.
    return ResistanceType.DamageType.Slash
```

This was always the plan. We just never built gear.

**Design rule:** For any physical skill (including basic attack), the weapon decides
the damage type *unless* the skill explicitly overrides it (`inherit_from_weapon = false`).

Examples:
- Basic attack with a spear → Pierce
- "Rend" skill with a spear → Pierce (inherits)
- "Shield Bash" skill → always Blunt (override, regardless of weapon)
- "Fireball" skill → always Fire (magic, weapon ignored)

**What the weapon resource needs:**
- `damage_type: ResistanceType.DamageType` (Slash / Pierce / Blunt)

---

## 3. Weapon-Driven Scaling Stat

**This is the open question.**

Most weapons use `AtkPhys`. A "Soul Reaver" or "Crystal Staff" might use `AtkMag` for basic attacks.
But what about *skills*?

**Option A — Weapon scaling stat only affects basic attack**
- Basic attack: `stat_scalings = [weapon.scaling_stat × 1.0]`
- Skills: use whatever the skill author wrote (usually `AtkPhys`)
- Soul Reaver user still uses `AtkPhys` for "Rend", but `AtkMag` for basic attack
- *Pros:* Skills are honest. A slash skill is a slash skill.
- *Cons:* Soul Reaver user might feel their weapon identity doesn't extend to skills.

**Option B — Weapon scaling stat can override skills**
- Skills have a flag: `use_weapon_scaling_stat: bool = false`
- If true, the skill replaces its own `stat_scalings` with `[weapon.scaling_stat × skill_total_scaling]`
- *Pros:* Soul Reaver feels coherent. "Rend" scales off Mag.Atk because the weapon is magical.
- *Cons:* Every physical skill needs that flag. Designer overhead. Risk of "everything is the same" feel.

**Option C — Hybrid weapons are just stat sticks**
- Soul Reaver gives `+AtkMag`, player invests in `AtkMag`, skills that scale `AtkMag` work
- Basic attack is the *only* place that auto-scales off the weapon's preferred stat
- *Pros:* Simple. Build-craft drives identity, not a hidden weapon override.
- *Cons:* Requires skills that scale `AtkMag` but deal physical damage. Is that allowed?

**My gut:** Option A for now. Basic attack is the only thing that reads the weapon's scaling stat.
Skills are authored with explicit scalings. If we want a "magical melee" build, we author skills
that scale `AtkMag` and deal physical damage. The weapon's job is damage type + maybe a passive.

But this needs to be a conscious design call, not an accident.

---

## 4. What a Minimal Weapon Resource Looks Like

```gdscript
class_name WeaponData
extends Resource

@export var weapon_name: String = ""
@export var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Slash
@export var scaling_stat: CharacterStats.Stat = CharacterStats.Stat.AtkPhys
@export var slot_count: int = 0  # mnemonic slots on the weapon
# stats granted while equipped:
@export var bonus_atk_phys: int = 0
@export var bonus_atk_mag: int = 0
@export var bonus_hit: int = 0
# etc.
```

`CombatCharacter` (or a future `GearComponent`) holds the equipped weapon.
`RuntimeToken_Damage._get_weapon_damage_type()` queries it.
`CombatCharacter.initialize_player` generates the basic attack using `weapon.scaling_stat`.

---

## 5. Player Basic Attack — Runtime Generation

Once weapons exist, the player basic attack should be generated at runtime in
`CombatCharacter.initialize_player`, same pattern as enemies:

```gdscript
var basic := MnemonicResource.new()
basic.mnemonic_name = "Attack"
basic.ap_cost = 0
basic.ap_generates = 1

var scaling := StatScaling.new()
scaling.stat = _equipped_weapon.scaling_stat  # AtkPhys or AtkMag
scaling.scaling = 1.0

var dmg := RuntimeToken_Damage.new()
dmg.stat_scalings = [scaling]
dmg.damage_type = _equipped_weapon.damage_type
dmg.inherit_from_weapon = false  # we already resolved it

var effect := Skill_Effect_Instant.new()
effect.token = dmg
basic.effect_steps = [effect]
```

This eliminates `basic_attack.tres` entirely.

---

## 6. Enemy Basic Attack Is Already Solved

Enemies don't use weapons (per GDD). Their basic attack is inline on `EnemyData`:
- `base_attack_damage`
- `base_attack_type`
- `base_attack_crit_chance`
- `base_attack_chance_tier`

`CombatCharacter.initialize_enemy` builds the `EnemySkill` at runtime.
This works. Don't touch it.

---

## 7. Open Questions for Design

1. **Does a weapon ever change a skill's scaling stat?** (see §3)
2. **Do two-handed weapons get different damage types?** (e.g., greatsword = Slash, halberd = Pierce)
3. **Do unarmed attacks have a default damage type?** (probably Blunt)
4. **Do ranged weapons use a different stat?** (e.g., bows use Hit instead of AtkPhys for basic?)
5. **Does weapon damage type affect ailment tokens?** (e.g., a Poison skill — does the weapon type matter?)
6. **Should `RuntimeToken_Damage` keep `inherit_from_weapon` once gear exists, or should the
   skill/attack author just resolve it before creating the token?**

---

## 8. Immediate Action Items

- [ ] Decide on §3 (weapon scaling stat scope) and document in GDD.
- [ ] Generate player basic attack at runtime OR fix `basic_attack.tres` enum bug as temp band-aid.
- [ ] Remove `basic_attack.tres` once runtime generation is in.
- [ ] Build `WeaponData` resource when gear system starts.
- [ ] Wire `RuntimeToken_Damage._get_weapon_damage_type()` to read from equipped weapon.
- [ ] Update `PlayerCard` AP bar if weapon system changes max AP (unlikely, but flag it).

---

## 9. Files Touched by This Session (for reference)

| File | What changed |
|------|-------------|
| `scripts/characters/CombatData.gd` | Stripped `MaxMP`, `MaxAP`, `AtkPhys`, `AtkMag` (moved to `PlayerData`) |
| `scripts/characters/PlayerData.gd` | Added `MaxMP`, `AtkPhys`, `AtkMag`; removed `MaxAP` |
| `scripts/characters/EnemyData.gd` | Removed `basic_attack: EnemySkill`; added inline basic attack fields |
| `scripts/characters/stats/CharacterStats.gd` | Removed `MaxAP`, `CurAP` from enum |
| `scripts/combat/StatCalculator.gd` | `compute_enemy` no longer fills dead stats; `compute_player` no longer reads `MaxAP` |
| `scripts/combat/CombatCharacter.gd` | `initialize_enemy` builds basic `EnemySkill` at runtime |
| `scripts/combat/CombatCalculator.gd` | Added `calc_flat_damage`; `resolve_hit` branches on `base_damage` |
| `scripts/combat/tokens/RuntimeToken_Damage.gd` | Added `base_damage` field |
| `scripts/combat/skills/EnemySkill.gd` | New resource for enemy special abilities |
| `scripts/combat/ui/PlayerCard.gd` | AP bar max now reads `VitalsComponent.AP_CAP` |
| `DOCS/GDD_V3.md` | Added Enemy Skill Authoring section |
| `resources/characters/enemy/VarnWolf.tres` | Uses inline basic attack fields |

---

*End of note. Next design discussion: gear system scope, or §3 scaling stat decision.*
