// ============================================================================
// combat.qnt — Galactic Expanse: fleet movement, space & ground combat
//
// Movement: range-based (no hyperlanes).  A fleet reaches any star within
// its squared fuel range (from engine tech) in one turn.
//
// Each star has at most one colony.  Bombardment and invasion target
// the star directly — no PlanetId needed.
//
// Missile bases (built via the Defense spending slider) participate in
// defence when an enemy fleet arrives at a colonised star.
// ============================================================================

module combat {

  import types.*
  import galaxy.*
  import empire.*

  // ── Constants ─────────────────────────────────────────────────────────────

  const MAX_COMBAT_ROUNDS:        int
  const MAX_FLEETS:               int
  const BOMBARDMENT_DMG_PER_SHIP: int   // pop killed per ship per bombardment round
  const MISSILE_BASE_HP:          int   // HP each missile base contributes to defence

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
    else                                         { 9  }  // NuclearEngines

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

  // List has no exists; fold instead.
  def isAlive(fid: FleetId): bool =
    fleets.get(fid).ships.foldl(false, (acc, s) => acc or s.currentHp > 0)

  def fleetStrength(fid: FleetId): int =
    fleets.get(fid).ships.foldl(0, (acc, s) => acc + s.currentHp)

  // ── Movement legality ─────────────────────────────────────────────────────

  def movementLegal(fid: FleetId): bool =
    val f = fleets.get(fid)
    f.destination == f.location or
    withinRange(stars, f.location, f.destination, f.fuelRangeSq)

  action orderMove(fid: FleetId, dest: StarId): bool =
    val f = fleets.get(fid)
    all {
      withinRange(stars, f.location, dest, f.fuelRangeSq),
      dest != f.location,
      fleets'      = fleets.put(fid, { ...f, destination: dest, order: MoveTo(dest) }),
      combatRound' = combatRound
    }

  // All in-transit fleets arrive at their destination in one step.
  action advanceFleets: bool = {
    val updated = fleets.keys().fold(fleets, (acc, fid) => {
      val f = acc.get(fid)
      if (f.location != f.destination) { acc.put(fid, { ...f, location: f.destination }) }
      else { acc }
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

  // List has no filter returning a List; use foldl.
  pure def pruneDeadShips(f: Fleet): Fleet =
    { ...f, ships: f.ships.foldl(List(), (acc, s) =>
        if (s.currentHp > 0) { acc.append(s) } else { acc }) }

  // ── Space combat round ────────────────────────────────────────────────────
  //
  // Non-deterministic: the model checker explores all attacker/target/damage
  // combinations.  `nondet` stays at action scope only.

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
      // Damage the first living ship (foldl preserves list order).
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

  // Missile bases contribute to defence HP alongside the fleet.
  // Each base adds MISSILE_BASE_HP to the effective defensive strength.
  def defenceStrength(sid: StarId): int =
    val baseHP = colonies.filter(c => c.star == sid)
                         .fold(0, (acc, c) => acc + c.missileBases * MISSILE_BASE_HP)
    val fleetHP = fleetsAtStar(sid).fold(0, (acc, fid) => acc + fleetStrength(fid))
    baseHP + fleetHP

  // Battle ends when one side has no living ships (missile bases are not
  // modelled as destroyable units here; they absorb damage silently).
  def battleOver(sid: StarId): bool =
    val owners = fleetsAtStar(sid).map(fid => fleets.get(fid).owner)
    owners.exists(e =>
      fleetsAtStar(sid).filter(fid => fleets.get(fid).owner == e)
                       .forall(fid => not(isAlive(fid)))
    )

  // ── Orbital bombardment ───────────────────────────────────────────────────
  //
  // Target is the star the fleet currently occupies.  Kills population;
  // leaves factories and missile bases intact (unless NeutronBomb is used —
  // distinction handled by the engine; the spec models population reduction).

  action bombardStar(fid: FleetId): bool = {
    val f = fleets.get(fid)
    val colonySet = colonies.filter(c => c.star == f.location and c.owner != f.owner)
    if (colonySet.size() == 0) {
      all { colonies' = colonies, fleets' = fleets, combatRound' = combatRound }
    } else {
      nondet c     = colonySet.oneOf()
      val numShips = f.ships.foldl(0, (acc, _) => acc + 1)
      val popDmg   = numShips * BOMBARDMENT_DMG_PER_SHIP
      val newPop   = if (c.population - popDmg < 0) { 0 } else { c.population - popDmg }
      all {
        colonies'    = colonies.exclude(colonySet).union(Set({ ...c, population: newPop })),
        fleets'      = fleets,
        combatRound' = combatRound + 1
      }
    }
  }

  // ── Ground combat ─────────────────────────────────────────────────────────
  //
  // Troops land at the fleet's current star.  Bulrathi get +50% attack.

  pure def groundAttackStrength(f: Fleet, e: Empire): int =
    val base = f.troops.strength
    if (e.race == Bulrathi) { base * 3 / 2 } else { base }

  pure def groundDefendStrength(c: Colony): int =
    c.population   // every defending colonist fights

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
}
