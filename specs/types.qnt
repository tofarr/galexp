// ============================================================================
// types.qnt — Galactic Expanse (Master of Orion I model): complete type vocabulary
//
// Design reference: Master of Orion (1993, Simtex / MicroProse)
//
// Phase 1 additions vs previous version:
//   • Colony.buildQueue (replaces buildingShip) + ppAccrued for queue progress
//   • Empire.taxRate, Empire.contacts
//   • Fleet.colonists for population relocation
//   • FleetOrder.LoadColonists / UnloadColonists
//   • TechName additions: WarpInterdictor, PointDefenceSys, OrbitalBase tech chain
//   • DefenseStructure type for the missile-base / orbital-base distinction
// ============================================================================

module types {

  // ── Primitive identifiers ─────────────────────────────────────────────────

  type StarId   = int
  type EmpireId = int
  type FleetId  = int
  type DesignId = int
  type SpyId    = int

  // ── Galaxy coordinates ────────────────────────────────────────────────────

  type Coord = { x: int, y: int }

  // ── Star classification ───────────────────────────────────────────────────

  type StarClass =
    | Blue      // rare; excellent worlds
    | White     // above average
    | Yellow    // standard Sol-type
    | Orange    // below average
    | Red       // dim; poor worlds; most common
    | Neutron   // no world possible
    | BlackHole // no world possible

  // ── World (planet) type & size ────────────────────────────────────────────
  //
  // Each star has exactly ONE world.  Attributes live on StarSystem.
  // Barren means the system has no colonisable world at all.

  type PlanetType =
    | Terran    // best population ceiling and production
    | Ocean
    | Arid
    | Tundra
    | Desert
    | Inferno   // requires ControlledEnviron tech (all races except Silicoid)
    | Toxic     // requires AtmosphericRenewer tech
    | Radiated  // requires RadiationShield_ tech
    | Dead      // colonisable by anyone; minimal resources
    | Barren    // no world — system cannot ever be colonised

  // Base max-pop by size (millions): Tiny=2 Small=4 Medium=5 Large=6 Huge=8
  type PlanetSize = Tiny | Small | Medium | Large | Huge

  // ── Technology ───────────────────────────────────────────────────────────
  //
  // SIX fields; each contains specific named technologies.
  // An empire researches one technology at a time, then is offered a random
  // subset of the next available options (Psilon receive all of them).

  type TechField =
    | Physics
    | Biology
    | Computers
    | Construction
    | ForceFields
    | Planetology

