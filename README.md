# Galactic Expanse

A browser-playable **4X space-strategy** game in the tradition of
*Master of Orion* **(1993, Simtex / MicroProse)** — the original.
**eXplore · eXpand · eXploit · eXterminate** across a procedurally-generated galaxy.

---

## Project status

| Layer | Status |
|---|---|
| Formal specifications (Quint) | ✅ First draft complete |
| Browser game engine | 🚧 Pending |
| UI / rendering | 🚧 Pending |
| AI opponents | 🚧 Pending |

---

## Game design pillars

### Galaxy
A procedurally-generated star map of **24–108 systems** (Small/Medium/Large/Huge)
with stars placed freely in 2-D space.  **There are no hyperlanes**; a fleet can
fly to any star within its fuel range in one turn.  Fuel range is determined by
engine technology (Nuclear → Fusion → Ion → Sub-Space → Hyper → Interphased Drive).
Each system holds 1–5 planets; star colour (Blue → Red, Neutron, Black Hole)
sets planet quality.

### Races (10 fixed)
| Race | Key trait |
|---|---|
| **Humans** | Best diplomacy; average stats |
| **Psilon** | Creative — receive ALL tech options simultaneously |
| **Sakkra** | ×2 population growth rate |
| **Bulrathi** | +50% ground-combat strength |
| **Mrrshan** | +50% beam-weapon accuracy |
| **Klackon** | +25% factory production |
| **Meklar** | Cybernetic — 1 extra factory per population above cap |
| **Alkari** | +25% ship defence / manoeuvrability |
| **Silicoid** | Lithovores — eat minerals, not food; colonise any planet without tech |
| **Darlok** | +50% spy success rate; −50% detection rate |

Races are fixed — there is no custom trait-picking system.

### Colonies & production
Every colonist is assigned to one of three roles each turn:
- **Farmers** → food production; prevents starvation.
- **Workers** → operate factories → produce **Production Points (PP)**.
- **Scientists** → produce **Research Points (RP)**.

Factories accumulate over time; the cap is set by Robotic Controls tech
(1–5 factories per million pop).  Active factories emit **pollution**, which
reduces effective population.  **Ecology** spending converts PP into pollution
cleanup.

### Technology (6 named fields)
Six research fields — **Physics, Biology, Computers, Construction,
Force Fields, Planetology** — each containing specific named technologies.
An empire researches one technology at a time and, on completion, chooses
from a random subset of the next available options in that field.
Psilon (Creative) receive all options simultaneously.

### Ships & combat
Players design ships by choosing weapons and special systems for each hull
(Scout → Colony Ship → Destroyer → Cruiser → Battleship → Titan → Doom Star).
Battles are **round-based**; initiative comes from Computers tech (Battle Scanner,
ECM).  After winning a space battle, a fleet may bombard the colony from orbit,
then **land ground troops** to capture it.  Bulrathi troops are +50% stronger.

### Spying
Empires recruit **spies** (level 1–10) and assign them missions:
Defend (counter-espionage), Steal Tech, Sabotage Industry, or Assassinate.
Darlok spies have a +50% base success rate.

### Diplomacy
Relations follow a simple ladder: **War → Neutral → Peace → Alliance**.
Offers (Peace, Alliance, Tech Trade, Tribute demand, Declare War) are resolved
each turn.  Allied empires vote together in the Galactic Council.

### Victory conditions
1. **Conquest** — eliminate every other empire.
2. **Council** — the Galactic Council is convened when any empire controls
   ≥ 1/3 of the galaxy's total population.  Empires cast votes proportional
   to their own population; allies vote for the candidate automatically.
   A candidate needs ≥ 2/3 of all votes to be elected **Supreme Leader**.

---

## Turn structure

```
OrdersPhase → ProductionPhase → MovementPhase → CombatPhase
    → InvasionPhase → GrowthPhase → SpyPhase → CouncilPhase
    → VictoryCheckPhase → (next turn's OrdersPhase …)
```

---

## Repository layout

```
galexp/
├── README.md              this file
├── AGENTS.md              persistent AI-agent context
├── package.json           Quint dev-dependency + npm scripts
├── specs/
│   ├── README.md          how to read & run the specifications
│   ├── types.qnt          all type definitions (foundation module)
│   ├── galaxy.qnt         star map, coordinate reachability, exploration
│   ├── empire.qnt         colonies, factory/worker model, named tech
│   ├── combat.qnt         range-based movement, space & ground combat
│   ├── turn.qnt           master turn machine, council, spy phase, victory
│   ├── galexp.qnt         ← bundled single-file spec (generated; Quint target)
│   └── bundle.sh          script that regenerates galexp.qnt from the five modules
└── src/
    └── README.md          browser game implementation (planned)
```

---

## Formal specifications

The `specs/` directory contains a complete formal model written in
**[Quint](https://github.com/informalsystems/quint)** (TLA⁺-inspired,
TypeScript-friendly).  Quint resolves module imports within a single file, so
`bundle.sh` concatenates the five source modules into `galexp.qnt` before
running any Quint command.

The specs serve three purposes:

1. **Design document** — precise, executable definition of every game rule.
2. **Invariant checker** — `quint verify --invariant <name>` proves safety
   properties hold across all reachable game states.
3. **Blueprint** — the browser engine implements these specs 1-to-1.

See [`specs/README.md`](specs/README.md) for full usage.

---

## Quick start (specs only)

```bash
# Quint is installed as a local dev-dependency
bash specs/bundle.sh                      # regenerate galexp.qnt
npx quint parse    specs/galexp.qnt       # syntax check
npx quint typecheck specs/galexp.qnt      # type + effect check
npx quint run --main turn specs/galexp.qnt  # random simulation
```

---

## Planned browser stack

| Concern | Candidate |
|---|---|
| Language | TypeScript |
| Rendering | Canvas 2D or WebGL (via PixiJS) |
| State management | Zustand or XState |
| Build | Vite |
| AI opponents | MCTS + rule-based hybrid |

The Quint type definitions will be transpiled (or manually ported) directly
into TypeScript types to guarantee the engine and specs stay in sync.
