// ============================================================================
// types.qnt — Galactic Expanse (Master of Orion I model): core type vocabulary
//
// All shared types live here so every other module can `import types.*`.
// No state variables, no actions — pure data model.
//
// Design reference: Master of Orion (1993, Simtex / MicroProse)
//   • 10 fixed races with hardcoded bonuses (no custom trait-picking)
//   • 6 named tech fields; each field contains specific named technologies
//   • Coordinate-based galaxy — no hyperlanes; engine tech sets fuel range
//   • Worker system: colonists are Farmers / Workers / Scientists
//   • Factories produce PP; pollution accumulates and must be cleaned
//   • Victory: Conquest OR Galactic Council election (≥ 2/3 majority)
// ============================================================================

module types {

  // ── Primitive identifiers ─────────────────────────────────────────────────

  type StarId   = int
  type PlanetId = int
  type EmpireId = int
  type FleetId  = int
  type DesignId = int
  type SpyId    = int

  // ── Galaxy coordinates ────────────────────────────────────────────────────
  //
  // Stars sit on a 2-D integer grid.  Distances are stored and compared as
  // squared Euclidean values (no floating-point arithmetic needed).

  type Coord = { x: int, y: int }

  // ── Star classification ───────────────────────────────────────────────────
  //
  // Star colour determines the quality distribution of its planets.
  // Blue / White → higher-quality planets (rare).
  // Yellow → Sol-like, well-balanced.
  // Orange / Red → poorer habitability, very common.
  // Neutron / BlackHole → no colonisable planets; trigger special events.

  type StarClass =
    | Blue      // rare; excellent planets
    | White     // above average
    | Yellow    // standard Sol-type
    | Orange    // below average
    | Red       // dim; poor planets; most common
    | Neutron   // no colonies possible
    | BlackHole // no colonies possible

  // ── Planet types ──────────────────────────────────────────────────────────
  //
  // Planet type sets base food yield and habitability for each race.
  // Inferno / Toxic / Radiated require specific technologies to colonise;
  // all races including Silicoid can settle Dead / Terran / Ocean etc.

  type PlanetType =
    | Terran    // optimal: best food and highest pop ceiling
    | Ocean     // good food; lower production
    | Arid      // below-average food; decent production
    | Tundra    // moderate; harsh winters reduce farming
    | Desert    // poor food; adequate production
    | Inferno   // uninhabitable without Controlled Environment
    | Toxic     // uninhabitable without Atmospheric Renewer
    | Radiated  // uninhabitable without Radiation Shield
    | Dead      // minimal; colonisable but barren

  // Population ceiling scales with size.  Base caps (millions):
  //   Tiny=2  Small=4  Medium=5  Large=6  Huge=8  (before Biospheres tech)
  type PlanetSize = Tiny | Small | Medium | Large | Huge

  // ── Technology ───────────────────────────────────────────────────────────
  //
  // MOO1 has SIX tech fields.  Within each field are specific named
  // technologies researched one at a time.  An empire that finishes
  // researching one tech is presented with a random subset of the next
  // available technologies in that field and must choose one.
  //
  // Exception: Psilon (Creative) receive all available options simultaneously.

  type TechField =
    | Physics      // beam weapons, bombs, power generators
    | Biology      // food, population, bioweapons
    | Computers    // sensors, ECM/ECCM, androids, targeting
    | Construction // engines, hull armour, factory upgrades
    | ForceFields  // ship & planetary shields, stasis, repulsors
    | Planetology  // terraforming, atmosphere, ecology

