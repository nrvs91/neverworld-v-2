# Combat UI FSM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the combat UI layer — character cards for players and enemies, an action menu with stub skill selection, a targeting cursor, world-space damage numbers, and an info strip — then wire the `CombatUIFSM` that drives them all, replacing the 0.4s auto-select stub in `CombatFSM` with real player input.

**Architecture:** `CombatUIFSM` is a Node child of `CombatScene`, sitting alongside `CombatFSM`. It listens to `CombatEvents` and drives all UI. Character cards live in the existing `CombatUI` CanvasLayer (2D overlay). Damage numbers and the targeting cursor live in 3D world space alongside the characters.

`CombatFSM._enter_action_select()` now branches: **enemy turns** auto-pick a target via the old `_first_living_opponent()` logic (placeholder until enemy AI is built), and **player turns** suspend via `await CombatEvents.action_selected` while `CombatUIFSM` drives the player through menu → targeting → confirmation. The UI FSM emits `action_selected` to resume the logic FSM.

**Input scheme:**
- `combat_prev` / `combat_next` (A / D) — cycle menu categories
- `combat_up` / `combat_down` (W / S) — navigate items within a category
- During targeting: `combat_next` / `combat_down` → next target; `combat_prev` / `combat_up` → previous target
- `combat_confirm` (Enter / Space) — confirm selection
- `combat_cancel` (Escape / Backspace) — cancel / back

**Tech Stack:** GDScript 4, Godot 4.6, Godot Tween API, existing `CombatCharacter` / `VitalsComponent` / `StatsComponent` / `CombatEvents` infrastructure.

---

## File Map

| File | Status | Responsibility |
|------|--------|---------------|
| `scripts/combat/ui/CharacterCard.gd` | create | Card display: name, HP/MP/AP bars, nudge tween, refresh API |
| `scenes/combat/ui/character_card.tscn` | create | VBoxContainer: name label, portrait placeholder, three ProgressBars, token slot |
| `scripts/combat/ui/ActionMenu.gd` | create | ACT / ITEM / WAIT / RUN tabs + skill list; navigation methods; `action_chosen` signal |
| `scenes/combat/ui/action_menu.tscn` | create | Category tab row + skill VBoxContainer |
| `scripts/combat/ui/EnemyCardBar.gd` | create | Spawns / removes enemy cards; routes nudge and refresh calls by actor reference |
| `scenes/combat/ui/enemy_card_bar.tscn` | create | HBoxContainer anchored top-center |
| `scripts/combat/ui/PlayerCardBar.gd` | create | Spawns player cards with per-slot ActionMenu; active card management; re-emits `action_chosen` |
| `scenes/combat/ui/player_card_bar.tscn` | create | HBoxContainer anchored bottom-center, grows upward |
| `scripts/combat/ui/InfoPanel.gd` | create | Bottom strip: `show_text` / `hide_panel` |
| `scenes/combat/ui/info_panel.tscn` | create | Full-width PanelContainer + Label anchored to screen bottom |
| `scripts/combat/ui/TargetingCursor.gd` | create | Node3D cursor: cycles live actor candidates; emits hover / confirm / cancel signals |
| `scenes/combat/targeting_cursor.tscn` | create | Node3D with a small visible MeshInstance3D marker |
| `scripts/combat/ui/DamageNumber.gd` | create | World-space float-up + fade; emits `animation_finished` when done |
| `scenes/combat/ui/damage_number.tscn` | create | Node3D with Label3D (billboard, no depth test) |
| `scripts/combat/ui/CombatUIFSM.gd` | create | 5-state UI FSM; all input handling; wires CombatEvents to subsystems |
| `scripts/combat/CombatEvents.gd` | modify | Simplify `action_selected` from `(skill, target)` to `(target)` only |
| `scenes/combat/CharacterCard.gd` | delete | Placeholder — replaced entirely |
| `scripts/combat/CombatFSM.gd` | modify | `_enter_action_select()`: branch on `is_player_controlled` — enemies auto-pick, players await `CombatEvents.action_selected` |
| `scripts/combat/CombatScene.gd` | modify | Remove old card reference; add `ui_fsm` onready; call `ui_fsm.start(all_actors)` |
| `scenes/combat/combat_scene.tscn` | modify | Remove old CharacterCard node from CombatUI; add EnemyCardBar, PlayerCardBar, InfoPanel; add TargetingCursor (Node3D) and CombatUIFSM as scene-root children |

---

## Task 0 — Simplify `action_selected` Signal

**Files:**
- Modify: `scripts/combat/CombatEvents.gd`

The current signal has two arguments: `signal action_selected(skill: Resource, target: CombatCharacter)`. GDScript `await` on a signal returns **only the first argument**, so the original plan's `result[1]` would crash on `null`.

Simplify to a single `target` argument. When skills are added later, expand the payload as a single resource/dictionary object — never multiple signal args.

- [ ] **Step 1: Change the signal signature**

In `scripts/combat/CombatEvents.gd`, replace line 16:

```gdscript
signal action_selected(target: CombatCharacter)
```

- [ ] **Step 2: Commit**

```bash
git add scripts/combat/CombatEvents.gd
git commit -m "Simplify action_selected signal to single target arg for await compatibility"
```

---

## Task 1 — Define Combat Input Actions

**Files:**
- Modify: `project.godot` (via Godot Input Map)

