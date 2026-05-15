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