  // Each technology is a named item.  The field each belongs to and any
  // prerequisites are documented below and enforced in empire.qnt.
  type TechName =
    // ── Physics ──────────────────────────────────────────────────────────
    | LaserCannon       // starting beam weapon
    | MassDriver        // starting kinetic weapon
    | GatlingLaser      // rapid-fire laser; fires 4× per round
    | FusionBeam        // mid-tier energy beam
    | IonCannon         // disrupts shields on hit
    | NeutronBomb       // kills population; leaves factories intact
    | MegaBoltCannon    // heavy rapid beam
    | PhasorCannon      // high-accuracy energy weapon
    | DisruptorCannon   // bypasses shields entirely
    | AntiMatterBomb    // most powerful explosive warhead
    | DeathRay          // instant kills one ship module
    | StellarConverter  // ultimate weapon; can destroy a planet
    // ── Biology ──────────────────────────────────────────────────────────
    | HydroponicFarm    // +1 food per turn at this colony
    | SoilEnrichment    // permanently increases planet fertility by +1
    | CloneCenter       // halves population growth time
    | BioToxinWarhead   // biological bomb; kills pop on orbital hit
    | AdvancedFarming   // further food multiplier for farmers
    | GeneticMutation   // one-time massive population growth event
    | BioTerminator     // enhanced bioweapon warhead
    // ── Computers ────────────────────────────────────────────────────────
    | BattleScanner     // reveals enemy ship types before combat begins
    | TachyonComms      // long-range deep space scanner
    | EcmJammer         // reduces enemy missile hit probability
    | Eccm              // negates enemy ECM
    | BattleComputer1   // +10 beam accuracy (Mark I)
    | BattleComputer2   // +20 beam accuracy (Mark II)
    | BattleComputer3   // +30 beam accuracy (Mark III)
    | AndroidFarmers    // android workers provide +1 food without consuming food
    | AndroidWorkers    // android workers provide +1 PP without consuming food
    | AndroidScientists // android workers provide +1 RP without consuming food
    | RoboticControls2  // colonies may build up to 2 factories per million pop
    | RoboticControls3  // up to 3 factories per million pop
    | RoboticControls4  // up to 4 factories per million pop
    | RoboticControls5  // up to 5 factories per million pop
    // ── Construction ─────────────────────────────────────────────────────
    | NuclearEngines    // starting drive; squared range = 9  (3 parsecs)
    | FusionEngines     // squared range = 16 (4 parsecs)
    | IonDrive          // squared range = 25
    | SubSpaceDrive     // squared range = 36
    | HyperDrive        // squared range = 49
    | InterphasedDrive  // squared range = 64; immune to Warp Interdictor
    | TitaniumArmour    // +30 HP per armour slot
    | TritaniumArmour   // +40 HP
    | ZortiumArmour     // +60 HP
    | AdamantiumArmour  // +100 HP
    | NeutroniumArmour  // +150 HP (ultimate)
    | IndustrialTech9   // factory build cost −9 BC (starting)
    | IndustrialTech10  // factory build cost −10 BC
    | AutomatedFactory  // +1 PP per active factory (empire-wide)
    // ── Force Fields ─────────────────────────────────────────────────────
    | Class1Shield
    | Class3Shield
    | Class5Shield
    | Class7Shield
    | Class10Shield
    | Class15Shield
    | Class20Shield
    | Class25Shield
    | Class30Shield     // ultimate planetary shield
    | RepulsorBeam      // pushes enemy ships backward in combat
    | StasisField       // freezes one target ship for several rounds
    | InertialStabilizer // halves beam damage during movement phase
    | LightningField    // area-effect damage to all enemy ships
    // ── Planetology ──────────────────────────────────────────────────────
    | AtmosphericRenewer  // allows Toxic planet colonisation
    | RadiationShield_    // allows Radiated planet colonisation
    | ControlledEnviron   // allows Inferno planet colonisation
    | WeatherController   // +2 food per turn at colonised world
    | Biospheres          // +2 maximum population (empire-wide)
    | TerraformingMed     // raises planet type one step toward Terran
    | TerraformingMax     // raises planet type to Gaia (ultimate tier)
    | EcoRestoration      // rapidly eliminates all existing pollution
    | AdvancedEcology     // permanently reduces pollution rate by 50%

