// ============================================================================
// empire.qnt — Galactic Expanse: empire, colony & research (MOO1 model)
//
// Phase 1 additions vs previous version:
//   • raceStartingTechs — per-race initial technology set (Gap 8)
//   • taxIncome / tradeIncome — BC economy (Gaps 9, 10)
//   • androidPPBonus / androidRPBonus — android worker effects (Gap 13)
//   • processShipBuild — build-queue PP accrual and ship completion (Gap 3)
//   • buildMissileBase — missile base construction with population cap
//   • upgradeShield — planetary shield level progression (Gap 5)
//   • terraformWorld — PlanetType mutation via TerraformingMed/Max (Gap 6)
//   • enrichSoil — richness increment via SoilEnrichment (Gap 7)
//   • techOptions state variable + offerTechOptions + chooseTech (Gap 2)
//   • espionage consequence actions for StealTech and SabotageIndustry (Gap 19)
//   • colonist load / unload helpers (Gap 17)
//   • initEmpire — seeds an empire with race-appropriate starting state
// ============================================================================

module empire {

  import types.*
  import galaxy.*

  // ── Configuration constants ───────────────────────────────────────────────

  const NUM_EMPIRES:            int
  const BASE_PP_PER_FACTORY:    int   // base PP one factory produces per turn
  const POLLUTION_PER_FACTORY:  int   // pollution units one active factory emits
  const ECOLOGY_CLEANUP_RATE:   int   // pollution removed per PP spent on ecology
  const COLONY_SHIP_POP:        int   // millions deposited when founding a colony
  const BASE_ANDROID_PP:        int   // PP bonus per colony from AndroidWorkers tech
  const BASE_ANDROID_RP:        int   // RP bonus per colony from AndroidScientists tech
  const TRADE_FACTOR:           int   // numerator in trade-income formula (× 100)
  const MAX_MISSILE_BASES:      int   // absolute cap on missile bases per colony
  const MISSILE_BASE_DEF_COST:  int   // PP cost (defense-slider) per missile base
  const SHIELD_UPGRADE_COST:    int   // PP cost (defense-slider) per shield level-up

  // ── State ─────────────────────────────────────────────────────────────────

  var empires:     EmpireId -> Empire
  var colonies:    Set[Colony]
  var spies:       Set[Spy]

  // techOptions holds the set of technologies currently being offered to an
  // empire after completing research.  Empty when not in a choice state.
  // The engine populates this; the player action chooseTech consumes it.
  var techOptions: EmpireId -> Set[TechName]

  // ── Race attribute table ──────────────────────────────────────────────────

  pure def industryPct(r: Race): int =
    if (r == Klackon) { 125 } else { 100 }

  pure def researchPct(r: Race): int =
    if (r == Psilon) { 150 } else { 100 }

  pure def growthPct(r: Race): int =
    if (r == Sakkra) { 200 } else { 100 }

  pure def isLithovore(r: Race): bool = r == Silicoid
  pure def isCreative(r: Race): bool  = r == Psilon

  pure def extraFactoryCap(r: Race): int =
    if (r == Meklar) { 1 } else { 0 }

  // Combat accuracy bonus percentage for beam weapons.
  pure def beamAccuracyBonus(r: Race): int =
    if (r == Mrrshan) { 50 } else { 0 }

  // Ground combat attack strength multiplier (×100).
  pure def groundAttackPct(r: Race): int =
    if (r == Bulrathi) { 150 } else { 100 }

  // Ship manoeuvrability / defence bonus percentage.
  pure def shipDefencePct(r: Race): int =
    if (r == Alkari) { 125 } else { 100 }

  // Spy mission success bonus (percentage added to SPY_SUCCESS_BASE_PCT).
  pure def spyBonus(r: Race): int =
    if (r == Darlok) { 50 } else { 0 }

  // Diplomacy reception bonus (percentage; affects AI willingness to accept offers).
  pure def diplomacyBonus(r: Race): int =
    if (r == Humans) { 50 } else { 0 }

