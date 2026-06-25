# AGENTS.md — Galactic Expanse

Persistent context for AI-agent sessions working on this repository.

---

## Project identity

**Galactic Expanse** is a browser-playable 4X space-strategy game modelled
faithfully on **Master of Orion (1993, Simtex / MicroProse)** — the original,
not MOO2.  Formal specifications are written in Quint before any engine code
is written.

---

## Critical design reference: MOO1 vs MOO2

Always verify against MOO1 rules, not MOO2.  Key differences that agents must
remember:

| Feature | MOO1 (this project) | MOO2 (NOT this project) |
|---|---|---|
| Races | 10 fixed races with hardcoded bonuses | Custom trait-picking system |
| Tech system | Named techs in 6 fields; one at a time | Levels 1-15 per 7 categories |
| Galaxy travel | Coordinate-based; fuel range from engine tech | Hyperlane graph |
| Worker model | Farmers / Workers / Scientists per colony | Allocation percentages |
| Production | Factories built over time; pollution | Direct PP output |
| Morale | None | Yes (0-100 scale) |
| Victory | Conquest OR Galactic Council vote | 4 paths incl. tech & score |
| Sociology | Not a tech field | Yes (7th field) |
| Spying | Named spy missions (Steal, Sabotage…) | Simpler |
| Galaxy sizes | 24 / 36 / 54 / 108 stars | Different sizes |

---

## Repository layout

```
specs/types.qnt     — all type definitions (foundation; no state)
specs/galaxy.qnt    — coordinate star map, exploration, well-formedness
specs/empire.qnt    — colonies, factories, pollution, race bonuses, tech
specs/combat.qnt    — range-based movement, space battles, ground combat
specs/turn.qnt      — master turn machine, diplomacy, council, victory
specs/galexp.qnt    — GENERATED bundle (concat of above; Quint CLI target)
specs/bundle.sh     — generates galexp.qnt from the five source modules
specs/README.md     — how to run Quint commands
src/README.md       — planned browser engine
```

---

## Tooling

| Tool | Version | How to invoke |
|---|---|---|
| Quint | 0.32.0 (local) | `./node_modules/.bin/quint` or `npx quint` |
| Node.js | 22.x | system |
| npm | 10.x | system |

**Critical**: Quint 0.32 resolves `import X.*` only within the same `.qnt`
file.  Always run `bash specs/bundle.sh` before any Quint CLI command.
Do NOT pass multiple `.qnt` files as arguments to `quint`.

---

## Essential Quint commands

```bash
# After editing any source module:
bash specs/bundle.sh                                # regenerate galexp.qnt

# Check syntax
./node_modules/.bin/quint parse specs/galexp.qnt

# Check types and effects (catches pure-def/def misuse, List/Set confusion)
./node_modules/.bin/quint typecheck specs/galexp.qnt

# Random simulation (exercises the step action)
./node_modules/.bin/quint run --main turn specs/galexp.qnt

# Verify a named invariant (requires Apalache on PATH)
./node_modules/.bin/quint verify --invariant invAtMostOneWinner specs/galexp.qnt
```

---

## Quint syntax rules learned from this project

| Issue | Correct pattern |
|---|---|
| State-reading helper | `def f(...)` not `pure def f(...)` |
| Pure (no state) helper | `pure def f(x: T): U = ...` |
| List filtering | `list.foldl(List(), (acc, x) => if (cond) acc.append(x) else acc)` |
| List forall/exists | `list.foldl(true, (acc, x) => acc and cond(x))` |
| Non-det pick from set | `nondet x = set.oneOf()` (not inside `val`) |
| Multi-branch if in action | All branches must update the same state variables |
| `any` with different effects | Wrap smaller-effect branches to stamp all vars |
| Record spread update | `{ ...r, field: newValue }` |
| Map rebuild (no remove) | `set.mapBy(k => map.get(k))` on surviving-key set |
| Built-in name `to` | Do NOT use `to` as a parameter name (use `recipient` etc.) |
| Invariants | Declare as `val invFoo: bool = expr` not `invariant` keyword |
| No recursion | Use `1.to(n).fold(init, (acc, _step) => ...)` for iteration |
| Multi-arg variant | Not supported; use a record wrapper type instead |

---

## MOO1 game constants (defaults)

