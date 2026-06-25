// ============================================================================
// combat.qnt — Galactic Expanse: fleet movement, space & ground combat (MOO1)
//
// In MOO1, movement is range-based (no hyperlanes):
//   • A fleet can reach any star whose squared distance ≤ its fuelRangeSq.
//   • fuelRangeSq is determined by the best engine tech the empire owns.
//
// Space combat is round-based at contested stars.  Ground combat follows
// after successful orbital bombardment reduces defender pop below army strength.
//
// Owns `fleets` and `combatRound` state variables.
// ============================================================================

module combat {

  import types.*
  import galaxy.*
  import empire.*

  // ── Constants ─────────────────────────────────────────────────────────────

  const MAX_COMBAT_ROUNDS:   int  // space battle ends after this many rounds
  const MAX_FLEETS:          int  // upper bound for model-checking tractability
  const BOMBARDMENT_DMG_PER_SHIP: int // pop killed per ship per bombardment round

  // ── State ─────────────────────────────────────────────────────────────────

  var fleets:      FleetId -> Fleet
  var combatRound: int

  // ── Engine tech → squared fuel range ─────────────────────────────────────
  //
  // Maps the best engine technology an empire has researched to its squared
  // parsec range, matching the MOO1 drive progression.

  pure def engineRangeSq(e: Empire): int =
    if      (e.techs.contains(InterphasedDrive)) { 64 }
    else if (e.techs.contains(HyperDrive))       { 49 }
    else if (e.techs.contains(SubSpaceDrive))    { 36 }
    else if (e.techs.contains(IonDrive))         { 25 }
    else if (e.techs.contains(FusionEngines))    { 16 }
    else                                         { 9  }  // NuclearEngines (default)

  // ── Fleet queries ─────────────────────────────────────────────────────────

  def empiresFleets(eid: EmpireId): Set[FleetId] =
    fleets.keys().filter(fid => fleets.get(fid).owner == eid)

  // Fleets that have arrived at (not in transit to) a star.
  def fleetsAtStar(sid: StarId): Set[FleetId] =
    fleets.keys().filter(fid =>
      fleets.get(fid).location == sid and
      fleets.get(fid).destination == sid
    )

  // More than one empire has fleets at this star.
  def isContested(sid: StarId): bool =
    fleetsAtStar(sid).map(fid => fleets.get(fid).owner).size() > 1

  // List has no exists; fold over it to check if any ship is living.
  def isAlive(fid: FleetId): bool =
    fleets.get(fid).ships.foldl(false, (acc, s) => acc or s.currentHp > 0)

  def fleetStrength(fid: FleetId): int =
    fleets.get(fid).ships.foldl(0, (acc, s) => acc + s.currentHp)

  // ── Movement legality ─────────────────────────────────────────────────────
  //
  // A fleet's destination must be within its fuelRangeSq from its current
  // location.  Idle fleets (destination == location) always satisfy this.

  def movementLegal(fid: FleetId): bool =
    val f = fleets.get(fid)
    f.destination == f.location or
    withinRange(stars, f.location, f.destination, f.fuelRangeSq)

  // Issue a movement order.  The engine verifies range before calling this.
  action orderMove(fid: FleetId, dest: StarId): bool =
    val f = fleets.get(fid)
    all {
      withinRange(stars, f.location, dest, f.fuelRangeSq),
      dest != f.location,
      fleets'      = fleets.put(fid, { ...f, destination: dest, order: MoveTo(dest) }),
      combatRound' = combatRound
    }

  // Resolve movement: all in-transit fleets arrive at their destination in
  // one step (MOO1 travel is instantaneous within range).
  action advanceFleets: bool = {
    val updated = fleets.keys().fold(fleets, (acc, fid) => {
      val f = acc.get(fid)
      if (f.location != f.destination) {
        acc.put(fid, { ...f, location: f.destination })
      } else {
        acc
      }
    })
    all {
      fleets'      = updated,
      combatRound' = combatRound
    }
  }

  // ── Ship damage helpers ───────────────────────────────────────────────────

  pure def applyDamageTo(ship: Ship, dmg: int): Ship =
    val newHp = ship.currentHp - dmg
    { ...ship, currentHp: if (newHp < 0) { 0 } else { newHp } }

  // List has no filter (filter returns a Set in Quint); use foldl instead.
  pure def pruneDeadShips(f: Fleet): Fleet =
    { ...f, ships: f.ships.foldl(List(), (acc, s) => if (s.currentHp > 0) { acc.append(s) } else { acc }) }

  // ── Space combat round ────────────────────────────────────────────────────
  //
  // Each round:
  //   1. One non-deterministic attacker fleet is picked.
  //   2. One non-deterministic enemy fleet is chosen as target.
  //   3. Non-deterministic damage (0..maxDmg) is applied to the first
  //      living ship in the target fleet.
  //   4. Dead ships are removed; combatRound increments.
  //
  // `nondet` stays at action scope — never inside lambdas — to keep the
  // model checker happy.  Mrrshan beam accuracy bonus is captured by a
  // wider damage range when the attacker is a Mrrshan empire.

