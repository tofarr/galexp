// ============================================================================
// empire.qnt — Galactic Expanse: empire, colony & research (MOO1 model)
//
// Owns the `empires`, `colonies`, and `spies` state variables.  Specifies:
//
//   • Per-turn production (food, PP, RP) using the worker / factory model
//   • Pollution accumulation and ecology cleanup
//   • Population growth and starvation
//   • Race-specific production multipliers (10 fixed races)
//   • Named-technology research (single active target per empire)
//   • Colony founding, factory building, project completion
//   • Spy recruitment and empire elimination
// ============================================================================

module empire {

  import types.*
  import galaxy.*

  // ── Configuration constants ───────────────────────────────────────────────

  const NUM_EMPIRES:         int  // 2–10 players + AIs
  const BASE_FOOD_PER_FARMER: int // food units one farmer produces per turn (base)
  const BASE_PP_PER_WORKER:   int // PP one worker produces per factory per turn
  const BASE_RP_PER_SCIENTIST: int
  const POLLUTION_PER_FACTORY: int // pollution units one active factory emits
  const ECOLOGY_PP_PER_UNIT:   int // PP needed to remove 1 pollution unit
  const COLONY_SHIP_POP_COST:  int // millions of colonists consumed at founding

  // ── State ─────────────────────────────────────────────────────────────────

  var empires:  EmpireId -> Empire
  var colonies: Set[Colony]
  var spies:    Set[Spy]

  // ── Race bonus table ──────────────────────────────────────────────────────
  //
  // Returns the integer percentage bonus (100 = no bonus) for the given race
  // and production type.  Mirrors the hardcoded MOO1 race statistics.

  pure def farmingPct(r: Race): int =
    if      (r == Sakkra)   { 100 }  // no food bonus; growth is their trait
    else if (r == Silicoid) { 0   }  // Silicoids do NOT eat food (lithovore)
    else                    { 100 }

  pure def industryPct(r: Race): int =
    if      (r == Klackon) { 125 }   // +25%
    else if (r == Meklar)  { 100 }   // bonus comes from extra factory cap
    else                   { 100 }

  pure def researchPct(r: Race): int =
    if (r == Psilon) { 150 }         // +50% RP (combined with Creative trait)
    else             { 100 }

  // Growth rate multiplier (×100).  Sakkra grow twice as fast.
  pure def growthPct(r: Race): int =
    if (r == Sakkra) { 200 } else { 100 }

  // Silicoids do not consume food; they eat minerals (abstracted as no food need).
  pure def isLithovore(r: Race): bool =
    r == Silicoid

  // Meklar may run one additional factory above the normal cap.
  pure def extraFactoryCap(r: Race): int =
    if (r == Meklar) { 1 } else { 0 }

  // Creative race: Psilon receive all tech options simultaneously.
  pure def isCreative(r: Race): bool =
    r == Psilon

  // ── Robotic Controls: factory cap ratio ──────────────────────────────────
  //
  // The number of factories a colony may build per million population is set
  // by the highest Robotic Controls technology the empire has researched.
  // Meklar get +1 on top of whatever the tech provides.

  pure def roboticControlsRatio(e: Empire): int =
    if      (e.techs.contains(RoboticControls5)) { 5 }
    else if (e.techs.contains(RoboticControls4)) { 4 }
    else if (e.techs.contains(RoboticControls3)) { 3 }
    else if (e.techs.contains(RoboticControls2)) { 2 }
    else                                         { 1 }  // MOO1 default: 1 per pop

  pure def effectiveFactoryCap(e: Empire, c: Colony): int =
    c.population * (roboticControlsRatio(e) + extraFactoryCap(e.race))

  // ── Production formulas ───────────────────────────────────────────────────

  // Food produced.  Silicoids produce 0 food (they don't need it).
  // Farmers produce BASE_FOOD_PER_FARMER × planet fertility modifier.
  pure def foodOutput(e: Empire, c: Colony, p: Planet): int =
    if (isLithovore(e.race)) { 0 }
    else {
      val fertilityMod = 100 + (p.fertility * 20)     // each fertility pt = +20%
      c.alloc.farmers * BASE_FOOD_PER_FARMER * fertilityMod / 100
    }

