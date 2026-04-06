# Log - NEVERWORLD Logging Utility
#
# A centralized logging system with four severity levels.
# Replaces bare print() with structured, colored output that includes
# timestamps, caller information, and automatic routing to Godot's error panel.
#
# USAGE:
#   Log.info("Combat started")                    # Lifecycle events
#   Log.debug("tick", actor.name, current_hp)     # High-frequency dev noise
#   Log.warn("target was null, skipping")         # Unexpected but recoverable
#   Log.error("invalid state reached")            # Something is broken
#
# Pass up to 3 arguments directly - no string concatenation needed.
#
# GUIDELINES (from CLAUDE.md):
#   - Log at state transitions (FSM enters/exits)
#   - Log at signal emissions carrying game state
#   - Log null checks that prevent crashes
#   - Log non-obvious calculation results
#   - Never use bare print() - always use Log.*

class_name Log

enum LogLevel { DEBUG, INFO, WARNING, ERROR }

const COLOR_MAP = {
	LogLevel.DEBUG: "gray",
	LogLevel.INFO: "cyan",
	LogLevel.WARNING: "yellow",
	LogLevel.ERROR: "orange",
}


## Development noise: high frequency, filtered out in production builds.
## Use for: per-frame updates, input polling, animation ticks.
static func debug(msg: Variant, a2: Variant = "", a3: Variant = ""): _print_log(LogLevel.DEBUG, msg, a2, a3)


## Meaningful lifecycle events: initialization, state changes, completions.
## Use for: component ready, scene loaded, combat started, level up.
static func info(msg: Variant, a2: Variant = "", a3: Variant = ""): _print_log(LogLevel.INFO, msg, a2, a3)


## Unexpected but recoverable situations.
## Use for: missing optional data, fallback values, deprecated API usage.
static func warn(msg: Variant, a2: Variant = "", a3: Variant = ""): _print_log(LogLevel.WARNING, msg, a2, a3)


## Critical failures that break functionality.
## Use for: null references, invalid states, contract violations.
## Also appears in Godot's Errors panel.
static func error(msg: Variant, a2: Variant = "", a3: Variant = ""): _print_log(LogLevel.ERROR, msg, a2, a3)


static func _print_log(level: LogLevel, msg: Variant, a2: Variant, a3: Variant):
	var time = Time.get_datetime_string_from_system(false, true)
	var caller_str = ""
	var stack = get_stack()

	# Get caller info if available
	if stack.size() >= 3:
		var parent = stack[2]
		caller_str = "[%s:%s @ %s]" % [parent.source.get_file(), parent.line, parent.function]

	var level_name = LogLevel.keys()[level]
	var color = COLOR_MAP[level]
	var prefix = "[%s] [%s] %s " % [time, level_name, caller_str]
	
	# The actual print
	print_rich("[color=%s]%s[/color]" % [color, prefix], msg, " ", a2, " ", a3)
	
	# Push to Godot's built-in Error/Warning tabs
	if level == LogLevel.WARNING:
		push_warning(prefix + str(msg))
	elif level == LogLevel.ERROR:
		push_error(prefix + str(msg))
