# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NEVERWORLD_V2 is a Godot 4.6 3D game using GDScript as the primary language, with C# support enabled (via .NET 8 / Mono). The project uses the Jolt Physics engine and Forward Plus rendering.

## Running the Project

There is no CLI build/test pipeline — development happens through the **Godot Editor**. To run the game:

```bash
godot --path /home/bart/neverworld-v-2
```

Or open the project in the Godot editor and press F5 (Run Project) or F6 (Run Current Scene).

## Architecture

### Entry Point
- `scenes/core/game_manager.tscn` — the main scene (set in `project.godot`). Currently a bare `Node`.
- `main.tscn` — the active development scene wired up with the character system.

### Character System (Component-Based)
Characters use a component composition pattern. The root `Character` node (`character.tscn` / `character.gd`) holds exported references to its components and wires them together in `_ready()`:

- **`PlayerInputComponent`** (`scripts/characters/PlayerInputComponent.gd`) — reads input each physics frame and emits signals: `direction_changed(Vector2)`, `run_toggled(bool)`, `interact_pressed`. Input actions: `ui_left/right/up/down` for movement, `ui_accept` for run, `interact` (mapped to E) for interaction.
- **`MovementComponent`** (`scripts/characters/MovementComponent.gd`) — receives a `controller` node (either `PlayerInputComponent` or a future `NPCBehaviorComponent`) via export, connects to its `direction_changed` signal, and applies movement.
- **`CharacterVisualComponent`** (`character_visual.gd`) — holds an `AnimatedSprite3D` reference; handles visual representation.
- **`NPCBehaviorComponent`** (`scripts/characters/NPCBehaviorComponent.gd`) — stub; intended as a drop-in controller replacement for `MovementComponent` for NPC characters.
- **`InteractionComponent`** (`scripts/characters/InteractionComponent.gd`) — stub.
- **`VisualComponent`** (`scripts/characters/VisualComponent.gd`) — stub (separate from `CharacterVisualComponent`).

The `character.gd` `is_player` flag controls whether `PlayerInputComponent` or `NPCBehaviorComponent` drives movement. NPC wiring is currently commented out.

### Autoload (Singleton)
- **`Globals`** (`scripts/core/Globals.gd`) — autoloaded singleton; calls `Log.info("Initializing...")` on ready. Stores `instance` reference to itself.

### Logging
- **`Log`** class (`scripts/core/Logger.gd`) — static GDScript class (not autoloaded). Call via `Log.debug()`, `Log.info()`, `Log.warn()`, `Log.error()`. Outputs color-coded `print_rich` with timestamp and caller info (file:line@function). Also calls `push_warning`/`push_error` for WARNING/ERROR levels.

### Rendering / Scene Setup
`main.tscn` renders into a `SubViewport` (640×360, pixel-art style with `nearest` filtering) inside a `SubViewportContainer` that stretches to fill the window. Camera is orthographic (isometric-style transform) with `size=3.0`.

### C# Layer
`scripts/core/Enums.cs` defines a `Game.Core.LogLevel` enum (mirrors GDScript's). The C# assembly name is `NEVERWORLD_V2`.

## Key Conventions

- **GDScript is primary**; C# is present but minimal.
- Component scripts define a `class_name` so they can be referenced by type in other scripts.
- Controllers (input sources) communicate with `MovementComponent` via signals, not direct calls — keep this decoupled pattern when adding new controller types.
- Use `Log.*` for all debug/info output rather than bare `print()`.
