# src/ — Browser Game Implementation

This directory will contain the browser-playable implementation of
**Galactic Expanse**.

## Planned architecture

```
src/
├── types/              TypeScript mirrors of specs/types.qnt
├── engine/
│   ├── galaxy.ts       Galaxy generation (must satisfy galaxy.qnt postconditions)
│   ├── empire.ts       Colony production, research, growth
│   ├── combat.ts       Fleet movement, battle resolution
│   ├── turn.ts         Turn/phase state machine
│   └── ai/
│       ├── mcts.ts     Monte Carlo Tree Search for fleet decisions
│       └── planner.ts  Colony / research planning heuristics
├── rendering/
│   ├── GalaxyMap.ts    Star map canvas renderer
│   ├── PlanetView.ts   Colony management panel
│   ├── FleetView.ts    Fleet orders UI
│   └── CombatView.ts   Battle animation
├── ui/
│   ├── HUD.ts          Credits, turn number, alerts
│   ├── TechTree.ts     Research panel
│   └── Diplomacy.ts    Diplomatic proposal UI
└── main.ts             Entry point
```

## Key design constraints

Every function in `engine/` that corresponds to a Quint action must
uphold the invariants stated in the matching `.qnt` file.  When in
doubt, check the spec first.

## Tech stack decisions pending

- **Rendering**: PixiJS v8 (WebGL) vs. native Canvas 2D
- **State management**: Zustand (simple) vs. XState (phase machine)
- **AI difficulty**: easy / normal / hard via MCTS iteration budget
- **Networking**: offline-only initially; WebRTC P2P for multiplayer later
- **Build**: Vite + TypeScript strict mode

## Getting started (once implementation begins)

```bash
npm install
npm run dev      # Vite dev server
npm run build    # Production build to dist/
npm run test     # Unit tests (Vitest)
```