  // Food needed per turn.  Silicoids need 0.
  pure def foodNeeded(e: Empire, c: Colony): int =
    if (isLithovore(e.race)) { 0 } else { c.population }

  // Net food balance (positive = surplus, negative = starvation).
  pure def foodBalance(e: Empire, c: Colony, p: Planet): int =
    foodOutput(e, c, p) - foodNeeded(e, c)

  // PP from workers operating factories.  Workers without a factory are idle.
  // Pollution reduces effective population, which bounds available workers.
  pure def activeWorkers(c: Colony): int =
    val effectivePop = c.population - c.pollution
    val availWorkers = if (effectivePop < c.alloc.workers) { effectivePop }
                       else { c.alloc.workers }
    val activeFact   = if (availWorkers < c.factories) { availWorkers }
                       else { c.factories }
    activeFact

  pure def ppOutput(e: Empire, c: Colony, p: Planet): int =
    val basePP      = activeWorkers(c) * BASE_PP_PER_WORKER
    val richnessBonus = p.richness * 10                  // each richness pt = +10%
    val raceMod     = industryPct(e.race)
    basePP * (100 + richnessBonus) / 100 * raceMod / 100

  // RP from scientists.
  pure def rpOutput(e: Empire, c: Colony): int =
    c.alloc.scientists * BASE_RP_PER_SCIENTIST * researchPct(e.race) / 100

  // Pollution produced per turn (active factories × rate).
  // AdvancedEcology tech halves the pollution rate.
  pure def pollutionProduced(e: Empire, c: Colony): int =
    val base = activeWorkers(c) * POLLUTION_PER_FACTORY
    if (e.techs.contains(AdvancedEcology)) { base / 2 } else { base }

  // PP needed to fully clean current pollution (rounded up).
  pure def cleanupCost(c: Colony): int =
    c.pollution * ECOLOGY_PP_PER_UNIT

  // ── Population growth ─────────────────────────────────────────────────────
  //
  // MOO1 pop growth model:
  //   • Each turn, potential growth = population / 2  (logistic ceiling)
  //   • Actual growth is capped by food surplus and headroom to maxPop.
  //   • Starvation (food < need) causes population decline equal to the deficit.
  //   • Sakkra grow at twice the normal rate.

  pure def popGrowth(e: Empire, c: Colony, p: Planet): int =
    val fb       = foodBalance(e, c, p)
    val headroom = c.maxPop - c.population
    if (fb < 0) {
      fb            // starvation: pop drops by the food deficit
    } else if (headroom <= 0) {
      0             // at cap: no growth
    } else {
      val natural = c.population / 2               // base MOO1 growth potential
      val capped  = if (natural < headroom) { natural } else { headroom }
      val food_capped = if (capped < fb) { capped } else { fb }
      food_capped * growthPct(e.race) / 100
    }

  pure def nextPopulation(e: Empire, c: Colony, p: Planet): int =
    val raw = c.population + popGrowth(e, c, p)
    if (raw < 0) { 0 }
    else if (raw > c.maxPop) { c.maxPop }
    else { raw }

  // ── Actions: production phase ─────────────────────────────────────────────
  //
  // Applies one production tick to a single colony.
  // PP is spent according to the colony's project; remainder is converted to BC.