  // ── Races ────────────────────────────────────────────────────────────────
  //
  // There are exactly 10 playable races in MOO1.  Attributes are hardcoded.
  // The game engine uses raceBonus() in empire.qnt to resolve differences.

  type Race =
    | Humans    // Diplomats: best diplomacy; balanced stats
    | Psilon    // Creative: receive ALL techs in a field simultaneously
    | Sakkra    // Fertile: ×2 population growth rate
    | Bulrathi  // Fighters: +50% ground-combat attack strength
    | Mrrshan   // Warriors: +50% beam-weapon accuracy in space combat
    | Klackon   // Industrious: +25% factory production output
    | Meklar    // Cybernetic: may run 1 extra factory above normal cap
    | Alkari    // Piloting: +25% ship manoeuvrability / defense rating
    | Silicoid  // Lithovores: eat minerals not food; colonise any planet
    | Darlok    // Shapeshifters: +50% spy success; −50% spy detection rate

  // ── Ship design ───────────────────────────────────────────────────────────
  //
  // Hull size determines weapon and special-equipment slot counts:
  //   Scout=1 weapon  Destroyer=2  Cruiser=3  Battleship=4
  //   Titan=5  DoomStar=6
  // (ColonyShip carries no weapons but 1 special slot for colony equipment.)

  type ShipHull =
    | Scout
    | ColonyShip
    | Destroyer
    | Cruiser
    | Battleship
    | Titan
    | DoomStar

  type WeaponSlot = {
    tech:  TechName, // the weapon technology mounted in this slot
    count: int       // number of mounts (1–5); more mounts = more shots
  }

  type SpecialSlot = {
    tech: TechName   // engine / shield / ECM / special tech installed
  }

  type ShipDesign = {
    id:       DesignId,
    owner:    EmpireId,
    hull:     ShipHull,
    weapons:  List[WeaponSlot],
    specials: List[SpecialSlot],
    cost:     int,  // BC to build
    upkeep:   int   // BC per turn maintenance cost
  }

  type Ship = {
    design:    DesignId,
    currentHp: int,
    maxHp:     int
  }

  // ── Colony worker allocation ──────────────────────────────────────────────
  //
  // Every colonist (million) is assigned to exactly one role each turn.
  // Guard: farmers + workers + scientists == population.

  type WorkerAlloc = {
    farmers:    int, // produce food
    workers:    int, // operate factories → produce PP
    scientists: int  // produce RP
  }

  // What the colony's surplus production is directed toward this turn.
  type ColonyProject =
    | BuildFactory
    | BuildShip(DesignId)
    | BuildBase
    | CleanEcology  // PP → pollution removal
    | Idle          // no active project; PP wasted / banked as BC

  // ── Colony ───────────────────────────────────────────────────────────────

  type Colony = {
    star:         StarId,
    planet:       PlanetId,
    owner:        EmpireId,
    population:   int,         // millions
    maxPop:       int,         // planet size base + Biospheres bonus
    factories:    int,         // number of factories built at this colony
    maxFactories: int,         // population × roboticControlsRatio
    pollution:    int,         // accumulated pollution (reduces effective pop)
    alloc:        WorkerAlloc,
    project:      ColonyProject
  }

  // ── Empire ───────────────────────────────────────────────────────────────

  type Empire = {
    id:          EmpireId,
    race:        Race,
    homeStar:    StarId,
    bc:          int,        // BioCredits (the MOO1 currency)
    techs:       Set[TechName],
    rpAccum:     int,        // RP accumulated toward `researching`
    researching: TechName,   // tech the empire is currently working on
    eliminated:  bool
  }

  // ── Spies ────────────────────────────────────────────────────────────────
  //
  // Empires recruit spies who are assigned a mission each turn.
  // Spy level increases with successful missions (max 10).

