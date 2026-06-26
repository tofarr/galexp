import type { Empire, Colony, StarSystem, TechName, Race, SpendingAlloc, DesignId, ShipDesign } from '../types'
import { C, TECH_COST, TECH_FIELD } from './constants'

// ── Race attribute table ──────────────────────────────────────────────────
export const industryPct  = (r: Race) => r === 'Klackon' ? 125 : 100
export const researchPct  = (r: Race) => r === 'Psilon'  ? 150 : 100
export const growthPct    = (r: Race) => r === 'Sakkra'  ? 200 : 100
export const isLithovore  = (r: Race) => r === 'Silicoid'
export const isCreative   = (r: Race) => r === 'Psilon'
export const extraFactCap = (r: Race) => r === 'Meklar'  ?   1 : 0
export const beamAccBonus = (r: Race) => r === 'Mrrshan' ?  50 : 0
export const groundAtkPct = (r: Race) => r === 'Bulrathi'? 150 : 100
export const shipDefPct   = (r: Race) => r === 'Alkari'  ? 125 : 100
export const spyBonus     = (r: Race) => r === 'Darlok'  ?  50 : 0
export const diplomBonus  = (r: Race) => r === 'Humans'  ?  50 : 0

// ── Race starting technologies ────────────────────────────────────────────
export function raceStartingTechs(r: Race): Set<TechName> {
  const base: TechName[] = ['NuclearEngines','LaserCannon','MassDriver','IndustrialTech9','Class1Shield','RoboticControls2']
  const extras: Partial<Record<Race, TechName[]>> = {
    Klackon:  ['RoboticControls3','AutomatedFactory'],
    Meklar:   ['RoboticControls3'],
    Mrrshan:  ['BattleComputer1'],
    Sakkra:   ['CloneCenter'],
    Bulrathi: ['TitaniumArmour'],
    Alkari:   ['InertialStabilizer'],
    Darlok:   ['EcmJammer'],
  }
  return new Set([...base, ...(extras[r] ?? [])])
}

// ── Research prerequisite chain ───────────────────────────────────────────
const PREREQS: Partial<Record<TechName, TechName>> = {
  FusionEngines:'NuclearEngines', IonDrive:'FusionEngines', SubSpaceDrive:'IonDrive',
  HyperDrive:'SubSpaceDrive',     InterphasedDrive:'HyperDrive',
  RoboticControls3:'RoboticControls2', RoboticControls4:'RoboticControls3',
  RoboticControls5:'RoboticControls4',
  BattleComputer2:'BattleComputer1', BattleComputer3:'BattleComputer2',
  Class3Shield:'Class1Shield', Class5Shield:'Class3Shield', Class7Shield:'Class5Shield',
  Class10Shield:'Class7Shield', Class15Shield:'Class10Shield', Class20Shield:'Class15Shield',
  Class25Shield:'Class20Shield', Class30Shield:'Class25Shield',
  PlanetaryShield10:'PlanetaryShield5', PlanetaryShield15:'PlanetaryShield10',
  PlanetaryShield20:'PlanetaryShield15',
  WarpInterdictor:'StasisField', StellarConverter:'AntiMatterBomb',
  TerraformingMax:'TerraformingMed',
}

export function hasPrerequisite(techs: Set<TechName>, t: TechName): boolean {
  const prereq = PREREQS[t]
  return !prereq || techs.has(prereq)
}

// Technologies available to research next (not owned, prereqs met)
export function availableTechs(e: Empire): TechName[] {
  return (Object.keys(TECH_COST) as TechName[]).filter(
    t => !e.techs.has(t) && hasPrerequisite(e.techs, t)
  )
}

// Pick 2 random techs from available (Psilon gets all)
export function offerTechOptions(e: Empire, rng: () => number): TechName[] {
  const avail = availableTechs(e)
  if (avail.length === 0) return []
  if (isCreative(e.race)) return avail
  // Offer 2 per field that has options, pick one field randomly
  const fields = [...new Set(avail.map(t => TECH_FIELD[t]))]
  const field  = fields[Math.floor(rng() * fields.length)]
  const inField = avail.filter(t => TECH_FIELD[t] === field)
  // Shuffle and take up to 2
  for (let i = inField.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [inField[i], inField[j]] = [inField[j], inField[i]]
  }
  return inField.slice(0, 2)
}

