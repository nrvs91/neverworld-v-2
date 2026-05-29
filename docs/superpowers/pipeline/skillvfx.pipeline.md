The Production Pipeline (Melee Skills)
Step 0: The Foundation (Done Once)
Someone (you, right now) sets up the shared attack_skeleton animation in the AnimationPlayer on combat_character.tscn. Four method call tracks targeting SkillPresenter. This is the one timeline every melee skill uses. You do this once, never touch it again for new melee skills.
Step 1: Make the VFX Scene (Artist / You)
Open Godot. Scene -> New Scene. Root node: CPUParticles3D. Tweak emission shape, color, gravity, lifetime. Set one_shot = true. In the Node dock, connect finished to queue_free(). Save as scenes/combat/vfx/vfx_whatever.tscn.
No script. No code. Just particles and inspector values.
Step 2: Import the Sound (Sound Designer / You)
Drop slash.wav or power_up.wav into the project. Godot imports it automatically.
Step 3: Create the Presentation Data Resource (Designer / You)
In the FileSystem dock, right-click -> New Resource. Pick SkillPresentationData. The Inspector shows four fields. Drag your VFX scene into on_target_vfx. Drag your sound into impact_sfx. Leave the others null. Save as resources/vfx/skill_name_presentation.tres.
Still no code. Just drag-and-drop in the inspector.
Step 4: Hook It to the Skill (Designer / You)
Open uskrav_tergo_lupi.tres (or whatever mnemonic). The Inspector now has a presentation field thanks to Task 1. Drag your .tres from Step 3 into that slot. Save.
Step 5: Test
Press F5. Use the skill. The shared attack_skeleton plays. At frame 0: nothing (no cast VFX). At frame 15: character dashes. At frame 30: your hit spark spawns, your slash sound plays, damage numbers pop. At frame 45: character recovers.
If the timing feels off, you have two knobs:
- 
VFX looks wrong → edit the .tscn particle values, save, F5 again.
- 
Sound is too early/late → nudge the method call keyframe in the AnimationPlayer timeline. Save the scene, F5 again.
Neither change touches GDScript.
Why This Pipeline Is Good
Compare it to what the old plan would have required:
Old Plan (VFXType enum)
Add a new enum value in GDScript
Write a switch case in a manager to handle the new type
Hardcode VFX path strings somewhere
Recompile / restart to test
Under this plan, adding a new skill with unique VFX is a data-only operation. You make a particle scene, you make a resource, you link them in the inspector. The code doesn't know or care. The AnimationPlayer doesn't know or care. It just plays the skeleton and calls on_impact(), and whatever decoration data happens to be loaded, spawns.
The Future Cases
"What if I need a completely different timing structure?"
e.g., a mage spell that goes cast → channel → launch projectile → travel → impact
You don't hack the melee skeleton. You author a new animation in the same AnimationPlayer: ranged_skeleton. New method call tracks: on_cast(), on_channel(), on_launch(), etc. You write a new SkillPresenter subclass (or just add methods to the existing one) that knows how to spawn projectiles. The MnemonicResource gets a @export var animation_name: String = "attack_skeleton" so ActionPipeline can pick the right one.
But that's future work. Your plan correctly scopes itself to melee only.
"What if two skills use the same hit spark but different colors?"
Make two VFX scenes: vfx_hit_spark_red.tscn and vfx_hit_spark_blue.tscn. Both are CPUParticles3D with different color values. Two .tscn files, zero code duplication. Or if you're fancy, one .tscn with an exported Color variable and a tiny script. Either way, the pipeline is the same: make scene, reference in .tres, assign to skill.