  // ── Race starting technologies ────────────────────────────────────────────
  //
  // Gap 8: every empire begins the game with a race-appropriate tech set.
  // The base set is common to all races; each race then adds specialisations.
  // (Exact starting sets are approximated here and can be tuned from MOO1 data.)

  pure def raceStartingTechs(r: Race): Set[TechName] =
    val base = Set(
      NuclearEngines, LaserCannon, MassDriver,
      IndustrialTech9, Class1Shield, RoboticControls2
    )
    if (r == Klackon) {
      base.union(Set(RoboticControls3, AutomatedFactory))
    } else if (r == Meklar) {
      base.union(Set(RoboticControls3))
    } else if (r == Mrrshan) {
      base.union(Set(BattleComputer1))
    } else if (r == Sakkra) {
      base.union(Set(CloneCenter))
    } else if (r == Bulrathi) {
      base.union(Set(TitaniumArmour))
    } else if (r == Alkari) {
      base.union(Set(InertialStabilizer))
    } else if (r == Darlok) {
      base.union(Set(EcmJammer))
    } else {
      base   // Humans, Psilon, Silicoid: base set only
    }

  // ── Robotic Controls cap ──────────────────────────────────────────────────

  pure def roboticControlsRatio(e: Empire): int =
    if      (e.techs.contains(RoboticControls5)) { 5 }
    else if (e.techs.contains(RoboticControls4)) { 4 }
    else if (e.techs.contains(RoboticControls3)) { 3 }
    else if (e.techs.contains(RoboticControls2)) { 2 }
    else                                         { 1 }

  pure def effectiveFactoryCap(e: Empire, pop: int): int =
    pop * (roboticControlsRatio(e) + extraFactoryCap(e.race))

  // ── Richness modifier ─────────────────────────────────────────────────────
  // richness 0 → 75%  richness 2 → 125%  richness 4 → 175%

  pure def richnessPct(richness: int): int = 75 + richness * 25

  // ── Core production formulas ──────────────────────────────────────────────

  pure def effectivePop(c: Colony): int =
    val ep = c.population - c.pollution
    if (ep < 0) { 0 } else { ep }

  pure def activeFactories(c: Colony): int =
    val ep = effectivePop(c)
    if (ep < c.factories) { ep } else { c.factories }

  // Gross PP from factories this turn.
  pure def grossPP(e: Empire, c: Colony, sys: StarSystem): int =
    val basePP  = activeFactories(c) * BASE_PP_PER_FACTORY
                    * richnessPct(sys.richness) / 100
                    * industryPct(e.race)       / 100
    // AutomatedFactory tech adds +1 PP per active factory.
    val autoBonus = if (e.techs.contains(AutomatedFactory)) { activeFactories(c) } else { 0 }
    basePP + autoBonus

  // Gap 13: Android workers add flat PP/RP bonuses independent of factories.
  pure def androidPPBonus(e: Empire): int =
    if (e.techs.contains(AndroidWorkers)) { BASE_ANDROID_PP } else { 0 }

  pure def androidRPBonus(e: Empire): int =
    if (e.techs.contains(AndroidScientists)) { BASE_ANDROID_RP } else { 0 }

  // Total effective PP for spending-slider calculations (including android bonus).
  pure def totalPP(e: Empire, c: Colony, sys: StarSystem): int =
    grossPP(e, c, sys) + androidPPBonus(e)

  // Pollution produced this turn.
  pure def pollutionProduced(e: Empire, c: Colony): int =
    val base = activeFactories(c) * POLLUTION_PER_FACTORY
    if (e.techs.contains(AdvancedEcology)) { base / 2 } else { base }

  // Pollution cleaned from the ecology slider.
  pure def pollutionCleaned(e: Empire, c: Colony, sys: StarSystem): int =
    totalPP(e, c, sys) * c.spending.ecology / 100 * ECOLOGY_CLEANUP_RATE

  pure def nextPollution(e: Empire, c: Colony, sys: StarSystem): int =
    val raw = c.pollution + pollutionProduced(e, c) - pollutionCleaned(e, c, sys)
    if (raw < 0) { 0 } else { raw }

