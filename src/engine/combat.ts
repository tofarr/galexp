import type { Fleet, FleetId, StarId, GameState, Colony, Empire, ShipDesign, Ship } from '../types'
import { C, HULL_HP, HULL_COST, HULL_UPKEEP, HULL_ATTACK } from './constants'
import { distSq, withinRange, hasColonisableWorld } from './galaxy'
import { groundAtkPct, isColonisable, combatInitiative, engineRangeSq } from './empire'

// ── Fleet queries ─────────────────────────────────────────────────────────
export function fleetsAtStar(state: GameState, sid: StarId): FleetId[] {
  return [...state.fleets.entries()]
    .filter(([, f]) => f.location === sid && f.destination === sid)
    .map(([id]) => id)
}

export function empireFleets(state: GameState, eid: number): FleetId[] {
  return [...state.fleets.entries()]
    .filter(([, f]) => f.owner === eid)
    .map(([id]) => id)
}

export function isAlive(f: Fleet): boolean {
  return f.ships.some(s => s.currentHp > 0)
}

export function fleetStrength(f: Fleet): number {
  return f.ships.reduce((a, s) => a + s.currentHp, 0)
}

// ── Default ship designs ──────────────────────────────────────────────────
export function makeDesign(
  id: number, owner: number,
  hull: 'Scout' | 'ColonyShip' | 'Destroyer' | 'Cruiser' | 'Battleship',
): ShipDesign {
  return {
    id, owner, hull,
    weapons:  [],
    specials: [],
    cost:     HULL_COST[hull],
    upkeep:   HULL_UPKEEP[hull],
    attack:   HULL_ATTACK[hull],
    hp:       HULL_HP[hull],
  }
}

export function makeShip(design: ShipDesign): Ship {
  return { design: design.id, currentHp: design.hp, maxHp: design.hp }
}

// ── Movement ─────────────────────────────────────────────────────────────
export function canMoveTo(state: GameState, fid: FleetId, dst: StarId): boolean {
  const f = state.fleets.get(fid)!
  return withinRange(state.stars, f.location, dst, f.fuelRangeSq)
}

export function orderMove(state: GameState, fid: FleetId, dst: StarId): GameState {
  if (!canMoveTo(state, fid, dst)) return state
  const f = state.fleets.get(fid)!
  const newFleets = new Map(state.fleets)
  newFleets.set(fid, { ...f, destination: dst, transitPct: 0, order: { type: 'MoveTo', destination: dst } })
  return { ...state, fleets: newFleets }
}

export function advanceFleets(state: GameState): GameState {
  const newFleets = new Map<FleetId, Fleet>()
  for (const [id, f] of state.fleets) {
    if (f.location !== f.destination) {
      newFleets.set(id, { ...f, location: f.destination, transitPct: 1,
        order: { type: 'HoldPosition' } })
    } else {
      newFleets.set(id, f)
    }
  }
  return { ...state, fleets: newFleets }
}

// ── Space combat ──────────────────────────────────────────────────────────
function applyDmg(ship: Ship, dmg: number): Ship {
  return { ...ship, currentHp: Math.max(0, ship.currentHp - dmg) }
}

function pruneDeadShips(f: Fleet): Fleet {
  return { ...f, ships: f.ships.filter(s => s.currentHp > 0) }
}

export function resolveCombatAtStar(state: GameState, sid: StarId, rng: () => number): GameState {
  const fids   = fleetsAtStar(state, sid).filter(id => isAlive(state.fleets.get(id)!))
  const owners = [...new Set(fids.map(id => state.fleets.get(id)!.owner))]
  if (owners.length < 2) return state

  // Attacker = highest-initiative owner among those with living fleets
  const sorted = [...owners].sort((a, b) => {
    const ea = state.empires.get(a)!, eb = state.empires.get(b)!
    return combatInitiative(eb) - combatInitiative(ea)
  })
  const atkOwner = sorted[0]
  const defOwners = sorted.slice(1)

  // Pick a target fleet from enemies (weakest first)
  const enemyFids = fids
    .filter(id => defOwners.includes(state.fleets.get(id)!.owner))
    .sort((a, b) => fleetStrength(state.fleets.get(a)!) - fleetStrength(state.fleets.get(b)!))
  if (enemyFids.length === 0) return state
  const targetFid = enemyFids[0]

  // Find the attacker's fleet with most ships
  const atkFids = fids.filter(id => state.fleets.get(id)!.owner === atkOwner)
  const atkFid  = atkFids.sort((a, b) => fleetStrength(state.fleets.get(b)!) - fleetStrength(state.fleets.get(a)!))[0]
  const atkFleet = state.fleets.get(atkFid)!
  const atkEmp   = state.empires.get(atkOwner)!

  // Calculate damage
  const baseDmg  = atkFleet.ships.reduce((a, s) => {
    const d = state.designs.get(s.design)!
    return a + d.attack
  }, 0)
  const dmg = Math.max(1, Math.floor(baseDmg * (1 + rng() * 0.5) * (1 + (atkEmp.race === 'Mrrshan' ? 0.5 : 0))))

  // Apply to first living ship in target fleet
  const target = state.fleets.get(targetFid)!
  let hit = false
  const newShips = target.ships.map(s => {
    if (!hit && s.currentHp > 0) { hit = true; return applyDmg(s, dmg) }
    return s
  })
  const newTarget = pruneDeadShips({ ...target, ships: newShips })
  const newFleets = new Map(state.fleets)
  if (newTarget.ships.length === 0) {
    newFleets.delete(targetFid)
  } else {
    newFleets.set(targetFid, newTarget)
  }

  return { ...state, fleets: newFleets, combatRound: state.combatRound + 1 }
}