  type SpyMission =
    | Defend(EmpireId)      // counter-espionage; protects against incoming spies
    | StealTech(EmpireId)   // attempt to copy one technology from target
    | SabotageIndustry(EmpireId) // destroy factories at target colony
    | Assassinate(EmpireId)  // try to eliminate a target empire's spy

  type Spy = {
    id:      SpyId,
    owner:   EmpireId,
    level:   int,        // 1–10
    mission: SpyMission
  }

  // ── Ground combat ─────────────────────────────────────────────────────────
  //
  // Ground troops are embarked on fleets.  When a fleet has bombarded a
  // colony's population below the defender's army strength, troops land.

  type GroundForce = {
    owner:    EmpireId,
    strength: int   // millions of marines
  }

  // ── Diplomatic relations ──────────────────────────────────────────────────
  //
  // MOO1 relations are a simple four-step ladder: War → Neutral → Peace → Alliance.
  // Proposals are all simple (no parameterised data) so equality checks work.

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
    | OfferTechTrade  // propose a technology exchange
    | DemandTribute   // demand BC payment; refusal degrades relations

  // ── Fleet & movement ──────────────────────────────────────────────────────
  //
  // MOO1 has NO hyperlanes.  A fleet may fly to any star within its fuel
  // range in a single turn.  Range = best engine tech the empire has researched.
  // We store `fuelRangeSq` as the squared Euclidean limit to avoid floats.

  type FleetOrder =
    | HoldPosition
    | MoveTo(StarId)
    | ColonisePlanet(PlanetId)
    | BombardPlanet(PlanetId)
    | ReturnToBase    // retreat to nearest friendly colony

  type Fleet = {
    id:          FleetId,
    owner:       EmpireId,
    location:    StarId,
    destination: StarId,    // == location when idle
    ships:       List[Ship],
    troops:      GroundForce,
    order:       FleetOrder,
    fuelRangeSq: int        // squared travel-distance limit
  }

  // ── Star system ───────────────────────────────────────────────────────────

  type Planet = {
    id:         PlanetId,
    type_:      PlanetType,
    size:       PlanetSize,
    maxPopBase: int,  // base pop cap before Biospheres
    fertility:  int,  // farming modifier 0–5
    richness:   int   // industry modifier 0–5
  }

  type StarSystem = {
    id:       StarId,
    class_:   StarClass,
    coords:   Coord,          // 2-D position on galaxy map
    planets:  Set[Planet],
    explored: Set[EmpireId]   // empires that have sent a fleet here
  }

  // ── Galactic Council ──────────────────────────────────────────────────────
  //
  // A council session is triggered when any empire controls ≥ 1/3 of the
  // galaxy's total population.  Votes are proportional to each empire's
  // own population.  A candidate needs ≥ 2/3 of all votes cast to win.
  // Empires allied with the candidate vote for them automatically.

  type CouncilSession = {
    candidate: EmpireId,
    votes:     EmpireId -> int  // votes cast by each empire for the candidate
  }

  // ── Turn structure ────────────────────────────────────────────────────────

  type TurnPhase =
    | OrdersPhase       // empires set worker allocations, projects, fleet orders
    | ProductionPhase   // food consumed; PP and RP generated; pollution grows
    | MovementPhase     // fleets fly to destinations
    | CombatPhase       // space battles at contested stars
    | InvasionPhase     // ground combat after orbital bombardment
    | GrowthPhase       // population grows; research completes
    | SpyPhase          // spy missions resolve (steal tech, sabotage, etc.)
    | CouncilPhase      // Galactic Council vote if threshold is met
    | VictoryCheckPhase // check conquest and council-win conditions

  type VictoryKind =
    | ConquestVictory  // every other empire eliminated
    | CouncilVictory   // elected Supreme Leader with ≥ 2/3 council vote

  type VictoryResult = {
    winner:     EmpireId,
    kind:       VictoryKind,
    turnNumber: int
  }
}