  // RP from research slider + android bonus.
  pure def rpFromColony(e: Empire, c: Colony, sys: StarSystem): int =
    val sliderRP  = totalPP(e, c, sys) * c.spending.research / 100 * researchPct(e.race) / 100
    sliderRP + androidRPBonus(e)

  // PP allocated to each spending category.
  pure def shipsPP(e: Empire, c: Colony, sys: StarSystem): int =
    totalPP(e, c, sys) * c.spending.ships / 100

  pure def defensePP(e: Empire, c: Colony, sys: StarSystem): int =
    totalPP(e, c, sys) * c.spending.defense / 100

  pure def industryPP(e: Empire, c: Colony, sys: StarSystem): int =
    totalPP(e, c, sys) * c.spending.industry / 100

  // ── BC income ─────────────────────────────────────────────────────────────
  //
  // Gap 9: Colony tax — a percentage of population size.
  pure def taxIncome(e: Empire, c: Colony): int =
    c.population * e.taxRate / 100

  // Gap 10: Trade income — mutual benefit for contacted, non-hostile empires.
  // Approximation of MOO1's contact-based trade:
  //   tradeBC ≈ sqrt(popA × popB) × TRADE_FACTOR / 100
  // We avoid floats by computing (popA × popB × TRADE_FACTOR²) and noting the
  // engine computes the integer square root; here we model the intent only.
  def tradeIncomePair(e: Empire, otherPop: int): int =
    val product = empirePop(e.id) * otherPop * TRADE_FACTOR / 100
    // Integer approximation: we use product / (empirePop + otherPop + 1) × 2
    // as a rough proxy for sqrt; the engine uses exact isqrt.
    product * 2 / (empirePop(e.id) + otherPop + 1)

  // ── Population growth ─────────────────────────────────────────────────────

  pure def popGrowth(e: Empire, c: Colony): int =
    val headroom = c.maxPop - c.population
    if (headroom <= 0) { 0 } else {
      val natural  = c.population / 2
      val capped   = if (natural < headroom) { natural } else { headroom }
      capped * growthPct(e.race) / 100
    }

  pure def nextPopulation(e: Empire, c: Colony): int =
    val raw = c.population + popGrowth(e, c)
    if (raw > c.maxPop) { c.maxPop } else { raw }

  // ── Population helpers for council ───────────────────────────────────────

  def empirePop(eid: EmpireId): int =
    colonies.filter(c => c.owner == eid).fold(0, (acc, c) => acc + c.population)

  def totalPop: int =
    colonies.fold(0, (acc, c) => acc + c.population)

  // ── Colonisation ─────────────────────────────────────────────────────────