// ── Orbital bombardment ───────────────────────────────────────────────────
export function bombardStar(state: GameState, fid: FleetId, rng: () => number): GameState {
  const f = state.fleets.get(fid)!
  const enemy = state.colonies.find(c => c.star === f.location && c.owner !== f.owner)
  if (!enemy) return state

  const numShips  = f.ships.length
  const shieldRed = enemy.shieldLevel * 5
  const rawDmg    = numShips * C.BOMBARDMENT_DMG_PER_SHIP + Math.floor(rng() * numShips)
  const dmg       = Math.max(0, rawDmg - shieldRed)
  const newPop    = Math.max(0, enemy.population - dmg)

  const newCols   = state.colonies.map(c =>
    c.star === f.location && c.owner !== f.owner ? { ...c, population: newPop } : c
  )
  return { ...state, colonies: newCols }
}

// ── Ground combat ─────────────────────────────────────────────────────────
export function landTroops(state: GameState, fid: FleetId, rng: () => number): GameState {
  const f       = state.fleets.get(fid)!
  if (f.troops.strength === 0) return state
  const enemy   = state.colonies.find(c => c.star === f.location && c.owner !== f.owner)
  if (!enemy) return state

  const atkEmp  = state.empires.get(f.owner)!
  const atkStr  = Math.floor(f.troops.strength * groundAtkPct(atkEmp.race) / 100)
  const defStr  = enemy.population
  const atkRoll = Math.floor(rng() * atkStr) + 1
  const defRoll = Math.floor(rng() * defStr) + 1

  const newFleets = new Map(state.fleets)
  newFleets.set(fid, { ...f, troops: { owner: f.owner, strength: 0 } })

  if (atkRoll > defRoll) {
    // Captured
    const newCols = state.colonies.map(c =>
      c === enemy ? { ...c, owner: f.owner, population: Math.max(1, Math.floor(c.population / 2)) } : c
    )
    return { ...state, colonies: newCols, fleets: newFleets,
      log: [...state.log, `Empire ${f.owner} captured ${state.stars.get(f.location)!.name}!`] }
  }
  return { ...state, fleets: newFleets }
}

// ── Colony ship: found colony ─────────────────────────────────────────────
export function foundColony(state: GameState, fid: FleetId): GameState {
  const f   = state.fleets.get(fid)!
  const sys = state.stars.get(f.location)!
  const e   = state.empires.get(f.owner)!
  if (!isColonisable(sys, e)) return state
  if (state.colonies.some(c => c.star === f.location)) return state

  // Remove colony ship from fleet; if empty, remove fleet
  const colShip = f.ships.find(s => state.designs.get(s.design)!.hull === 'ColonyShip')
  if (!colShip) return state

  const newShips  = f.ships.filter(s => s !== colShip)
  const newFleets = new Map(state.fleets)
  if (newShips.length === 0) newFleets.delete(fid)
  else newFleets.set(fid, { ...f, ships: newShips })

  const ratio = Math.floor(e.techs.has('RoboticControls3') ? 3
                         : e.techs.has('RoboticControls2') ? 2 : 1)
  const pop   = C.COLONY_SHIP_POP
  const newCol = {
    star: f.location, owner: f.owner,
    population: pop, maxPop: sys.maxPopBase + (e.techs.has('Biospheres') ? 2 : 0),
    factories: 0, maxFactories: pop * ratio,
    pollution: 0, missileBases: 0, shieldLevel: 0,
    spending: { ships:0, defense:0, industry:50, ecology:20, research:30 },
    buildQueue: [], ppAccrued: 0,
  }
  const newStars = new Map(state.stars)
  const s = newStars.get(f.location)!
  newStars.set(f.location, { ...s, explored: new Set([...s.explored, f.owner]) })

  return { ...state, colonies: [...state.colonies, newCol],
    fleets: newFleets, stars: newStars,
    log: [...state.log, `${e.race} empire founded colony at ${sys.name}`] }
}

// ── Fleet scrapping ───────────────────────────────────────────────────────
export function scrapeFleet(state: GameState, fid: FleetId): GameState {
  const f        = state.fleets.get(fid)!
  const e        = state.empires.get(f.owner)!
  const cost     = f.ships.reduce((a, s) => a + (state.designs.get(s.design)?.cost ?? 0), 0)
  const refund   = Math.floor(cost * C.SCRAP_REFUND_PCT / 100)
  const newFleets = new Map(state.fleets)
  newFleets.delete(fid)
  const newEmpires = new Map(state.empires)
  newEmpires.set(f.owner, { ...e, bc: e.bc + refund })
  return { ...state, fleets: newFleets, empires: newEmpires }
}

// ── Spawn a new fleet at a star ───────────────────────────────────────────
export function spawnFleet(state: GameState, eid: number, sid: StarId, ships: Ship[]): GameState {
  const e      = state.empires.get(eid)!
  const fid    = state.nextFleetId
  const fleet: Fleet = {
    id: fid, owner: eid, location: sid, destination: sid, transitPct: 0,
    ships, troops: { owner: eid, strength: 0 }, colonists: 0,
    order: { type: 'HoldPosition' }, fuelRangeSq: engineRangeSq(e),
  }
  const newFleets = new Map(state.fleets)
  newFleets.set(fid, fleet)
  return { ...state, fleets: newFleets, nextFleetId: fid + 1 }
}