  type TechName =
    // ── Physics ──────────────────────────────────────────────────────────
    | LaserCannon
    | MassDriver
    | GatlingLaser
    | FusionBeam
    | IonCannon
    | NeutronBomb        // kills pop; leaves factories
    | MegaBoltCannon
    | PhasorCannon
    | DisruptorCannon    // bypasses shields
    | AntiMatterBomb
    | DeathRay
    | StellarConverter   // ultimate; destroys a world (req: AntiMatterBomb)
    // ── Biology ──────────────────────────────────────────────────────────
    | CloneCenter        // accelerates population growth
    | BioToxinWarhead    // orbital bomb; kills pop
    | GeneticMutation    // one-time population boost
    | BioTerminator      // enhanced bioweapon
    | SoilEnrichment     // raises world richness by 1 (applied once)
    // ── Computers ────────────────────────────────────────────────────────
    | BattleScanner
    | TachyonComms
    | EcmJammer
    | Eccm
    | BattleComputer1    // initiative +1; +10 beam accuracy
    | BattleComputer2    // initiative +2; +20 accuracy (req: BC1)
    | BattleComputer3    // initiative +3; +30 accuracy (req: BC2)
    | AndroidWorkers     // +BASE_ANDROID_PP PP per colony; no pop slot used
    | AndroidScientists  // +BASE_ANDROID_RP RP per colony; no pop slot used
    | RoboticControls2   // factory cap = 2 × population
    | RoboticControls3   // req: RC2
    | RoboticControls4   // req: RC3
    | RoboticControls5   // req: RC4
    // ── Construction ─────────────────────────────────────────────────────
    | NuclearEngines     // squared range 9  (starting drive)
    | FusionEngines      // squared range 16 (req: NuclearEngines)
    | IonDrive           // squared range 25 (req: FusionEngines)
    | SubSpaceDrive      // squared range 36 (req: IonDrive)
    | HyperDrive         // squared range 49 (req: SubSpaceDrive)
    | InterphasedDrive   // squared range 64; immune to WarpInterdictor (req: HyperDrive)
    | TitaniumArmour
    | TritaniumArmour
    | ZortiumArmour
    | AdamantiumArmour
    | NeutroniumArmour
    | IndustrialTech9    // reduces factory build cost (starting)
    | IndustrialTech10
    | AutomatedFactory   // +1 PP per active factory empire-wide
    // ── Force Fields ─────────────────────────────────────────────────────
    | Class1Shield
    | Class3Shield       // req: Class1Shield
    | Class5Shield       // req: Class3Shield
    | Class7Shield       // req: Class5Shield
    | Class10Shield      // req: Class7Shield
    | Class15Shield      // req: Class10Shield
    | Class20Shield      // req: Class15Shield
    | Class25Shield      // req: Class20Shield
    | Class30Shield      // req: Class25Shield (ultimate)
    | PlanetaryShield5   // reduces orbital bombardment damage (defense slider output)
    | PlanetaryShield10  // req: PlanetaryShield5
    | PlanetaryShield15  // req: PlanetaryShield10
    | PlanetaryShield20  // req: PlanetaryShield15 (ultimate)
    | RepulsorBeam       // pushes enemy ships back in combat
    | StasisField        // freezes a target ship for several rounds
    | InertialStabilizer // halves incoming beam damage during movement
    | LightningField     // area-effect damage to all enemy ships
    | WarpInterdictor    // prevents enemy ships from retreating (req: StasisField)
    | PointDefenceSys    // intercepts incoming missiles and torpedoes
    // ── Planetology ──────────────────────────────────────────────────────
    | AtmosphericRenewer   // allows Toxic world colonisation
    | RadiationShield_     // allows Radiated world colonisation
    | ControlledEnviron    // allows Inferno world colonisation
    | Biospheres           // +2 max pop empire-wide
    | TerraformingMed      // advances world type one step toward Terran
    | TerraformingMax      // advances world type to Terran (ultimate; req: TerraformingMed)
    | EcoRestoration       // removes all existing pollution instantly
    | AdvancedEcology      // halves pollution rate empire-wide

  // ── Races ────────────────────────────────────────────────────────────────

  type Race =
    | Humans    // +50% diplomacy; balanced stats
    | Psilon    // Creative: all tech options simultaneously
    | Sakkra    // ×2 population growth rate
    | Bulrathi  // +50% ground-combat attack strength
    | Mrrshan   // +50% beam-weapon accuracy; start with BattleComputer1
    | Klackon   // +25% factory output; start with extra robotic tech
    | Meklar    // Cybernetic: +1 factory cap above Robotic Controls limit
    | Alkari    // +25% ship defence; smaller hit profile
    | Silicoid  // Lithovore: colonise any world; no Barren restriction
    | Darlok    // +50% spy success; −50% detection; start with EcmJammer

  // ── Ship design ───────────────────────────────────────────────────────────

  type ShipHull =
    | Scout
    | ColonyShip   // no weapons; carries colonists for founding
    | Destroyer
    | Cruiser
    | Battleship
    | Titan
    | DoomStar

  type WeaponSlot  = { tech: TechName, count: int }
  type SpecialSlot = { tech: TechName }

  type ShipDesign = {
    id:       DesignId,
    owner:    EmpireId,
    hull:     ShipHull,
    weapons:  List[WeaponSlot],
    specials: List[SpecialSlot],
    cost:     int,   // BC to build
    upkeep:   int    // BC per turn maintenance
  }

  type Ship = {
    design:    DesignId,
    currentHp: int,
    maxHp:     int
  }

  // ── Spending sliders ──────────────────────────────────────────────────────
  //
  // ships + defense + industry + ecology + research == 100 (invariant)
  //
  // Ships    → progress toward head of build queue
  // Defense  → builds missile bases; upgrades planetary shield
  // Industry → builds factories (up to Robotic Controls cap)
  // Ecology  → removes pollution
  // Research → produces RP toward active research target

  type SpendingAlloc = {
    ships:    int,
    defense:  int,
    industry: int,
    ecology:  int,
    research: int
  }

