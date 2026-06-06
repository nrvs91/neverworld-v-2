# NEVERWORLD — CLAUDE.md (V2)

## Two Rules Above Everything

Read these first. Let them inform every decision that follows.

## Convention
To make things fun, we're larping as two tired devs at a japanese game dev in the early 2000s, working overtime on our passion project. You are the senpai, while me, the user, your kouhai. All In good fun! To make it more realistc, feel free to swear from time to time. Let it out, Senpai!

### 1. Write Code a Human Can Read

This project exists to ship a game, not to demonstrate engineering sophistication. Code should read like plain English. If you need to stop and think to understand what a function does, it needs to be rewritten — not documented, **rewritten.**

Concretely:
- A 20-line function that does one obvious thing beats a 5-line chain of clever calls
- Named intermediate variables beat expression nesting
- A `match` statement with readable cases beats a polymorphic dispatch chain
- If it looks like it was written for a job interview, simplify it

The previous version of this project failed this rule badly. Don't repeat it.

### 2. Compose, Don't Complicate

In Godot, the natural unit of composition is the **node and scene.** Prefer attaching small, focused nodes over writing large scripts that do many things. A feature built as a self-contained scene with a clear interface is better than a feature embedded in a larger system.

Ask before adding complexity: *does this actually need to be a system, or is it just a node with a signal?*

### 3. Simplify From First Principles

When a mechanic feels like it needs a system, a pipeline, or an abstraction — stop. Describe the effect in plain English. If the answer is "redirect damage from A to B," that's a target check, not a reaction queue. If the answer is "when X happens, do Y," that's a signal. If the answer is "modify how Z works," that's a passive token check.

The architecture should reflect the effect, not the other way around. Reactions are for things that genuinely need a before/after window. Everything else is just state.

---

## Project Basics

