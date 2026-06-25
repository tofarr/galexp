# Galactic Expanse — Formal Specifications (MOO1 model)

This directory contains the Quint formal model of the game.
Design reference: **Master of Orion (1993)**.

---

## File organisation

| File | Role |
|---|---|
| `types.qnt` | All type definitions — no state, no actions |
| `galaxy.qnt` | Star map: coordinates, exploration, well-formedness |
| `empire.qnt` | Colonies, factories, workers, pollution, research |
| `combat.qnt` | Fleet movement (range-based), space & ground combat |
| `turn.qnt` | Master turn machine, council vote, spy phase, victory |
| `galexp.qnt` | **Generated** — bundle of the five modules above |
| `bundle.sh` | Script that concatenates modules → `galexp.qnt` |

`galexp.qnt` is listed in `.gitignore`; always regenerate before running Quint.

---

## Module dependency

```
types.qnt           (no imports)
    ↑
galaxy.qnt          import types.*
    ↑
empire.qnt          import types.*  import galaxy.*
    ↑
combat.qnt          import types.*  import galaxy.*  import empire.*
    ↑
turn.qnt            import types.*  import galaxy.*  import empire.*  import combat.*
```

---

## Workflow

### 1 — Edit a source module

Edit any of `types.qnt`, `galaxy.qnt`, `empire.qnt`, `combat.qnt`, or `turn.qnt`.

### 2 — Regenerate the bundle

```bash
bash specs/bundle.sh      # writes specs/galexp.qnt
```

### 3 — Check syntax and types

```bash
./node_modules/.bin/quint parse     specs/galexp.qnt
./node_modules/.bin/quint typecheck specs/galexp.qnt
```

### 4 — Simulate (random execution)

```bash
./node_modules/.bin/quint run --main turn specs/galexp.qnt
```

### 5 — Verify an invariant (requires Apalache)

```bash
./node_modules/.bin/quint verify \
    --main turn \
    --invariant invAtMostOneWinner \
    specs/galexp.qnt
```

---

## Module summaries

### `types.qnt`

Pure type vocabulary; imported by every other module with `import types.*`.

| Type group | Key types |
|---|---|
| Identifiers | `StarId`, `PlanetId`, `EmpireId`, `FleetId`, `DesignId`, `SpyId` |
| Geography | `Coord`, `StarClass`, `PlanetType`, `PlanetSize`, `Planet`, `StarSystem` |
| Technology | `TechField` (6 fields), `TechName` (~50 named techs) |
| Races | `Race` (10 fixed: Humans, Psilon, Sakkra, Bulrathi, Mrrshan, Klackon, Meklar, Alkari, Silicoid, Darlok) |
| Colonies | `WorkerAlloc`, `ColonyProject`, `Colony` |
| Empires | `Empire` (race, bc, techs, researching) |
| Spying | `SpyMission`, `Spy` |
| Ground combat | `GroundForce` |
| Diplomacy | `Relation` (War/Neutral/Peace/Alliance), `DiplomaticOffer` |
| Ships | `ShipHull`, `WeaponSlot`, `SpecialSlot`, `ShipDesign`, `Ship` |
| Fleets | `Fleet` with `fuelRangeSq` (squared Euclidean range) |
| Council | `CouncilSession` |
| Turn | `TurnPhase` (9 phases), `VictoryKind` (Conquest / Council) |

### `galaxy.qnt`

**No hyperlanes.**  Stars have 2-D coordinates.  A fleet reaches any star
within its squared Euclidean fuel range.

Key definitions:
- `distSq(a, b)` — squared Euclidean distance between two coordinates
- `withinRange(g, src, dst, rangeSq)` — true if dst is reachable in one turn
- `reachableStars(g, src, rangeSq)` — all reachable destinations
- `nearestStar(g, src)` — closest other star
- `explorestar(sid, eid)` — mark a star as explored by an empire
- `initGalaxy(newStars)` — postcondition for valid galaxy generation

Galaxy sizes: Small=24, Medium=36, Large=54, Huge=108 stars.

### `empire.qnt`

**Factory / worker model:**
- Colonists = Farmers + Workers + Scientists (must sum to `population`)
- Workers operate factories → PP; one worker = one factory
- Factory cap = `population × roboticControlsRatio` (set by Robotic Controls tech)
- Active factories emit pollution; Ecology spending (PP → cleanup) removes it

**Race-specific bonuses** (hardcoded):
- `farmingPct`, `industryPct`, `researchPct`, `growthPct` per race
- `isLithovore` (Silicoid: no food needed; colonise any planet)
- `isCreative` (Psilon: all tech options)
- `extraFactoryCap` (Meklar: +1 factory per pop)

**Named tech prerequisites** enforced in `hasPrerequisite`:
- Engine chain: Nuclear → Fusion → Ion → Sub-Space → Hyper → Interphased
- Robotic Controls: 2 → 3 → 4 → 5
- Battle Computers: 1 → 2 → 3
- Shields: 1 → 3 → 5 → 7 → 10 → 15 → 20 → 25 → 30
- Stellar Converter requires Anti-Matter Bomb first

### `combat.qnt`

**Range-based movement** (not hop-based):
- `engineRangeSq(e)` derives squared fuel range from the empire's best engine tech
- `orderMove(fid, dest)` — validate and issue move; fails if out of range
- `advanceFleets` — all in-transit fleets arrive at destination in one step

**Space combat** (`combatRoundAt`):
- Non-deterministic damage (model checker explores all rolls)
- `nondet` always at action scope; never inside lambdas
- `pruneDeadShips` uses `foldl` (List has no filter returning List)

**Orbital bombardment** (`bombardPlanet`):
- Reduces enemy colony population by `numShips × BOMBARDMENT_DMG_PER_SHIP` per round
- Colony can be reduced to 0 pop (then it must be captured by troops)

**Ground combat** (`landTroops`):
- Non-deterministic outcome (dice rolls)
- Bulrathi attackers get ×1.5 strength
- On success: colony flips ownership at half population

### `turn.qnt`

**Nine turn phases** in order:
`Orders → Production → Movement → Combat → Invasion → Growth → Spy → Council → VictoryCheck`

**Diplomacy:**
- `makeOffer(sender, recipient, offer)` — queue an offer
- `resolveOffer(o, accepted)` — apply the relation change

**Galactic Council:**
- Triggered when any empire has ≥ `COUNCIL_POP_THRESHOLD_PCT`% of total pop
- `councilCandidate` — empire with highest population is nominated
- `votesFor(voter, candidate)` — allied empires vote for the candidate
- `hasCouncilMajority` — candidate wins if ≥ 2/3 of total galaxy population votes for them

**Victory:**
- `conquestWinner` — only one non-eliminated empire remains
- `CouncilVictory` — set by `resolveCouncilVote` when majority is achieved

---

## Key design decisions

- **No hyperlanes** — stars are freely placed; any star within fuel range is reachable.
- **Fixed 10 races** — no custom trait-picking; MOO2 is a different game.
- **Named tech tree** — `TechName` variants, not `(category, level)` pairs.
- **Two victory paths only** — Conquest and Council; no tech-research or score victory.
- **Immutable galaxy** — `stars` is written once by `initGalaxy`; never mutated.
- **Relation symmetry** — `setRelation` always writes both (a→b) and (b→a).
- **Bundle required** — Quint 0.32 resolves `import X.*` within a single file only.

---

## Open questions (tracked in AGENTS.md)

- Antaran raids (endgame feature)
- Tech randomisation (which options appear at each research opportunity)
- Orbital base combat (Starbases as separate entities)
- Food redistribution between same-system colonies
