// ============================================================================
// types.qnt — Galactic Expanse (Master of Orion I model): core type vocabulary
//
// Design reference: Master of Orion (1993, Simtex / MicroProse)
//
// Key simplifications vs MOO2:
//   • Each star has ONE colonisable world — no separate Planet sub-type.
//     The world's attributes (type, size, richness) sit directly on StarSystem.
//   • No food system.  Population grows naturally toward the planet's cap.
//   • Production is divided via five spending sliders (Ships / Defense /
//     Industry / Ecology / Research) rather than worker-type assignments.
//   • 10 fixed races with hardcoded bonuses (no custom trait-picking).
//   • 6 named tech fields; each field contains specific named technologies.
//   • Victory: Conquest OR Galactic Council election (≥ 2/3 majority).
// ============================================================================

module types {

  // ── Primitive identifiers ─────────────────────────────────────────────────

  type StarId   = int
  type EmpireId = int
  type FleetId  = int
  type DesignId = int
  type SpyId    = int

  // ── Galaxy coordinates ────────────────────────────────────────────────────
  //
  // Stars sit on a 2-D integer grid.  Distances are stored as squared
  // Euclidean values to avoid floating-point arithmetic.

  type Coord = { x: int, y: int }

  // ── Star classification ───────────────────────────────────────────────────
  //
  // Star colour determines the quality of the system's colonisable world.
  // Blue / White → higher quality.  Red → most common, poorer worlds.
  // Neutron / Black Hole → no colony possible.

  type StarClass =
    | Blue
    | White
    | Yellow
    | Orange
    | Red
    | Neutron
    | BlackHole

  // ── Planet / world attributes ─────────────────────────────────────────────
  //
  // Every star has exactly ONE colonisable world (or none for Neutron/BlackHole).
  // The world's properties are stored directly on StarSystem — there is no
  // separate Planet entity or PlanetId.

  // World type affects colonisation requirements and max population.
  // Inferno / Toxic / Radiated require specific technologies to colonise,
  // except for Silicoid who can colonise any world from the start.
  type PlanetType =
    | Terran    // best: highest population cap
    | Ocean     // good cap; moderate production
    | Arid      // adequate cap; decent production
    | Tundra    // moderate all-round
    | Desert    // below-average cap
    | Inferno   // uninhabitable without Controlled Environment tech
    | Toxic     // uninhabitable without Atmospheric Renewer tech
    | Radiated  // uninhabitable without Radiation Shield tech
    | Dead      // minimal cap; colonisable by anyone
    | Barren    // no world — system has no colonisable planet

  // World size determines base population ceiling (millions):
  //   Tiny=2  Small=4  Medium=5  Large=6  Huge=8  (before Biospheres)
  type PlanetSize = Tiny | Small | Medium | Large | Huge

  // ── Technology ───────────────────────────────────────────────────────────
  //
  // SIX tech fields.  An empire researches one named technology at a time.
  // On completion it chooses the next from a random subset (engine: the game).
  // Psilon (Creative) receive all available options simultaneously.

  type TechField =
    | Physics      // beam weapons, bombs, power
    | Biology      // population growth, bioweapons
    | Computers    // sensors, ECM/ECCM, androids, targeting
    | Construction // engines, hull armour, factory upgrades
    | ForceFields  // ship & planetary shields, stasis, repulsors
    | Planetology  // terraforming, atmosphere, ecology