- [ ] **Step 1: Add the 6 combat actions**

Open **Project → Project Settings → Input Map** and add:

| Action name | Keys |
|-------------|------|
| `combat_prev` | A, Left Arrow |
| `combat_next` | D, Right Arrow |
| `combat_up` | W, Up Arrow |
| `combat_down` | S, Down Arrow |
| `combat_confirm` | Enter, Space |
| `combat_cancel` | Escape, Backspace |

Or via MCP `configure_input_map` with the same entries.

- [ ] **Step 2: Commit**

```bash
git add project.godot
git commit -m "Add combat input actions to Input Map"
```

---

## Task 2 — CharacterCard

**Files:**
- Create: `scripts/combat/ui/CharacterCard.gd`
- Create: `scenes/combat/ui/character_card.tscn`

### Required Node Architecture

The code references these nodes by path. **Names and types must match exactly.**

```
CharacterCard (Control)         ← script: CharacterCard.gd
  VBox (VBoxContainer)
    NameLabel (Label)
    Portrait (ColorRect)
    Bars (VBoxContainer)
      HPBar (ProgressBar)
      MPBar (ProgressBar)
      APBar (ProgressBar)
    TokenContainer (HBoxContainer)
```

Code node paths:
- `$VBox/NameLabel` → `Label`
- `$VBox/Bars/HPBar` → `ProgressBar`
- `$VBox/Bars/MPBar` → `ProgressBar`
- `$VBox/Bars/APBar` → `ProgressBar`

`TokenContainer` is not referenced by code yet — it's a placeholder for the token system. Keep it in the tree, set `visible = false`.

### Styling Notes (Your Call)

- `custom_minimum_size` on root: ~`Vector2(80, 0)` as a starting point
- Portrait: ~64×64, grey placeholder until art is ready
- HP bar fill: green, MP: blue, AP: purple
- Name label: centered text
- These are rough defaults — adjust to taste, just don't break the node tree above.

- [ ] **Step 1: Create the scene**

Create `scenes/combat/ui/` folder. Create `scenes/combat/ui/character_card.tscn` with the node tree above. Attach `scripts/combat/ui/CharacterCard.gd` to the root node.

- [ ] **Step 2: Write the script**

Create `scripts/combat/ui/CharacterCard.gd`:

```gdscript
class_name CharacterCard
extends Control

const NUDGE_AMOUNT: float = 12.0
const NUDGE_DURATION: float = 0.12

@onready var name_label: Label = $VBox/NameLabel
@onready var hp_bar: ProgressBar = $VBox/Bars/HPBar
@onready var mp_bar: ProgressBar = $VBox/Bars/MPBar
@onready var ap_bar: ProgressBar = $VBox/Bars/APBar

var _actor: CombatCharacter = null

func setup(actor: CombatCharacter) -> void:
	_actor = actor
	name_label.text = actor.character_name
	hp_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxHP)
	mp_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxMP)
	ap_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxAP)
	refresh_vitals()

func refresh_vitals() -> void:
	if _actor == null:
		return
	hp_bar.value = _actor.vitals.cur_hp
	mp_bar.value = _actor.vitals.cur_mp
	ap_bar.value = _actor.vitals.cur_ap

func set_inactive() -> void:
	modulate.a = 0.5

func nudge(enabled: bool) -> void:
	var target_y: float = NUDGE_AMOUNT if enabled else 0.0
	var tween := create_tween()
	tween.tween_property(self, "offset_top", -target_y, NUDGE_DURATION)
```
> **Why `offset_top` instead of `position:y`?** Container nodes overwrite `position` on every layout pass. `offset_top` is respected by the layout engine as part of the child's anchor calculation, so it survives reflows (e.g. when an ActionMenu shows/hides in a sibling slot, or when a card is removed from the HBox).

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ui/CharacterCard.gd scenes/combat/ui/character_card.tscn
git commit -m "Add CharacterCard scene with HP/MP/AP bars and nudge tween"
```

---

## Task 3 — EnemyCardBar

**Files:**
- Create: `scripts/combat/ui/EnemyCardBar.gd`
- Create: `scenes/combat/ui/enemy_card_bar.tscn`

### Required Node Architecture

```
EnemyCardBar (HBoxContainer)  ← script: EnemyCardBar.gd
```

That's it. The bar spawns `CharacterCard` instances dynamically at runtime via `setup(enemies)`. No child nodes needed in the scene file.

### Styling Notes (Your Call)

- Anchor preset: Top Center (`anchor_left = 0.5, anchor_right = 0.5, anchor_top = 0.0, anchor_bottom = 0.0`)
- `offset_top = 8` to pull it down from the very top edge
- `alignment = ALIGNMENT_CENTER` so cards cluster in the middle
- Adjust spacing, padding, and container theme to taste

- [ ] **Step 1: Create the scene**

Create `scenes/combat/ui/enemy_card_bar.tscn` with the node tree above. Attach `scripts/combat/ui/EnemyCardBar.gd`.

- [ ] **Step 2: Write the script**

Create `scripts/combat/ui/EnemyCardBar.gd`:

```gdscript
class_name EnemyCardBar
extends HBoxContainer

const CharacterCardScene = preload("res://scenes/combat/ui/character_card.tscn")

var _cards: Dictionary = {}