| Constant | Value | Defined in |
|---|---|---|
| `NUM_STARS` | 24 / 36 / 54 / 108 | galaxy.qnt |
| `MAP_WIDTH`, `MAP_HEIGHT` | 100 each | galaxy.qnt |
| `MIN_STAR_DIST_SQ` | 25 (5 parsec min) | galaxy.qnt |
| `NUM_EMPIRES` | 2–10 | empire.qnt |
| `BASE_FOOD_PER_FARMER` | 2 | empire.qnt |
| `BASE_PP_PER_WORKER` | 1 | empire.qnt |
| `POLLUTION_PER_FACTORY` | 1 | empire.qnt |
| `ECOLOGY_PP_PER_UNIT` | 2 | empire.qnt |
| `MAX_COMBAT_ROUNDS` | 40 | combat.qnt |
| `COUNCIL_POP_THRESHOLD_PCT` | 33 | turn.qnt |
| `TURN_LIMIT` | 200 | turn.qnt |

For model-checking tractability use: `NUM_STARS=4`, `NUM_EMPIRES=2`,
`TURN_LIMIT=5`, `MAX_COMBAT_ROUNDS=3`.

---

## Named invariants (verify with `--invariant`)

### galaxy module
- `invStarCount` — galaxy has exactly NUM_STARS stars
- `invCoordsInBounds` — all stars within MAP_WIDTH × MAP_HEIGHT
- `invNoDuplicateCoords` — no two stars share the same position
- `invStarsWellSpaced` — no two stars closer than MIN_STAR_DIST_SQ
- `invPlanetIdsDistinct` — planet ids are unique galaxy-wide

### empire module
- `invAllocationsValid` — farmers+workers+scientists == population at every colony
- `invPopulationPositive` — every colony has pop > 0
- `invPollutionNonNegative` — pollution ≥ 0 always
- `invFactoriesInBounds` — factories ≤ maxFactories everywhere
- `invBcNonNegative` — no empire goes into debt
- `invResearchingNotOwned` — empire never "researches" a tech it already has
- `invPrerequisitesRespected` — no tech appears without its prerequisite

### combat module
- `invFleetLocationsValid` — all fleet locations are real stars
- `invMovementLegal` — all fleet destinations within fuel range
- `invShipHpNonNegative` — no ship has negative HP
- `invCombatRoundBounded` — rounds stay ≤ MAX_COMBAT_ROUNDS

### turn module
- `invAtMostOneWinner` — at most one empire wins
- `invWinnerIsAlive` — the declared winner is not eliminated
- `invRelationSymmetry` — if A→B = AtWar then B→A = AtWar
- `invConquestImpliesWinnerPending` — lone survivor triggers VictoryCheckPhase

---

## Common agent tasks

### Add a new named technology
1. Add the variant to `type TechName` in `specs/types.qnt` with a comment.
2. If it has a prerequisite, add a case to `hasPrerequisite` in `specs/empire.qnt`.
3. If it changes production, add a branch in the relevant formula (`foodOutput`, `ppOutput`, etc.).
4. Re-bundle and typecheck.

### Add a new race special ability
1. The race variant already exists in `type Race`.
2. Add / edit the relevant multiplier function in `specs/empire.qnt`
   (`farmingPct`, `industryPct`, `researchPct`, `growthPct`, `isLithovore`, `extraFactoryCap`, `isCreative`).
3. Re-bundle and typecheck.

### Add a new invariant
1. Identify which module owns the relevant state variable.
2. Add `val invFoo: bool = expr` in that module's source file.
3. Re-bundle, typecheck, then verify: `quint verify --invariant invFoo specs/galexp.qnt`.

### Edit and rebundle
Every edit to a source `.qnt` file requires regenerating `galexp.qnt`:
```bash
bash specs/bundle.sh && ./node_modules/.bin/quint typecheck specs/galexp.qnt
```

---

## Open design questions

- [ ] **Antaran attacks**: MOO1 endgame features Antaran raiders attacking the
  most advanced empire.  Not yet modelled.
- [ ] **Multi-player turn order**: In MOO1 all empires submit orders simultaneously
  and then resolution runs server-side.  The spec models sequential resolution
  for simplicity.
- [ ] **Orbital bases (Starbases)**: Currently not a separate entity; ground
  combat model doesn't account for planetary defences separately.
- [ ] **Tech rarity / randomness**: The spec treats all named techs as always
  available for research.  MOO1 randomly selects which options appear at each
  research opportunity (except for Creative races).
- [ ] **Ship scrapping**: No action to dismantle a fleet for BC refund.
- [ ] **Food redistribution**: MOO1 allows transferring food between same-empire
  colonies in the same star system; not yet modelled.
