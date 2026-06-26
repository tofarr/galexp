import type { GameState, EmpireId, StarId, FleetId, Colony } from '../types'
import { C } from './constants'
import { nearestUnexplored, reachableStars, hasColonisableWorld, distSq } from './galaxy'
import { isColonisable, defaultSpending, availableTechs, engineRangeSq } from './empire'
import { fleetsAtStar, orderMove, isAlive, empireFleets, foundColony, makeShip, spawnFleet } from './combat'

// ── Colony AI ─────────────────────────────────────────────────────────────
// Adjusts spending sliders and queues ships based on game stage.

function runColonyAI(state: GameState, eid: EmpireId): GameState {
  const e     = state.empires.get(eid)!
  const spend = defaultSpending(state.turn)

  const myColonies   = state.colonies.filter(c => c.owner === eid)
  const myFleets     = [...state.fleets.values()].filter(f => f.owner === eid)

  // One colony ship in transit or queued is enough
  const colShipInFleet = myFleets.some(f =>
    f.ships.some(s => state.designs.get(s.design)?.hull === 'ColonyShip'))
  const colShipQueued  = myColonies.some(c =>
    c.buildQueue.some(did => state.designs.get(did)?.hull === 'ColonyShip'))
  const needColShip    = !colShipInFleet && !colShipQueued

  // Want a destroyer if we have 2+ colonies and no combat ships anywhere
  const hasCombat = myFleets.some(f =>
    f.ships.some(s => {
      const h = state.designs.get(s.design)?.hull
      return h === 'Destroyer' || h === 'Cruiser' || h === 'Battleship'
    }))
  const needDestroyer = myColonies.length >= 2 && !hasCombat

  const hasFreeStars = [...state.stars.values()].some(sys =>
    hasColonisableWorld(sys) &&
    !state.colonies.some(c => c.star === sys.id) &&
    isColonisable(sys, e)
  )

  // Pick one queuing colony (largest production colony for ships)
  const bestCol = myColonies.reduce(
    (best: Colony | null, c) => !best || c.factories > best.factories ? c : best,
    null,
  )

  const newCols = state.colonies.map(c => {
    if (c.owner !== eid) return c
    let s = { ...spend }
    if (c.buildQueue.length === 0) {
      const isBest = c.star === bestCol?.star
      if (isBest && needColShip && hasFreeStars) {
        const des = [...state.designs.values()].find(d => d.owner === eid && d.hull === 'ColonyShip')
        if (des) return { ...c, spending: { ...s, ships: 25, industry: Math.max(0, s.industry - 25) },
          buildQueue: [des.id] }
      }
      if (isBest && needDestroyer) {
        const des = [...state.designs.values()].find(d => d.owner === eid && d.hull === 'Destroyer')
        if (des) return { ...c, spending: { ...s, ships: 25, industry: Math.max(0, s.industry - 25) },
          buildQueue: [des.id] }
      }
      // Nothing to build: redirect ships into industry
      s = { ...s, ships: 0, industry: s.industry + s.ships }
    }
    return { ...c, spending: s }
  })

  // Auto-pick next research if none queued (prefer engine > robotics > weapons)
  const newEmpires = new Map(state.empires)
  const avail      = availableTechs(e)
  if (e.rpAccum === 0 && avail.length > 0 && !e.techs.has(e.researching)) {
    const priority = ['FusionEngines','IonDrive','SubSpaceDrive','RoboticControls3',
                      'RoboticControls4','BattleComputer1','BattleComputer2','Class3Shield']
    const pick = priority.find(t => avail.includes(t as any)) ?? avail[0]
    newEmpires.set(eid, { ...e, researching: pick as any })
  }

  return { ...state, colonies: newCols, empires: newEmpires }
}

// ── Fleet AI ──────────────────────────────────────────────────────────────
// Sends scouts to explore, colony ships to colonise, warships to attack.

