# Combat HUD — Design Spec
**Date:** 2026-04-16
**Status:** AGREED — ready for implementation plan
**Scope:** The in-combat HUD — enemy nameplates, player cards, shared UI sub-components, and the resistance overlay during targeting. No combat loop mechanics, no command menu, no skill list.

---

## Purpose

Define the layout and data connections for the combat HUD so that the token system, vitals bars, and AP economy are all readable at a glance for both parties.

This spec supersedes the token visualization section of `2026-04-13-combat-visuals-design.md` and resolves Open Questions #3 and #4 from that spec. It also drives targeted amendments to that spec (see end of this document).

---

## Guiding Principles

1. **All identity information lives in the HUD.** Nameplates, tokens, resource bars — none of it floats in world space. The world contains only sprites, VFX, and combat text.
2. **Symmetry.** Enemies and players expose the same resources (HP, MP, AP, tokens). The HUD reflects this — same components, different palette.
3. **Clutter deferred, not eliminated.** Resistance information exists but is hidden until the moment it's relevant: targeting mode. Everything else is always visible.
4. **Shared components.** `TokenDisplay.tscn`, `HPBar.tscn` and `MPBar.tscn`, and `APStrip.tscn` are instanced in both enemy nameplates and player cards. One scene, many hosts.

---

## Scope

### In scope
- `CombatHUD` scene — top-level canvas layer containing both strips
- `EnemyNameplate.tscn` — enemy identity card
- `CombatCard.tscn` — player identity card
- `TokenDisplay.tscn` — shared token icon row, instanced in both cards
- `HPBar.tscn` and `MPBar.tscn` — shared HP | MP bar, instanced in both cards
- `APStrip.tscn` — shared segmented AP display (10 cells), instanced in both cards
- Enemy nameplate ordering, dead-enemy handling, targeting bump
- Resistance overlay during targeting mode

### Out of scope
- `CombatText.tscn` internals — own spec
- Token icon artwork and styling — own spec
- `CombatCard` command menu / skill list / item list — own spec
- Inspect view (full enemy data panel) — deferred, out of vertical slice scope
- Combat camera — own spec

---

## HUD Structure

```
CombatHUD (CanvasLayer)
  ├── EnemyStrip (HBoxContainer)     — anchored top of screen, left-to-right
  │     └── EnemyNameplate × 1–6    — one per active enemy slot, spawned at combat start
  └── PlayerStrip (HBoxContainer)   — anchored bottom of screen
        └── CombatCard × 3          — one per player, spawned at combat start
```

`CombatHUD` lives in the combat scene as a `CanvasLayer`. It is not an autoload. Spawning and wiring happen during `FSMSTATE_CombatEntry`.

---

## Shared Sub-components

### `TokenDisplay.tscn`

An `HFlowContainer` (or `HBoxContainer`) of token icon nodes. Empty until tokens are applied; collapses to zero height when empty.

- Subscribes to `ActiveTokens.token_added`, `token_removed`, `token_updated` on the character it's assigned to.
- Each token icon shows: icon texture + charge count label (e.g. `☆3`).
- Does not own any game logic — display only.

Instanced **above** the resource bars on `CombatCard`, **below** the resource bars on `EnemyNameplate`. Same scene, different position in the host layout.

### `HPBar.tscn` and `MPBar.tscn`

Two independent `TextureProgressBar` scenes, placed side by side in the host layout's `HBoxContainer`:

- `HPBar` — green on `CombatCard`, red on `EnemyNameplate`. Subscribes to `VitalsComponent.hp_changed`.
- `MPBar` — blue on `CombatCard`, a darker muted colour on `EnemyNameplate`. Subscribes to `VitalsComponent.mp_changed`.

Smooth fill, percentage-based. No number label — the bar is the readout.

**On `EnemyNameplate`:** both bars are replaced entirely by a single `?` label until the enemy type has been defeated at least once. You don't know their HP or MP scale until you've killed one. After first defeat the bars show normally. The unlock flag (`has_been_defeated`) lives on `EnemyData`, persisted to save data, and is set when `actor_downed` fires for that enemy type for the first time.

### `APStrip.tscn`

A row of **10 discrete cells** in an `HBoxContainer`. Each cell is a small coloured square — filled (purple) or empty (dark). Cells are updated as integers: `cur_ap` cells filled, the rest empty.

Subscribes to `VitalsComponent.ap_changed`. No smoothing — snaps immediately to the new integer value.

Same component, same palette (purple), used on both `CombatCard` and `EnemyNameplate`.

---

## `EnemyNameplate.tscn`

```
EnemyNameplate (PanelContainer)
  └── VBoxContainer
        ├── NameLabel (Label)              — enemy name; letter suffix if duplicates (e.g. "Draugr B")
        ├── ResourceRow (HBoxContainer)
        │     ├── HPBar (instanced)        — red
        │     └── MPBar (instanced)        — muted dark colour
        ├── APStrip (instanced)            — 10 cells, purple
        └── TokenDisplay (instanced)       — empty until tokens applied
```

**Targeting bump:** when this enemy is the current targeting cursor target, the nameplate's `position.y` shifts down by a small authored offset (e.g. 8px). Reverts when the cursor moves away or targeting ends.

**Dead enemy:** `hide()` the nameplate. The `HBoxContainer` layout closes the gap naturally. Slot order for living enemies is preserved — left-to-right always matches ascending slot index among survivors.