func setup(enemies: Array) -> void:
	for child in get_children():
		child.queue_free()
	_cards.clear()
	for actor in enemies:
		var card := CharacterCardScene.instantiate() as CharacterCard
		add_child(card)
		card.setup(actor)
		_cards[actor] = card
	Log.info("EnemyCardBar — cards spawned:", _cards.size())

func remove_actor(actor: CombatCharacter) -> void:
	if not _cards.has(actor):
		return
	_cards[actor].queue_free()
	_cards.erase(actor)
	Log.info("EnemyCardBar — removed", actor.character_name)

func nudge_actor(actor: CombatCharacter, enabled: bool) -> void:
	if _cards.has(actor):
		_cards[actor].nudge(enabled)

func refresh_actor(actor: CombatCharacter) -> void:
	if _cards.has(actor):
		_cards[actor].refresh_vitals()
```

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ui/EnemyCardBar.gd scenes/combat/ui/enemy_card_bar.tscn
git commit -m "Add EnemyCardBar — spawns and manages enemy character cards"
```

---

## Task 4 — ActionMenu

**Files:**
- Create: `scripts/combat/ui/ActionMenu.gd`
- Create: `scenes/combat/ui/action_menu.tscn`

For this plan, ACT and WAIT are functional. ITEM and RUN are visible but do nothing when confirmed. ACT shows one "ATTACK" skill stub (slot 0) and three disabled "--" slots (slots 1–3). WAIT has no items — confirming on the WAIT tab immediately emits the signal.

### Required Node Architecture

The code references these nodes by path. **Names and types must match exactly.**

```
ActionMenu (VBoxContainer)    ← script: ActionMenu.gd
  Categories (HBoxContainer)
    BtnACT  (Button)
    BtnITEM (Button)
    BtnWAIT (Button)
    BtnRUN  (Button)
  SkillList (VBoxContainer)
    Skill0  (Button)
    Skill1  (Button)   ← disabled = true
    Skill2  (Button)   ← disabled = true
    Skill3  (Button)   ← disabled = true
```

Code node paths:
- `$SkillList` → `VBoxContainer` (the code calls `get_children()` on this to find skill buttons)
- `$Categories` → `HBoxContainer` (the code calls `get_children()` on this to find category buttons)

Button text defaults:
- Category buttons: "ACT", "ITEM", "WAIT", "RUN"
- Skill buttons: "ATTACK", "--", "--", "--"

Category buttons should have `toggle_mode = true` and `focus_mode = FOCUS_NONE` (the code manages selection state manually via `button_pressed`).

### Styling Notes (Your Call)

- `custom_minimum_size` on root: ~`Vector2(120, 0)` as a starting point
- Button sizes, fonts, colors, hover states — all your call
- SkillList visibility is toggled by the script (hidden on non-ACT tabs)
- Adjust spacing, padding, and container theme to taste

- [ ] **Step 1: Create the scene**

Create `scenes/combat/ui/action_menu.tscn` with the node tree above. All category buttons: `toggle_mode = true`, `focus_mode = FOCUS_NONE`. Attach `scripts/combat/ui/ActionMenu.gd`.

- [ ] **Step 2: Write the script**

Create `scripts/combat/ui/ActionMenu.gd`:

```gdscript
class_name ActionMenu
extends VBoxContainer

signal action_chosen(category: String, item_index: int)

const CATEGORIES: Array[String] = ["ACT", "ITEM", "WAIT", "RUN"]

@onready var skill_list: VBoxContainer = $SkillList
@onready var _category_buttons: Array = []

var _category_index: int = 0
var _item_index: int = 0

func _ready() -> void:
	for btn in $Categories.get_children():
		_category_buttons.append(btn)

func reset() -> void:
	_category_index = 0
	_item_index = 0
	_refresh_display()

func next_category() -> void:
	_category_index = (_category_index + 1) % CATEGORIES.size()
	_item_index = 0
	_refresh_display()

func prev_category() -> void:
	_category_index = (_category_index - 1 + CATEGORIES.size()) % CATEGORIES.size()
	_item_index = 0
	_refresh_display()

func next_item() -> void:
	var items := _active_skill_buttons()
	if items.is_empty():
		return
	_item_index = (_item_index + 1) % items.size()
	_refresh_display()

func prev_item() -> void:
	var items := _active_skill_buttons()
	if items.is_empty():
		return
	_item_index = (_item_index - 1 + items.size()) % items.size()
	_refresh_display()

func confirm() -> void:
	var category := CATEGORIES[_category_index]
	if category == "ITEM" or category == "RUN":
		Log.info("ActionMenu — stub, no action", category)
		return
	action_chosen.emit(category, _item_index)
	Log.info("ActionMenu chosen", category, _item_index)

func _active_skill_buttons() -> Array:
	if CATEGORIES[_category_index] != "ACT":
		return []
	return skill_list.get_children().filter(func(b: Button) -> bool: return not b.disabled)

func _refresh_display() -> void:
	var category := CATEGORIES[_category_index]
	for i in _category_buttons.size():
		_category_buttons[i].button_pressed = (i == _category_index)
	var is_act := (category == "ACT")
	skill_list.visible = is_act
	if is_act:
		var items := _active_skill_buttons()
		for i in items.size():
			items[i].button_pressed = (i == _item_index)
	Log.debug("ActionMenu", category, _item_index)
```

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ui/ActionMenu.gd scenes/combat/ui/action_menu.tscn
git commit -m "Add ActionMenu with ACT/WAIT functional tabs and stub skill list"
```

---

## Task 5 — PlayerCardBar

Each player slot is a `VBoxContainer` holding a `CharacterCard` (top) and an `ActionMenu` (bottom, hidden by default). The `HBoxContainer` is bottom-anchored and grows upward — when a slot's `ActionMenu` becomes visible, that slot gets taller and the card appears to bump up.

**Files:**
- Create: `scripts/combat/ui/PlayerCardBar.gd`
- Create: `scenes/combat/ui/player_card_bar.tscn`

### Required Node Architecture

```
PlayerCardBar (HBoxContainer)  ← script: PlayerCardBar.gd
```

That's it. The bar spawns slots dynamically at runtime via `setup(players)`. Each slot is a `VBoxContainer` created in code, containing a `CharacterCard` instance and an `ActionMenu` instance. No child nodes needed in the scene file.

### Styling Notes (Your Call)

- Anchor preset: Bottom Center (`anchor_left = 0.5, anchor_right = 0.5, anchor_top = 1.0, anchor_bottom = 1.0`)
- `grow_vertical = GROW_DIRECTION_BEGIN` so it grows upward from the bottom
- `offset_bottom = -8` to pull it up from the very bottom edge
- `alignment = ALIGNMENT_CENTER` so cards cluster in the middle
- Adjust spacing, padding, and container theme to taste

- [ ] **Step 1: Create the scene**

Create `scenes/combat/ui/player_card_bar.tscn` with the node tree above. Attach `scripts/combat/ui/PlayerCardBar.gd`.

- [ ] **Step 2: Write the script**

Create `scripts/combat/ui/PlayerCardBar.gd`:

```gdscript
class_name PlayerCardBar
extends HBoxContainer