function runFleetAI(state: GameState, eid: EmpireId, rng: () => number): GameState {
  let s = state
  const e = s.empires.get(eid)!
  const rangeSq = engineRangeSq(e)

  for (const fid of empireFleets(s, eid)) {
    const f = s.fleets.get(fid)
    if (!f || !isAlive(f)) continue
    if (f.location !== f.destination) continue  // already moving

    const hull = s.designs.get(f.ships[0]?.design)?.hull

    if (hull === 'Scout') {
      // Move to nearest unexplored star
      const target = nearestUnexplored(s.stars, f.location, eid)
      if (target !== null && distSq(s.stars.get(f.location)!.coords, s.stars.get(target)!.coords) <= rangeSq) {
        s = orderMove(s, fid, target)
      } else {
        // Random reachable star
        const reachable = reachableStars(s.stars, f.location, rangeSq)
        if (reachable.length > 0) {
          s = orderMove(s, fid, reachable[Math.floor(rng() * reachable.length)])
        }
      }
    } else if (hull === 'ColonyShip') {
      // Find nearest colonisable empty star
      const candidates = [...s.stars.values()]
        .filter(sys =>
          hasColonisableWorld(sys) &&
          !s.colonies.some(c => c.star === sys.id) &&
          isColonisable(sys, e) &&
          distSq(s.stars.get(f.location)!.coords, sys.coords) <= rangeSq
        )
        .sort((a, b) =>
          distSq(s.stars.get(f.location)!.coords, a.coords) -
          distSq(s.stars.get(f.location)!.coords, b.coords)
        )
      if (candidates.length > 0) {
        if (candidates[0].id === f.location) {
          // We're here — colonise
          s = foundColony(s, fid)
        } else {
          s = orderMove(s, fid, candidates[0].id)
        }
      }
    } else if (hull === 'Destroyer' || hull === 'Cruiser' || hull === 'Battleship') {
      // Find nearest enemy colony within range
      const myPop = s.colonies.filter(c => c.owner === eid).reduce((a, c) => a + c.population, 0)
      const enemies = s.colonies
        .filter(c => {
          const rel = s.relations.get(eid)?.get(c.owner)
          return c.owner !== eid && rel === 'AtWar'
        })
        .filter(c =>
          distSq(s.stars.get(f.location)!.coords, s.stars.get(c.star)!.coords) <= rangeSq
        )
        .sort((a, b) => a.population - b.population)

      if (enemies.length > 0) {
        if (enemies[0].star === f.location) {
          // Bombard
          s = { ...s, log: [...s.log, `Empire ${eid} bombards ${s.stars.get(f.location)!.name}`] }
        } else {
          s = orderMove(s, fid, enemies[0].star)
        }
      } else {
        // Explore or patrol
        const unexplored = nearestUnexplored(s.stars, f.location, eid)
        if (unexplored && distSq(s.stars.get(f.location)!.coords, s.stars.get(unexplored)!.coords) <= rangeSq) {
          s = orderMove(s, fid, unexplored)
        }
      }
    }
  }

  return s
}

// ── Diplomatic AI ─────────────────────────────────────────────────────────
// Accept peace if losing; occasionally declare war on weakest rival.

function runDiplomacyAI(state: GameState, eid: EmpireId, rng: () => number): GameState {
  let s = state
  const e = s.empires.get(eid)!
  const myPop = s.colonies.filter(c => c.owner === eid).reduce((a, c) => a + c.population, 0)

  for (const o of [...s.pendingOffers]) {
    if (o.recipient !== eid) continue
    const sender = s.empires.get(o.sender)!
    const senderPop = s.colonies.filter(c => c.owner === o.sender).reduce((a, c) => a + c.population, 0)

    let accept = false
    if (o.offer === 'OfferPeace') {
      // Accept peace if we're weaker or if random chance favours it
      accept = myPop <= senderPop || rng() < 0.3
    } else if (o.offer === 'OfferAlliance') {
      // Accept alliance if sender is strong and we're not at war
      const rel = s.relations.get(eid)?.get(o.sender)
      accept = rel !== 'AtWar' && senderPop > myPop * 0.7 && rng() < 0.5
    } else if (o.offer === 'DeclareWar') {
      accept = true  // it's a declaration, not a choice
    }

    if (accept) {
      const newRel = o.offer === 'OfferPeace' ? 'Neutral'
                   : o.offer === 'OfferAlliance' ? 'Alliance'
                   : o.offer === 'DeclareWar' ? 'AtWar' : 'Neutral'
      const newRelations = new Map(s.relations)
      const inner = new Map(newRelations.get(o.sender)!)
      inner.set(eid, newRel as any)
      newRelations.set(o.sender, inner)
      const inner2 = new Map(newRelations.get(eid)!)
      inner2.set(o.sender, newRel as any)
      newRelations.set(eid, inner2)
      s = { ...s, relations: newRelations,
        pendingOffers: s.pendingOffers.filter(x => x !== o) }
    } else {
      s = { ...s, pendingOffers: s.pendingOffers.filter(x => x !== o) }
    }
  }

  // Occasionally declare war on weakest empire if we're strong
  if (rng() < 0.02 && myPop > 10) {
    const weakest = [...s.empires.values()]
      .filter(other => {
        if (other.id === eid || other.eliminated) return false
        const rel = s.relations.get(eid)?.get(other.id)
        if (rel === 'AtWar') return false
        if (!e.contacts.has(other.id)) return false
        return true
      })
      .map(other => ({
        id: other.id,
        pop: s.colonies.filter(c => c.owner === other.id).reduce((a, c) => a + c.population, 0)
      }))
      .sort((a, b) => a.pop - b.pop)[0]

    if (weakest && weakest.pop < myPop * 0.6) {
      const newRelations = new Map(s.relations)
      const inner = new Map(newRelations.get(eid)!)
      inner.set(weakest.id, 'AtWar' as any)
      newRelations.set(eid, inner)
      const inner2 = new Map(newRelations.get(weakest.id)!)
      inner2.set(eid, 'AtWar' as any)
      newRelations.set(weakest.id, inner2)
      s = { ...s, relations: newRelations,
        log: [...s.log, `Empire ${eid} (${e.race}) declares war on Empire ${weakest.id}!`] }
    }
  }

  return s
}

// ── Full AI turn ──────────────────────────────────────────────────────────
export function runAITurns(state: GameState, rng: () => number): GameState {
  let s = state
  for (const [eid] of s.empires) {
    if (eid === s.playerId) continue
    const e = s.empires.get(eid)!
    if (e.eliminated) continue
    s = runColonyAI(s, eid)
    s = runFleetAI(s, eid, rng)
    s = runDiplomacyAI(s, eid, rng)
  }
  return s
}
