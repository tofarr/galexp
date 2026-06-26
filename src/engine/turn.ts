import type { GameState, EmpireId, TurnPhase, StarId, Empire, VictoryResult, ShipDesign, TechName, Race } from '../types'
import { C, TECH_COST, EMPIRE_COLORS, HULL_HP, HULL_COST, HULL_UPKEEP, HULL_ATTACK } from './constants'
import { generateGalaxy, makeRng, hasColonisableWorld, distSq } from './galaxy'
import {
  raceStartingTechs, factoryCap, tickColonyProduction, tickColonyGrowth,
  engineRangeSq, offerTechOptions, tradeIncomePair, availableTechs,
} from './empire'
import {
  fleetsAtStar, resolveCombatAtStar, advanceFleets, bombardStar,
  landTroops, makeDesign, makeShip, spawnFleet, isAlive, empireFleets,
} from './combat'

// ── Phase order ───────────────────────────────────────────────────────────
const PHASE_ORDER: TurnPhase[] = [
  'OrdersPhase','ProductionPhase','MovementPhase','CombatPhase',
  'InvasionPhase','GrowthPhase','SpyPhase','CouncilPhase','VictoryCheckPhase',
]

export function nextPhase(p: TurnPhase): TurnPhase {
  const idx = PHASE_ORDER.indexOf(p)
  return PHASE_ORDER[(idx + 1) % PHASE_ORDER.length]
}

// ── Production phase ──────────────────────────────────────────────────────
function runProductionPhase(state: GameState, rng: () => number): GameState {
  let s = state
  const newEmpires = new Map(s.empires)

  for (const [eid, e] of s.empires) {
    if (e.eliminated) continue
    let totalRp = 0, totalBc = 0
    const shipsToSpawn: { sid: StarId; did: number }[] = []

    const newCols = s.colonies.map(c => {
      if (c.owner !== eid) return c
      const sys = s.stars.get(c.star)!
      const res = tickColonyProduction(e, c, sys, s.designs)
      totalRp += res.rpGained
      totalBc += res.bcGained
      for (const did of res.shipsCompleted) shipsToSpawn.push({ sid: c.star, did })
      return res.colony
    })
    s = { ...s, colonies: newCols }

    // Trade income
    const emp = newEmpires.get(eid)!
    const ePop = newCols.filter(c => c.owner === eid).reduce((a, c) => a + c.population, 0)
    let tradeBc = 0
    for (const other of emp.contacts) {
      const oe = newEmpires.get(other)!
      if (oe.eliminated) continue
      const rel = s.relations.get(eid)?.get(other)
      if (rel === 'AtWar') continue
      const oPop = newCols.filter(c => c.owner === other).reduce((a, c) => a + c.population, 0)
      tradeBc += tradeIncomePair(emp, ePop, oPop)
    }

    // Research
    let newRpAccum = emp.rpAccum + totalRp
    let newTechs   = new Set(emp.techs)
    let newResearching = emp.researching
    let newOptions = s.techOptions.get(eid) ?? []
    const cost = TECH_COST[emp.researching] ?? 999

    if (newRpAccum >= cost) {
      newRpAccum -= cost
      newTechs = new Set([...newTechs, emp.researching])
      newOptions = offerTechOptions({ ...emp, techs: newTechs }, rng)
      if (newOptions.length > 0) newResearching = newOptions[0]  // AI auto-picks first
    }

    const updatedEmp: Empire = {
      ...emp, bc: emp.bc + totalBc + tradeBc,
      rpAccum: newRpAccum, techs: newTechs, researching: newResearching,
    }
    newEmpires.set(eid, updatedEmp)

    const newTechOptions = new Map(s.techOptions)
    newTechOptions.set(eid, newOptions)
    s = { ...s, techOptions: newTechOptions }

    // Spawn completed ships
    for (const { sid, did } of shipsToSpawn) {
      const design = s.designs.get(did)!
      s = spawnFleet(s, eid, sid, [makeShip(design)])
    }
  }

  return { ...s, empires: newEmpires }
}

// ── Movement phase ────────────────────────────────────────────────────────
function runMovementPhase(state: GameState): GameState {
  let s = advanceFleets(state)

  // Explore stars — any fleet arriving marks the system as explored
  const newStars = new Map(s.stars)
  for (const f of s.fleets.values()) {
    const sys = newStars.get(f.location)!
    if (!sys.explored.has(f.owner)) {
      newStars.set(f.location, { ...sys, explored: new Set([...sys.explored, f.owner]) })
    }
  }

  // Update contacts — empires whose fleets share a star meet each other
  const newEmpires = new Map(s.empires)
  for (const sid of s.stars.keys()) {
    const atStar = fleetsAtStar({ ...s, stars: newStars }, sid)
    const owners = [...new Set(atStar.map(id => s.fleets.get(id)!.owner))]
    // Also include colony owner
    const colOwner = s.colonies.find(c => c.star === sid)?.owner
    if (colOwner !== undefined) owners.push(colOwner)
    const uniqueOwners = [...new Set(owners)]

    for (const a of uniqueOwners) {
      for (const b of uniqueOwners) {
        if (a === b) continue
        const ea = newEmpires.get(a)!
        const eb = newEmpires.get(b)!
        if (!ea.contacts.has(b)) {
          newEmpires.set(a, { ...ea, contacts: new Set([...ea.contacts, b]) })
        }
        if (!eb.contacts.has(a)) {
          newEmpires.set(b, { ...eb, contacts: new Set([...eb.contacts, a]) })
        }
      }
    }
  }

  return { ...s, stars: newStars, empires: newEmpires }
}