signal action_chosen(category: String, item_index: int)

const CharacterCardScene = preload("res://scenes/combat/ui/character_card.tscn")
const ActionMenuScene = preload("res://scenes/combat/ui/action_menu.tscn")

var _cards: Dictionary = {}
var _menus: Dictionary = {}
var _active_actor: CombatCharacter = null

func setup(players: Array) -> void:
	for child in get_children():
		child.queue_free()
	_cards.clear()
	_menus.clear()
	for actor in players:
		var slot := VBoxContainer.new()
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(slot)

		var card := CharacterCardScene.instantiate() as CharacterCard
		slot.add_child(card)
		card.setup(actor)
		_cards[actor] = card

		var menu := ActionMenuScene.instantiate() as ActionMenu
		slot.add_child(menu)
		menu.visible = false
		menu.action_chosen.connect(_on_menu_action_chosen)
		_menus[actor] = menu
	Log.info("PlayerCardBar — slots spawned:", _cards.size())

func set_active(actor: CombatCharacter) -> void:
	if _active_actor and _menus.has(_active_actor):
		_menus[_active_actor].visible = false
	_active_actor = actor
	if _menus.has(actor):
		_menus[actor].visible = true
		_menus[actor].reset()

func reset_active() -> void:
	if _active_actor and _menus.has(_active_actor):
		_menus[_active_actor].visible = false
	_active_actor = null

func get_active_menu() -> ActionMenu:
	if _active_actor == null or not _menus.has(_active_actor):
		return null
	return _menus[_active_actor]

func nudge_actor(actor: CombatCharacter, enabled: bool) -> void:
	if _cards.has(actor):
		_cards[actor].nudge(enabled)

func refresh_actor(actor: CombatCharacter) -> void:
	if _cards.has(actor):
		_cards[actor].refresh_vitals()

func set_actor_inactive(actor: CombatCharacter) -> void:
	if _cards.has(actor):
		_cards[actor].set_inactive()

func _on_menu_action_chosen(category: String, item_index: int) -> void:
	action_chosen.emit(category, item_index)
```

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ui/PlayerCardBar.gd scenes/combat/ui/player_card_bar.tscn
git commit -m "Add PlayerCardBar with per-slot cards and action menus"
```

---

## Task 6 — TargetingCursor

The cursor is a `Node3D` in world space. It positions itself above the currently hovered actor. It emits `hover_changed` on start, cycling, confirm, and cancel so the UI FSM can nudge cards without the cursor knowing about them.

**Files:**
- Create: `scripts/combat/ui/TargetingCursor.gd`
- Create: `scenes/combat/targeting_cursor.tscn`

### Required Node Architecture

```
TargetingCursor (Node3D)  ← script: TargetingCursor.gd, visible = false
  Marker (MeshInstance3D)
```

Code references:
- Root node's `visible` property is toggled by `start()` / `stop()`
- `Marker` is purely visual — the script doesn't reference it directly, but it must exist for the cursor to be visible in 3D space

The cursor positions itself via `global_position = target.global_position + Vector3(0.0, CURSOR_HEIGHT, 0.0)`.

### Styling Notes (Your Call)

- Marker mesh: small shape (e.g. `PrismMesh` 0.2×0.2×0.2, or any indicator you prefer)
- Material: yellow `StandardMaterial3D` is a placeholder — use whatever reads as a targeting indicator
- `rotation_degrees.x = 180` on the mesh if using a cone/prism so the tip points down
- `CURSOR_HEIGHT` in the script defaults to `0.6` — adjust if your characters are taller/shorter
- Feel free to use a sprite, animated mesh, particle, or whatever fits the game's look