  type TechName =
    // ── Physics ──────────────────────────────────────────────────────────
    | LaserCannon
    | MassDriver
    | GatlingLaser
    | FusionBeam
    | IonCannon
    | NeutronBomb       // kills population; leaves factories intact
    | MegaBoltCannon
    | PhasorCannon
    | DisruptorCannon   // bypasses shields
    | AntiMatterBomb
    | DeathRay
    | StellarConverter  // ultimate; can destroy a world (req: AntiMatterBomb)
    // ── Biology ──────────────────────────────────────────────────────────
    | CloneCenter       // accelerates population growth rate
    | BioToxinWarhead   // orbital bomb; kills population
    | GeneticMutation   // one-time empire-wide population boost
    | BioTerminator     // enhanced bioweapon warhead
    | SoilEnrichment    // permanently increases world richness by 1
    // ── Computers ────────────────────────────────────────────────────────
    | BattleScanner
    | TachyonComms
    | EcmJammer
    | Eccm
    | BattleComputer1   // +10 beam accuracy
    | BattleComputer2   // +20 beam accuracy (req: BattleComputer1)
    | BattleComputer3   // +30 beam accuracy (req: BattleComputer2)
    | AndroidWorkers    // android workers: +1 PP without consuming pop slot
    | AndroidScientists // android workers: +1 RP without consuming pop slot
    | RoboticControls2  // factory cap = 2× population
    | RoboticControls3  // factory cap = 3× population (req: RC2)
    | RoboticControls4  // factory cap = 4× population (req: RC3)
    | RoboticControls5  // factory cap = 5× population (req: RC4)
    // ── Construction ─────────────────────────────────────────────────────
    | NuclearEngines    // starting drive; squared range 9
    | FusionEngines     // squared range 16 (req: NuclearEngines)
    | IonDrive          // squared range 25 (req: FusionEngines)
    | SubSpaceDrive     // squared range 36 (req: IonDrive)
    | HyperDrive        // squared range 49 (req: SubSpaceDrive)
    | InterphasedDrive  // squared range 64; immune to interdictor (req: HyperDrive)
    | TitaniumArmour
    | TritaniumArmour
    | ZortiumArmour
    | AdamantiumArmour
    | NeutroniumArmour  // ultimate hull armour
    | IndustrialTech9   // starting; reduces factory build cost
    | IndustrialTech10
    | AutomatedFactory  // +1 PP per active factory empire-wide
    // ── Force Fields ─────────────────────────────────────────────────────
    | Class1Shield
    | Class3Shield
    | Class5Shield
    | Class7Shield
    | Class10Shield
    | Class15Shield
    | Class20Shield
    | Class25Shield
    | Class30Shield     // ultimate shield
    | PlanetaryShield5  // defensive planetary shield level 5
    | PlanetaryShield10
    | PlanetaryShield15
    | PlanetaryShield20 // ultimate planetary defence shield
    | RepulsorBeam
    | StasisField
    | InertialStabilizer
    | LightningField
    // ── Planetology ──────────────────────────────────────────────────────
    | AtmosphericRenewer  // allows Toxic world colonisation
    | RadiationShield_    // allows Radiated world colonisation
    | ControlledEnviron   // allows Inferno world colonisation
    | Biospheres          // +2 max population empire-wide
    | TerraformingMed     // raises world type one step toward Terran
    | TerraformingMax     // raises world type to Terran (ultimate)
    | EcoRestoration      // removes all existing pollution instantly
    | AdvancedEcology     // halves pollution rate empire-wide

  // ── Races ────────────────────────────────────────────────────────────────
  //
  // Exactly 10 playable races; attributes are hardcoded (no trait-picking).

  type Race =
    | Humans    // +50% diplomacy; balanced stats
    | Psilon    // Creative: all tech options simultaneously
    | Sakkra    // ×2 population growth rate
    | Bulrathi  // +50% ground-combat attack strength
    | Mrrshan   // +50% beam-weapon accuracy
    | Klackon   // +25% factory production output
    | Meklar    // Cybernetic: +1 factory cap above normal limit
    | Alkari    // +25% ship defence rating
    | Silicoid  // Lithovore: colonise any world without tech prerequisites
    | Darlok    // +50% spy success; −50% detection rate

  // ── Ship design ───────────────────────────────────────────────────────────

  type ShipHull =
    | Scout
    | ColonyShip  // no weapons; carries colonists
    | Destroyer
    | Cruiser
    | Battleship
    | Titan
    | DoomStar

  type WeaponSlot = { tech: TechName, count: int }
  type SpecialSlot = { tech: TechName }

  type ShipDesign = {
    id:       DesignId,
    owner:    EmpireId,
    hull:     ShipHull,
    weapons:  List[WeaponSlot],
    specials: List[SpecialSlot],
    cost:     int,  // BC to build
    upkeep:   int   // BC/turn maintenance
  }

  type Ship = {
    design:    DesignId,
    currentHp: int,
    maxHp:     int
  }

