class_name ResistanceType

enum DamageType {
	Slash,
	Pierce,
	Blunt,
	Fire,   # covers Burn
	Water,  # covers Freeze
	Air,
	Nature, # covers Poison
	Stone,  # covers Petrify
	Feral,
	Bleed,
	Stun,
}

enum State {
	NONE,
	RESISTANT,
	WEAK,
	IMMUNE,
}
