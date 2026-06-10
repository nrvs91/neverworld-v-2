class_name StatCalculator
## Pure utility. Takes authored data + save state, returns compiled final stats.
## FUTURE: signature grows as systems come online.
##   compute_player(player_data, save_data, GearData[], MnemonicData[]) — once gear and
##   mnemonic passive stat mods exist, they join the pipeline here.

static func compute_player(player_data: PlayerData, save_data: CharacterSaveData) -> Dictionary:
	var stats: Dictionary = {
		CharacterStats.Stat.MaxHP: player_data.MaxHP,
		CharacterStats.Stat.MaxMP: player_data.MaxMP,
		CharacterStats.Stat.AtkPhys: player_data.AtkPhys,
		CharacterStats.Stat.AtkMag: player_data.AtkMag,
		CharacterStats.Stat.Hit: player_data.Hit,
		CharacterStats.Stat.DefPhys: player_data.DefPhys,
		CharacterStats.Stat.DefMag: player_data.DefMag,
		CharacterStats.Stat.Dodge: player_data.Dodge,
		CharacterStats.Stat.Pulse: player_data.Pulse,
	}
	if player_data.growth_table:
		var growth_count: int = mini(save_data.character_level - 1, player_data.growth_table.levels.size())
		for i in growth_count:
			var entry: GrowthEntry = player_data.growth_table.levels[i]
			stats[CharacterStats.Stat.MaxHP] += entry.MaxHP
			stats[CharacterStats.Stat.MaxMP] += entry.MaxMP
			stats[CharacterStats.Stat.AtkPhys] += entry.AtkPhys
			stats[CharacterStats.Stat.AtkMag] += entry.AtkMag
			stats[CharacterStats.Stat.Hit] += entry.Hit
			stats[CharacterStats.Stat.DefPhys] += entry.DefPhys
			stats[CharacterStats.Stat.DefMag] += entry.DefMag
			stats[CharacterStats.Stat.Dodge] += entry.Dodge
			stats[CharacterStats.Stat.Pulse] += entry.Pulse
	for stat in save_data.choice_bonuses:
		stats[stat] += save_data.choice_bonuses[stat]
	return stats

static func compute_enemy(enemy_data: EnemyData) -> Dictionary:
	return {
		CharacterStats.Stat.MaxHP: enemy_data.MaxHP,
		CharacterStats.Stat.Hit: enemy_data.Hit,
		CharacterStats.Stat.DefPhys: enemy_data.DefPhys,
		CharacterStats.Stat.DefMag: enemy_data.DefMag,
		CharacterStats.Stat.Dodge: enemy_data.Dodge,
		CharacterStats.Stat.Pulse: enemy_data.Pulse,
	}
