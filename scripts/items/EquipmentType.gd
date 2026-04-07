class_name EquipmentType

enum Flags {
    None = 0,

    #WEAPONS
    Sword = 1 << 0,
    Dagger = 1 << 1,
    Axe = 1 << 2,
    Claw = 1 << 3,
    Mace = 1 << 4,
    Staff = 1 << 5,
    Bow = 1 << 6,
    
    #ARMOR
    LightArmor = 1 << 7,
    MediumArmor = 1 << 8,
    HeavyArmor = 1 << 9,

    #GEAR
    Shield = 1 << 10,
    Helmet = 1 << 11,
    Hat = 1 << 12,
    Cloak = 1 << 13,
    Boots = 1 << 14,
    Gloves = 1 << 15,
    Amulet = 1 << 16,
    Ring = 1 << 17
}