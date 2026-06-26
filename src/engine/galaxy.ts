import type { StarId, StarSystem, EmpireId, Coord, StarClass, PlanetType, PlanetSize } from '../types'
import { C, PLANET_BASE_POP } from './constants'

// ── Procedural star names ─────────────────────────────────────────────────
const PREFIXES = ['Al','An','Arc','Ar','As','Ath','Az','Bel','Bol','Cae','Cal','Can','Car','Cas','Cel',
  'Cet','Cor','Cru','Dal','Den','Des','Dra','El','Em','En','Er','Fal','Fel','For','Gal','Gar','Gel',
  'Hem','Her','Hol','Hy','Ith','Jor','Jun','Kan','Kel','Ker','Kol','Lan','Lir','Mal','Men','Mir',
  'Mol','Mor','My','Nar','Nel','Nor','Nox','Ob','Om','Or','Pal','Par','Pen','Per','Pho','Pri',
  'Qu','Ran','Rel','Ren','Rig','Rin','Rom','Ros','Rul','Sar','Sel','Ser','Sig','Sol','Som','Spe',
  'Str','Sul','Sys','Tal','Tar','Tel','Ter','Tho','Tor','Tri','Tul','Tur','Ull','Uv','Val','Van',
  'Vel','Ver','Vor','Vul','War','Wel','Wer','Xan','Xel','Yar','Yel','Zal','Zel','Zir','Zor']
const SUFFIXES = ['a','ai','an','ar','as','ax','el','em','en','er','es','i','ia','ian','id',
  'il','in','is','ix','o','on','or','os','ra','ran','ri','rin','rix','rox','rus',
  'ta','tae','tan','tar','tis','tor','tri','tus','um','un','us','van','var','via',
  'von','vor','xa','xar','xi','xis','yon','yra','za','zan','zar','zix']

let nameIdx = 0
const GENERATED_NAMES: string[] = []
for (const p of PREFIXES) {
  for (const s of SUFFIXES) {
    GENERATED_NAMES.push(p + s)
    if (GENERATED_NAMES.length >= 400) break
  }
  if (GENERATED_NAMES.length >= 400) break
}

function shuffleNames(rng: () => number) {
  for (let i = GENERATED_NAMES.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [GENERATED_NAMES[i], GENERATED_NAMES[j]] = [GENERATED_NAMES[j], GENERATED_NAMES[i]]
  }
  nameIdx = 0
}

function nextName(): string {
  return GENERATED_NAMES[nameIdx++ % GENERATED_NAMES.length]
}