- [ ] **Step 1: Create the scene**

Create `scenes/combat/targeting_cursor.tscn`. Add a `MeshInstance3D` named `Marker` with a `PrismMesh` and a yellow `StandardMaterial3D`. Set root `visible = false`. Attach `scripts/combat/ui/TargetingCursor.gd`.

- [ ] **Step 2: Write the script**

Create `scripts/combat/ui/TargetingCursor.gd`:

```gdscript
class_name TargetingCursor
extends Node3D

signal hover_changed(old_actor: CombatCharacter, new_actor: CombatCharacter)
signal target_confirmed(actor: CombatCharacter)
signal target_cancelled

const CURSOR_HEIGHT: float = 0.6

var _candidates: Array = []
var _index: int = 0

func start(candidates: Array) -> void:
	_candidates = candidates
	_index = 0
	visible = true
	if not _candidates.is_empty():
		_update_position()
		hover_changed.emit(null, _current())
	Log.info("TargetingCursor started, candidates:", _candidates.size())

func stop() -> void:
	visible = false
	_candidates = []
	Log.info("TargetingCursor stopped")

func next() -> void:
	if _candidates.is_empty():
		return
	var old := _current()
	_index = (_index + 1) % _candidates.size()
	hover_changed.emit(old, _current())
	_update_position()

func prev() -> void:
	if _candidates.is_empty():
		return
	var old := _current()
	_index = (_index - 1 + _candidates.size()) % _candidates.size()
	hover_changed.emit(old, _current())
	_update_position()

func confirm() -> void:
	if _candidates.is_empty():
		return
	var actor := _current()
	hover_changed.emit(actor, null)
	Log.info("TargetingCursor confirmed", actor.character_name)
	target_confirmed.emit(actor)

func cancel() -> void:
	if not _candidates.is_empty():
		hover_changed.emit(_current(), null)
	Log.info("TargetingCursor cancelled")
	target_cancelled.emit()

func _current() -> CombatCharacter:
	return _candidates[_index]

func _update_position() -> void:
	if _candidates.is_empty():
		return
	global_position = _current().global_position + Vector3(0.0, CURSOR_HEIGHT, 0.0)
```

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ui/TargetingCursor.gd scenes/combat/targeting_cursor.tscn
git commit -m "Add TargetingCursor — world-space actor targeting with hover/confirm/cancel signals"
```

---

## Task 7 — InfoPanel and DamageNumber

**Files:**
- Create: `scripts/combat/ui/InfoPanel.gd`
- Create: `scenes/combat/ui/info_panel.tscn`
- Create: `scripts/combat/ui/DamageNumber.gd`
- Create: `scenes/combat/ui/damage_number.tscn`

### InfoPanel — Required Node Architecture

```
InfoPanel (PanelContainer)  ← script: InfoPanel.gd, visible = false
  InfoLabel (Label)
```

Code node path:
- `$InfoLabel` → `Label` (the script sets `.text` on this)

Root visibility is toggled by `show_text()` / `hide_panel()`.

### InfoPanel — Styling Notes (Your Call)

- Anchor: full-width bottom strip (`anchor_left = 0, anchor_right = 1, anchor_top = 1, anchor_bottom = 1`)
- `offset_top = -32` to give it height from the bottom edge
- Label: centered text, adjust font/size/color to taste
- PanelContainer theme, margins, background — all your call

### DamageNumber — Required Node Architecture

```
DamageNumber (Node3D)     ← script: DamageNumber.gd
  NumberLabel (Label3D)
```

Code node path:
- `$NumberLabel` → `Label3D` (the script sets `.text` and tweens `.modulate:a`)

The node positions itself via `global_position` passed into `show_at()`.

### DamageNumber — Styling Notes (Your Call)

- `Label3D` settings: `billboard = BILLBOARD_ENABLED`, `no_depth_test = true`
- Font size, color, outline, shadow — all your call (yellow `modulate` is set in the scene as a default)
- Tween duration (`0.8s`) and float distance (`0.6`) in the script are starting points — adjust if the animation feels too fast/slow
- Feel free to use a `Sprite3D`, `MeshInstance3D` with a text texture, or any other 3D visual approach

- [ ] **Step 1: Create InfoPanel**

Create `scenes/combat/ui/info_panel.tscn` with the node tree above.

Create `scripts/combat/ui/InfoPanel.gd`:

```gdscript
class_name InfoPanel
extends PanelContainer

@onready var info_label: Label = $InfoLabel

func show_text(text: String) -> void:
	info_label.text = text
	visible = true

func hide_panel() -> void:
	visible = false
```

- [ ] **Step 2: Create DamageNumber**

Create `scenes/combat/ui/damage_number.tscn` with the node tree above.

Create `scripts/combat/ui/DamageNumber.gd`:

```gdscript
class_name DamageNumber
extends Node3D

signal animation_finished

const TWEEN_DURATION: float = 0.8
const FLOAT_DISTANCE: float = 0.6

@onready var number_label: Label3D = $NumberLabel

