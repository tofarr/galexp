// Engine constants — mirrors the Quint module constants with tuned defaults

export const C = {
  // Galaxy
  MAP_W:              100,
  MAP_H:              100,
  MIN_STAR_DIST_SQ:   36,   // 6-unit min spacing
  MIN_HOME_DIST_SQ:   400,  // 20-unit homeworld separation
  MAX_RICHNESS:       4,

  // Empire / colony
  BASE_PP_PER_FACTORY:    1,
  POLLUTION_PER_FACTORY:  1,
  ECOLOGY_CLEANUP_RATE:   2,
  COLONY_SHIP_POP:        2,
  BASE_ANDROID_PP:        5,
  BASE_ANDROID_RP:        5,
  TRADE_FACTOR:           10,
  MAX_MISSILE_BASES:      5,
  MISSILE_BASE_HP:        10,
  SCRAP_REFUND_PCT:       25,

  // Combat
  MAX_COMBAT_ROUNDS:        40,
  MAX_FLEETS:               500,
  BOMBARDMENT_DMG_PER_SHIP: 2,

  // Turn
  COUNCIL_POP_THRESHOLD_PCT: 33,
  SPY_SUCCESS_BASE_PCT:      30,
  TURN_LIMIT:                200,
} as const

// Hull stats
export const HULL_HP: Record<string, number> = {
  Scout:      15,
  ColonyShip: 10,
  Destroyer:  30,
  Cruiser:    60,
  Battleship: 100,
  Titan:      160,
  DoomStar:   250,
}

export const HULL_COST: Record<string, number> = {
  Scout:       10,
  ColonyShip:  40,
  Destroyer:   60,
  Cruiser:     120,
  Battleship:  200,
  Titan:       350,
  DoomStar:    600,
}

export const HULL_UPKEEP: Record<string, number> = {
  Scout:       0,
  ColonyShip:  0,
  Destroyer:   2,
  Cruiser:     4,
  Battleship:  8,
  Titan:       14,
  DoomStar:    25,
}

export const HULL_ATTACK: Record<string, number> = {
  Scout:       5,
  ColonyShip:  0,
  Destroyer:   15,
  Cruiser:     25,
  Battleship:  40,
  Titan:       60,
  DoomStar:    100,
}

export const PLANET_BASE_POP: Record<string, number> = {
  Tiny:   2,
  Small:  4,
  Medium: 5,
  Large:  6,
  Huge:   8,
}

// RP cost to research each technology (flat table; tuned for balance)
export const TECH_COST: Record<string, number> = {
  NuclearEngines: 80,     FusionEngines: 180,    IonDrive: 320,
  SubSpaceDrive: 500,     HyperDrive: 720,       InterphasedDrive: 1000,
  LaserCannon: 50,        MassDriver: 80,        GatlingLaser: 160,
  FusionBeam: 260,        IonCannon: 380,        NeutronBomb: 450,
  MegaBoltCannon: 540,    PhasorCannon: 640,     DisruptorCannon: 760,
  AntiMatterBomb: 900,    DeathRay: 1100,        StellarConverter: 1400,
  CloneCenter: 100,       BioToxinWarhead: 300,  GeneticMutation: 400,
  BioTerminator: 700,     SoilEnrichment: 220,
  BattleScanner: 80,      TachyonComms: 150,     EcmJammer: 180,
  Eccm: 260,              BattleComputer1: 120,  BattleComputer2: 260,
  BattleComputer3: 440,   AndroidWorkers: 360,   AndroidScientists: 460,
  RoboticControls2: 60,   RoboticControls3: 160, RoboticControls4: 340,
  RoboticControls5: 580,
  TitaniumArmour: 80,     TritaniumArmour: 200,  ZortiumArmour: 380,
  AdamantiumArmour: 600,  NeutroniumArmour: 900,
  IndustrialTech9: 50,    IndustrialTech10: 120, AutomatedFactory: 500,
  Class1Shield: 80,       Class3Shield: 160,     Class5Shield: 280,
  Class7Shield: 420,      Class10Shield: 600,    Class15Shield: 800,
  Class20Shield: 1000,    Class25Shield: 1200,   Class30Shield: 1500,
  PlanetaryShield5: 200,  PlanetaryShield10: 420,PlanetaryShield15: 700,
  PlanetaryShield20: 1000,
  RepulsorBeam: 260,      StasisField: 480,      InertialStabilizer: 180,
  LightningField: 600,    WarpInterdictor: 720,  PointDefenceSys: 340,
  AtmosphericRenewer: 250,RadiationShield_: 250, ControlledEnviron: 300,
  Biospheres: 400,        TerraformingMed: 600,  TerraformingMax: 900,
  EcoRestoration: 350,    AdvancedEcology: 550,
}