  // ── Production spending sliders ───────────────────────────────────────────
  //
  // Every turn a colony's gross PP is split across five categories.
  // Invariant enforced in empire.qnt: ships + defense + industry + ecology + research == 100.
  //
  //   ships    → progress toward building the active ship design
  //   defense  → build missile bases and planetary shields
  //   industry → build new factories (up to the Robotic Controls cap)
  //   ecology  → remove accumulated pollution
  //   research → contribute to empire-wide research (converted to RP)

  type SpendingAlloc = {
    ships:    int,
    defense:  int,
    industry: int,
    ecology:  int,
    research: int
  }

  // ── Colony ───────────────────────────────────────────────────────────────
  //
  // One colony per star system (a star may be unexplored or uninhabited).
  // `buildingShip`: DesignId of the ship currently under construction;
  //                 -1 means no ship being built.

  type Colony = {
    star:         StarId,
    owner:        EmpireId,
    population:   int,         // millions
    maxPop:       int,         // ceiling (world size + Biospheres bonus)
    factories:    int,         // number of factories built
    maxFactories: int,         // population × roboticControlsRatio + Meklar bonus
    pollution:    int,         // accumulated waste units (reduces effective pop)
    missileBases: int,         // orbital missile bases (each adds defensive firepower)
    shieldLevel:  int,         // planetary shield level (0 = none; tech-gated)
    spending:     SpendingAlloc,
    buildingShip: int          // DesignId of active ship build; -1 if none
  }

  // ── Empire ───────────────────────────────────────────────────────────────

  type Empire = {
    id:          EmpireId,
    race:        Race,
    homeStar:    StarId,
    bc:          int,          // BioCredits (currency)
    techs:       Set[TechName],
    rpAccum:     int,          // RP accumulated toward `researching`
    researching: TechName,     // currently active research target
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
    level:   int,        // 1–10; improves on success
    mission: SpyMission
  }

  // ── Ground troops ─────────────────────────────────────────────────────────

  type GroundForce = {
    owner:    EmpireId,
    strength: int   // millions of marines embarked
  }

  // ── Diplomatic relations ──────────────────────────────────────────────────
  //
  // Simple four-step ladder: War → Neutral → Peace → Alliance.

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
  // No hyperlanes.  A fleet can fly to any star within its squared fuel range.
  // Each system has at most one colonisable world; fleet orders reference
  // the star, not a sub-planet entity.

  type FleetOrder =
    | HoldPosition
    | MoveTo(StarId)
    | ColoniseStar       // land colonists on this star's unoccupied world
    | BombardStar        // orbital bombardment of this star's colony
    | ReturnToBase

  type Fleet = {
    id:          FleetId,
    owner:       EmpireId,
    location:    StarId,
    destination: StarId,
    ships:       List[Ship],
    troops:      GroundForce,
    order:       FleetOrder,
    fuelRangeSq: int
  }

  // ── Star system ───────────────────────────────────────────────────────────
  //
  // Each system has exactly one world whose attributes are stored here.
  // `planetType = Barren` means the system has no colonisable world at all.

  type StarSystem = {
    id:         StarId,
    class_:     StarClass,
    coords:     Coord,
    planetType: PlanetType,   // Barren = no world
    size:       PlanetSize,   // ignored when planetType == Barren
    richness:   int,          // 0 (Ultra Poor) to 4 (Ultra Rich); affects PP output
    maxPopBase: int,          // base population ceiling before Biospheres tech
    explored:   Set[EmpireId]
  }

  // ── Galactic Council ──────────────────────────────────────────────────────

  type CouncilSession = {
    candidate: EmpireId,
    votes:     EmpireId -> int
  }

  // ── Turn structure ────────────────────────────────────────────────────────

  type TurnPhase =
    | OrdersPhase       // empires set spending, ship builds, fleet orders
    | ProductionPhase   // PP generated; sliders applied; pop grows; pollution accumulates
    | MovementPhase     // fleets fly to destinations
    | CombatPhase       // space battles at contested stars
    | InvasionPhase     // ground combat after orbital bombardment
    | GrowthPhase       // research completes; population grows
    | SpyPhase          // spy missions resolve
    | CouncilPhase      // Galactic Council vote if threshold met
    | VictoryCheckPhase // conquest and council-win checks

  type VictoryKind =
    | ConquestVictory
    | CouncilVictory

  type VictoryResult = {
    winner:     EmpireId,
    kind:       VictoryKind,
    turnNumber: int
  }
}
