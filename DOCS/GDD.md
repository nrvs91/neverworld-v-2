NEVERWORLD — Game Design Document V2
This document supersedes GDD.md for all systems design. Setting, characters, factions, and narrative carry over from GDD.md until explicitly rewritten here. This is a living document. Stubs and TODOs are intentional — fill them as design crystallizes.


SKILL SYSTEM
Core Principle: Mnemonics
Skills are Mnemonics — physical objects that encode technique, combat knowledge, and concentrated belief. You don't learn a skill, you run a mnemonic. You don't train an ability, you carry one.

In NEVERWORLD's post-singularity setting, the boundary between information and matter has eroded. The unconscious layer — where emotion, belief, and hyperstition accumulate — seeps into physical reality wherever the signal is strong enough. Mnemonics are nodes where that layer punched through and crystallized. Some predate living memory. Nobody knows who encoded the first ones. They exist, they work, and that's enough.

This is hyperstition made literal: a technique that became real because enough people believed it, used it, and passed it on. The mnemonic works because it has always worked. Belief and matter are the same thing here.

Mechanically: Mnemonics are discrete, ownable items — not entries in a character-locked tree, not stat unlocks, not class features. Each instance is its own object. Skugge's copy and Vargi's copy are two separate things. They grow, get reforged, and can be lost. Think equipment, not abilities.

Mnemonics are acquirable party-wide — any character can carry any mnemonic. New instances can be scribed from the Compendium for REZ as many times as you can afford. What differentiates characters is not an exclusive list but which mnemonics they're drawn toward, invest in, and build around.

TODO: Debate whether to encourage character-mnemonic affinity mechanically. Example: a dagger mnemonic used by Skugge ranks up faster than the same mnemonic in Vargi's hands. Rewards thematic coherence without hard gating. Risk: creates invisible pressure that feels punishing if the player doesn't know about it.


Skill Ranks
Skills have ranks. Higher rank means higher base damage, better scaling, better AP efficiency — not arbitrary resistance flags. A low-rank skill against a high-defense enemy does pathetic damage. The numbers tell the story. No "RESIST" labels needed.

This is the core pressure to engage with the REZ system. Ignoring skill investment doesn't lock you out — it just makes you ineffective in a way that's immediately legible.
Damage Formula
Each damaging skill effect has a hand-authored integer Power value. Damage resolves as:

damage = Power × AtkStat / (DefStat + 10) × Random(0.85, 1.0)

Power — authored per effect. Readable baseline: Power 35 means roughly 35 damage against an equally-matched enemy.
AtkStat — attacker's relevant stat: Phys.Atk for physical skills, Magic.Atk for magical.
DefStat — defender's relevant stat: Phys.Def or Magic.Def.
+10 offset — added to DefStat before division. Softens defense scaling at low values and prevents division by near-zero stats.
Random(0.85–1.0) — variance roll. Same spread as Pokémon.
Result is rounded to int; minimum 1.

No level multiplier. NEVERWORLD's dual-axis stat growth means AtkStat already reflects level progression — a separate level term would double-amplify it.

What the ratio does: Against weak enemies (low DefStat), damage punches above Power. Against tough enemies (high DefStat), it falls below. This is the mechanical reason to rank up skills — low Power can't compensate for a widening stat gap as the game progresses.

This formula feeds into the existing combat pipeline after base damage: resist multiplier → crit multiplier → final floor 1.


Two Vectors of Mnemonic Progression
Mnemonics have two distinct states: BASE and UPGRADED/MUTATED.
BASE Mnemonics
The entry point. Usually, that means, the skill is either more reserved mechanically or it's just "starting out".

BASE mnemonics enter your possession through:

REZ purchase — scribe from the Compendium (see below)
REFRACTION — capture resonance directly from an enemy (see REFRACTION section)
Loot — mnemonic fragments dropped by enemies or found in the world
UPGRADED / MUTATED Mnemonics
Only reachable by climbing a tree. Cannot be purchased, REFRACTION and looting are possible but rare. Most are earned through REZ investment — the mnemonic is reforged, not replaced.

