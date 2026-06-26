// ============================================================================
// Galactic Expanse — TypeScript type definitions
// Direct port of specs/types.qnt — MOO1 model
// ============================================================================

export type StarId   = number
export type EmpireId = number
export type FleetId  = number
export type DesignId = number
export type SpyId    = number

export interface Coord { x: number; y: number }

// ── Star classification ───────────────────────────────────────────────────
export type StarClass = 'Blue' | 'White' | 'Yellow' | 'Orange' | 'Red' | 'Neutron' | 'BlackHole'

// ── World attributes ──────────────────────────────────────────────────────
export type PlanetType =
  | 'Terran' | 'Ocean' | 'Arid' | 'Tundra' | 'Desert'
  | 'Inferno' | 'Toxic' | 'Radiated' | 'Dead' | 'Barren'

export type PlanetSize = 'Tiny' | 'Small' | 'Medium' | 'Large' | 'Huge'

// ── Technology ────────────────────────────────────────────────────────────
export type TechField = 'Physics' | 'Biology' | 'Computers' | 'Construction' | 'ForceFields' | 'Planetology'

export type TechName =
  // Physics
  | 'LaserCannon' | 'MassDriver' | 'GatlingLaser' | 'FusionBeam' | 'IonCannon'
  | 'NeutronBomb' | 'MegaBoltCannon' | 'PhasorCannon' | 'DisruptorCannon'
  | 'AntiMatterBomb' | 'DeathRay' | 'StellarConverter'
  // Biology
  | 'CloneCenter' | 'BioToxinWarhead' | 'GeneticMutation' | 'BioTerminator' | 'SoilEnrichment'
  // Computers
  | 'BattleScanner' | 'TachyonComms' | 'EcmJammer' | 'Eccm'
  | 'BattleComputer1' | 'BattleComputer2' | 'BattleComputer3'
  | 'AndroidWorkers' | 'AndroidScientists'
  | 'RoboticControls2' | 'RoboticControls3' | 'RoboticControls4' | 'RoboticControls5'
  // Construction
  | 'NuclearEngines' | 'FusionEngines' | 'IonDrive' | 'SubSpaceDrive' | 'HyperDrive' | 'InterphasedDrive'
  | 'TitaniumArmour' | 'TritaniumArmour' | 'ZortiumArmour' | 'AdamantiumArmour' | 'NeutroniumArmour'
  | 'IndustrialTech9' | 'IndustrialTech10' | 'AutomatedFactory'
  // Force Fields
  | 'Class1Shield' | 'Class3Shield' | 'Class5Shield' | 'Class7Shield' | 'Class10Shield'
  | 'Class15Shield' | 'Class20Shield' | 'Class25Shield' | 'Class30Shield'
  | 'PlanetaryShield5' | 'PlanetaryShield10' | 'PlanetaryShield15' | 'PlanetaryShield20'
  | 'RepulsorBeam' | 'StasisField' | 'InertialStabilizer' | 'LightningField'
  | 'WarpInterdictor' | 'PointDefenceSys'
  // Planetology
  | 'AtmosphericRenewer' | 'RadiationShield_' | 'ControlledEnviron'
  | 'Biospheres' | 'TerraformingMed' | 'TerraformingMax'
  | 'EcoRestoration' | 'AdvancedEcology'

// ── Races ─────────────────────────────────────────────────────────────────
export type Race =
  | 'Humans' | 'Psilon' | 'Sakkra' | 'Bulrathi' | 'Mrrshan'
  | 'Klackon' | 'Meklar' | 'Alkari' | 'Silicoid' | 'Darlok'

export const ALL_RACES: Race[] = ['Humans','Psilon','Sakkra','Bulrathi','Mrrshan','Klackon','Meklar','Alkari','Silicoid','Darlok']

// ── Ship design ───────────────────────────────────────────────────────────
export type ShipHull = 'Scout' | 'ColonyShip' | 'Destroyer' | 'Cruiser' | 'Battleship' | 'Titan' | 'DoomStar'

export interface WeaponSlot  { tech: TechName; count: number }
export interface SpecialSlot { tech: TechName }

export interface ShipDesign {
  id:       DesignId
  owner:    EmpireId
  hull:     ShipHull
  weapons:  WeaponSlot[]
  specials: SpecialSlot[]
  cost:     number
  upkeep:   number
  attack:   number  // beam damage per round
  hp:       number  // max hit points
}

export interface Ship {
  design:    DesignId
  currentHp: number
  maxHp:     number
}

// ── Spending sliders ──────────────────────────────────────────────────────
export interface SpendingAlloc {
  ships:    number  // 0-100
  defense:  number
  industry: number
  ecology:  number
  research: number
  // invariant: sum == 100
}

