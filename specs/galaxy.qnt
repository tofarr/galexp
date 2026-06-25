// ============================================================================
// galaxy.qnt — Galactic Expanse: star map (MOO1 model)
//
// In Master of Orion 1 there are NO hyperlanes.  Stars are placed freely in
// 2-D space and any fleet can fly to any star within its fuel range in a
// single turn.  This module owns the `stars` state variable and provides:
//
//   • Coordinate-distance reachability (squared Euclidean, no floats)
//   • Exploration state (which empires have visited each star)
//   • Well-formedness predicates and invariant conditions
//
// Galaxy sizes (number of stars):  Small=24  Medium=36  Large=54  Huge=108
// ============================================================================

module galaxy {

  import types.*

  // ── Configuration constants ───────────────────────────────────────────────

  const NUM_STARS:       int   // 24 | 36 | 54 | 108 depending on galaxy size
  const MAP_WIDTH:       int   // galaxy grid width  (e.g. 100)
  const MAP_HEIGHT:      int   // galaxy grid height (e.g. 100)
  const MIN_STAR_DIST_SQ: int  // minimum squared distance between any two stars
                                // (prevents star crowding during generation)

  // ── State ─────────────────────────────────────────────────────────────────
  //
  // The star map is generated once at the start of the game and is thereafter
  // immutable — stars do not move.

  var stars: StarId -> StarSystem

  // ── Coordinate helpers ───────────────────────────────────────────────────

  pure def distSq(a: Coord, b: Coord): int =
    (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)

  // True when a fleet at star `src` with the given squared fuel range can
  // reach star `dst` in one turn.
  pure def withinRange(g: StarId -> StarSystem, src: StarId, dst: StarId, rangeSq: int): bool =
    distSq(g.get(src).coords, g.get(dst).coords) <= rangeSq

  // Set of all stars reachable from `src` for an empire whose best engine
  // provides squared range `rangeSq`.
  pure def reachableStars(g: StarId -> StarSystem, src: StarId, rangeSq: int): Set[StarId] =
    g.keys().filter(dst => dst != src and withinRange(g, src, dst, rangeSq))

  // Nearest star to `src` (by squared distance), excluding src itself.
  // Returns src when the galaxy has only one star (degenerate; avoided by
  // NUM_STARS > 1 invariant).
  pure def nearestStar(g: StarId -> StarSystem, src: StarId): StarId =
    g.keys()
      .filter(dst => dst != src)
      .fold(src, (best, candidate) =>
        if (distSq(g.get(src).coords, g.get(candidate).coords) <
            distSq(g.get(src).coords, g.get(best).coords))
        { candidate }
        else { best }
      )

  // ── Exploration ───────────────────────────────────────────────────────────

  // Mark a star as explored by the given empire.
  action explorestar(sid: StarId, eid: EmpireId): bool = {
    val sys = stars.get(sid)
    stars' = stars.put(sid, { ...sys, explored: sys.explored.union(Set(eid)) })
  }

  // True when `eid` has explored `sid`.
  pure def isExplored(g: StarId -> StarSystem, sid: StarId, eid: EmpireId): bool =
    g.get(sid).explored.contains(eid)

  // ── Well-formedness predicates ────────────────────────────────────────────

  // Every star's coordinates lie within the galaxy boundary.
  pure def coordsInBounds(g: StarId -> StarSystem): bool =
    g.keys().forall(sid =>
      g.get(sid).coords.x >= 0 and g.get(sid).coords.x <= MAP_WIDTH  and
      g.get(sid).coords.y >= 0 and g.get(sid).coords.y <= MAP_HEIGHT
    )

  // No two stars are placed closer than MIN_STAR_DIST_SQ (prevents overlap).
  pure def starsWellSpaced(g: StarId -> StarSystem): bool =
    g.keys().forall(a =>
      g.keys().forall(b =>
        a == b or distSq(g.get(a).coords, g.get(b).coords) >= MIN_STAR_DIST_SQ
      )
    )

  // No two stars share the same coordinates.
  pure def noDuplicateCoords(g: StarId -> StarSystem): bool =
    g.keys().forall(a =>
      g.keys().forall(b =>
        a == b or
        not(g.get(a).coords.x == g.get(b).coords.x and
            g.get(a).coords.y == g.get(b).coords.y)
      )
    )

  // Planet IDs are unique across the whole galaxy (not just per star).
  pure def planetIdsDistinct(g: StarId -> StarSystem): bool =
    g.keys().forall(a =>
      g.get(a).planets.forall(p =>
        g.keys().forall(b =>
          a == b or
          g.get(b).planets.forall(q => q.id != p.id)
        )
      )
    )

  // Every empire listed as having explored a star actually exists.
  // (Checked against the set of empire IDs passed in.)
  pure def exploredByKnownEmpires(g: StarId -> StarSystem, empireIds: Set[EmpireId]): bool =
    g.keys().forall(sid =>
      g.get(sid).explored.forall(eid => empireIds.contains(eid))
    )

  // ── Galaxy generation postcondition ──────────────────────────────────────
  //
  // The game engine calls this with a freshly generated star map.  The `all`
  // block encodes every postcondition the map must satisfy.  At game start,
  // each empire has explored only its home star.

  action initGalaxy(newStars: StarId -> StarSystem): bool =
    all {
      newStars.keys().size() == NUM_STARS,
      coordsInBounds(newStars),
      starsWellSpaced(newStars),
      noDuplicateCoords(newStars),
      planetIdsDistinct(newStars),
      stars' = newStars
    }

  // ── Invariant conditions ──────────────────────────────────────────────────
  //
  // Verify with:  quint verify --invariant <name> specs/galaxy.qnt

  val invStarCount: bool =
    stars.keys().size() == NUM_STARS

  val invCoordsInBounds: bool =
    coordsInBounds(stars)

  val invNoDuplicateCoords: bool =
    noDuplicateCoords(stars)

  val invStarsWellSpaced: bool =
    starsWellSpaced(stars)

  val invPlanetIdsDistinct: bool =
    planetIdsDistinct(stars)
}