  action runColonyProduction(eid: EmpireId, c: Colony, p: Planet): bool = {
    val e        = empires.get(eid)
    val pp       = ppOutput(e, c, p)
    val rp       = rpOutput(e, c)
    val newPoll  = c.pollution + pollutionProduced(e, c)
    // Apply ecology cleanup if the project is CleanEcology.
    val pollAfterClean =
      if (c.project == CleanEcology) {
        val removed = pp / ECOLOGY_PP_PER_UNIT
        if (removed > newPoll) { 0 } else { newPoll - removed }
      } else { newPoll }
    // BC income: 1 BC per 2 PP of surplus not used on a project.
    val surplusBC = if (c.project == Idle) { pp / 2 } else { 0 }
    all {
      colonies' = colonies.exclude(Set(c)).union(Set({ ...c, pollution: pollAfterClean })),
      empires'  = empires.put(eid, { ...e,
        bc:     e.bc + surplusBC,
        rpAccum: e.rpAccum + rp
      })
    }
  }

  // ── Actions: growth phase ─────────────────────────────────────────────────

  action runColonyGrowth(eid: EmpireId, c: Colony, p: Planet): bool = {
    val e      = empires.get(eid)
    val newPop = nextPopulation(e, c, p)
    val newMaxFact = effectiveFactoryCap(e, { ...c, population: newPop })
    all {
      colonies' = colonies.exclude(Set(c)).union(Set({ ...c,
        population:   newPop,
        maxFactories: newMaxFact
      })),
      empires' = empires
    }
  }

  // ── Actions: build factory ────────────────────────────────────────────────

  action buildFactory(eid: EmpireId, c: Colony): bool = {
    val e = empires.get(eid)
    all {
      c.project == BuildFactory,
      c.factories < c.maxFactories,
      colonies' = colonies.exclude(Set(c)).union(Set({ ...c, factories: c.factories + 1 })),
      empires'  = empires
    }
  }

  // ── Actions: research phase ───────────────────────────────────────────────
  //
  // The research cost for each named technology is looked up from the game
  // engine's cost table (not modelled here; the spec treats `rpCost` as an
  // opaque function provided by the engine).  When accumulated RP >= cost the
  // tech is added to the empire's set and `rpAccum` is reset.

  pure def hasPrerequisite(e: Empire, t: TechName): bool =
    // Encodes the partial MOO1 tech prerequisites.
    // Construction drives must be researched in order.
    if      (t == FusionEngines)     { e.techs.contains(NuclearEngines) }
    else if (t == IonDrive)          { e.techs.contains(FusionEngines) }
    else if (t == SubSpaceDrive)     { e.techs.contains(IonDrive) }
    else if (t == HyperDrive)        { e.techs.contains(SubSpaceDrive) }
    else if (t == InterphasedDrive)  { e.techs.contains(HyperDrive) }
    // Robotic Controls must be researched in order.
    else if (t == RoboticControls3)  { e.techs.contains(RoboticControls2) }
    else if (t == RoboticControls4)  { e.techs.contains(RoboticControls3) }
    else if (t == RoboticControls5)  { e.techs.contains(RoboticControls4) }
    // Battle computers in order.
    else if (t == BattleComputer2)   { e.techs.contains(BattleComputer1) }
    else if (t == BattleComputer3)   { e.techs.contains(BattleComputer2) }
    // Shields in order.
    else if (t == Class3Shield)      { e.techs.contains(Class1Shield) }
    else if (t == Class5Shield)      { e.techs.contains(Class3Shield) }
    else if (t == Class7Shield)      { e.techs.contains(Class5Shield) }
    else if (t == Class10Shield)     { e.techs.contains(Class7Shield) }
    else if (t == Class15Shield)     { e.techs.contains(Class10Shield) }
    else if (t == Class20Shield)     { e.techs.contains(Class15Shield) }
    else if (t == Class25Shield)     { e.techs.contains(Class20Shield) }
    else if (t == Class30Shield)     { e.techs.contains(Class25Shield) }
    // Stellar Converter requires Anti-Matter Bomb.
    else if (t == StellarConverter)  { e.techs.contains(AntiMatterBomb) }
    // Terraforming requires prior terraforming.
    else if (t == TerraformingMax)   { e.techs.contains(TerraformingMed) }
    // All others have no prerequisite tracked in the spec.
    else                             { true }

  // Attempt to complete the current research target.  The cost is supplied by
  // the caller (engine looks it up from its tech-cost table).
  action tryCompleteResearch(eid: EmpireId, cost: int): bool = {
    val e = empires.get(eid)
    if (e.rpAccum >= cost and not(e.techs.contains(e.researching))) {
      empires' = empires.put(eid, { ...e,
        techs:   e.techs.union(Set(e.researching)),
        rpAccum: 0
        // `researching` is updated by the player choosing the next target.
      })
    } else {
      empires' = empires
    }
  }

  // ── Colony founding ───────────────────────────────────────────────────────
  //
  // A fleet bearing a Colony Ship lands colonists on an unoccupied planet.
  // The colony ship is consumed; `COLONY_SHIP_POP_COST` pop is transferred.

  pure def isColonisable(t: PlanetType, e: Empire): bool =
    if (isLithovore(e.race)) { true }  // Silicoid colonise anything
    else if (t == Inferno)   { e.techs.contains(ControlledEnviron) }
    else if (t == Toxic)     { e.techs.contains(AtmosphericRenewer) }
    else if (t == Radiated)  { e.techs.contains(RadiationShield_) }
    else                     { true }

  def isUnoccupied(star: StarId, planetId: PlanetId): bool =
    not(colonies.exists(c => c.star == star and c.planet == planetId))

  action foundColony(eid: EmpireId, star: StarId, p: Planet): bool = {
    val e = empires.get(eid)
    val newCol: Colony = {
      star:         star,
      planet:       p.id,
      owner:        eid,
      population:   COLONY_SHIP_POP_COST,   // colonists disembark from ship
      maxPop:       p.maxPopBase,
      factories:    0,
      maxFactories: COLONY_SHIP_POP_COST * roboticControlsRatio(e),
      pollution:    0,
      alloc:        { farmers: COLONY_SHIP_POP_COST, workers: 0, scientists: 0 },
      project:      Idle
    }
    all {
      isColonisable(p.type_, e),
      isUnoccupied(star, p.id),
      colonies' = colonies.union(Set(newCol)),
      empires'  = empires
    }
  }

  // ── Empire elimination ────────────────────────────────────────────────────

  def hasColonies(eid: EmpireId): bool =
    colonies.exists(c => c.owner == eid)

  action eliminateIfDefeated(eid: EmpireId): bool = {
    val e = empires.get(eid)
    if (not(hasColonies(eid)) and not(e.eliminated)) {
      empires' = empires.put(eid, { ...e, eliminated: true })
    } else {
      empires' = empires
    }
  }

  // ── Total galaxy population (for council threshold) ───────────────────────

  def totalPop: int =
    colonies.fold(0, (acc, c) => acc + c.population)

  def empirePop(eid: EmpireId): int =
    colonies.filter(c => c.owner == eid).fold(0, (acc, c) => acc + c.population)

  // ── Worker allocation validity ────────────────────────────────────────────

  pure def allocOk(c: Colony): bool =
    c.alloc.farmers >= 0 and
    c.alloc.workers >= 0 and
    c.alloc.scientists >= 0 and
    c.alloc.farmers + c.alloc.workers + c.alloc.scientists == c.population

  // ── Invariant conditions ──────────────────────────────────────────────────

  val invAllocationsValid: bool =
    colonies.forall(c => allocOk(c))

  val invPopulationPositive: bool =
    colonies.forall(c => c.population > 0)

  val invPollutionNonNegative: bool =
    colonies.forall(c => c.pollution >= 0)

  val invFactoriesInBounds: bool =
    colonies.forall(c => c.factories >= 0 and c.factories <= c.maxFactories)

  val invBcNonNegative: bool =
    empires.keys().forall(eid => empires.get(eid).bc >= 0)

  val invResearchingNotOwned: bool =
    // An empire should not be "researching" a tech it already has.
    empires.keys().forall(eid =>
      not(empires.get(eid).techs.contains(empires.get(eid).researching))
    )

  val invColonyOwnerExists: bool =
    colonies.forall(c => empires.keys().contains(c.owner))

  val invEliminatedHaveNoColonies: bool =
    empires.keys().forall(eid =>
      empires.get(eid).eliminated implies not(hasColonies(eid))
    )

  val invPrerequisitesRespected: bool =
    empires.keys().forall(eid =>
      empires.get(eid).techs.forall(t =>
        hasPrerequisite(empires.get(eid), t)
      )
    )
}