// ── Combat phase ──────────────────────────────────────────────────────────
function runCombatPhase(state: GameState, rng: () => number): GameState {
  let s = state
  for (const sid of s.stars.keys()) {
    for (let round = 0; round < C.MAX_COMBAT_ROUNDS; round++) {
      const fids = fleetsAtStar(s, sid).filter(id => isAlive(s.fleets.get(id)!))
      const owners = [...new Set(fids.map(id => s.fleets.get(id)!.owner))]
      if (owners.length < 2) break
      s = resolveCombatAtStar(s, sid, rng)
    }
  }
  return s
}

// ── Growth phase ──────────────────────────────────────────────────────────
function runGrowthPhase(state: GameState): GameState {
  const newCols = state.colonies.map(c => {
    const e = state.empires.get(c.owner)!
    return tickColonyGrowth(e, c)
  })
  // Update maxFactories after growth
  const newEmpires = new Map(state.empires)
  const updatedCols = newCols.map(c => {
    const e = newEmpires.get(c.owner)!
    return { ...c, maxFactories: factoryCap(e, c.population) }
  })
  return { ...state, colonies: updatedCols }
}

// ── Upkeep deduction ──────────────────────────────────────────────────────
function runUpkeepPhase(state: GameState): GameState {
  const newEmpires = new Map(state.empires)
  for (const [eid, e] of state.empires) {
    if (e.eliminated) continue
    const upkeep = empireFleets(state, eid)
      .reduce((a, fid) => a + state.fleets.get(fid)!.ships
        .reduce((b, s) => b + (state.designs.get(s.design)?.upkeep ?? 0), 0), 0)
    newEmpires.set(eid, { ...e, bc: Math.max(0, e.bc - upkeep) })
  }
  return { ...state, empires: newEmpires }
}

// ── Victory check ─────────────────────────────────────────────────────────
function checkVictory(state: GameState): GameState {
  const alive = [...state.empires.values()].filter(e => !e.eliminated)
  if (alive.length === 1) {
    const v: VictoryResult = { winner: alive[0].id, kind: 'ConquestVictory', turnNumber: state.turn }
    return { ...state, winner: v }
  }

  // Eliminate empires with no colonies
  const newEmpires = new Map(state.empires)
  for (const e of alive) {
    if (!state.colonies.some(c => c.owner === e.id)) {
      newEmpires.set(e.id, { ...e, eliminated: true })
    }
  }

  // Council check
  const totalPop = state.colonies.reduce((a, c) => a + c.population, 0)
  const threshold = Math.floor(totalPop * C.COUNCIL_POP_THRESHOLD_PCT / 100)
  const empPops = new Map<EmpireId, number>()
  for (const c of state.colonies) {
    empPops.set(c.owner, (empPops.get(c.owner) ?? 0) + c.population)
  }
  const candidate = [...empPops.entries()]
    .filter(([eid]) => !newEmpires.get(eid)?.eliminated)
    .sort((a, b) => b[1] - a[1])[0]

  if (candidate && candidate[1] >= threshold) {
    // Count votes: candidate + allied empires
    let votes = candidate[1]
    for (const [eid, pop] of empPops) {
      if (eid === candidate[0]) continue
      const rel = state.relations.get(eid)?.get(candidate[0])
      if (rel === 'Alliance') votes += pop
    }
    if (votes * 3 >= totalPop * 2) {
      return { ...state, empires: newEmpires,
        winner: { winner: candidate[0], kind: 'CouncilVictory', turnNumber: state.turn } }
    }
  }

  return { ...state, empires: newEmpires }
}

// ── Full turn resolution ──────────────────────────────────────────────────
export function resolveTurn(state: GameState, rng: () => number): GameState {
  let s = state
  s = runProductionPhase(s, rng)
  s = runMovementPhase(s)
  s = runCombatPhase(s, rng)
  // Invasion (ground assault) — handled by player/AI before calling resolveTurn
  s = runGrowthPhase(s)
  s = runUpkeepPhase(s)
  s = checkVictory(s)
  s = { ...s, turn: s.turn + 1, phase: 'OrdersPhase' }
  return s
}

// ── Initial game setup ────────────────────────────────────────────────────

export interface NewGameOptions {
  playerRace:  Race
  numEmpires:  number   // includes the player
  numStars:    number   // 24 | 36 | 54 | 108
  seed?:       number
}

