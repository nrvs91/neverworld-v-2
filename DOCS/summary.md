  Session Summary — 2026-04-08                                                                                                     
                                                                                                                                   
  What we decided                                                                                                                  
                                                                                                                                   
  Combat scene: Separate scene, additively loaded. Camera swap, not a scene transition. Static layout, no overworld enemies. Max   
  3v6.                                                                                                                             
                                                                                                                                   
  Encounter initialization: Each map has an EncounterManager holding an array of CombatConfig resources. Each config maps Node3D   
  spawn anchors to EnemyData resources (for enemies) and PartyManager slots (for players). Combat start = pick a config,           
  instantiate actors at anchors.                                                                                                   
                                                                                                                                   
  Actor composition:                                                                                                           
  combat_character
    character_data        ← blueprint                                                                                              
    resistance_profile    ← static after init                                                                                      
    ├── VisualComponent                                                                                                            
    ├── CombatInputComponent                                                                                                       
    ├── VitalsComponent   ← cur_hp/mp/ap + mutations                                                                               
    └── TokenContainer                                                                                                             
  TurnOrderManager and CombatCalculator live externally.                                                                           
                                                                                                                                   
  Resistance: Three states — WEAK (2×) / NONE (1×) / RESISTANT (0.5×) / IMMUNE (0×). Tokens override, opposing states cancel.      
  IMMUNE is a hard wall, BYPASS only.                                                                                              
                                                                                                                                   
  Ailment HitChance: Authored per skill as CERTAIN/HIGH/MEDIUM/LOW. min(chance × resistMult, 100%). Separate from Hit/Dodge.       
                                                                                                                                   
  MVP loop: Spawn → CT ticks → player menu → action resolves → downed check → repeat → exit. 