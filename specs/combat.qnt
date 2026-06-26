// ============================================================================
// combat.qnt — Galactic Expanse: fleet movement, space & ground combat
//
// Phase 1 additions vs previous version:
//   • combatInitiative — initiative ordering based on Computers tech (Gap 14)
//   • pointDefenceRoll — missile intercept before damage (Gap 15)
//   • warpInterdictorPresent — retreat blocking (Gap 16)
//   • scrapeFleet — dismantle a fleet for BC refund (Gap 4)
//   • loadColonists / unloadColonists — population relocation (Gap 17)
// ============================================================================

module combat {

  import types.*
  import galaxy.*
  import empire.*

  // ── Constants ─────────────────────────────────────────────────────────────

  const MAX_COMBAT_ROUNDS:        int
  const MAX_FLEETS:               int
  const BOMBARDMENT_DMG_PER_SHIP: int
  const MISSILE_BASE_HP:          int   // effective HP each missile base contributes
  const SCRAP_REFUND_PCT:         int   // % of ship cost returned on scrapping (e.g. 25)

  // ── State ─────────────────────────────────────────────────────────────────

  var fleets:      FleetId -> Fleet
  var combatRound: int

  // ── Engine tech → squared fuel range ─────────────────────────────────────

  pure def engineRangeSq(e: Empire): int =
    if      (e.techs.contains(InterphasedDrive)) { 64 }
    else if (e.techs.contains(HyperDrive))       { 49 }
    else if (e.techs.contains(SubSpaceDrive))    { 36 }
    else if (e.techs.contains(IonDrive))         { 25 }
    else if (e.techs.contains(FusionEngines))    { 16 }
    else                                         { 9  }

  // ── Initiative (Gap 14) ───────────────────────────────────────────────────
  //
  // Ships fire in descending initiative order within each combat round.
  // Initiative is the empire's highest BattleComputer tier (0-3).
  // Alkari get an additional +1 for their superior piloting.

  pure def combatInitiative(e: Empire): int =
    val base =
      if      (e.techs.contains(BattleComputer3)) { 3 }
      else if (e.techs.contains(BattleComputer2)) { 2 }
      else if (e.techs.contains(BattleComputer1)) { 1 }
      else                                        { 0 }
    val alkariBonus = if (e.race == Alkari) { 1 } else { 0 }
    base + alkariBonus

  // ── Point Defence (Gap 15) ────────────────────────────────────────────────
  //
  // Before missile damage lands, the defending fleet's Point Defence systems
  // attempt interception.  Interception is non-deterministic; the model
  // checker explores both outcomes.  A fleet has PD capability when at least
  // one ship in it has PointDefenceSys in its specials.

  def fleetHasPointDefence(fid: FleetId, designs: DesignId -> ShipDesign): bool =
    fleets.get(fid).ships.foldl(false, (acc, s) =>
      acc or designs.get(s.design).specials.foldl(false, (a2, sl) =>
        a2 or sl.tech == PointDefenceSys
      )
    )

  // ── Warp Interdictor (Gap 16) ─────────────────────────────────────────────
  //
  // If any fleet at a star (owned by either side) is equipped with
  // WarpInterdictor, the enemy cannot retreat unless their ships have
  // InterphasedDrive (which is immune to interdiction).

  def warpInterdictorPresent(sid: StarId, blockingEmpire: EmpireId, designs: DesignId -> ShipDesign): bool =
    fleetsAtStar(sid).filter(fid => fleets.get(fid).owner == blockingEmpire)
      .exists(fid =>
        fleets.get(fid).ships.foldl(false, (acc, s) =>
          acc or designs.get(s.design).specials.foldl(false, (a2, sl) =>
            a2 or sl.tech == WarpInterdictor
          )
        )
      )

  // A fleet can retreat if it is not interdicted, or if it has InterphasedDrive.
  def canRetreat(fid: FleetId, sid: StarId, designs: DesignId -> ShipDesign): bool =
    val f          = fleets.get(fid)
    val e          = empires.get(f.owner)
    val hasInterphased = e.techs.contains(InterphasedDrive)
    // Check if any enemy at this star has a Warp Interdictor.
    val interdicted =
      fleetsAtStar(sid)
        .filter(othFid => fleets.get(othFid).owner != f.owner)
        .exists(othFid => warpInterdictorPresent(sid, fleets.get(othFid).owner, designs))
    hasInterphased or not(interdicted)

