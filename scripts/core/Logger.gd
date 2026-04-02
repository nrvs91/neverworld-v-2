class_name Log

enum LogLevel { DEBUG, INFO, WARNING, ERROR }

const COLOR_MAP = {
	LogLevel.DEBUG: "gray",
	LogLevel.INFO: "cyan",
	LogLevel.WARNING: "yellow",
	LogLevel.ERROR: "orange",
}

static func debug(msg: Variant, a2: Variant = "", a3: Variant = ""): _print_log(LogLevel.DEBUG, msg, a2, a3)
static func info(msg: Variant, a2: Variant = "", a3: Variant = ""): _print_log(LogLevel.INFO, msg, a2, a3)
static func warn(msg: Variant, a2: Variant = "", a3: Variant = ""): _print_log(LogLevel.WARNING, msg, a2, a3)
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