// Tech field membership
export const TECH_FIELD: Record<string, string> = {
  LaserCannon:'Physics', MassDriver:'Physics', GatlingLaser:'Physics',
  FusionBeam:'Physics', IonCannon:'Physics', NeutronBomb:'Physics',
  MegaBoltCannon:'Physics', PhasorCannon:'Physics', DisruptorCannon:'Physics',
  AntiMatterBomb:'Physics', DeathRay:'Physics', StellarConverter:'Physics',

  CloneCenter:'Biology', BioToxinWarhead:'Biology', GeneticMutation:'Biology',
  BioTerminator:'Biology', SoilEnrichment:'Biology',

  BattleScanner:'Computers', TachyonComms:'Computers', EcmJammer:'Computers',
  Eccm:'Computers', BattleComputer1:'Computers', BattleComputer2:'Computers',
  BattleComputer3:'Computers', AndroidWorkers:'Computers', AndroidScientists:'Computers',
  RoboticControls2:'Computers', RoboticControls3:'Computers',
  RoboticControls4:'Computers', RoboticControls5:'Computers',

  NuclearEngines:'Construction', FusionEngines:'Construction', IonDrive:'Construction',
  SubSpaceDrive:'Construction', HyperDrive:'Construction', InterphasedDrive:'Construction',
  TitaniumArmour:'Construction', TritaniumArmour:'Construction', ZortiumArmour:'Construction',
  AdamantiumArmour:'Construction', NeutroniumArmour:'Construction',
  IndustrialTech9:'Construction', IndustrialTech10:'Construction', AutomatedFactory:'Construction',

  Class1Shield:'ForceFields', Class3Shield:'ForceFields', Class5Shield:'ForceFields',
  Class7Shield:'ForceFields', Class10Shield:'ForceFields', Class15Shield:'ForceFields',
  Class20Shield:'ForceFields', Class25Shield:'ForceFields', Class30Shield:'ForceFields',
  PlanetaryShield5:'ForceFields', PlanetaryShield10:'ForceFields',
  PlanetaryShield15:'ForceFields', PlanetaryShield20:'ForceFields',
  RepulsorBeam:'ForceFields', StasisField:'ForceFields', InertialStabilizer:'ForceFields',
  LightningField:'ForceFields', WarpInterdictor:'ForceFields', PointDefenceSys:'ForceFields',

  AtmosphericRenewer:'Planetology', RadiationShield_:'Planetology',
  ControlledEnviron:'Planetology', Biospheres:'Planetology',
  TerraformingMed:'Planetology', TerraformingMax:'Planetology',
  EcoRestoration:'Planetology', AdvancedEcology:'Planetology',
}

// Empire palette (PixiJS hex colours)
export const EMPIRE_COLORS = [
  0x4488ff,  // Blue  (player)
  0xff4444,  // Red
  0x44ff88,  // Green
  0xffaa00,  // Orange
  0xaa44ff,  // Purple
  0x00ccff,  // Cyan
  0xff44aa,  // Pink
  0xffff44,  // Yellow
]