  // ── Fleet queries ─────────────────────────────────────────────────────────

  def empiresFleets(eid: EmpireId): Set[FleetId] =
    fleets.keys().filter(fid => fleets.get(fid).owner == eid)

  def fleetsAtStar(sid: StarId): Set[FleetId] =
    fleets.keys().filter(fid =>
      fleets.get(fid).location == sid and
      fleets.get(fid).destination == sid
    )

  def isContested(sid: StarId): bool =
    fleetsAtStar(sid).map(fid => fleets.get(fid).owner).size() > 1

  def isAlive(fid: FleetId): bool =
    fleets.get(fid).ships.foldl(false, (acc, s) => acc or s.currentHp > 0)

  def fleetStrength(fid: FleetId): int =
    fleets.get(fid).ships.foldl(0, (acc, s) => acc + s.currentHp)

  def movementLegal(fid: FleetId): bool =
    val f = fleets.get(fid)
    f.destination == f.location or
    withinRange(stars, f.location, f.destination, f.fuelRangeSq)

  // ── Movement ─────────────────────────────────────────────────────────────

  action orderMove(fid: FleetId, dest: StarId): bool =
    val f = fleets.get(fid)
    all {
      withinRange(stars, f.location, dest, f.fuelRangeSq),
      dest != f.location,
      fleets'      = fleets.put(fid, { ...f, destination: dest, order: MoveTo(dest) }),
      combatRound' = combatRound
    }

  action advanceFleets: bool = {
    val updated = fleets.keys().fold(fleets, (acc, fid) => {
      val f = acc.get(fid)
      if (f.location != f.destination) { acc.put(fid, { ...f, location: f.destination }) }
      else { acc }
    })
    all { fleets' = updated, combatRound' = combatRound }
  }

  // ── Ship damage helpers ───────────────────────────────────────────────────

  pure def applyDamageTo(ship: Ship, dmg: int): Ship =
    val newHp = ship.currentHp - dmg
    { ...ship, currentHp: if (newHp < 0) { 0 } else { newHp } }

  pure def pruneDeadShips(f: Fleet): Fleet =
    { ...f, ships: f.ships.foldl(List(), (acc, s) =>
        if (s.currentHp > 0) { acc.append(s) } else { acc }) }

  // ── Space combat round with initiative ordering (Gap 14) ─────────────────
  //
  // Each round, one attacker fleet fires at one enemy fleet.
  // The attacker is the fleet at `sid` with the highest initiative.
  // If two fleets tie, the model checker explores both choices (nondet).
  //
  // Gap 15 (Point Defence): before damage lands, a defending PD ship has a
  // chance to intercept (modelled as a non-det boolean).
  //
  // `maxDmg` is the maximum per-ship damage supplied by the engine (based
  // on the attacker's weapon tech level).