The upgrade path is branching, not linear. REZ investment upgrades a skill vertically (Uskrav → Uskrav II → Uskrav III). At certain thresholds, the skill reaches a branch point — a permanent, no-take-backs reforge decision. Pick one branch; the other is gone from that instance. No ghost skills, no recovery of the unchosen path.

Branches can themselves become new trunks with further investment.

Uskrav

    └── Uskrav II (higher base dmg)

        └── Uskrav III (higher base dmg)

            ├── Sporlaus       (DMG + guaranteed first strike)

            │   └── ...

            └── Tvingar   (guaranteed CRIT against enemy with DOT)

                └── Tvingar II (guaranteed CRIT against enemy with DOT + higher base dmg)

Vertical upgrades — same skill, improved. Branch points — permanent identity decision. You are changing what this skill fundamentally is. Choose once.


Chain Design
Depth is a design signal, not a quality signal
A 1-node chain (no upgrades) means the skill is complete at base — no investment needed, no decisions to make. A 5-node branching chain means the designer wants the player to commit and choose. Neither is better. Depth reflects the skill's role in the game.
Vertical ranks: same identity, better numbers
Linear upgrades improve the skill without changing what it does. The primary lever is Power. Other changes (cost reduction, secondary effects) are optional — only used when they reinforce something specific about the rank, not as a default pattern.
Branch points: identity mutations, not upgrades
A branch is a permanent reforge decision. Both paths should feel genuinely different — not "option A is objectively better." Tools for making branches feel distinct:

Power trade-off — one branch takes a Power cut in exchange for a mechanic
Cost personality — AP or HP% changes that reinforce the branch's identity
Conditional mechanics — the payoff requires setup (DoT on target, ally low HP, etc.)
Reliability vs ceiling — guaranteed hit/effect vs higher raw output with risk
Costs are tools, not progression rules
AP and HP% costs don't automatically decrease as a skill ranks up. They change only when that change means something. Cutting every skill's cost at every rank just makes every chain look identical.
Worked example: Uskrav chain
Skugge's starting dagger skill. An elaborate chain — not every mnemonic will look like this.

Uskrav

  └── Uskrav II

        └── Uskrav III

              ├── Sporlaus   (reliability branch)

              └── Tvingar

                    └── Tvingar II

Node
Power
AP
HP%
Special
Uskrav
30
2
15%
—
Uskrav II
45
2
15%
—
Uskrav III
70
2
15%
—
Sporlaus
55
1
5%
True Strike (never misses)
Tvingar
55
2
25%
Guaranteed crit if target has DoT
Tvingar II
75
2
25%
Guaranteed crit if target has DoT


Trunk (I→II→III): same cost, increasing Power. Rewards REZ investment with raw output.

Sporlaus: takes a power cut but becomes cheap (1 AP, 5% HP, never misses). Reliable, low-maintenance pressure.

Tvingar: same power cut, higher HP cost (25%), guaranteed crit against DoT targets. Miss the setup and you've paid 25% HP for a weak hit. Land it and effective Power is 82.5 — above the trunk.