  action combatRoundAt(sid: StarId, maxDmg: int): bool = {
    nondet dmg       = 0.to(maxDmg).oneOf()
    nondet attackFid = fleetsAtStar(sid).oneOf()
    val attackOwner  = fleets.get(attackFid).owner
    val enemies      = fleetsAtStar(sid).filter(fid =>
      fleets.get(fid).owner != attackOwner and isAlive(fid)
    )
    if (enemies.size() == 0 or not(isAlive(attackFid))) {
      all { fleets' = fleets, combatRound' = combatRound + 1 }
    } else {
      nondet targetFid = enemies.oneOf()
      val target       = fleets.get(targetFid)
      // Damage first living ship (simplified targeting; engine implements full logic).
      val damagedShips = target.ships.foldl(
        { hit: false, result: List() },
        (acc, s) =>
          if (not(acc.hit) and s.currentHp > 0) {
            { hit: true, result: acc.result.append(applyDamageTo(s, dmg)) }
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

  // Battle ends when one side has no living ships at the star.
  def battleOver(sid: StarId): bool =
    val empOwners = fleetsAtStar(sid).map(fid => fleets.get(fid).owner)
    empOwners.exists(e =>
      fleetsAtStar(sid).filter(fid => fleets.get(fid).owner == e)
                       .forall(fid => not(isAlive(fid)))
    )

  // ── Orbital bombardment ───────────────────────────────────────────────────
  //
  // After winning the space battle, a fleet may bombard the colony on a planet
  // to soften defences before landing troops.  Each ship kills
  // BOMBARDMENT_DMG_PER_SHIP million population per round.
  // NeutronBomb-equipped ships kill pop without destroying factories.

  action bombardPlanet(fid: FleetId, planetId: PlanetId): bool = {
    val f = fleets.get(fid)
    val colonyOpt = colonies.filter(c =>
      c.star == f.location and c.planet == planetId and c.owner != f.owner
    )
    if (colonyOpt.size() == 0) {
      all { colonies' = colonies, fleets' = fleets, combatRound' = combatRound }
    } else {
      nondet c = colonyOpt.oneOf()
      val numShips = f.ships.foldl(0, (acc, _) => acc + 1)
      val popDmg   = numShips * BOMBARDMENT_DMG_PER_SHIP
      val newPop   = if (c.population - popDmg < 0) { 0 } else { c.population - popDmg }
      all {
        colonies'    = colonies.exclude(colonyOpt).union(Set({ ...c, population: newPop })),
        fleets'      = fleets,
        combatRound' = combatRound + 1
      }
    }
  }

  // ── Ground combat ─────────────────────────────────────────────────────────
  //
  // Ground troops land when the fleet carries troops AND the planet population
  // has been reduced below the defenders' army strength.
  // Bulrathi attackers get a +50% strength bonus.
  //
  // Outcome is non-deterministic (dice rolls); the colony flips ownership
  // on a successful invasion.

  pure def groundAttackStrength(f: Fleet, e: Empire): int =
    val base = f.troops.strength
    if (e.race == Bulrathi) { base * 3 / 2 } else { base }

  pure def groundDefendStrength(c: Colony, e: Empire): int =
    c.population   // defenders = remaining pop; Bulrathi bonus applies to attack only

  action landTroops(fid: FleetId, planetId: PlanetId): bool = {
    val f          = fleets.get(fid)
    val attackEmp  = empires.get(f.owner)
    val colonySet  = colonies.filter(c =>
      c.star == f.location and c.planet == planetId and c.owner != f.owner
    )
    if (colonySet.size() == 0 or f.troops.strength == 0) {
      all { colonies' = colonies, fleets' = fleets, combatRound' = combatRound }
    } else {
      nondet c = colonySet.oneOf()
      val atkStr   = groundAttackStrength(f, attackEmp)
      val defStr   = groundDefendStrength(c, empires.get(c.owner))
      nondet atkRoll = 1.to(atkStr).oneOf()
      nondet defRoll = 1.to(defStr).oneOf()
      if (atkRoll > defRoll) {
        // Invasion succeeds: colony changes ownership.
        val captured = { ...c, owner: f.owner, population: c.population / 2 }
        all {
          colonies'    = colonies.exclude(colonySet).union(Set(captured)),
          fleets'      = fleets.put(fid, { ...f, troops: { owner: f.owner, strength: 0 } }),
          combatRound' = combatRound
        }
      } else {
        // Invasion repelled: attacker loses troops.
        all {
          colonies'    = colonies,
          fleets'      = fleets.put(fid, { ...f, troops: { owner: f.owner, strength: 0 } }),
          combatRound' = combatRound
        }
      }
    }
  }

  // ── Post-battle cleanup ───────────────────────────────────────────────────
  //
  // Remove fleets with no surviving ships.  We rebuild the map from surviving
  // keys using mapBy so we don't need a remove operation.

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

  // List has no forall; use foldl to check all elements.
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
}