// ── Robotic Controls cap ──────────────────────────────────────────────────
export function roboticRatio(e: Empire): number {
  if (e.techs.has('RoboticControls5')) return 5
  if (e.techs.has('RoboticControls4')) return 4
  if (e.techs.has('RoboticControls3')) return 3
  if (e.techs.has('RoboticControls2')) return 2
  return 1
}

export function factoryCap(e: Empire, pop: number): number {
  return pop * (roboticRatio(e) + extraFactCap(e.race))
}

// ── Richness modifier ─────────────────────────────────────────────────────
export function richnessPct(r: number): number { return 75 + r * 25 }

// ── Core production ───────────────────────────────────────────────────────
export function effectivePop(c: Colony): number {
  return Math.max(0, c.population - c.pollution)
}

export function activeFactories(c: Colony): number {
  return Math.min(effectivePop(c), c.factories)
}

export function grossPP(e: Empire, c: Colony, sys: StarSystem): number {
  const base = activeFactories(c) * C.BASE_PP_PER_FACTORY
    * richnessPct(sys.richness) / 100
    * industryPct(e.race) / 100
  const auto = e.techs.has('AutomatedFactory') ? activeFactories(c) : 0
  return Math.floor(base + auto)
}

export function androidPPBonus(e: Empire): number {
  return e.techs.has('AndroidWorkers') ? C.BASE_ANDROID_PP : 0
}
export function androidRPBonus(e: Empire): number {
  return e.techs.has('AndroidScientists') ? C.BASE_ANDROID_RP : 0
}

export function totalPP(e: Empire, c: Colony, sys: StarSystem): number {
  return grossPP(e, c, sys) + androidPPBonus(e)
}

export function rpFromColony(e: Empire, c: Colony, sys: StarSystem): number {
  const sliderRP = Math.floor(totalPP(e, c, sys) * c.spending.research / 100 * researchPct(e.race) / 100)
  return sliderRP + androidRPBonus(e)
}

export function taxIncome(e: Empire, c: Colony): number {
  return Math.floor(c.population * e.taxRate / 100)
}

export function tradeIncomePair(e: Empire, ePop: number, otherPop: number): number {
  // Integer approximation of sqrt(ePop * otherPop) * TRADE_FACTOR / 100
  const product = Math.sqrt(ePop * otherPop)
  return Math.floor(product * C.TRADE_FACTOR / 100)
}

// ── Pollution ─────────────────────────────────────────────────────────────
export function pollutionProduced(e: Empire, c: Colony): number {
  const base = activeFactories(c) * C.POLLUTION_PER_FACTORY
  return e.techs.has('AdvancedEcology') ? Math.floor(base / 2) : base
}

export function pollutionCleaned(e: Empire, c: Colony, sys: StarSystem): number {
  return Math.floor(totalPP(e, c, sys) * c.spending.ecology / 100 * C.ECOLOGY_CLEANUP_RATE)
}

export function nextPollution(e: Empire, c: Colony, sys: StarSystem): number {
  return Math.max(0, c.pollution + pollutionProduced(e, c) - pollutionCleaned(e, c, sys))
}

// ── Population growth ─────────────────────────────────────────────────────
export function popGrowth(e: Empire, c: Colony): number {
  const headroom = c.maxPop - c.population
  if (headroom <= 0) return 0
  const bonus = e.techs.has('CloneCenter') ? 1.5 : 1
  const natural = Math.floor(c.population / 2 * bonus)
  return Math.min(natural, headroom) * growthPct(e.race) / 100
}

export function nextPopulation(e: Empire, c: Colony): number {
  return Math.min(c.maxPop, c.population + Math.floor(popGrowth(e, c)))
}

// ── Missile base cap ──────────────────────────────────────────────────────
export function missileCap(c: Colony): number {
  return Math.min(C.MAX_MISSILE_BASES, Math.floor(c.population / 2))
}