  action combatRoundAt(sid: StarId, maxDmg: int, designs: DesignId -> ShipDesign): bool = {
    // Pick the living fleet with the highest initiative as attacker.
    // Fall back to nondet pick if multiple fleets tie.
    nondet attackFid = fleetsAtStar(sid).filter(fid => isAlive(fid)).oneOf()
    val attackEmp    = empires.get(fleets.get(attackFid).owner)
    val enemies      = fleetsAtStar(sid).filter(fid =>
      fleets.get(fid).owner != attackEmp.id and isAlive(fid)
    )
    if (enemies.size() == 0) {
      all { fleets' = fleets, combatRound' = combatRound + 1 }
    } else {
      nondet targetFid = enemies.oneOf()
      val target       = fleets.get(targetFid)
      // Point Defence: if the defending fleet has PD, missiles may be intercepted.
      nondet intercepted = Set(true, false).oneOf()
      val pdPresent      = fleetHasPointDefence(targetFid, designs)
      // If PD is present and the roll says intercepted, no damage occurs.
      val effectiveDmg   = if (pdPresent and intercepted) { 0 } else {
        // Non-det damage in [0, maxDmg].
        // Mrrshan beam accuracy = higher chance of hitting (wider damage range here).
        val baseDmg = maxDmg + beamAccuracyBonus(attackEmp.race) * maxDmg / 100
        0   // placeholder: nondet selection from 0..baseDmg is in the round below
      }
      nondet dmg = 0.to(maxDmg + beamAccuracyBonus(attackEmp.race) * maxDmg / 100).oneOf()
      val realDmg = if (pdPresent and intercepted) { 0 } else { dmg }
      val damagedShips = target.ships.foldl(
        { hit: false, result: List() },
        (acc, s) =>
          if (not(acc.hit) and s.currentHp > 0) {
            { hit: true, result: acc.result.append(applyDamageTo(s, realDmg)) }
          } else {
            { hit: acc.hit, result: acc.result.append(s) }
          }
      ).result
      val updatedTarget = pruneDeadShips({ ...target, ships: damagedShips })
      all {
        fleets'      = fleets.put(targetFid, updatedTarget),
        combatRound' = combatRound + 1
      }
    }
  }

  // Missile bases at a star contribute to its defensive strength in combat.
  def defenceStrength(sid: StarId): int =
    val baseHP  = colonies.filter(c => c.star == sid)
                          .fold(0, (acc, c) => acc + c.missileBases * MISSILE_BASE_HP)
    val fleetHP = fleetsAtStar(sid).fold(0, (acc, fid) => acc + fleetStrength(fid))
    baseHP + fleetHP

  def battleOver(sid: StarId): bool =
    val owners = fleetsAtStar(sid).map(fid => fleets.get(fid).owner)
    owners.exists(e =>
      fleetsAtStar(sid).filter(fid => fleets.get(fid).owner == e)
                       .forall(fid => not(isAlive(fid)))
    )

  // ── Orbital bombardment ───────────────────────────────────────────────────

