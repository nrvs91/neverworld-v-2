# Enums - NEVERWORLD Global Enums
#
# Central location for game-wide enum definitions.
# Use class_name to access from anywhere: Enums.LogLevel

class_name Enums


## Logging severity levels. Used by Log utility and debug UI.
## DEBUG: Development noise, filtered in production
## INFO: Lifecycle events and state changes  
## WARNING: Recoverable issues, unexpected data
## ERROR: Critical failures, crash conditions
enum LogLevel {
	DEBUG,
	INFO,
	WARNING,
	ERROR
}