// ── Colonisation check ────────────────────────────────────────────────────
export function isColonisable(sys: StarSystem, e: Empire): boolean {
  if (sys.planetType === 'Barren') return false
  if (isLithovore(e.race)) return true
  if (sys.planetType === 'Inferno') return e.techs.has('ControlledEnviron')
  if (sys.planetType === 'Toxic')   return e.techs.has('AtmosphericRenewer')
  if (sys.planetType === 'Radiated')return e.techs.has('RadiationShield_')
  return true
}

// ── Terraforming ──────────────────────────────────────────────────────────
const TERRAFORM_STEPS: Partial<Record<string, string>> = {
  Dead:'Radiated', Radiated:'Toxic', Toxic:'Inferno', Inferno:'Desert',
  Desert:'Arid', Arid:'Tundra', Tundra:'Ocean', Ocean:'Terran',
}
export function terraformStep(pt: string): string {
  return TERRAFORM_STEPS[pt] ?? pt
}

// ── Engine tick: single colony production + growth ────────────────────────
export interface ProductionResult {
  colony:   Colony
  rpGained: number
  bcGained: number
  shipsCompleted: DesignId[]
}

export function tickColonyProduction(
  e: Empire, c: Colony, sys: StarSystem,
  designs: Map<number, ShipDesign>
): ProductionResult {
  const rp       = rpFromColony(e, c, sys)
  const bcTax    = taxIncome(e, c)
  const newPoll  = nextPollution(e, c, sys)

  // Industry PP → build factories
  const indPP    = Math.floor(totalPP(e, c, sys) * c.spending.industry / 100)
  const newFact  = Math.min(c.maxFactories, c.factories + Math.floor(indPP / 10))

  // Defense PP → build missile bases
  const defPP    = Math.floor(totalPP(e, c, sys) * c.spending.defense / 100)
  const newBases = Math.min(missileCap(c), c.missileBases + Math.floor(defPP / 15))

  // Ships PP → accrue toward build queue
  const sPP       = Math.floor(totalPP(e, c, sys) * c.spending.ships / 100)
  let accrued     = c.ppAccrued + sPP
  let queue       = [...c.buildQueue]
  const completed: DesignId[] = []

  while (queue.length > 0) {
    const did  = queue[0]
    const cost = designs.get(did)?.cost ?? 9999
    if (accrued >= cost) {
      accrued -= cost
      completed.push(did)
      queue = queue.slice(1)
    } else break
  }

  return {
    colony: { ...c, pollution: newPoll, factories: newFact, missileBases: newBases,
              buildQueue: queue, ppAccrued: accrued },
    rpGained: rp, bcGained: bcTax, shipsCompleted: completed,
  }
}

export function tickColonyGrowth(e: Empire, c: Colony): Colony {
  const newPop    = nextPopulation(e, c)
  const newMaxFact = factoryCap(e, newPop)
  return { ...c, population: newPop, maxFactories: newMaxFact }
}

// ── Best engine tech → squared range ─────────────────────────────────────
export function engineRangeSq(e: Empire): number {
  if (e.techs.has('InterphasedDrive')) return 64
  if (e.techs.has('HyperDrive'))       return 49
  if (e.techs.has('SubSpaceDrive'))    return 36
  if (e.techs.has('IonDrive'))         return 25
  if (e.techs.has('FusionEngines'))    return 16
  return 9
}

// ── Combat initiative ─────────────────────────────────────────────────────
export function combatInitiative(e: Empire): number {
  const base = e.techs.has('BattleComputer3') ? 3
             : e.techs.has('BattleComputer2') ? 2
             : e.techs.has('BattleComputer1') ? 1 : 0
  return base + (e.race === 'Alkari' ? 1 : 0)
}

// ── Default spending presets ──────────────────────────────────────────────
export function defaultSpending(turn: number): SpendingAlloc {
  if (turn < 20)  return { ships:0, defense:5, industry:45, ecology:20, research:30 }
  if (turn < 60)  return { ships:10, defense:5, industry:35, ecology:15, research:35 }
  return               { ships:20, defense:5, industry:25, ecology:10, research:40 }
}

// ── Tech research progress percentage ────────────────────────────────────
export function researchPctDone(e: Empire): number {
  const cost = TECH_COST[e.researching] ?? 100
  return Math.min(100, Math.round(e.rpAccum / cost * 100))
}