Tvingar II: recovers the power gap (75 vs trunk's 70) while keeping the condition and the cost. Rewards full commitment to the branch.

The branch decision is reliability vs ceiling. Sporlaus players don't need to build around DoT. Tvingar players commit to setup — and when it lands, they hit harder than anything else in the chain.


The Skill Compendium
The Compendium is the party's skill catalogue — a grimoire with blank pages. Known skills appear by name and can be scribed (spend REZ to create an instance). Unknown skills appear as ??? — slots you know exist but can't access yet.

Templates enter the Compendium through play:

REFRACTION — learn from an enemy, template added to Compendium
Loot — find a skill item, template added to Compendium
Vendor/NPC unlocks — specific merchants in specific locations carry specific templates

The catalogue is not a spreadsheet available from the start. You build it by engaging with the world. Knowing what's behind a ??? before anyone else does is itself a form of progress.


REFRACTION
A character can learn a skill directly from an enemy by witnessing it while under a DEFENSIVE "stance" and surviving combat. Rewards game knowledge. Witnessed skill -> no longer "???" in the compendium, available for purchase.

REFRACTION is the a discovery vector — it introduces skills into the Compendium that couldn't be predicted or purchased. Engaging with the world fills the grimoire.

Acquisition condition details (defend stance? HP threshold? specific setup?) — TBD.


Skills as Loot
Skills can drop from enemies or appear in chests as physical items. Picking one up adds its template to the Compendium, and makes the skill available for purchase.


RESOURCE SYSTEM
AP — Action Economy (combat only)
Per-character. Gained at the start of your own turn (+1, modifiable by gear/mnemonics). Carries over between turns — unspent AP accumulates and creates tempo pressure. Spent to play mnemonics. Resets between encounters.
HP — Physical Cost + Survival
Some mnemonics cost HP to run (physical techniques that damage the user). Also the primary survival resource — hit zero and the character goes down, their mnemonics go offline for the rest of the encounter. Persists across encounters. Restored at rest points and via healing mnemonics.
MP — Magical Cost + Dungeon Attrition
Some mnemonics cost MP to run (magical/encoded techniques that draw on the signal). MP is the dungeon attrition layer — it drains across encounters and isn't restored by winning fights. A boss approached with empty MP means your signal-hungry mnemonics are offline or running degraded. Restored at rest points.

The dungeon loop: AP resets each fight. HP and MP persist and drain. Rest points restore both. Arrive at the boss in the right shape — that's the puzzle.


SYSTEMS — STUBS
Sections to be written as design crystallizes.

Combat loop (token/keyword interplay, setup → transfer → detonate)
Turn structure (CT/PULSE system — carries over from V1, already implemented)
Character identity — stat growth + gear restrictions, no mnemonic eligibility gates. Any character can scribe and run any mnemonic. Identity is suggested by stats and gear, not enforced by the system. Running an off-identity mnemonic is hard but possible — low stats and mismatched gear say "are you sure?", not the game. Player expression over designer mandate.
Gear system — 1 weapon + 1 armor + N open slots. Open slots accept any mix of accessories (Shield, Boots, Cloak, Ring, etc.) or consumable items (Potion, Antidote, Bomb, etc.) freely. No pouch/bag abstraction — consumables are equipped directly into slots like gear. In combat, the item menu reflects whatever consumables are sitting in your slots. Every consumable slot is a slot not filled by gear — the tradeoff is the design. 4 open slots.
REZ economy — REZ is loot. Dropped by enemies, found in chests, authored and placed like gold. No performance scoring, no opaque calculation. Scarcity is the design lever — rare enough that every spend is a decision (new mnemonic vs ranking up existing). Tuned via drop tables. Party-wide resource.
Encounter design — authored only, no random encounters. Hand-placed, hand-paced, player-chosen engagement. Rest points restore HP + MP and are the only place to swap loadout (mnemonics, gear). Dungeon is a two-axis attrition puzzle — HP and MP both drain across encounters, both restored at rest. Arrive at the boss in the right shape. Encounter difficulty tuned assuming players may arrive depleted.
Progression — carries over intact from V1. XP → level up → dual-axis stat growth (base gains + player choice). See PROGRESSION section below.
RESONANCE — retired name. REZ is the skill currency. See REZ ECONOMY above.


SETTING & WORLD
Genre: Turn-based JRPG Setting: Post-singularity world with Baltic/Slavic-inspired tribal factions. Tone: FFT meets Xenogears. Grim, political, existential.

The singularity did not produce utopia. The boundary between information and matter has eroded — the unconscious layer, where emotion, belief, and hyperstition accumulate, seeps into physical reality wherever the signal is strong enough. This is not metaphor. Mnemonics are the physical evidence.

Six tribal factions survive in this world. Their politics, territories, and conflicts form the backdrop for the narrative. The world is not post-apocalyptic in the scorched-earth sense — it is post-transformation. Structures exist, people survive, but the rules of reality have shifted.

Note: Detailed faction names, territories, and political relationships are not yet authored in the GDD. This section expands as narrative design progresses.

Design Pillars:

Readability — Player can intuit outcomes without spreadsheets.
Build Identity — Same character, different loadout, different playstyle.
Ripples — Everything is a discrete, visible, manipulable event. Ripple is just a nice name for "TOKEN" (think darkest dungeon II)
Shared Investment — Party-wide resource decisions, not just individual progression.
Preparation Matters — Enemy knowledge is rewarded.
Exploration as Infrastructure — Traversal serves story and combat.
Scope Honesty — Solo dev reality informs every design choice.


CHARACTERS
In the final version, we’re planing for 6 characters permanent, some guests/temporary.
They are as follows: Skugge, Vargi, Milis, Yanik, Zorya, Vor, Terenas, Ghedi.

Character identity is expressed through stat growth curves (each character has different per-level base gains), gear access (weapon types and armor weight vary per character). No hard class gating exists — any character can carry any mnemonic. Identity is suggested by stats and gear, not enforced by the system.


COMBAT — TURN STRUCTURE
Party Size
3 characters. Final. 3 × loadout = the full toolkit for every encounter.

Enemy count per encounter: 1–6.
CT / PULSE Turn System
Turn order is governed by CT (Charge Time) and the PULSE stat.

Each actor has a CT value (float, 0.0–1.0+).
After each action, every non-downed actor accumulates CT equal to PULSE / 100 per tick.
The first actor to reach CT ≥ 1.0 takes their turn.
Acting subtracts 1.0 from CT — overflow is preserved, giving faster actors a head start on their next turn.
Tiebreaker: higher PULSE acts first.
PULSE is displayed as a plain integer (e.g., 10); the CT rate is derived at runtime.
Downed actors do not tick CT and cannot act.

This means higher-PULSE characters act noticeably more often over the course of a fight, not merely sooner in the first round. Tempo is a real stat.
Combat Encounter Flow
Good old classic random encounters with a fade in> fade out post combat. Minimizes asset load tbh.


Party wipe: Game Over → return to last save. No permadeath.
Stat Block
Resources (% growth per level, % allocation):

Stat
Purpose
HP
Survival. Some skills cost % of MaxHP to use. Persists across encounters.
MP
Magical attrition. Costs flat MP. Persists across encounters. Restored at rest points.


Offensive:

Stat
Purpose
Phys.Atk
Physical damage output
Magic.Atk
Magical damage output


Defensive:

Stat
Purpose
Phys.Def
Physical damage reduction
Magic.Def
Magical damage reduction


Utility:

Stat
Purpose
PULSE
CT accumulation rate — governs turn frequency
HIT
Physical accuracy
DODGE
Physical evasion
WARD
Magical evasion

Hit / Miss Formula
hitChance = clamp( (attacker.HIT × ChanceTier%) / defender.DODGE, 5%, 95% )

For magical skills, WARD replaces DODGE. 5% floor means nothing is impossible; 95% ceiling means nothing is guaranteed.
Crit System
Baseline 5% crit chance on all offensive skills (authored per skill, not global).
Crit = 1.5× damage (implemented); GDD target is 2×. Tune during balancing.
KEEN buff (stackable=false, persists until consumed) guarantees crit on the next physical hit.
Resistance & Damage Types
Physical damage types: Slash, Pierce, Blunt. Elemental damage types: Fire, Water, Air, Nature, Stone, Feral.

Resistance is a single axis from −100 (full weakness, 2.0×) through 0 (neutral, 1.0×) to 100+ (immune, 0×). The formula in code: multiplier = clamp(1f − resistStat / 100f, 0f, 2.0f).
AP Economy
All actors start combat with 3 AP.
Each actor gains +1 AP at the start of their turn.
AP carries over between turns (unspent AP accumulates — tempo pressure).
AP cap: ~12 (MaxAP stat, per character/enemy).
AP resets between encounters.
Enemies pay AP costs too. Every enemy has a 1–2 AP fallback skill so AP drain can't cause a permanent stall.

AP Cost
Skill Class
1–2
Basic attacks, weak skills, items
3–4
Core bread-and-butter skills
5–6
Strong skills
7–9
Powerful fight-changers
10–12
Ultimate abilities — boss charge-up attacks live here

Skill Costs
Physical skills (weapon/physical mnemonics) cost HP% + AP. Magical skills (elemental mnemonics) cost flat MP + AP.

Tier
HP% Cost
MP Cost
Minor/Weak
5%
4–8
Light/Solid
10%
12–20
Heavy
15%
25–35
Severe
20%
40+

Death
0 HP = Downed. Cannot act. Revivable mid-combat.
All party members downed = Game Over. Return to last save.
No permadeath.


COMBAT — RIPPLE FRAMEWORK
The core combat hook: ripple manipulation. Stack them, trigger them, strip them, combo them. Combat is reading and reacting to visible board state.
Six Ripple Types
Type
Player Reads As
Behavior
AILMENT
"I'm being hurt/disabled"
Ticks or expires; resistance-gated; tiered intensity
BUFF
"I'm stronger"
Duration-based; beneficial; always applies
DEBUFF
"They're weaker"
Duration-based; harmful; always applies if skill hits
STANCE
"I'm in a mode"
Persists until replaced/cancelled; multi-charge token
TRIGGER
"Something fires IF..."
Consumes when condition met; single-charge token
MARK
"This target is special"
Enables or empowers follow-up skills

Token Architecture
Tokens are objects, not counters. A BURN token is a discrete object that can be moved between combatants by transfer skills. Ripple count = duration (charges remaining). One charge consumed per tick. Intensity is fixed per type.

Generator / Transfer / Detonator pattern: Skills are designed as combo pieces. Every skill must have standalone value — combo payoff is the ceiling, not the floor. Full combo lines unlock gradually across progression (generator arrives before detonator in the unlock order).
Status Effects Reference
Elemental CC Ailments (apply-chance gated, resistance blocks landing):

Ailment
Effect
FREEZE (Water)
Action loss / speed debuff
WINDED (Air)
AP reduction
PETRIFY (Stone)
Skip turn(s)


Elemental DoTs (always land if skill hits; resistance scales tick damage):

DoT
Tag
Tick Formula
Passive Effect
BURN
Fire
MaxHP × 10% × resistMult
+fire damage taken while active
POISON
Nature
MaxHP × 10% + MaxMP × 10% × resistMult
—
BLEED
Feral
MaxHP × 10% × resistMult
Healing reduction while active


resistMult = clamp(1 − resistStat / 100, 0.0, 2.0)

Physical Debuffs (always apply if skill hits):

Debuff
Effect
WEAKEN
Reduced damage dealt
EXPOSE
Increased crit received
FRAIL
Reduced defense
SLOW
Turn order penalty
FEAR
Restricted actions
SILENCE
Can't use skills


Physical Buffs (always apply):

Buff
Effect
EMPOWER
Increased damage dealt
FOCUS
Increased crit/accuracy
FORTIFY
Reduced damage taken
HASTE
Turn order bonus
RESOLVE
Increased ailment resistance
ATTUNE
Reduced skill costs


Special stackable buffs:

MOMENTUM — +25% Phys.Atk per stack (physical only). Stacks consumed on next physical hit. Granted per enemy hit by CrimsonRhythm / BloodScent.
KEEN — guarantees crit on the next physical hit. PersistUntilConsumed. Applied by Stalk.

HoTs (tick on recipient's TurnStart):

HoT
Formula
Regen
MaxHP × 10% per tick
Vivify
MaxMP × 10% per tick
Rejuvenate
MaxHP × 10% + MaxMP × 10% per tick

Damage
Damage is Power-based. See Skill System → Skill Ranks → Damage Formula for the formula. There are no fixed multiplier tiers — Power is authored per skill effect and scales naturally through the Atk/Def ratio. The old EffectTier enum has been removed.


PROGRESSION — XP, LEVELS, STAT GROWTH
XP & Leveling
XP is earned from combat, per enemy defeated.
Level up = automatic base stat growth + player choice allocation (currently implemented as a 3-choice pick from generated stat options).
Max level: 99. (98 level-ups from level 1.)
REZ is separate — shared party resource for mnemonic acquisition, not tied to XP.
Dual-Layer Stat Growth
Layer
Description
Agency
Base Growth
Automatic per level. Varies by character — reinforces identity.
None
Choice Allocation
Player picks from generated stat options at each level-up.
Full control


Base growth ensures characters remain viable regardless of allocation. Choice allocation enables specialization.
Enemy AI
Enemies use the same skill resolution pipeline as the player. The AI layer only decides which skill and which target.

Two decision strategies:

Scripted (Gambit-style): ordered priority list of condition → action rules. Evaluated top-to-bottom; first match wins. Used for standard encounters.
Utility Scoring: every (skill, target) pair scored against current board state. Highest score wins with a small random band. Reserved for bosses and elites.

Behavior Profiles (for utility scoring):

Profile
Bias
Feral
Near-random, chaotic
Predator
Target the weakest / finish low HP
Bully
Pile on already-afflicted targets
Tactician
Spread control/ailments
Guardian
Protect allies, sustain
Berserker
Maximum raw damage, ignores ailments

Enemy Information Reveal
Enemy data is not fully visible on first encounter. Information persists permanently in save data per enemy type.

Always visible: name, race/type.
Discovered by hitting: damage type weaknesses and resistances — revealed automatically when triggered during combat.
Discovered post-combat: XP reward, loot table, enemy skills witnessed in combat.


GEAR SYSTEM
Slots
Each character has:

1 Weapon slot — always equipped; weapon type varies per character (e.g., Skugge uses daggers/swords, not bows).
1 Armor slot — armor weight class varies per character (Light/Medium/Heavy).
4 Open slots — accept any mix of accessories (Shield, Boots, Cloak, Ring, etc.) or consumable items (Potion, Antidote, Bomb, etc.) freely. No pouch/bag abstraction. Consumables sit directly in slots like gear.

In combat, the ITEM card lists whatever consumables are currently in a character's open slots. Every consumable slot is a slot not filled by combat gear — that tradeoff is the design.
Rule: One of each type per character
No duplicate gear types in the same loadout (e.g., no two shields). Exception: rings, if implemented.
Stat Modifiers
Gear provides flat stat modifiers (ATK, DEF, etc.) and elemental resistance values. Gear identity comes from what stats and resistances it provides, not from unlocking skill access.
Swapping
Loadout is locked at dungeon/rest-point entry. No mid-dungeon swapping. Preparation matters.


REZ ECONOMY
REZ is a shared party resource — not per-character. Dropped by enemies, found in chests. Spent to scribe new mnemonic instances from the Compendium, or to invest in mnemonic upgrades (rank progression).

Scarcity is the design lever. Rare enough that every spend is a real decision: new mnemonic vs. ranking up an existing one vs. scribing a copy for a second character. Drop tables control tuning.

No performance scoring, no opaque calculation. REZ is loot.


ENCOUNTER DESIGN
Encounters are authored only — no random encounters. Every fight is hand-placed, hand-paced, and player-chosen engagement.

Rest points restore HP and MP and are the only location where loadout can be swapped. The dungeon is a two-axis attrition puzzle: HP and MP both drain across encounters; both restore at rest. Arrive at the boss in the right shape.

Encounter difficulty is tuned assuming players may arrive depleted.