  pure def isColonisable(sys: StarSystem, e: Empire): bool =
    if (sys.planetType == Barren)         { false }
    else if (isLithovore(e.race))         { true }
    else if (sys.planetType == Inferno)   { e.techs.contains(ControlledEnviron) }
    else if (sys.planetType == Toxic)     { e.techs.contains(AtmosphericRenewer) }
    else if (sys.planetType == Radiated)  { e.techs.contains(RadiationShield_) }
    else                                  { true }

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
      buildQueue:   List(),
      ppAccrued:    0
    }
    all {
      isColonisable(sys, e),
      isUnoccupied(sys.id),
      colonies' = colonies.union(Set(newCol)),
      empires'  = empires,
      techOptions' = techOptions
    }
  }

  // ── Action: production tick ───────────────────────────────────────────────

  action runColonyProduction(eid: EmpireId, c: Colony, sys: StarSystem): bool = {
    val e      = empires.get(eid)
    val rp     = rpFromColony(e, c, sys)
    val bcTax  = taxIncome(e, c)
    val newPoll = nextPollution(e, c, sys)
    all {
      colonies'    = colonies.exclude(Set(c)).union(Set({ ...c, pollution: newPoll })),
      empires'     = empires.put(eid, { ...e,
        bc:      e.bc + bcTax,
        rpAccum: e.rpAccum + rp
      }),
      techOptions' = techOptions
    }
  }

  // ── Action: growth tick ───────────────────────────────────────────────────

  action runColonyGrowth(eid: EmpireId, c: Colony): bool = {
    val e      = empires.get(eid)
    val newPop = nextPopulation(e, c)
    val newMax  = effectiveFactoryCap(e, newPop)
    all {
      colonies'    = colonies.exclude(Set(c)).union(Set({ ...c,
        population:   newPop,
        maxFactories: newMax
      })),
      empires'     = empires,
      techOptions' = techOptions
    }
  }

  // ── Action: build factory ─────────────────────────────────────────────────

  action buildFactory(eid: EmpireId, c: Colony, sys: StarSystem): bool = {
    val e = empires.get(eid)
    all {
      c.factories < c.maxFactories,
      c.spending.industry > 0,
      colonies'    = colonies.exclude(Set(c)).union(Set({ ...c, factories: c.factories + 1 })),
      empires'     = empires,
      techOptions' = techOptions
    }
  }

  // ── Action: build missile base ────────────────────────────────────────────
  //
  // Missile bases are capped at MAX_MISSILE_BASES and additionally limited by
  // half the colony population (can't build more bases than you have workers
  // to man them).

  pure def missileCap(c: Colony): int =
    val popCap = c.population / 2
    if (popCap < MAX_MISSILE_BASES) { popCap } else { MAX_MISSILE_BASES }

  action buildMissileBase(eid: EmpireId, c: Colony, sys: StarSystem): bool = {
    val e = empires.get(eid)
    all {
      c.missileBases < missileCap(c),
      c.spending.defense > 0,
      colonies'    = colonies.exclude(Set(c)).union(Set({ ...c, missileBases: c.missileBases + 1 })),
      empires'     = empires,
      techOptions' = techOptions
    }
  }

  // ── Action: upgrade planetary shield (Gap 5) ─────────────────────────────
  //
  // Shield levels 1-4 correspond to PlanetaryShield5/10/15/20 techs.
  // The empire must have researched the next tier's tech before upgrading.

  pure def shieldTechForLevel(lvl: int): TechName =
    if      (lvl == 1) { PlanetaryShield5  }
    else if (lvl == 2) { PlanetaryShield10 }
    else if (lvl == 3) { PlanetaryShield15 }
    else               { PlanetaryShield20 }

  action upgradeShield(eid: EmpireId, c: Colony): bool = {
    val e       = empires.get(eid)
    val nextLvl = c.shieldLevel + 1
    all {
      nextLvl <= 4,
      e.techs.contains(shieldTechForLevel(nextLvl)),
      c.spending.defense > 0,
      colonies'    = colonies.exclude(Set(c)).union(Set({ ...c, shieldLevel: nextLvl })),
      empires'     = empires,
      techOptions' = techOptions
    }
  }

  // ── Action: ship build queue processing (Gap 3) ──────────────────────────
  //
  // Ships PP accrues each turn toward the cost of the head of buildQueue.
  // When ppAccrued >= cost, the ship is complete: it is returned as a new
  // Ship record (the engine adds it to a fleet); the queue advances.
  //
  // Returning the completed DesignId via the colony state: we set a sentinel
  // signal by writing the completed ship to a separate output channel in the
  // engine.  Here we model the state change only.

  action processShipBuild(eid: EmpireId, c: Colony, sys: StarSystem, designs: DesignId -> ShipDesign): bool = {
    val e       = empires.get(eid)
    val shipsPP_ = shipsPP(e, c, sys)
    if (c.buildQueue.length() == 0) {
      // Nothing to build; PP is lost.
      all {
        colonies'    = colonies,
        empires'     = empires,
        techOptions' = techOptions
      }
    } else {
      val headDesignId = c.buildQueue.head()
      val cost         = designs.get(headDesignId).cost
      val newAccrued   = c.ppAccrued + shipsPP_
      if (newAccrued >= cost) {
        // Ship complete; dequeue and reset accrual.
        val newQueue = c.buildQueue.tail()
        all {
          colonies' = colonies.exclude(Set(c)).union(Set({ ...c,
            buildQueue: newQueue,
            ppAccrued:  newAccrued - cost
          })),
          empires'     = empires,
          techOptions' = techOptions
        }
      } else {
        // Still building; accumulate PP.
        all {
          colonies' = colonies.exclude(Set(c)).union(Set({ ...c, ppAccrued: newAccrued })),
          empires'  = empires,
          techOptions' = techOptions
        }
      }
    }
  }

  // ── Action: terraforming (Gap 6) ─────────────────────────────────────────
  //
  // Advances the world type one step toward Terran.  TerraformingMed handles
  // the lower tiers; TerraformingMax allows reaching Terran from Ocean.
  // Costs some PP from the industry or a dedicated action (engine decides).

  pure def terraformStep(current: PlanetType): PlanetType =
    if      (current == Dead)    { Radiated }
    else if (current == Radiated){ Toxic    }
    else if (current == Toxic)   { Inferno  }
    else if (current == Inferno) { Desert   }
    else if (current == Desert)  { Arid     }
    else if (current == Arid)    { Tundra   }
    else if (current == Tundra)  { Ocean    }
    else if (current == Ocean)   { Terran   }
    else                         { current  }  // already Terran or unimprovable

  pure def canTerraform(e: Empire, current: PlanetType): bool =
    if (current == Terran or current == Barren) { false }
    else if (current == Ocean) { e.techs.contains(TerraformingMax) }
    else                       { e.techs.contains(TerraformingMed) }

  action terraformWorld(eid: EmpireId, sid: StarId): bool = {
    val e   = empires.get(eid)
    val sys = stars.get(sid)
    all {
      canTerraform(e, sys.planetType),
      colonies.exists(c => c.star == sid and c.owner == eid),
      stars'       = stars.put(sid, { ...sys, planetType: terraformStep(sys.planetType) }),
      empires'     = empires,
      colonies'    = colonies,
      techOptions' = techOptions
    }
  }

  // ── Action: soil enrichment (Gap 7) ──────────────────────────────────────

  action enrichSoil(eid: EmpireId, sid: StarId): bool = {
    val e   = empires.get(eid)
    val sys = stars.get(sid)
    all {
      e.techs.contains(SoilEnrichment),
      sys.richness < MAX_RICHNESS,
      colonies.exists(c => c.star == sid and c.owner == eid),
      stars'       = stars.put(sid, { ...sys, richness: sys.richness + 1 }),
      empires'     = empires,
      colonies'    = colonies,
      techOptions' = techOptions
    }
  }

  // ── Research: tech prerequisite chain ────────────────────────────────────

  pure def hasPrerequisite(e: Empire, t: TechName): bool =
    if      (t == FusionEngines)      { e.techs.contains(NuclearEngines) }
    else if (t == IonDrive)           { e.techs.contains(FusionEngines) }
    else if (t == SubSpaceDrive)      { e.techs.contains(IonDrive) }
    else if (t == HyperDrive)         { e.techs.contains(SubSpaceDrive) }
    else if (t == InterphasedDrive)   { e.techs.contains(HyperDrive) }
    else if (t == RoboticControls3)   { e.techs.contains(RoboticControls2) }
    else if (t == RoboticControls4)   { e.techs.contains(RoboticControls3) }
    else if (t == RoboticControls5)   { e.techs.contains(RoboticControls4) }
    else if (t == BattleComputer2)    { e.techs.contains(BattleComputer1) }
    else if (t == BattleComputer3)    { e.techs.contains(BattleComputer2) }
    else if (t == Class3Shield)       { e.techs.contains(Class1Shield) }
    else if (t == Class5Shield)       { e.techs.contains(Class3Shield) }
    else if (t == Class7Shield)       { e.techs.contains(Class5Shield) }
    else if (t == Class10Shield)      { e.techs.contains(Class7Shield) }
    else if (t == Class15Shield)      { e.techs.contains(Class10Shield) }
    else if (t == Class20Shield)      { e.techs.contains(Class15Shield) }
    else if (t == Class25Shield)      { e.techs.contains(Class20Shield) }
    else if (t == Class30Shield)      { e.techs.contains(Class25Shield) }
    else if (t == PlanetaryShield10)  { e.techs.contains(PlanetaryShield5) }
    else if (t == PlanetaryShield15)  { e.techs.contains(PlanetaryShield10) }
    else if (t == PlanetaryShield20)  { e.techs.contains(PlanetaryShield15) }
    else if (t == WarpInterdictor)    { e.techs.contains(StasisField) }
    else if (t == StellarConverter)   { e.techs.contains(AntiMatterBomb) }
    else if (t == TerraformingMax)    { e.techs.contains(TerraformingMed) }
    else                              { true }

  // ── Research: tech options (Gap 2) ───────────────────────────────────────
  //
  // When research completes, the engine calls offerTechOptions with a subset
  // of available techs in the completed field.  For Psilon (Creative), the
  // engine passes the full available set.  The player calls chooseTech.

  action offerTechOptions(eid: EmpireId, offered: Set[TechName]): bool = {
    all {
      // All offered techs must be not-yet-owned and have prereqs met.
      offered.forall(t =>
        not(empires.get(eid).techs.contains(t)) and
        hasPrerequisite(empires.get(eid), t)
      ),
      techOptions' = techOptions.put(eid, offered),
      empires'     = empires,
      colonies'    = colonies
    }
  }

  action chooseTech(eid: EmpireId, chosen: TechName): bool = {
    val e = empires.get(eid)
    all {
      techOptions.get(eid).contains(chosen),
      empires'     = empires.put(eid, { ...e, researching: chosen }),
      techOptions' = techOptions.put(eid, Set()),
      colonies'    = colonies
    }
  }

  // Complete research and offer the next set of choices.
  action tryCompleteResearch(eid: EmpireId, cost: int): bool = {
    val e = empires.get(eid)
    if (e.rpAccum >= cost and not(e.techs.contains(e.researching))) {
      val withTech = { ...e, techs: e.techs.union(Set(e.researching)), rpAccum: 0 }
      all {
        empires'     = empires.put(eid, withTech),
        // techOptions will be populated by a subsequent offerTechOptions call.
        techOptions' = techOptions,
        colonies'    = colonies
      }
    } else {
      all {
        empires'     = empires,
        techOptions' = techOptions,
        colonies'    = colonies
      }
    }
  }

  // ── Espionage consequences (Gap 19) ──────────────────────────────────────
  //
  // StealTech success: copy one tech from the target empire.
  // The engine provides the specific tech to copy (chosen non-deterministically).

  action applyTechSteal(thiefEid: EmpireId, stolenTech: TechName): bool = {
    val thief = empires.get(thiefEid)
    all {
      not(thief.techs.contains(stolenTech)),
      empires'     = empires.put(thiefEid, { ...thief, techs: thief.techs.union(Set(stolenTech)) }),
      techOptions' = techOptions,
      colonies'    = colonies
    }
  }

  // SabotageIndustry success: destroy some factories at the target colony.
  action applySabotage(targetEid: EmpireId, sid: StarId, factoriesDestroyed: int): bool = {
    val colonySet = colonies.filter(c => c.star == sid and c.owner == targetEid)
    if (colonySet.size() == 0) {
      all { empires' = empires, colonies' = colonies, techOptions' = techOptions }
    } else {
      nondet c = colonySet.oneOf()
      val newFact = if (c.factories - factoriesDestroyed < 0) { 0 }
                    else { c.factories - factoriesDestroyed }
      all {
        colonies'    = colonies.exclude(colonySet).union(Set({ ...c, factories: newFact })),
        empires'     = empires,
        techOptions' = techOptions
      }
    }
  }

  // ── Colonist relocation helpers (Gap 17) ─────────────────────────────────
  //
  // Loading and unloading are resolved in combat.qnt (which owns fleets).
  // Here we expose the colony-side state changes needed.

  // Transfer `count` colonists from the colony at `sid` to a transport fleet.
  // The fleet side is updated in combat.qnt.
  action colonyEmbarksColonists(eid: EmpireId, sid: StarId, count: int): bool = {
    val colonySet = colonies.filter(c => c.star == sid and c.owner == eid)
    if (colonySet.size() == 0) {
      all { empires' = empires, colonies' = colonies, techOptions' = techOptions }
    } else {
      nondet c = colonySet.oneOf()
      all {
        count > 0,
        c.population - count >= 1,   // at least 1M must remain
        colonies' = colonies.exclude(colonySet)
                             .union(Set({ ...c, population: c.population - count })),
        empires'     = empires,
        techOptions' = techOptions
      }
    }
  }

  // Land colonists from a transport at `sid`.  If there is already a colony
  // there (owned by the same empire), they are added to its population.
  action colonyReceivesColonists(eid: EmpireId, sid: StarId, count: int): bool = {
    val colonySet = colonies.filter(c => c.star == sid and c.owner == eid)
    if (colonySet.size() == 0) {
      all { empires' = empires, colonies' = colonies, techOptions' = techOptions }
    } else {
      nondet c = colonySet.oneOf()
      val newPop = if (c.population + count > c.maxPop) { c.maxPop }
                   else { c.population + count }
      all {
        colonies' = colonies.exclude(colonySet)
                             .union(Set({ ...c, population: newPop })),
        empires'     = empires,
        techOptions' = techOptions
      }
    }
  }

  // ── Empire elimination ────────────────────────────────────────────────────

  def hasColonies(eid: EmpireId): bool =
    colonies.exists(c => c.owner == eid)

  action eliminateIfDefeated(eid: EmpireId): bool = {
    val e = empires.get(eid)
    if (not(hasColonies(eid)) and not(e.eliminated)) {
      all {
        empires'     = empires.put(eid, { ...e, eliminated: true }),
        colonies'    = colonies,
        techOptions' = techOptions
      }
    } else {
      all { empires' = empires, colonies' = colonies, techOptions' = techOptions }
    }
  }

  // ── initEmpire helper ─────────────────────────────────────────────────────

  // Builds the initial Empire record for a given race and home star.
  // The engine calls this during game setup before calling initGalaxy.
  pure def makeEmpire(eid: EmpireId, r: Race, home: StarId): Empire = {
    id:          eid,
    race:        r,
    homeStar:    home,
    bc:          50,       // starting treasury
    taxRate:     25,       // default 25% tax rate
    contacts:    Set(),    // no contacts at game start
    techs:       raceStartingTechs(r),
    rpAccum:     0,
    researching: NuclearEngines,  // placeholder; engine sets real target on turn 1
    eliminated:  false
  }

  // ── Spending validity ─────────────────────────────────────────────────────

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

  val invMissileBasesInBounds: bool =
    colonies.forall(c => c.missileBases >= 0 and c.missileBases <= missileCap(c))

  val invShieldLevelInBounds: bool =
    colonies.forall(c => c.shieldLevel >= 0 and c.shieldLevel <= 4)

  val invPpAccruedNonNeg: bool =
    colonies.forall(c => c.ppAccrued >= 0)

  val invBcNonNegative: bool =
    empires.keys().forall(eid => empires.get(eid).bc >= 0)

  val invTaxRateInRange: bool =
    empires.keys().forall(eid =>
      empires.get(eid).taxRate >= 0 and empires.get(eid).taxRate <= 50
    )

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
    colonies.forall(c =>
      stars.keys().contains(c.star) and
      stars.get(c.star).planetType != Barren
    )

  val invAtMostOneColonyPerStar: bool =
    colonies.forall(c1 =>
      colonies.forall(c2 => c1.star == c2.star implies c1.owner == c2.owner)
    )

  val invContactsSymmetric: bool =
    empires.keys().forall(a =>
      empires.get(a).contacts.forall(b =>
        empires.get(b).contacts.contains(a)
      )
    )

  val invStartingTechsOwned: bool =
    // Every empire has at least its race's starting tech set.
    empires.keys().forall(eid =>
      raceStartingTechs(empires.get(eid).race).forall(t =>
        empires.get(eid).techs.contains(t)
      )
    )
}
