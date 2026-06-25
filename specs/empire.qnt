// ============================================================================
// empire.qnt — Galactic Expanse: empire, colony & research (MOO1 model)
//
// Production model (no food):
//   • All colonists implicitly work in factories.
//   • Active factories = min(effective_population, factories_built).
//   • Effective population = max(0, population − pollution_penalty).
//   • Gross PP = active_factories × BASE_PP_PER_FACTORY × richness_modifier.
//   • Gross PP is then divided via five spending sliders:
//       Ships / Defense (missile bases & shields) / Industry / Ecology / Research.
//   • Research slider converts PP to RP for the empire's active research target.
//   • Ecology slider converts PP to pollution cleanup.
//   • Industry slider builds new factories (up to the Robotic Controls cap).
//   • Defense slider builds missile bases and upgrades planetary shields.
//
// Population growth is logistic (no food gate): grows toward maxPop each turn.
// ============================================================================

module empire {

  import types.*
  import galaxy.*

  // ── Configuration constants ───────────────────────────────────────────────

  const NUM_EMPIRES:          int
  const BASE_PP_PER_FACTORY:  int   // base PP one factory produces per turn
  const POLLUTION_PER_FACTORY: int  // pollution units one active factory emits/turn
  const ECOLOGY_CLEANUP_RATE: int   // pollution units removed per PP spent on ecology
  const COLONY_SHIP_POP:      int   // millions of colonists deposited when founding

  // ── State ─────────────────────────────────────────────────────────────────

  var empires:  EmpireId -> Empire
  var colonies: Set[Colony]
  var spies:    Set[Spy]

  // ── Race attribute table ──────────────────────────────────────────────────
  //
  // All multipliers are expressed as integer percentages (100 = no change).

  // Factory production multiplier.
  pure def industryPct(r: Race): int =
    if      (r == Klackon) { 125 }   // +25% factory output
    else                   { 100 }

  // Research-point conversion multiplier.
  pure def researchPct(r: Race): int =
    if (r == Psilon) { 150 } else { 100 }   // Psilon: +50% RP

  // Population growth rate multiplier.
  pure def growthPct(r: Race): int =
    if (r == Sakkra) { 200 } else { 100 }   // Sakkra: ×2 growth

  // Silicoid can colonise any world type without technology prerequisites.
  pure def isLithovore(r: Race): bool =
    r == Silicoid

  // Psilon receive all available tech options simultaneously.
  pure def isCreative(r: Race): bool =
    r == Psilon

  // Meklar may run one extra factory above the Robotic Controls cap.
  pure def extraFactoryCap(r: Race): int =
    if (r == Meklar) { 1 } else { 0 }

  // ── Robotic Controls: factory-per-pop ratio ───────────────────────────────

  pure def roboticControlsRatio(e: Empire): int =
    if      (e.techs.contains(RoboticControls5)) { 5 }
    else if (e.techs.contains(RoboticControls4)) { 4 }
    else if (e.techs.contains(RoboticControls3)) { 3 }
    else if (e.techs.contains(RoboticControls2)) { 2 }
    else                                         { 1 }

  pure def effectiveFactoryCap(e: Empire, pop: int): int =
    pop * (roboticControlsRatio(e) + extraFactoryCap(e.race))

  // ── Richness modifier ─────────────────────────────────────────────────────
  //
  // richness 0 (Ultra Poor) → 75%   richness 2 (Adequate) → 125%
  // richness 4 (Ultra Rich) → 175%
  // Formula: (75 + richness × 25) %

  pure def richnessPct(richness: int): int =
    75 + richness * 25

  // ── Core production formulas ──────────────────────────────────────────────

  // Population reduced by pollution: one pollution unit reduces effective
  // population by one million (those colonists are incapacitated).
  pure def effectivePop(c: Colony): int =
    val ep = c.population - c.pollution
    if (ep < 0) { 0 } else { ep }

  // Active factories are limited by how many colonists can operate them.
  pure def activeFactories(c: Colony): int =
    val ep = effectivePop(c)
    if (ep < c.factories) { ep } else { c.factories }

  // Gross production points per turn before the spending split.
  pure def grossPP(e: Empire, c: Colony, sys: StarSystem): int =
    activeFactories(c) * BASE_PP_PER_FACTORY
      * richnessPct(sys.richness) / 100
      * industryPct(e.race) / 100

  // Pollution produced this turn by active factories.
  // AdvancedEcology halves the rate empire-wide.
  pure def pollutionProduced(e: Empire, c: Colony): int =
    val base = activeFactories(c) * POLLUTION_PER_FACTORY
    if (e.techs.contains(AdvancedEcology)) { base / 2 } else { base }

  // Pollution cleaned this turn from the Ecology spending slice.
  pure def pollutionCleaned(e: Empire, c: Colony, sys: StarSystem): int =
    val ecoPP = grossPP(e, c, sys) * c.spending.ecology / 100
    ecoPP * ECOLOGY_CLEANUP_RATE