func show_at(world_pos: Vector3, amount: int) -> void:
	global_position = world_pos
	number_label.text = str(amount)
	var end_y: float = position.y + FLOAT_DISTANCE
	var tween := create_tween()
	tween.tween_property(self, "position:y", end_y, TWEEN_DURATION)
	tween.parallel().tween_property(number_label, "modulate:a", 0.0, TWEEN_DURATION)
	tween.tween_callback(_on_tween_done)

func _on_tween_done() -> void:
	animation_finished.emit()
	queue_free()
```

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ui/InfoPanel.gd scenes/combat/ui/info_panel.tscn
git add scripts/combat/ui/DamageNumber.gd scenes/combat/ui/damage_number.tscn
git commit -m "Add InfoPanel and DamageNumber scenes and scripts"
```

---

## Task 8 — CombatUIFSM

**Files:**
- Create: `scripts/combat/ui/CombatUIFSM.gd`

The UI FSM has 5 states. `@onready` paths assume it is a direct child of the scene root, with `CombatUI` (CanvasLayer) and `TargetingCursor` as siblings. Verify paths match the actual scene tree after Task 9.

**States:**
- `IDLE` — initial, before `start()` is called
- `WATCHING` — a turn is in progress but the UI is only observing (enemy turn, or between player submitting and next turn starting)
- `PLAYER_MENU` — player's turn: action menu is visible and accepting input
- `PLAYER_TARGETING` — player picked a skill: targeting cursor is active
- `COMBAT_OVER` — combat has ended

> **Signal note:** `CombatEvents.action_selected` is currently simplified to a single `target` argument. When skills are added later, expand this payload — but keep it a single object (e.g. a small `ActionSelection` resource or dictionary) rather than multiple signal args, so `await` stays clean.

- [ ] **Step 1: Write the script**

Create `scripts/combat/ui/CombatUIFSM.gd`:

```gdscript
class_name CombatUIFSM
extends Node

enum State { IDLE, WATCHING, PLAYER_MENU, PLAYER_TARGETING, COMBAT_OVER }

const DamageNumberScene = preload("res://scenes/combat/ui/damage_number.tscn")

@onready var enemy_bar: EnemyCardBar = $"../CombatUI/EnemyCardBar"
@onready var player_bar: PlayerCardBar = $"../CombatUI/PlayerCardBar"
@onready var info_panel: InfoPanel = $"../CombatUI/InfoPanel"
@onready var cursor: TargetingCursor = $"../TargetingCursor"

var _state: State = State.IDLE
var _actors: Array = []
var _active_actor: CombatCharacter = null
var _started: bool = false

func start(actors: Array) -> void:
	if _started:
		Log.warn("CombatUIFSM.start() called twice — ignoring")
		return
	_started = true
	_actors = actors
	var players := actors.filter(func(a: CombatCharacter) -> bool: return a.is_player_controlled)
	var enemies := actors.filter(func(a: CombatCharacter) -> bool: return not a.is_player_controlled)
	player_bar.setup(players)
	enemy_bar.setup(enemies)
	player_bar.action_chosen.connect(_on_action_chosen)
	cursor.hover_changed.connect(_on_cursor_hover_changed)
	cursor.target_confirmed.connect(_on_target_confirmed)
	cursor.target_cancelled.connect(_on_target_cancelled)
	CombatEvents.turn_started.connect(_on_turn_started)
	CombatEvents.please_select_action.connect(_on_please_select_action)
	CombatEvents.action_executed.connect(_on_action_executed)
	CombatEvents.actor_downed.connect(_on_actor_downed)
	CombatEvents.combat_ended.connect(_on_combat_ended)
	_transition(State.WATCHING)
	Log.info("CombatUIFSM started")

func _transition(next: State) -> void:
	var msg: String = State.keys()[_state] + " -> " + State.keys()[next]
	Log.info("CombatUIFSM", msg)
	_state = next
	match next:
		State.WATCHING:         _enter_watching()
		State.PLAYER_MENU:      _enter_player_menu()
		State.PLAYER_TARGETING: _enter_player_targeting()
		State.COMBAT_OVER:      _enter_combat_over()

func _enter_watching() -> void:
	player_bar.reset_active()
	cursor.stop()
	info_panel.hide_panel()

func _enter_player_menu() -> void:
	cursor.stop()
	player_bar.set_active(_active_actor)
	info_panel.show_text("A/D: switch menu   W/S: navigate   Enter: confirm")

func _enter_player_targeting() -> void:
	var targets := _actors.filter(func(a: CombatCharacter) -> bool:
		return not a.is_player_controlled and not a.vitals.is_downed()
	)
	cursor.start(targets)
	info_panel.show_text("D/A: cycle target   Enter: confirm   Esc: cancel")

func _enter_combat_over() -> void:
	cursor.stop()
	info_panel.hide_panel()

func _on_turn_started(actor: CombatCharacter) -> void:
	_active_actor = actor
	Log.info("CombatUIFSM — turn", actor.character_name)

func _on_please_select_action(actor: CombatCharacter) -> void:
	_active_actor = actor
	if actor.is_player_controlled:
		_transition(State.PLAYER_MENU)
	else:
		_transition(State.WATCHING)

func _on_action_chosen(category: String, _item_index: int) -> void:
	if category == "WAIT":
		CombatEvents.action_selected.emit(null)
		_transition(State.WATCHING)
		return
	if category == "ACT":
		_transition(State.PLAYER_TARGETING)

func _on_target_confirmed(target: CombatCharacter) -> void:
	CombatEvents.action_selected.emit(target)
	_transition(State.WATCHING)

func _on_target_cancelled() -> void:
	_transition(State.PLAYER_MENU)

func _on_cursor_hover_changed(old_actor: CombatCharacter, new_actor: CombatCharacter) -> void:
	if old_actor:
		if old_actor.is_player_controlled:
			player_bar.nudge_actor(old_actor, false)
		else:
			enemy_bar.nudge_actor(old_actor, false)
	if new_actor:
		if new_actor.is_player_controlled:
			player_bar.nudge_actor(new_actor, true)
		else:
			enemy_bar.nudge_actor(new_actor, true)

func _on_action_executed(actor: CombatCharacter, target: CombatCharacter, damage: int) -> void:
	var dn := DamageNumberScene.instantiate() as DamageNumber
	get_parent().add_child(dn)
	dn.animation_finished.connect(_on_damage_number_done.bind(target))
	dn.show_at(target.global_position + Vector3(0.0, 0.5, 0.0), damage)

func _on_damage_number_done(target: CombatCharacter) -> void:
	if target.is_player_controlled:
		player_bar.refresh_actor(target)
	else:
		enemy_bar.refresh_actor(target)

func _on_actor_downed(actor: CombatCharacter) -> void:
	if actor.is_player_controlled:
		player_bar.set_actor_inactive(actor)
	else:
		enemy_bar.remove_actor(actor)
	Log.info("CombatUIFSM — downed", actor.character_name)

func _on_combat_ended(_player_won: bool) -> void:
	_transition(State.COMBAT_OVER)

func _unhandled_input(event: InputEvent) -> void:
	match _state:
		State.PLAYER_MENU:      _handle_menu_input(event)
		State.PLAYER_TARGETING: _handle_targeting_input(event)

func _handle_menu_input(event: InputEvent) -> void:
	var menu := player_bar.get_active_menu()
	if menu == null:
		return
	if event.is_action_pressed("combat_prev"):
		menu.prev_category()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_next"):
		menu.next_category()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_up"):
		menu.prev_item()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_down"):
		menu.next_item()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_confirm"):
		menu.confirm()
		get_viewport().set_input_as_handled()

func _handle_targeting_input(event: InputEvent) -> void:
	if event.is_action_pressed("combat_next") or event.is_action_pressed("combat_down"):
		cursor.next()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_prev") or event.is_action_pressed("combat_up"):
		cursor.prev()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_confirm"):
		cursor.confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_cancel"):
		cursor.cancel()
		get_viewport().set_input_as_handled()
```

