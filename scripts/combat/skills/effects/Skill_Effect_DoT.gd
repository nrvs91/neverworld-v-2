class_name Skill_Effect_DoT
extends Skill_Effect_Base

enum DotTag { POISON, BURN, BLEED }

@export var dot_tag: DotTag = DotTag.POISON
@export var charges: int = 3