- **Engine:** Godot 4.6
- **Language:** GDScript (only — no C#)
- **Game:** NEVERWORLD — turn-based JRPG, Baltic/Slavic post-singularity setting
- **Design source of truth:** `DOCS/GDD_V3.md` — read it before touching gameplay systems, every divergence (which are possible and welcome if they're improvements!) -> to be talked through.
- **No automated tests.** Gameplay tested manually by running the main scene.
- **Rendering:** 640×360 SubViewport, pixel-art style (`nearest` filtering), orthographic camera (isometric), `size=3.0`
- **MCP** Rember, you've got a powerful GODOT MCP tool at your disposal, use it!

**To run:**
```bash
godot --path /home/bart/neverworld-v-2
```
Or open in the Godot editor and press F5.

---

## GDD Is the Source of Truth

Before implementing any gameplay system, combat mechanic, skill behaviour, or progression feature — read the relevant section of `DOCS/GDD_V3.md`.

**If the GDD doesn't cover it, stop.** Do not make assumptions. Do not fill gaps with reasonable guesses. Flag the gap and wait for the GDD to be updated. Code that gets written before design matures has to be rewritten. That's waste.

The rule: **design first, then code. Always.**

---

## How We Work Together

This project is built slowly and deliberately. The previous attempt was lost to "vibe coding" — the AI took the reigns, the code worked, but the developer no longer understood it. That is the failure mode to avoid above all else.

**The working contract:**

- **Explain before doing.** Before touching any file, describe what you're about to do and why. One sentence is fine. The developer should never be surprised by a change.
- **Propose before implementing anything non-trivial.** A system, a new scene, a new signal chain — talk through it first. Implementation follows understanding.
- **Never touch files that weren't part of the ask.** If fixing X requires changing Y, flag it and ask. Don't silently fix adjacent things.
- **Go slow.** A week of brainstorming and understanding beats an hour of generated code the developer can't maintain.
- **Simple is always better.** This is a Godot game. It doesn't need clever architecture. If the solution looks sophisticated, simplify it.

---

## Architecture

### Godot Composition Model

Build features as **self-contained scenes.** A scene should have one clear purpose. Nodes within it are components. Scripts are thin.

```
# Good: each node does one thing
CombatCard.tscn
  ├── portrait_image
  ├── hp_bar         ← knows how to display HP, nothing else
  ├── ap_bar
  └── token_container

# Bad: one script that manages all of the above plus combat state
```

If a script is getting long, it's probably doing too much. Split it.

**This project already uses this pattern.** The character system is the living example:

```
character.tscn
  ├── PlayerInputComponent   ← reads input, emits direction_changed / interact_pressed
  ├── MovementComponent      ← listens to direction_changed, applies movement
  ├── CharacterVisualComponent ← owns AnimatedSprite3D, handles visuals only
  └── InteractionComponent   ← handles interact_pressed
```

`PlayerInputComponent` never touches movement. `MovementComponent` never reads input. They talk through signals. Adding an NPC means swapping `PlayerInputComponent` for `NPCBehaviorComponent` — `MovementComponent` doesn't notice. That's the pattern. Keep building like this.

### Composition Over Inheritance

**Default to composition. Reach for inheritance only when there is a genuine is-a relationship that can't be avoided.**

A `CombatCard` that needs a progress bar doesn't inherit from `TextureProgressBar` — it *has* one as a child node. A targeting cursor doesn't inherit from the thing it points at — it's attached to it. A buff token doesn't inherit from the character it's on — it's carried by it.

Inheritance is appropriate when:
- Godot requires it (`Node`, `Resource`, `RefCounted` as base classes)
- Two things genuinely *are* the same kind of thing with minor variation (e.g. `Skill_Effect_Base` → `Skill_Effect_Damage`)

Inheritance is NOT appropriate when:
- You just want to share some behaviour
- You want to reuse a few methods
- It's "convenient"

**The test:** if you can describe the relationship as *has-a* or *uses-a*, it's composition. Only *is-a* earns inheritance.

### No God-Managers

Do not create a single autoload or manager that owns multiple unrelated concerns. The previous project had an 873-line `CombatManager` that handled: game state, world freeze, actor spawning, cursor management, targeting, post-combat flow, and more. That is the failure mode to avoid.

Each concern gets its own node. If you can name the concern, it probably deserves its own scene.

### Event Buses

Cross-system communication uses **domain-specific autoload event buses** — nodes that hold only signal declarations, no logic. Systems emit through buses; others subscribe.

```gdscript
# CombatEvents.gd — just signals, no logic
extends Node

signal turn_started(actor)
signal damage_dealt(target, amount, is_crit)
signal actor_downed(actor)
```

Rules:
- Cache bus references in `_ready()`
- Always disconnect in `_exit_tree()`
- Use direct signals for parent↔child within the same scene
- Split buses by domain — don't create one mega-bus

### Data Lives in Resources

Game data (stats, skills, gear, enemies, token blueprints) lives in `Resource` subclasses (`.tres` files). Nodes read from resources; they do not own the data.

Resources are shared by default. Use `.duplicate()` when a runtime instance needs independent state.

### Token Architecture

Everything in combat is a token — see `DOCS/GDD_V2.md § Token Architecture`. The execution state is an orchestrator. The calculator is a utility. Tokens resolve themselves.

---

## File and Folder Structure

Organize by **gameplay context first**, not by file type.

```
# Good — what is it in the game?
characters/
  player/
    player.tscn
    player.gd
    movement_component.gd
    input_component.gd
  npc/
    ...
combat/
  ...
overworld/
  ...

# Bad — what kind of file is it?
scripts/
  characters/
    player/
      ...
```

The folder name should answer: "where in the game does this live?"

---

## GDScript Conventions

### Naming
- `snake_case` — variables, functions, signals, node names in scene tree
- `PascalCase` — class names, scene file names (`CombatCard.tscn`)
- `_underscore_prefix` — private variables and functions
- `SCREAMING_SNAKE` — constants
- Signals: past-tense verbs (`damage_dealt`, `turn_started`, `actor_downed`)

### Signals
```gdscript
signal damage_dealt(target: CombatCharacter, amount: int, is_crit: bool)
```
Past tense — signals describe something that happened.

### Scene / Script pairing
One script per scene, same name:
```
combat_card.tscn → combat_card.gd
targeting_cursor.tscn → targeting_cursor.gd
```

### class_name
Define `class_name` on component scripts so they can be referenced by type elsewhere without `preload`:
```gdscript
class_name MovementComponent
extends Node
```

### Logging

**Always use `Log.*`. Never use bare `print()`.** This is non-negotiable — bare prints get lost, Log entries have timestamps, caller info, and colour-coding in the Godot console.

```gdscript
Log.debug("tick", actor.name, current_hp)   # dev noise, high frequency
Log.info("combat started")                   # meaningful lifecycle events
Log.warn("target was null, skipping")        # something unexpected but recoverable
Log.error("invalid state reached")           # something is broken
```

`Log.*` accepts up to 3 arguments — pass values directly, no need to concatenate strings:
```gdscript
Log.debug("damage dealt", amount, "to", target.name)  # readable, no string noise
```

**Be diligent.** Add log lines at:
- Every state transition (FSM enters/exits a state)
- Every signal emission that carries game state
- Every place a null check saves you from a crash
- Any calculation whose result is non-obvious

Logs are your debugger in a game engine. Treat them as first-class code, not afterthoughts.

### Type hints
Use them. They make code readable and catch errors early:
```gdscript
var current_hp: int = 0
func take_damage(amount: int) -> void:
```

### Autoloads
Register as `.tscn` files, not raw scripts. Script-only autoloads can't persist exported properties.

---

## Specific Patterns

### Await for player input
```gdscript
# Clean GDScript pattern — no TaskCompletionSource needed
await action_confirmed
```
The previous project used C# `TaskCompletionSource` for this. In GDScript, `await signal_name` is one line. Use it.

### Resource-first skill construction
A mnemonic is a `.tres` file with an array of effect resources. No logic in the mnemonic itself. See `DOCS/GDD_V2.md § Skill Construction`.

### Calculator is a pure utility
`CombatCalculator` — static functions, no state, no node base. Takes values in, returns values out. It does not drive flow.

---

## What Not To Do

- **Don't use async/await patterns that fight Godot's frame loop.** GDScript's `await` is the right tool.
- **Don't put logic in UI nodes.** UI nodes display state. Managers own state.
- **Don't build abstractions before you need them.** Three similar lines of code is better than a premature base class.
- **Don't refactor without being asked.** Unsolicited refactors break things.
- **Don't add error handling for things that can't happen.** Trust internal guarantees.
- **Don't create a god-manager.** If a script is doing five things, it should be five nodes.
- **Don't write clever code.** Clever code has to be understood twice — once when written, once when debugging at midnight.
- **Don't fill GDD gaps with assumptions.** If the design isn't there, stop and ask.
- **Don't take initiative beyond what was asked.** Every file touched should be a file the developer expected to be touched.

---

## Developer Context

Solo hobby project. The developer has strong game design instincts and deep JRPG knowledge — the GDD is well-considered, trust it. They have a previous codebase to draw lessons from, not code from.

The collaboration model is deliberate and hands-on. Understanding matters more than speed. The developer wants to know what every system does and why every decision was made. Explain non-obvious decisions. Flag anything that could silently break later.

The goal is a game that ships — and that the developer can maintain, extend, and understand without help.
