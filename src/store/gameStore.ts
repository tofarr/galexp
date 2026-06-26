import { create } from 'zustand'
import type { GameState, StarId, FleetId, SpendingAlloc, DesignId, Colony } from '../types'
import { createNewGame, resolveTurn, type NewGameOptions } from '../engine/turn'
import { orderMove, foundColony, bombardStar, landTroops, scrapeFleet } from '../engine/combat'
import { runAITurns } from '../engine/ai'
import { makeRng } from '../engine/galaxy'

interface GameStore {
  game: GameState | null
  rng:  (() => number) | null

  // Game lifecycle
  newGame:    (opts: NewGameOptions) => void
  endTurn:    () => void

  // Player actions
  selectStar:     (id: StarId | null) => void
  selectFleet:    (id: FleetId | null) => void
  moveFleet:      (fid: FleetId, dst: StarId) => void
  colonise:       (fid: FleetId) => void
  bombard:        (fid: FleetId) => void
  invade:         (fid: FleetId) => void
  scrapeFleet:    (fid: FleetId) => void
  setSpending:    (star: StarId, alloc: SpendingAlloc) => void
  queueShip:      (star: StarId, did: DesignId) => void
  dequeueShip:    (star: StarId, idx: number) => void
  setResearching: (tech: import('../types').TechName) => void
}

export const useGameStore = create<GameStore>((set, get) => ({
  game: null,
  rng:  null,

  newGame(opts) {
    const seed = opts.seed ?? Math.floor(Math.random() * 0xFFFFFF)
    const rng  = makeRng(seed + 1)   // offset from galaxy seed
    const game = createNewGame({ ...opts, seed })
    set({ game, rng })
  },

  endTurn() {
    const { game, rng } = get()
    if (!game || !rng || game.winner) return
    // Run AI orders phase
    let s = runAITurns(game, rng)
    // Resolve the full turn
    s = resolveTurn(s, rng)
    set({ game: s })
  },

  selectStar(id) {
    set(st => ({ game: st.game ? { ...st.game, selectedStar: id } : null }))
  },

  selectFleet(id) {
    set(st => ({ game: st.game ? { ...st.game, selectedFleet: id } : null }))
  },

  moveFleet(fid, dst) {
    set(st => {
      if (!st.game) return {}
      return { game: orderMove(st.game, fid, dst) }
    })
  },

  colonise(fid) {
    set(st => {
      if (!st.game) return {}
      return { game: foundColony(st.game, fid) }
    })
  },

  bombard(fid) {
    set(st => {
      if (!st.game || !st.rng) return {}
      return { game: bombardStar(st.game, fid, st.rng) }
    })
  },

  invade(fid) {
    set(st => {
      if (!st.game || !st.rng) return {}
      return { game: landTroops(st.game, fid, st.rng) }
    })
  },

  scrapeFleet(fid) {
    set(st => {
      if (!st.game) return {}
      return { game: scrapeFleet(st.game, fid) }
    })
  },

  setSpending(starId, alloc) {
    set(st => {
      if (!st.game) return {}
      const total = alloc.ships + alloc.defense + alloc.industry + alloc.ecology + alloc.research
      if (total !== 100) return {}  // reject invalid allocation
      const newCols = st.game.colonies.map(c =>
        c.star === starId && c.owner === st.game!.playerId ? { ...c, spending: alloc } : c
      )
      return { game: { ...st.game, colonies: newCols } }
    })
  },

  queueShip(starId, did) {
    set(st => {
      if (!st.game) return {}
      const newCols = st.game.colonies.map(c =>
        c.star === starId && c.owner === st.game!.playerId
          ? { ...c, buildQueue: [...c.buildQueue, did] }
          : c
      )
      return { game: { ...st.game, colonies: newCols } }
    })
  },

  dequeueShip(starId, idx) {
    set(st => {
      if (!st.game) return {}
      const newCols = st.game.colonies.map(c => {
        if (c.star !== starId || c.owner !== st.game!.playerId) return c
        const q = [...c.buildQueue]
        q.splice(idx, 1)
        return { ...c, buildQueue: q }
      })
      return { game: { ...st.game, colonies: newCols } }
    })
  },

  setResearching(tech) {
    set(st => {
      if (!st.game) return {}
      const pid = st.game.playerId
      const e = st.game.empires.get(pid)!
      if (e.techs.has(tech)) return {}
      const newEmpires = new Map(st.game.empires)
      newEmpires.set(pid, { ...e, researching: tech, rpAccum: 0 })
      return { game: { ...st.game, empires: newEmpires,
        techOptions: new Map([...st.game.techOptions, [pid, []]]) } }
    })
  },
}))