export function createNewGame(opts: NewGameOptions): GameState {
  const seed = opts.seed ?? Math.floor(Math.random() * 0xFFFFFF)
  const rng  = makeRng(seed)

  const { stars, homeStars } = generateGalaxy({
    numStars:   opts.numStars,
    numEmpires: opts.numEmpires,
    seed,
  })

  const allRaces: Race[] = ['Humans','Psilon','Sakkra','Bulrathi','Mrrshan','Klackon','Meklar','Alkari','Silicoid','Darlok']
  const usedRaces = new Set<Race>([opts.playerRace])
  const races: Race[] = [opts.playerRace]
  while (races.length < opts.numEmpires) {
    const r = allRaces[Math.floor(rng() * allRaces.length)]
    if (!usedRaces.has(r)) { usedRaces.add(r); races.push(r) }
  }

  const empires = new Map<EmpireId, Empire>()
  const relations = new Map<EmpireId, Map<EmpireId, string>>()
  const contacts   = new Map<EmpireId, Set<EmpireId>>()
  const techOptions = new Map<EmpireId, string[]>()

  // Pre-create designs pool (Scout=0, ColonyShip=1, Destroyer=2 per empire would be too many)
  // We use shared design IDs; each empire starts with same basic designs
  const designs = new Map<number, ShipDesign>()
  let nextDesignId = 0

  // Create per-empire designs
  const empireDesigns: Map<EmpireId, { scout: number; colony: number; destroyer: number }> = new Map()

  for (let i = 0; i < opts.numEmpires; i++) {
    const eid  = i
    const race = races[i]
    const home = homeStars[i]

    const scoutDes = makeDesign(nextDesignId++, eid, 'Scout')
    const colDes   = makeDesign(nextDesignId++, eid, 'ColonyShip')
    const destDes  = makeDesign(nextDesignId++, eid, 'Destroyer')
    designs.set(scoutDes.id, scoutDes)
    designs.set(colDes.id,   colDes)
    designs.set(destDes.id,  destDes)
    empireDesigns.set(eid, { scout: scoutDes.id, colony: colDes.id, destroyer: destDes.id })

    const techs = raceStartingTechs(race)
    const avail = (Object.keys(TECH_COST) as any[]).filter(
      t => !techs.has(t) && !techs.has(t)
    )
    const startResearch = (avail.length > 0 ? avail[Math.floor(rng() * avail.length)] : 'FusionEngines') as any

    empires.set(eid, {
      id: eid, race, homeStar: home,
      bc: 60 + Math.floor(rng() * 40),
      taxRate: 25,
      contacts: new Set(),
      techs,
      rpAccum: 0,
      researching: startResearch,
      eliminated: false,
      color: EMPIRE_COLORS[i % EMPIRE_COLORS.length],
    })

    const innerRel = new Map<EmpireId, string>()
    for (let j = 0; j < opts.numEmpires; j++) { if (j !== i) innerRel.set(j, 'Neutral') }
    relations.set(eid, innerRel as Map<EmpireId, any>)
    contacts.set(eid, new Set())
    techOptions.set(eid, [])
  }

  // Home colonies
  const colonies: GameState['colonies'] = []
  for (let i = 0; i < opts.numEmpires; i++) {
    const eid  = i
    const home = homeStars[i]
    const sys  = stars.get(home)!
    const e    = empires.get(eid)!
    const pop  = 3 + Math.floor(rng() * 3)  // 3-5M starting pop
    const ratio = Math.floor(e.techs.has('RoboticControls3') ? 3
                           : e.techs.has('RoboticControls2') ? 2 : 1)
    colonies.push({
      star: home, owner: eid,
      population: pop, maxPop: sys.maxPopBase,
      factories: pop * ratio, maxFactories: pop * ratio,
      pollution: 0, missileBases: 0, shieldLevel: 0,
      spending: { ships:0, defense:0, industry:50, ecology:20, research:30 },
      buildQueue: [], ppAccrued: 0,
    })
    stars.get(home)!.explored.add(eid)
  }

  // Starter fleets
  let nextFleetId = 0
  let gameState: GameState = {
    stars, empires, colonies, spies: [], techOptions: techOptions as Map<EmpireId, TechName[]>,
    designs, nextDesignId, nextFleetId, nextSpyId: 0,
    fleets: new Map(), combatRound: 0,
    turn: 1, phase: 'OrdersPhase',
    relations: relations as Map<EmpireId, Map<EmpireId, any>>,
    pendingOffers: [], council: null, winner: null,
    contacts: contacts as Map<EmpireId, Set<EmpireId>>,
    playerId: 0,
    selectedStar: homeStars[0], selectedFleet: null,
    log: ['Welcome to Galactic Expanse!'],
  }

  // Each empire starts with 1 scout + 1 colony ship
  for (let i = 0; i < opts.numEmpires; i++) {
    const eid = i
    const home = homeStars[i]
    const ed = empireDesigns.get(eid)!
    const scoutShip = makeShip(designs.get(ed.scout)!)
    const colShip   = makeShip(designs.get(ed.colony)!)
    gameState = spawnFleet(gameState, eid, home, [scoutShip])
    gameState = spawnFleet(gameState, eid, home, [colShip])
  }

  return gameState
}