// ── Seeded RNG (mulberry32) ───────────────────────────────────────────────
export function makeRng(seed: number) {
  let s = seed >>> 0
  return () => {
    s += 0x6D2B79F5
    let t = Math.imul(s ^ (s >>> 15), 1 | s)
    t ^= t + Math.imul(t ^ (t >>> 7), 61 | t)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// ── Star class distribution ───────────────────────────────────────────────
const STAR_CLASS_WEIGHTS: [StarClass, number][] = [
  ['Blue',     4],  ['White',   10], ['Yellow',  25],
  ['Orange',  20],  ['Red',     30], ['Neutron',  7],
  ['BlackHole', 4],
]

function pickStarClass(rng: () => number): StarClass {
  const total = STAR_CLASS_WEIGHTS.reduce((a, [, w]) => a + w, 0)
  let r = rng() * total
  for (const [cls, w] of STAR_CLASS_WEIGHTS) {
    r -= w; if (r <= 0) return cls
  }
  return 'Yellow'
}

// ── Planet type distribution per star class ────────────────────────────────
type PlanetDist = [PlanetType, number][]
const PLANET_DIST_BY_CLASS: Record<StarClass, PlanetDist> = {
  Blue:      [['Radiated',25],['Dead',15],['Inferno',15],['Toxic',15],['Desert',15],['Arid',10],['Tundra',5]],
  White:     [['Dead',10],['Radiated',10],['Inferno',10],['Toxic',10],['Desert',15],['Arid',15],['Tundra',15],['Ocean',10],['Terran',5]],
  Yellow:    [['Dead',5],['Inferno',5],['Toxic',5],['Desert',10],['Arid',15],['Tundra',15],['Ocean',20],['Terran',25]],
  Orange:    [['Dead',10],['Inferno',10],['Desert',20],['Arid',20],['Tundra',20],['Ocean',15],['Terran',5]],
  Red:       [['Dead',20],['Inferno',15],['Toxic',10],['Desert',20],['Arid',20],['Tundra',10],['Ocean',5]],
  Neutron:   [['Barren',100]],
  BlackHole: [['Barren',100]],
}

function pickPlanetType(cls: StarClass, rng: () => number): PlanetType {
  const dist = PLANET_DIST_BY_CLASS[cls]
  const total = dist.reduce((a, [, w]) => a + w, 0)
  let r = rng() * total
  for (const [pt, w] of dist) { r -= w; if (r <= 0) return pt }
  return dist[dist.length - 1][0]
}

const PLANET_SIZE_WEIGHTS: [PlanetSize, number][] = [
  ['Tiny',10],['Small',20],['Medium',30],['Large',25],['Huge',15]
]
function pickPlanetSize(rng: () => number): PlanetSize {
  const total = PLANET_SIZE_WEIGHTS.reduce((a,[,w])=>a+w,0)
  let r = rng() * total
  for (const [sz,w] of PLANET_SIZE_WEIGHTS) { r -= w; if (r <= 0) return sz }
  return 'Medium'
}

function pickRichness(rng: () => number): number {
  // Weighted toward 1-2 (Poor/Adequate); tails to 0 and 4
  const weights = [5, 20, 40, 25, 10]
  const total = weights.reduce((a, w) => a + w, 0)
  let r = rng() * total
  for (let i = 0; i < weights.length; i++) { r -= weights[i]; if (r <= 0) return i }
  return 2
}

// ── Distance helpers ──────────────────────────────────────────────────────
export function distSq(a: Coord, b: Coord): number {
  return (a.x - b.x) ** 2 + (a.y - b.y) ** 2
}

export function withinRange(stars: Map<StarId, StarSystem>, src: StarId, dst: StarId, rangeSq: number): boolean {
  const a = stars.get(src)!; const b = stars.get(dst)!
  return distSq(a.coords, b.coords) <= rangeSq
}

export function reachableStars(stars: Map<StarId, StarSystem>, src: StarId, rangeSq: number): StarId[] {
  return [...stars.keys()].filter(id => id !== src && withinRange(stars, src, id, rangeSq))
}

export function nearestUnexplored(stars: Map<StarId, StarSystem>, src: StarId, eid: EmpireId): StarId | null {
  let best: StarId | null = null; let bestDist = Infinity
  const srcCoord = stars.get(src)!.coords
  for (const [id, sys] of stars) {
    if (id === src) continue
    if (sys.explored.has(eid)) continue
    const d = distSq(srcCoord, sys.coords)
    if (d < bestDist) { bestDist = d; best = id }
  }
  return best
}

export function hasColonisableWorld(sys: StarSystem): boolean {
  return sys.planetType !== 'Barren' && sys.class_ !== 'Neutron' && sys.class_ !== 'BlackHole'
}

// ── Galaxy generation ─────────────────────────────────────────────────────
export interface GalaxyOptions {
  numStars:   number   // 24 | 36 | 54 | 108
  numEmpires: number   // 2-8
  seed:       number
}

export function generateGalaxy(opts: GalaxyOptions): {
  stars: Map<StarId, StarSystem>
  homeStars: StarId[]
} {
  const { numStars, numEmpires, seed } = opts
  const rng = makeRng(seed)
  shuffleNames(rng)

  const W = C.MAP_W, H = C.MAP_H
  const placedCoords: Coord[] = []
  const stars = new Map<StarId, StarSystem>()
  let nextId = 0

  function place(
    minDist: number,
    cls?: StarClass,
    forcePlanetType?: PlanetType,
    forceSize?: PlanetSize,
    forceRichness?: number,
  ): StarId | null {
    for (let attempt = 0; attempt < 500; attempt++) {
      const x = Math.floor(rng() * (W - 10) + 5)
      const y = Math.floor(rng() * (H - 10) + 5)
      const c = { x, y }
      if (placedCoords.some(p => distSq(p, c) < minDist)) continue
      const starClass = cls ?? pickStarClass(rng)
      const planetType = forcePlanetType ?? pickPlanetType(starClass, rng)
      const size = forceSize ?? pickPlanetSize(rng)
      const richness = forceRichness ?? pickRichness(rng)
      const maxPopBase = planetType === 'Barren' ? 0 : PLANET_BASE_POP[size]
      const id = nextId++
      stars.set(id, {
        id, name: nextName(), class_: starClass, coords: c,
        planetType, size, richness, maxPopBase, explored: new Set(),
      })
      placedCoords.push(c)
      return id
    }
    return null
  }

  // Place homeworlds first — Terran, Large/Huge, Rich
  const homeStars: StarId[] = []
  for (let i = 0; i < numEmpires; i++) {
    const id = place(
      C.MIN_HOME_DIST_SQ,
      'Yellow',
      'Terran',
      rng() < 0.5 ? 'Large' : 'Huge',
      3 + Math.floor(rng() * 2),  // richness 3 or 4
    )
    if (id === null) throw new Error('Failed to place homeworld')
    homeStars.push(id)
  }

  // Fill remaining stars
  const remaining = numStars - numEmpires
  for (let i = 0; i < remaining; i++) {
    // Relax spacing as we fill up
    const minD = i < remaining * 0.6 ? C.MIN_STAR_DIST_SQ : Math.max(9, C.MIN_STAR_DIST_SQ / 2)
    place(minD)  // best-effort; skip if no room
  }

  return { stars, homeStars }
}