**Duplicate name disambiguation:** at spawn time, if two or more enemies share the same display name, append a letter suffix (`A`, `B`, `C`, …) in slot order.

---

## `CombatCard.tscn`

```
CombatCard (PanelContainer)
  └── VBoxContainer
        ├── TokenDisplay (instanced)       — empty until tokens applied
        ├── ResourceRow (HBoxContainer)
        │     ├── HPBar (instanced)        — green
        │     └── MPBar (instanced)        — blue
        ├── Portrait (TextureRect)         — character portrait; enemies have no portrait
        └── APStrip (instanced)            — 10 cells, purple, full width
```

Player cards are always visible. No hiding on KO — the card stays up, bars empty, so the player can see the downed character's resource state and plan a revive.

---

## Data Connections

Each card holds a typed reference to its `CombatCharacter`. Wired during `FSMSTATE_CombatEntry` when actors are spawned.

| Signal source | Subscriber | Effect |
|---|---|---|
| `VitalsComponent.hp_changed` | `HPBar` | Tween HP fill to new value |
| `VitalsComponent.mp_changed` | `MPBar` | Tween MP fill to new value |
| `VitalsComponent.ap_changed` | `APStrip` | Snap cells to new integer count |
| `ActiveTokens.token_added` | `TokenDisplay` | Spawn token icon |
| `ActiveTokens.token_removed` | `TokenDisplay` | Remove token icon |
| `ActiveTokens.token_updated` | `TokenDisplay` | Update charge count label |

Connections are made in `_ready()` after the character reference is assigned. Disconnected in `_exit_tree()`.

---

## Resistance Overlay (Targeting Mode)

When the player enters targeting mode for a skill with a known damage type, `EnemyStrip` shows discovered resistance badges on every enemy nameplate.

**Trigger:** `CombatEvents.targeting_started(skill: MnemonicData)` — emitted by the UI FSM's Targeting state when it activates. The signal definition lives in the UI FSM spec; this spec only consumes it.

**Behaviour:**
- `EnemyStrip` receives `targeting_started`. Reads `skill.damage_type`.
- For each live enemy nameplate: checks that enemy's `ResistanceProfile` for `skill.damage_type`, but only for **discovered** resistances.
  - `WEAK` (discovered) → show a `WEAK` badge
  - `RESISTANT` (discovered) → show a `RESIST` badge
  - `IMMUNE` (discovered) → show an `IMMUNE` badge
  - Neutral (1×) → no badge even if discovered — not actionable information
  - **Undiscovered** → no badge
- Badges are simple `Label` nodes overlaid on the nameplate. Not part of the permanent layout.

**End:** `CombatEvents.targeting_ended` — all badges hidden.

### Resistance Discovery

A resistance is discovered the moment `attack_resolved` fires with a non-neutral outcome (`WEAK`, `RESISTED`, `IMMUNE`) for a given damage type against a given enemy type. The discovery is written immediately to `EnemyData` and persisted to save data — it does not wait for end of combat.

**This means:** if you cast Fireball at an Ifrit and it resolves as `RESISTED`, the Fire/RESIST entry is unlocked right then. The next time you enter targeting with a Fire skill in that same fight, the `RESIST` badge will appear on Ifrit's nameplate.

`MISS` and `PARRY` outcomes carry no element information and do not trigger discovery. Only outcomes with a damage type (`HIT`, `CRIT`, `WEAK`, `RESISTED`) do.

**Scope note:** the inspect view (showing the full resistance table outside of targeting) is deliberately out of scope for the vertical slice.

---

## Amendments to `2026-04-13-combat-visuals-design.md`

The following changes are required to keep the combat visuals spec consistent with this spec:

### Rename `TokenContainer` → `ActiveTokens` throughout
Data node on `combat_character` that holds token state and emits signals. "Container" implies a UI node in Godot; `ActiveTokens` is unambiguous.

### Remove from `combat_character.tscn` scene shape
- `TokenDisplay` (enemy-only child) — moved to HUD
- `NameplateAnchor (Node3D)` — nothing mounts here anymore
- `TokenAnchor (Node3D)` — nothing mounts here anymore

### Update `get_anchor()` on `CombatCharacter`
Remove the `&"nameplate"` and `&"token"` cases. Only `&"vfx"` and `&"combat_text"` remain.

### Update Anchors table
Remove `NameplateAnchor` and `TokenAnchor` rows.

### Update Token Visualization section
Replace the asymmetric player/enemy description with: both parties use `TokenDisplay.tscn` instanced in their respective HUD card. `ActiveTokens` on `combat_character` is the data source for both.

### Update Scope
- Remove from in-scope: "Token visualization asymmetry (players → `CombatCard` UI, enemies → in-world `TokenDisplay`)"
- Add to out-of-scope: "Combat HUD layout — see `2026-04-16-combat-hud-design.md`"

### Update Guiding Principle #5
Change from: "`TokenContainer` emits; consumers (`CombatCard` UI, enemy `TokenDisplay`) subscribe."
To: "`ActiveTokens` emits; `TokenDisplay.tscn` (instanced in both player cards and enemy nameplates) subscribes. The data node doesn't know who's listening."

### Close Open Questions #3 and #4
Mark as resolved, pointing to this spec.