  // Net pollution after production and cleanup.
  pure def nextPollution(e: Empire, c: Colony, sys: StarSystem): int =
    val raw = c.pollution + pollutionProduced(e, c) - pollutionCleaned(e, c, sys)
    if (raw < 0) { 0 } else { raw }

  // Research points this colony contributes to the empire.
  pure def rpFromColony(e: Empire, c: Colony, sys: StarSystem): int =
    grossPP(e, c, sys) * c.spending.research / 100 * researchPct(e.race) / 100

  // PP available for ship construction this turn.
  pure def shipsPP(e: Empire, c: Colony, sys: StarSystem): int =
    grossPP(e, c, sys) * c.spending.ships / 100

  // PP available for missile base and shield construction.
  pure def defensePP(e: Empire, c: Colony, sys: StarSystem): int =
    grossPP(e, c, sys) * c.spending.defense / 100

  // PP available for building new factories.
  pure def industryPP(e: Empire, c: Colony, sys: StarSystem): int =
    grossPP(e, c, sys) * c.spending.industry / 100

  // ── Population growth ─────────────────────────────────────────────────────
  //
  // Logistic growth toward maxPop; no food gate.
  // Natural rate: population / 2 per turn, capped by headroom.
  // Sakkra grow at twice the rate.

  pure def popGrowth(e: Empire, c: Colony): int =
    val headroom = c.maxPop - c.population
    if (headroom <= 0) {
      0
    } else {
      val natural  = c.population / 2
      val capped   = if (natural < headroom) { natural } else { headroom }
      capped * growthPct(e.race) / 100
    }

  pure def nextPopulation(e: Empire, c: Colony): int =
    val raw = c.population + popGrowth(e, c)
    if (raw > c.maxPop) { c.maxPop } else { raw }

  // ── Action: production phase ──────────────────────────────────────────────
  //
  // Applies one production tick to a single colony:
  //   • RP added to empire rpAccum
  //   • Pollution updated
  //   • Surplus production allocated (factories / defense / ship queue)
  //     are handled by separate build actions

  action runColonyProduction(eid: EmpireId, c: Colony, sys: StarSystem): bool = {
    val e       = empires.get(eid)
    val rp      = rpFromColony(e, c, sys)
    val newPoll = nextPollution(e, c, sys)
    all {
      colonies' = colonies.exclude(Set(c)).union(Set({ ...c, pollution: newPoll })),
      empires'  = empires.put(eid, { ...e, rpAccum: e.rpAccum + rp })
    }
  }

  // ── Action: growth phase ──────────────────────────────────────────────────