// ── Colony ────────────────────────────────────────────────────────────────
export interface Colony {
  star:         StarId
  owner:        EmpireId
  population:   number  // millions
  maxPop:       number
  factories:    number
  maxFactories: number
  pollution:    number
  missileBases: number
  shieldLevel:  number  // 0-4
  spending:     SpendingAlloc
  buildQueue:   DesignId[]
  ppAccrued:    number
}

// ── Empire ────────────────────────────────────────────────────────────────
export interface Empire {
  id:          EmpireId
  race:        Race
  homeStar:    StarId
  bc:          number
  taxRate:     number    // 0-50
  contacts:    Set<EmpireId>
  techs:       Set<TechName>
  rpAccum:     number
  researching: TechName
  eliminated:  boolean
  color:       number    // PixiJS hex colour for this empire
}

// ── Spies ─────────────────────────────────────────────────────────────────
export type SpyMission =
  | { type: 'Defend';            target: EmpireId }
  | { type: 'StealTech';         target: EmpireId }
  | { type: 'SabotageIndustry';  target: EmpireId }
  | { type: 'Assassinate';       target: EmpireId }

export interface Spy {
  id:      SpyId
  owner:   EmpireId
  level:   number
  mission: SpyMission
}

// ── Ground troops ─────────────────────────────────────────────────────────
export interface GroundForce { owner: EmpireId; strength: number }

// ── Diplomacy ─────────────────────────────────────────────────────────────
export type Relation = 'AtWar' | 'Neutral' | 'Peace' | 'Alliance'

export type DiplomaticOffer =
  | 'OfferPeace' | 'OfferAlliance' | 'BreakAlliance'
  | 'DeclareWar' | 'OfferTechTrade' | 'DemandTribute'

export interface PendingOffer {
  sender:    EmpireId
  recipient: EmpireId
  offer:     DiplomaticOffer
}

// ── Fleet ─────────────────────────────────────────────────────────────────
export type FleetOrder =
  | { type: 'HoldPosition' }
  | { type: 'MoveTo';         destination: StarId }
  | { type: 'ColoniseStar' }
  | { type: 'BombardStar' }
  | { type: 'ReturnToBase' }
  | { type: 'LoadColonists';  count: number }
  | { type: 'UnloadColonists' }

export interface Fleet {
  id:          FleetId
  owner:       EmpireId
  location:    StarId
  destination: StarId
  transitPct:  number    // 0-1 visual progress toward destination
  ships:       Ship[]
  troops:      GroundForce
  colonists:   number
  order:       FleetOrder
  fuelRangeSq: number
}

// ── Star system ───────────────────────────────────────────────────────────
export interface StarSystem {
  id:         StarId
  name:       string
  class_:     StarClass
  coords:     Coord
  planetType: PlanetType
  size:       PlanetSize
  richness:   number    // 0-4
  maxPopBase: number
  explored:   Set<EmpireId>
}

// ── Galactic Council ──────────────────────────────────────────────────────
export interface CouncilSession {
  candidate: EmpireId
  votes:     Map<EmpireId, number>
}

// ── Turn structure ────────────────────────────────────────────────────────
export type TurnPhase =
  | 'OrdersPhase' | 'ProductionPhase' | 'MovementPhase' | 'CombatPhase'
  | 'InvasionPhase' | 'GrowthPhase' | 'SpyPhase' | 'CouncilPhase' | 'VictoryCheckPhase'

export type VictoryKind = 'ConquestVictory' | 'CouncilVictory'

export interface VictoryResult {
  winner:     EmpireId
  kind:       VictoryKind
  turnNumber: number
}

// ── Complete game state ───────────────────────────────────────────────────
export interface GameState {
  // Galaxy
  stars:       Map<StarId, StarSystem>
  // Empires
  empires:     Map<EmpireId, Empire>
  colonies:    Colony[]
  spies:       Spy[]
  techOptions: Map<EmpireId, TechName[]>
  designs:     Map<DesignId, ShipDesign>
  nextDesignId: DesignId
  nextFleetId:  FleetId
  nextSpyId:    SpyId
  // Combat
  fleets:      Map<FleetId, Fleet>
  combatRound: number
  // Turn
  turn:          number
  phase:         TurnPhase
  relations:     Map<EmpireId, Map<EmpireId, Relation>>
  pendingOffers: PendingOffer[]
  council:       CouncilSession | null
  winner:        VictoryResult | null
  contacts:      Map<EmpireId, Set<EmpireId>>
  // UI state (not part of formal spec)
  playerId:      EmpireId
  selectedStar:  StarId | null
  selectedFleet: FleetId | null
  log:           string[]
}
