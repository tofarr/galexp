// ============================================================================
// galaxy.qnt — Galactic Expanse: star map (MOO1 model)
//
// Phase 1 additions:
//   • MIN_HOME_DIST_SQ constant — homeworlds must be placed at least this
//     far apart so empires don't start on top of each other.
//   • initGalaxy postcondition enforces homeworld spacing given a homestar set.
//   • hasColonisableWorld helper used by empire.qnt to guard colonisation.
// ============================================================================

module galaxy {

  import types.*

  // ── Configuration constants ───────────────────────────────────────────────

  const NUM_STARS:        int   // 24 | 36 | 54 | 108
  const MAP_WIDTH:        int   // e.g. 100
  const MAP_HEIGHT:       int   // e.g. 100
  const MIN_STAR_DIST_SQ: int   // prevents star crowding (e.g. 25 = 5 parsec min)
  const MIN_HOME_DIST_SQ: int   // homeworlds must be at least this far apart (e.g. 400)
  const MAX_RICHNESS:     int   // e.g. 4 (Ultra Rich)

  // ── State ─────────────────────────────────────────────────────────────────

  var stars: StarId -> StarSystem

  // ── Coordinate helpers ────────────────────────────────────────────────────

  pure def distSq(a: Coord, b: Coord): int =
    (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)

  pure def withinRange(g: StarId -> StarSystem, src: StarId, dst: StarId, rangeSq: int): bool =
    distSq(g.get(src).coords, g.get(dst).coords) <= rangeSq

  pure def reachableStars(g: StarId -> StarSystem, src: StarId, rangeSq: int): Set[StarId] =
    g.keys().filter(dst => dst != src and withinRange(g, src, dst, rangeSq))

  pure def nearestStar(g: StarId -> StarSystem, src: StarId): StarId =
    g.keys()
     .filter(dst => dst != src)
     .fold(src, (best, cand) =>
       if (distSq(g.get(src).coords, g.get(cand).coords) <
           distSq(g.get(src).coords, g.get(best).coords)) { cand }
       else { best }
     )

  // ── World attribute helpers ───────────────────────────────────────────────

  pure def hasColonisableWorld(g: StarId -> StarSystem, sid: StarId): bool =
    g.get(sid).planetType != Barren and
    g.get(sid).class_     != Neutron   and
    g.get(sid).class_     != BlackHole

  // ── Exploration ───────────────────────────────────────────────────────────

  action explorestar(sid: StarId, eid: EmpireId): bool = {
    val sys = stars.get(sid)
    stars' = stars.put(sid, { ...sys, explored: sys.explored.union(Set(eid)) })
  }

  pure def isExplored(g: StarId -> StarSystem, sid: StarId, eid: EmpireId): bool =
    g.get(sid).explored.contains(eid)

  // ── Well-formedness predicates ────────────────────────────────────────────

  pure def coordsInBounds(g: StarId -> StarSystem): bool =
    g.keys().forall(sid =>
      g.get(sid).coords.x >= 0 and g.get(sid).coords.x <= MAP_WIDTH  and
      g.get(sid).coords.y >= 0 and g.get(sid).coords.y <= MAP_HEIGHT
    )

  pure def noDuplicateCoords(g: StarId -> StarSystem): bool =
    g.keys().forall(a =>
      g.keys().forall(b =>
        a == b or not(
          g.get(a).coords.x == g.get(b).coords.x and
          g.get(a).coords.y == g.get(b).coords.y
        )
      )
    )

  pure def starsWellSpaced(g: StarId -> StarSystem): bool =
    g.keys().forall(a =>
      g.keys().forall(b =>
        a == b or distSq(g.get(a).coords, g.get(b).coords) >= MIN_STAR_DIST_SQ
      )
    )

  pure def richnessInBounds(g: StarId -> StarSystem): bool =
    g.keys().forall(sid =>
      g.get(sid).richness >= 0 and g.get(sid).richness <= MAX_RICHNESS
    )

  pure def maxPopBasePositive(g: StarId -> StarSystem): bool =
    g.keys().forall(sid =>
      hasColonisableWorld(g, sid) implies g.get(sid).maxPopBase > 0
    )

  // Homeworlds must be well-separated so no two empires start adjacent.
  pure def homewordsWellSeparated(g: StarId -> StarSystem, homes: Set[StarId]): bool =
    homes.forall(a =>
      homes.forall(b =>
        a == b or distSq(g.get(a).coords, g.get(b).coords) >= MIN_HOME_DIST_SQ
      )
    )

  // Every homeworld must have a colonisable world (can't start on a Barren/Neutron star).
  pure def homestardsColonisable(g: StarId -> StarSystem, homes: Set[StarId]): bool =
    homes.forall(sid => hasColonisableWorld(g, sid))

  // ── Galaxy generation postcondition ──────────────────────────────────────
  //
  // `homes` is the set of homestar IDs assigned to the empires.

  action initGalaxy(newStars: StarId -> StarSystem, homes: Set[StarId]): bool =
    all {
      newStars.keys().size() == NUM_STARS,
      coordsInBounds(newStars),
      starsWellSpaced(newStars),
      noDuplicateCoords(newStars),
      richnessInBounds(newStars),
      maxPopBasePositive(newStars),
      homes.forall(h => newStars.keys().contains(h)),
      homewordsWellSeparated(newStars, homes),
      homestardsColonisable(newStars, homes),
      stars' = newStars
    }

  // ── Invariant conditions ──────────────────────────────────────────────────

  val invStarCount: bool =
    stars.keys().size() == NUM_STARS

  val invCoordsInBounds: bool =
    coordsInBounds(stars)

  val invNoDuplicateCoords: bool =
    noDuplicateCoords(stars)

  val invStarsWellSpaced: bool =
    starsWellSpaced(stars)

  val invRichnessInBounds: bool =
    richnessInBounds(stars)

  val invMaxPopBasePositive: bool =
    maxPopBasePositive(stars)
}