  action runColonyGrowth(eid: EmpireId, c: Colony): bool = {
    val e      = empires.get(eid)
    val newPop = nextPopulation(e, c)
    val newMax  = effectiveFactoryCap(e, newPop)
    all {
      colonies' = colonies.exclude(Set(c)).union(Set({ ...c,
        population:   newPop,
        maxFactories: newMax
      })),
      empires' = empires
    }
  }

  // ── Action: build factory ─────────────────────────────────────────────────

  action buildFactory(eid: EmpireId, c: Colony, sys: StarSystem): bool = {
    val e = empires.get(eid)
    all {
      c.factories < c.maxFactories,
      c.spending.industry > 0,
      colonies' = colonies.exclude(Set(c)).union(Set({ ...c, factories: c.factories + 1 })),
      empires'  = empires
    }
  }

  // ── Action: build missile base ────────────────────────────────────────────

  action buildMissileBase(eid: EmpireId, c: Colony, sys: StarSystem): bool = {
    val e = empires.get(eid)
    all {
      c.spending.defense > 0,
      colonies' = colonies.exclude(Set(c)).union(Set({ ...c, missileBases: c.missileBases + 1 })),
      empires'  = empires
    }
  }

  // ── Action: research ─────────────────────────────────────────────────────
  //
  // `cost` is the RP required for the empire's current research target.
  // When complete, the tech is added; the player then picks the next target.

  pure def hasPrerequisite(e: Empire, t: TechName): bool =
    if      (t == FusionEngines)     { e.techs.contains(NuclearEngines) }
    else if (t == IonDrive)          { e.techs.contains(FusionEngines) }
    else if (t == SubSpaceDrive)     { e.techs.contains(IonDrive) }
    else if (t == HyperDrive)        { e.techs.contains(SubSpaceDrive) }
    else if (t == InterphasedDrive)  { e.techs.contains(HyperDrive) }
    else if (t == RoboticControls3)  { e.techs.contains(RoboticControls2) }
    else if (t == RoboticControls4)  { e.techs.contains(RoboticControls3) }
    else if (t == RoboticControls5)  { e.techs.contains(RoboticControls4) }
    else if (t == BattleComputer2)   { e.techs.contains(BattleComputer1) }
    else if (t == BattleComputer3)   { e.techs.contains(BattleComputer2) }
    else if (t == Class3Shield)      { e.techs.contains(Class1Shield) }
    else if (t == Class5Shield)      { e.techs.contains(Class3Shield) }
    else if (t == Class7Shield)      { e.techs.contains(Class5Shield) }
    else if (t == Class10Shield)     { e.techs.contains(Class7Shield) }
    else if (t == Class15Shield)     { e.techs.contains(Class10Shield) }
    else if (t == Class20Shield)     { e.techs.contains(Class15Shield) }
    else if (t == Class25Shield)     { e.techs.contains(Class20Shield) }
    else if (t == Class30Shield)     { e.techs.contains(Class25Shield) }
    else if (t == StellarConverter)  { e.techs.contains(AntiMatterBomb) }
    else if (t == TerraformingMax)   { e.techs.contains(TerraformingMed) }
    else                             { true }

  action tryCompleteResearch(eid: EmpireId, cost: int): bool = {
    val e = empires.get(eid)
    if (e.rpAccum >= cost and not(e.techs.contains(e.researching))) {
      empires' = empires.put(eid, { ...e,
        techs:   e.techs.union(Set(e.researching)),
        rpAccum: 0
      })
    } else {
      empires' = empires
    }
  }

  // ── Colonisation ─────────────────────────────────────────────────────────
  //
  // No PlanetId: the star system is the colony site.
  // The world type on the system determines whether the empire can colonise it.

  pure def isColonisable(sys: StarSystem, e: Empire): bool =
    if (sys.planetType == Barren)   { false }
    else if (isLithovore(e.race))   { true }   // Silicoid can colonise anything
    else if (sys.planetType == Inferno)  { e.techs.contains(ControlledEnviron) }
    else if (sys.planetType == Toxic)    { e.techs.contains(AtmosphericRenewer) }
    else if (sys.planetType == Radiated) { e.techs.contains(RadiationShield_) }
    else                            { true }

  def isUnoccupied(star: StarId): bool =
    not(colonies.exists(c => c.star == star))

  action foundColony(eid: EmpireId, sys: StarSystem): bool = {
    val e = empires.get(eid)
    val newCol: Colony = {
      star:         sys.id,
      owner:        eid,
      population:   COLONY_SHIP_POP,
      maxPop:       sys.maxPopBase,
      factories:    0,
      maxFactories: effectiveFactoryCap(e, COLONY_SHIP_POP),
      pollution:    0,
      missileBases: 0,
      shieldLevel:  0,
      spending:     { ships: 0, defense: 0, industry: 50, ecology: 20, research: 30 },
      buildingShip: -1
    }
    all {
      isColonisable(sys, e),
      isUnoccupied(sys.id),
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

  // ── Population helpers for council ───────────────────────────────────────

  def totalPop: int =
    colonies.fold(0, (acc, c) => acc + c.population)

  def empirePop(eid: EmpireId): int =
    colonies.filter(c => c.owner == eid).fold(0, (acc, c) => acc + c.population)

  // ── Spending allocation validity ──────────────────────────────────────────

  pure def spendingOk(s: SpendingAlloc): bool =
    s.ships    >= 0 and s.defense   >= 0 and s.industry >= 0 and
    s.ecology  >= 0 and s.research  >= 0 and
    s.ships + s.defense + s.industry + s.ecology + s.research == 100

  // ── Invariant conditions ──────────────────────────────────────────────────

  val invSpendingValid: bool =
    colonies.forall(c => spendingOk(c.spending))

  val invPopulationPositive: bool =
    colonies.forall(c => c.population > 0)

  val invPollutionNonNegative: bool =
    colonies.forall(c => c.pollution >= 0)

  val invFactoriesInBounds: bool =
    colonies.forall(c => c.factories >= 0 and c.factories <= c.maxFactories)

  val invMissileBasesNonNegative: bool =
    colonies.forall(c => c.missileBases >= 0)

  val invShieldLevelNonNegative: bool =
    colonies.forall(c => c.shieldLevel >= 0)

  val invBcNonNegative: bool =
    empires.keys().forall(eid => empires.get(eid).bc >= 0)

  val invResearchingNotOwned: bool =
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
      empires.get(eid).techs.forall(t => hasPrerequisite(empires.get(eid), t))
    )

  val invColonyOnValidStar: bool =
    // Every colony sits on a star that actually has a colonisable world.
    colonies.forall(c =>
      stars.keys().contains(c.star) and
      stars.get(c.star).planetType != Barren
    )

  val invAtMostOneColonyPerStar: bool =
    colonies.forall(c1 =>
      colonies.forall(c2 =>
        c1.star == c2.star implies c1.owner == c2.owner
      )
    )
}