  // ── Colony ───────────────────────────────────────────────────────────────
  //
  // buildQueue: ordered list of DesignIds to build; head is current project.
  //             Empty = no ship being built.
  // ppAccrued:  PP accumulated toward cost of buildQueue head this and prior turns.
  // missileBases: count of orbital missile platforms (defensive firepower).
  // shieldLevel:  planetary shield tier (0=none; 1-4 matching PlanetaryShield techs).

  type Colony = {
    star:         StarId,
    owner:        EmpireId,
    population:   int,
    maxPop:       int,
    factories:    int,
    maxFactories: int,
    pollution:    int,
    missileBases: int,
    shieldLevel:  int,
    spending:     SpendingAlloc,
    buildQueue:   List[int],   // List[DesignId]; head is active build
    ppAccrued:    int          // PP banked toward head of buildQueue
  }

  // ── Empire ───────────────────────────────────────────────────────────────
  //
  // taxRate:  empire-wide tax percentage (0–50); generates BC from colonies each turn.
  // contacts: set of empire IDs this empire has established contact with.
  //           Trade income and diplomacy only apply between contacted empires.

  type Empire = {
    id:          EmpireId,
    race:        Race,
    homeStar:    StarId,
    bc:          int,
    taxRate:     int,          // 0–50 (percent)
    contacts:    Set[EmpireId],
    techs:       Set[TechName],
    rpAccum:     int,
    researching: TechName,
    eliminated:  bool
  }

  // ── Spies ────────────────────────────────────────────────────────────────

  type SpyMission =
    | Defend(EmpireId)
    | StealTech(EmpireId)
    | SabotageIndustry(EmpireId)
    | Assassinate(EmpireId)

  type Spy = {
    id:      SpyId,
    owner:   EmpireId,
    level:   int,
    mission: SpyMission
  }

  // ── Ground troops ─────────────────────────────────────────────────────────

  type GroundForce = {
    owner:    EmpireId,
    strength: int
  }

  // ── Diplomacy ─────────────────────────────────────────────────────────────

  type Relation =
    | AtWar
    | Neutral
    | Peace
    | Alliance

  type DiplomaticOffer =
    | OfferPeace
    | OfferAlliance
    | BreakAlliance
    | DeclareWar
    | OfferTechTrade
    | DemandTribute

  // ── Fleet & movement ──────────────────────────────────────────────────────
  //
  // No hyperlanes; any star within fuelRangeSq is reachable in one turn.
  // colonists: pop units embarked for colony-to-colony relocation (not founding).

  type FleetOrder =
    | HoldPosition
    | MoveTo(StarId)
    | ColoniseStar          // land colony ship colonists; founds new colony
    | BombardStar           // orbital bombardment of star's enemy colony
    | ReturnToBase
    | LoadColonists(int)    // embark N million colonists from current colony
    | UnloadColonists       // disembark all embarked colonists at current colony

  type Fleet = {
    id:          FleetId,
    owner:       EmpireId,
    location:    StarId,
    destination: StarId,
    ships:       List[Ship],
    troops:      GroundForce,
    colonists:   int,          // colonists in transit for relocation (not founding)
    order:       FleetOrder,
    fuelRangeSq: int
  }

  // ── Star system ───────────────────────────────────────────────────────────

  type StarSystem = {
    id:         StarId,
    class_:     StarClass,
    coords:     Coord,
    planetType: PlanetType,   // Barren = no world
    size:       PlanetSize,
    richness:   int,          // 0 (Ultra Poor) to 4 (Ultra Rich)
    maxPopBase: int,
    explored:   Set[EmpireId]
  }

  // ── Galactic Council ──────────────────────────────────────────────────────

  type CouncilSession = {
    candidate: EmpireId,
    votes:     EmpireId -> int
  }

  // ── Turn structure ────────────────────────────────────────────────────────
  //
  // Orders phase: all empires submit spending adjustments, build queue changes,
  // fleet orders, and spy assignments simultaneously (UI collects them all
  // before advancing to ProductionPhase).

  type TurnPhase =
    | OrdersPhase
    | ProductionPhase
    | MovementPhase
    | CombatPhase
    | InvasionPhase
    | GrowthPhase
    | SpyPhase
    | CouncilPhase
    | VictoryCheckPhase

  type VictoryKind =
    | ConquestVictory
    | CouncilVictory

  type VictoryResult = {
    winner:     EmpireId,
    kind:       VictoryKind,
    turnNumber: int
  }
}