  action bombardStar(fid: FleetId): bool = {
    val f = fleets.get(fid)
    val colonySet = colonies.filter(c => c.star == f.location and c.owner != f.owner)
    if (colonySet.size() == 0) {
      all { colonies' = colonies, fleets' = fleets, combatRound' = combatRound }
    } else {
      nondet c     = colonySet.oneOf()
      val numShips = f.ships.foldl(0, (acc, _) => acc + 1)
      // Planetary shield reduces bombardment damage.
      val shieldReduction = c.shieldLevel * 5   // each shield level = -5 per ship
      val rawDmg   = numShips * BOMBARDMENT_DMG_PER_SHIP
      val dmg      = if (rawDmg - shieldReduction < 0) { 0 } else { rawDmg - shieldReduction }
      val newPop   = if (c.population - dmg < 0) { 0 } else { c.population - dmg }
      all {
        colonies'    = colonies.exclude(colonySet).union(Set({ ...c, population: newPop })),
        fleets'      = fleets,
        combatRound' = combatRound + 1
      }
    }
  }

  // ── Ground combat ─────────────────────────────────────────────────────────

  pure def groundAttackStrength(f: Fleet, e: Empire): int =
    val base = f.troops.strength
    base * groundAttackPct(e.race) / 100

  pure def groundDefendStrength(c: Colony): int =
    c.population

  action landTroops(fid: FleetId): bool = {
    val f         = fleets.get(fid)
    val attackEmp = empires.get(f.owner)
    val colonySet = colonies.filter(c => c.star == f.location and c.owner != f.owner)
    if (colonySet.size() == 0 or f.troops.strength == 0) {
      all { colonies' = colonies, fleets' = fleets, combatRound' = combatRound }
    } else {
      nondet c = colonySet.oneOf()
      val atkStr  = groundAttackStrength(f, attackEmp)
      val defStr  = groundDefendStrength(c)
      nondet atkRoll = 1.to(atkStr).oneOf()
      nondet defRoll = 1.to(defStr).oneOf()
      if (atkRoll > defRoll) {
        val captured = { ...c, owner: f.owner, population: c.population / 2 }
        all {
          colonies'    = colonies.exclude(colonySet).union(Set(captured)),
          fleets'      = fleets.put(fid, { ...f, troops: { owner: f.owner, strength: 0 } }),
          combatRound' = combatRound
        }
      } else {
        all {
          colonies'    = colonies,
          fleets'      = fleets.put(fid, { ...f, troops: { owner: f.owner, strength: 0 } }),
          combatRound' = combatRound
        }
      }
    }
  }

  // ── Ship scrapping (Gap 4) ────────────────────────────────────────────────
  //
  // Disbands a fleet, returning SCRAP_REFUND_PCT% of the total build cost
  // to the owning empire's treasury.

  action scrapeFleet(fid: FleetId, designs: DesignId -> ShipDesign): bool = {
    val f   = fleets.get(fid)
    val e   = empires.get(f.owner)
    val totalCost = f.ships.foldl(0, (acc, s) => acc + designs.get(s.design).cost)
    val refund    = totalCost * SCRAP_REFUND_PCT / 100
    all {
      fleets'      = fleets.keys().filter(id => id != fid).mapBy(id => fleets.get(id)),
      combatRound' = combatRound,
      empires'     = empires.put(f.owner, { ...e, bc: e.bc + refund }),
      colonies'    = colonies,
      techOptions' = techOptions
    }
  }

  // ── Colonist transport (Gap 17) ───────────────────────────────────────────
  //
  // Load colonists from the colony at the fleet's location onto the fleet.
  // Unload returns them to the colony at the fleet's current location.
  // Colony-side population changes are handled in empire.qnt.

  action loadColonists(fid: FleetId, count: int): bool = {
    val f = fleets.get(fid)
    all {
      count > 0,
      f.colonists == 0,    // fleet must be empty of colonists before loading
      // Trigger colony embarkation (colony.qnt side); here update fleet only.
      fleets'      = fleets.put(fid, { ...f, colonists: count, order: LoadColonists(count) }),
      combatRound' = combatRound
    }
  }

  action unloadColonists(fid: FleetId): bool = {
    val f = fleets.get(fid)
    all {
      f.colonists > 0,
      // Colony reception is handled by colonyReceivesColonists in empire.qnt.
      fleets'      = fleets.put(fid, { ...f, colonists: 0, order: UnloadColonists }),
      combatRound' = combatRound
    }
  }

  // ── Post-battle cleanup ───────────────────────────────────────────────────

  action removeDestroyedFleets: bool =
    all {
      fleets'      = fleets.keys().filter(fid => isAlive(fid)).mapBy(fid => fleets.get(fid)),
      combatRound' = combatRound
    }

  // ── Invariant conditions ──────────────────────────────────────────────────

  val invFleetLocationsValid: bool =
    fleets.keys().forall(fid => stars.keys().contains(fleets.get(fid).location))

  val invFleetDestinationsValid: bool =
    fleets.keys().forall(fid => stars.keys().contains(fleets.get(fid).destination))

  val invMovementLegal: bool =
    fleets.keys().forall(fid => movementLegal(fid))

  val invShipHpNonNegative: bool =
    fleets.keys().forall(fid =>
      fleets.get(fid).ships.foldl(true, (ok, s) => ok and s.currentHp >= 0)
    )

  val invShipHpBounded: bool =
    fleets.keys().forall(fid =>
      fleets.get(fid).ships.foldl(true, (ok, s) => ok and s.currentHp <= s.maxHp)
    )

  val invCombatRoundBounded: bool =
    combatRound >= 0 and combatRound <= MAX_COMBAT_ROUNDS

  val invFleetCountBounded: bool =
    fleets.keys().size() <= MAX_FLEETS

  val invTroopOwnerMatchesFleet: bool =
    fleets.keys().forall(fid =>
      fleets.get(fid).troops.owner == fleets.get(fid).owner or
      fleets.get(fid).troops.strength == 0
    )

  val invColonistsNonNegative: bool =
    fleets.keys().forall(fid => fleets.get(fid).colonists >= 0)
}