- [ ] **Step 2: Commit**

```bash
git add scripts/combat/ui/CombatUIFSM.gd
git commit -m "Add CombatUIFSM — 5-state UI driver with input handling and event wiring"
```

---

## Task 9 — Wire CombatFSM + CombatScene + Integration

**Files:**
- Modify: `scripts/combat/CombatFSM.gd`
- Modify: `scripts/combat/CombatScene.gd`
- Modify: `scenes/combat/combat_scene.tscn`
- Delete: `scenes/combat/CharacterCard.gd` (and its `.uid` file)

- [ ] **Step 1: Update CombatFSM — replace await stub**

In `scripts/combat/CombatFSM.gd`, replace `_enter_action_select()` with:

```gdscript
func _enter_action_select() -> void:
	CombatEvents.please_select_action.emit(_active_actor)

	if not _active_actor.is_player_controlled:
		# Enemy turn — auto-pick target (placeholder until enemy AI is built)
		_pending_target = _first_living_opponent(_active_actor)
		if _pending_target == null:
			Log.info("ActionSelect — enemy has no valid target, skipping to TurnEnd")
			_transition(State.TURN_END)
			return
		Log.info("ActionSelect — enemy auto-target:", _pending_target.character_name)
		_transition(State.ACTION_EXECUTION)
		return

	# Player turn — suspend and wait for CombatUIFSM to emit action_selected
	var target: CombatCharacter = await CombatEvents.action_selected
	_pending_target = target
	if _pending_target == null:
		Log.info("ActionSelect — no target (WAIT), skipping to TurnEnd")
		_transition(State.TURN_END)
		return
	Log.info("ActionSelect — target:", _pending_target.character_name)
	_transition(State.ACTION_EXECUTION)
```

- [ ] **Step 2: Update CombatScene.gd**

Replace the full file content:

```gdscript
class_name CombatScene
extends Node

@onready var player_spawner: PlayerSpawner = $PlayerSpawner
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var environment_mount: Node3D = $EnvironmentMount
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var combat_camera: Camera3D = $Camera3D
@onready var logic_fsm: CombatFSM = $CombatFSM
@onready var ui_fsm: CombatUIFSM = $CombatUIFSM

func _clear_environment() -> void:
	for child in environment_mount.get_children():
		child.queue_free()

func initialize(composition: CombatConfig, environment: PackedScene, bgm: AudioStream) -> void:
	combat_camera.make_current()
	_clear_environment()
	player_spawner.initialize()
	enemy_spawner.initialize(composition)
	if environment:
		environment_mount.add_child(environment.instantiate())
	if bgm:
		bgm_player.stream = bgm
		bgm_player.play()
	await get_tree().process_frame
	var all_actors: Array = player_spawner.get_all_characters() + enemy_spawner.get_all_characters()
	Log.info("CombatScene — actors ready:", all_actors.size())
	ui_fsm.start(all_actors)
	logic_fsm.start(all_actors)
```

- [ ] **Step 3: Restructure combat_scene.tscn**

In the Godot editor (or via MCP), update `scenes/combat/combat_scene.tscn`:

1. Under `CombatUI` (CanvasLayer), **remove** the existing `CharacterCard` VBoxContainer and all its children.
2. Under `CombatUI`, **add** instances of:
   - `enemy_card_bar.tscn` → named `EnemyCardBar`
   - `player_card_bar.tscn` → named `PlayerCardBar`
   - `info_panel.tscn` → named `InfoPanel`
3. As a **direct child of the scene root** (not inside CombatUI), **add** an instance of:
   - `targeting_cursor.tscn` → named `TargetingCursor`
4. As a **direct child of the scene root**, **add** a plain `Node` named `CombatUIFSM` with `scripts/combat/ui/CombatUIFSM.gd` attached.

Verify the `@onready` paths in `CombatUIFSM.gd` match:
- `$"../CombatUI/EnemyCardBar"` — CombatUIFSM is a scene-root child; CombatUI is its sibling
- `$"../CombatUI/PlayerCardBar"`
- `$"../CombatUI/InfoPanel"`
- `$"../TargetingCursor"`

- [ ] **Step 4: Delete the old placeholder**

```bash
git rm scenes/combat/CharacterCard.gd scenes/combat/CharacterCard.gd.uid
```

- [ ] **Step 5: Full integration test**

Run the game and trigger an encounter. Verify in sequence:

1. Enemy cards appear at top (HP/MP/AP bars, names)
2. Player cards appear at bottom
3. On player turn: action menu appears below the active player card; info strip shows hint text
4. Press D to cycle to WAIT → Enter → turn skips to TurnEnd, combat loop continues
5. Press D to cycle back to ACT → Enter → targeting cursor (yellow triangle) appears above first enemy
6. Press D/A to cycle enemies; targeted card nudges down, previous un-nudges
7. Press Enter to confirm target; damage number appears above enemy and floats up; then HP bar decrements
8. On enemy death: card is removed from top bar; HBox reflows
9. **Enemy turn verification:** after a player turn ends, the next enemy turn should auto-resolve (no input required) — damage number appears above the targeted player, their HP bar decrements
10. Combat cycles until one side is wiped; CombatEnd fires, UI enters COMBAT_OVER

- [ ] **Step 6: Commit**

```bash
git add scripts/combat/CombatFSM.gd scripts/combat/CombatScene.gd scenes/combat/combat_scene.tscn
git commit -m "Wire CombatUIFSM — player input drives combat loop, replace auto-select stub"
```

---

## Known Deferred Items

- ITEM and RUN menus: visible stubs, non-functional
- Camera anchoring per skill (to be authored as per-skill Resource)
- Tactics View toggle (turn-order number display)
- Token icons in `TokenContainer`
- Victory screen (post-combat XP / loot — separate system)
- Defeat screen (quit / reload — add to `COMBAT_OVER` state when ready)
- AoE targeting (multiple cards nudge simultaneously)
- Ally targeting for healing / buff skills (pass `target_allies: bool` to `cursor.start()`)

---

## Review Conclusions (2026-05-10)

**Status:** Approved with corrections applied inline above.

1. **Enemy auto-pick is a placeholder.** `_first_living_opponent()` remains the default enemy behaviour until a dedicated Enemy AI system is designed. The branch in `CombatFSM._enter_action_select()` makes this boundary explicit.

2. **Signal elasticity.** `action_selected` is simplified to a single `target` argument for now. When skills arrive, expand the payload as a single resource/dictionary object — never multiple signal args — so `await` stays clean and type-safe.

3. **CombatEvents.gd modification added as Task 0.** The signal change was missing from the file map. It's now a dedicated first task since all downstream code depends on the new signature.

4. **Old CharacterCard discarded.** The existing `scenes/combat/CharacterCard.gd` and its scene node are removed entirely. The new `CharacterCard` is rebuilt from scratch as a `Control`-rooted scene with a nested `VBoxContainer`, solving the container-layout-vs-tween conflict.

5. **Nudge uses `offset_top` instead of `position:y`.** Containers overwrite `position` on every layout pass. `offset_top` is respected by the layout engine, so nudges survive sibling reflows (menu show/hide, card removal).

6. **Double-start guard.** `CombatUIFSM.start()` includes a `_started` boolean guard. `CombatScene.initialize()` is currently only called once per scene instance, but the guard costs nothing and prevents a hard crash if that ever changes.

7. **`_first_living_opponent()` stays alive.** It now serves only the enemy auto-pick path. No cleanup needed until enemy AI replaces it.

8. **Integration test covers enemy turns.** Step 9 explicitly verifies that enemy turns auto-resolve without player input, preventing the hard-lock bug that would have occurred with the original plan.

9. **Input events are marked as handled.** `_handle_menu_input` and `_handle_targeting_input` call `get_viewport().set_input_as_handled()` after processing. Prevents ghost inputs if other listeners are added later.

10. **Architecture validated.** Two side-by-side FSMs, event bus in the middle, composed scenes, no god-manager. The plan follows project conventions.
