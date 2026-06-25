// ============================================================================
// turn.qnt — Galactic Expanse: master turn state machine (MOO1 model)
//
// Integrates all sub-modules and specifies:
//   • Diplomatic relations (War → Neutral → Peace → Alliance ladder)
//   • Phase ordering (9 MOO1 phases per turn)
//   • Spy mission resolution
//   • Galactic Council vote trigger and resolution
//   • Victory conditions: Conquest and Council only (no tech / score victory)
// ============================================================================

module turn {

  import types.*
  import galaxy.*
  import empire.*
  import combat.*

  // ── Configuration ─────────────────────────────────────────────────────────

  const COUNCIL_POP_THRESHOLD_PCT: int  // % of total pop that triggers a session (e.g. 33)
  const SPY_SUCCESS_BASE_PCT:      int  // base % success for a spy mission
  const TURN_LIMIT:                int  // absolute turn cap (prevents infinite games)

  // ── State ─────────────────────────────────────────────────────────────────

  var turn:         int
  var phase:        TurnPhase

  // Nested relation map: relations.get(a).get(b) = relation A has with B.
  // Kept symmetric: setting (a,b) always sets (b,a) to the same value.
  var relations:    EmpireId -> (EmpireId -> Relation)

  // Pending diplomatic offers from one empire to another.
  var pendingOffers: Set[{ sender: EmpireId, recipient: EmpireId, offer: DiplomaticOffer }]

  // Active Galactic Council session (empty set = no session in progress).
  var council:      Set[CouncilSession]

  var winner:       Set[VictoryResult]

  // ── Diplomatic helpers ────────────────────────────────────────────────────

  def relationBetween(a: EmpireId, b: EmpireId): Relation =
    if (a == b) { Alliance }
    else        { relations.get(a).get(b) }

  def areAtWar(a: EmpireId, b: EmpireId): bool =
    relationBetween(a, b) == AtWar

  def areAllied(a: EmpireId, b: EmpireId): bool =
    relationBetween(a, b) == Alliance

  // Update both (a→b) and (b→a) to maintain symmetry.
  pure def setRelation(
    r:   EmpireId -> (EmpireId -> Relation),
    a:   EmpireId,
    b:   EmpireId,
    rel: Relation
  ): EmpireId -> (EmpireId -> Relation) =
    r.put(a, r.get(a).put(b, rel))
     .put(b, r.get(b).put(a, rel))

  // ── Diplomacy actions ─────────────────────────────────────────────────────

  action makeOffer(sender: EmpireId, recipient: EmpireId, offer: DiplomaticOffer): bool = {
    all {
      phase == OrdersPhase,
      not(empires.get(sender).eliminated),
      not(empires.get(recipient).eliminated),
      sender != recipient,
      pendingOffers' = pendingOffers.union(Set({ sender: sender, recipient: recipient, offer: offer })),
      turn'     = turn,
      phase'    = phase,
      relations' = relations,
      council'   = council,
      winner'    = winner
    }
  }

  // Resolve an offer (called during the production phase resolution).
  // "accepted" is non-deterministically chosen by the AI or input by the human.
  action resolveOffer(
    o:        { sender: EmpireId, recipient: EmpireId, offer: DiplomaticOffer },
    accepted: bool
  ): bool = {
    val cur = relations.get(o.sender).get(o.recipient)
    // All variants of DiplomaticOffer are simple (no data), so == works.
    val newRel =
      if      (o.offer == DeclareWar)     { AtWar }
      else if (o.offer == OfferPeace)     { if (accepted) { Neutral } else { cur } }
      else if (o.offer == OfferAlliance)  { if (accepted) { Alliance } else { cur } }
      else if (o.offer == BreakAlliance)  { Neutral }
      else                                { cur }  // TechTrade / Tribute: no relation change
    all {
      pendingOffers' = pendingOffers.exclude(Set(o)),
      relations'     = setRelation(relations, o.sender, o.recipient, newRel),
      turn'          = turn,
      phase'         = phase,
      council'       = council,
      winner'        = winner
    }
  }

  // ── Spy phase actions ─────────────────────────────────────────────────────
  //
  // Each spy on a non-Defend mission makes an attempt.  Success is
  // non-deterministic (model checker explores both outcomes).
  // Darlok spies have a higher success rate (captured by a wider nondet range).

  pure def spySuccessRange(spy: Spy, e: Empire): int =
    val base = SPY_SUCCESS_BASE_PCT
    if (e.race == Darlok) { base + 50 } else { base }

  action resolveSpyMission(spyId: SpyId): bool = {
    nondet spy = spies.filter(s => s.id == spyId).oneOf()
    val owner   = empires.get(spy.owner)
    nondet roll = 1.to(100).oneOf()
    val success = roll <= spySuccessRange(spy, owner)
    // StealTech: on success, copy one random tech from target.
    // We model the outcome abstractly: on success the empire gains one new tech.
    // The specific tech picked is left to the engine (non-det selection).
    if (success) {
      all {
        spies'       = spies.exclude(Set(spy)).union(Set({ ...spy, level: spy.level + 1 })),
        empires'     = empires,
        colonies'    = colonies,
        fleets'      = fleets,
        combatRound' = combatRound,
        relations'   = relations,
        pendingOffers' = pendingOffers,
        council'     = council,
        winner'      = winner,
        turn'        = turn,
        phase'       = phase,
        stars'       = stars
      }
    } else {
      // Mission failed; spy stays in place (may be caught by defenders).
      all {
        spies'       = spies,
        empires'     = empires,
        colonies'    = colonies,
        fleets'      = fleets,
        combatRound' = combatRound,
        relations'   = relations,
        pendingOffers' = pendingOffers,
        council'     = council,
        winner'      = winner,
        turn'        = turn,
        phase'       = phase,
        stars'       = stars
      }
    }
  }

  // ── Galactic Council ──────────────────────────────────────────────────────
  //
  // Triggered when any empire controls ≥ COUNCIL_POP_THRESHOLD_PCT % of total pop.
  //
  // Voting rules (MOO1):
  //   • Each empire casts votes equal to its own population.
  //   • Empires allied with the candidate vote for the candidate.
  //   • Human player may vote for themselves or the candidate.
  //   • Candidate wins if their vote total ≥ 2/3 of total votes cast.

  def councilThresholdMet: bool =
    val tot = totalPop
    empires.keys().exists(eid =>
      not(empires.get(eid).eliminated) and
      empirePop(eid) * 100 >= tot * COUNCIL_POP_THRESHOLD_PCT
    )

  // The empire with the largest population is nominated as council candidate.
  // Use -1 as the "no empire yet" sentinel (EmpireId = int).
  def councilCandidate: EmpireId =
    empires.keys()
           .filter(eid => not(empires.get(eid).eliminated))
           .fold(-1, (best, eid) =>
             if (best == -1 or empirePop(eid) > empirePop(best)) { eid } else { best }
           )

  // Votes an empire casts.  Allies of the candidate vote for them; others vote for themselves.
  def votesFor(voter: EmpireId, candidate: EmpireId): int =
    if (voter == candidate or areAllied(voter, candidate)) {
      empirePop(voter)   // vote for candidate
    } else {
      0                  // vote against (abstain in favour of self)
    }

  def totalVotesForCandidate(candidate: EmpireId): int =
    empires.keys()
           .filter(eid => not(empires.get(eid).eliminated))
           .fold(0, (acc, eid) => acc + votesFor(eid, candidate))

  def hasCouncilMajority(candidate: EmpireId): bool =
    totalVotesForCandidate(candidate) * 3 >= totalPop * 2

  // Open a council session if threshold is met and none is active.
  action openCouncilSession: bool = {
    val cand = councilCandidate
    all {
      phase == CouncilPhase,
      council.size() == 0,
      councilThresholdMet,
      council' = Set({ candidate: cand, votes: empires.keys().mapBy(_ => 0) }),
      turn'          = turn,
      phase'         = phase,
      relations'     = relations,
      pendingOffers' = pendingOffers,
      winner'        = winner,
      stars'         = stars,
      empires'       = empires,
      colonies'      = colonies,
      fleets'        = fleets,
      combatRound'   = combatRound
    }
  }

  // Cast votes and check for a winner.
  action resolveCouncilVote: bool = {
    nondet sesh = council.oneOf()
    if (hasCouncilMajority(sesh.candidate)) {
      all {
        winner' = Set({ winner: sesh.candidate, kind: CouncilVictory, turnNumber: turn }),
        council' = Set(),
        turn'          = turn,
        phase'         = phase,
        relations'     = relations,
        pendingOffers' = pendingOffers,
        stars'         = stars,
        empires'       = empires,
        colonies'      = colonies,
        fleets'        = fleets,
        combatRound'   = combatRound
      }
    } else {
      // No majority; session expires.
      all {
        council' = Set(),
        winner'        = winner,
        turn'          = turn,
        phase'         = phase,
        relations'     = relations,
        pendingOffers' = pendingOffers,
        stars'         = stars,
        empires'       = empires,
        colonies'      = colonies,
        fleets'        = fleets,
        combatRound'   = combatRound
      }
    }
  }

  // ── Phase ordering ────────────────────────────────────────────────────────

  pure def nextPhase(p: TurnPhase): TurnPhase =
    if      (p == OrdersPhase)       { ProductionPhase }
    else if (p == ProductionPhase)   { MovementPhase }
    else if (p == MovementPhase)     { CombatPhase }
    else if (p == CombatPhase)       { InvasionPhase }
    else if (p == InvasionPhase)     { GrowthPhase }
    else if (p == GrowthPhase)       { SpyPhase }
    else if (p == SpyPhase)          { CouncilPhase }
    else if (p == CouncilPhase)      { VictoryCheckPhase }
    else                             { OrdersPhase }   // VictoryCheckPhase → next turn

  // ── Phase advance ─────────────────────────────────────────────────────────

  action advancePhase: bool = {
    val np      = nextPhase(phase)
    val newTurn = if (np == OrdersPhase) { turn + 1 } else { turn }
    all {
      winner.size() == 0,
      phase'         = np,
      turn'          = newTurn,
      stars'         = stars,
      empires'       = empires,
      colonies'      = colonies,
      fleets'        = fleets,
      combatRound'   = if (np == CombatPhase) { 0 } else { combatRound },
      relations'     = relations,
      pendingOffers' = pendingOffers,
      council'       = council,
      winner'        = winner
    }
  }

  // ── Conquest victory ──────────────────────────────────────────────────────

  def conquestWinner: Set[EmpireId] =
    val alive = empires.keys().filter(eid => not(empires.get(eid).eliminated))
    if (alive.size() == 1) { alive } else { Set() }

  // ── Victory check ─────────────────────────────────────────────────────────

  action checkVictory: bool = {
    val cw = conquestWinner
    val result =
      if (cw.size() > 0) {
        cw.map(eid => { winner: eid, kind: ConquestVictory, turnNumber: turn })
      } else {
        Set()
      }
    all {
      winner'        = result,
      turn'          = turn,
      phase'         = phase,
      relations'     = relations,
      pendingOffers' = pendingOffers,
      council'       = council,
      stars'         = stars,
      empires'       = empires,
      colonies'      = colonies,
      fleets'        = fleets,
      combatRound'   = combatRound
    }
  }

  // ── Initialisation ────────────────────────────────────────────────────────
  //
  // At game start, all empires are at Neutral with each other.
  // Each empire has explored only its home star.

  action init: bool = {
    val empireIds    = empires.keys()
    val neutralInner = empireIds.mapBy(_ => Neutral)
    all {
      turn'          = 1,
      phase'         = OrdersPhase,
      winner'        = Set(),
      pendingOffers' = Set(),
      council'       = Set(),
      combatRound'   = 0,
      relations'     = empireIds.mapBy(_ => neutralInner)
    }
  }

  // ── Top-level step ────────────────────────────────────────────────────────

  // advanceFleets only touches `fleets` and `combatRound`; every branch of
  // `any` must update the same state-variable set, so stamp the rest here.
  action stepMovement: bool =
    all {
      phase == MovementPhase,
      advanceFleets,
      stars'         = stars,
      empires'       = empires,
      colonies'      = colonies,
      turn'          = turn,
      phase'         = phase,
      relations'     = relations,
      pendingOffers' = pendingOffers,
      council'       = council,
      winner'        = winner
    }

  action step: bool =
    any {
      advancePhase,
      checkVictory,
      resolveCouncilVote,
      stepMovement
    }

  // ── Invariant conditions ──────────────────────────────────────────────────

  val invTurnPositive: bool =
    turn >= 1

  val invTurnBounded: bool =
    turn <= TURN_LIMIT + 1

  val invAtMostOneWinner: bool =
    winner.size() <= 1

  val invWinnerIsAlive: bool =
    winner.forall(v =>
      empires.keys().contains(v.winner) and
      not(empires.get(v.winner).eliminated)
    )

  val invRelationSymmetry: bool =
    empires.keys().forall(a =>
      empires.keys().forall(b =>
        a == b or relationBetween(a, b) == relationBetween(b, a)
      )
    )

  val invPendingOffersValid: bool =
    pendingOffers.forall(o =>
      empires.keys().contains(o.sender) and
      empires.keys().contains(o.recipient) and
      o.sender != o.recipient
    )

  val invAtMostOneCouncilSession: bool =
    council.size() <= 1

  val invCouncilCandidateExists: bool =
    council.forall(s => empires.keys().contains(s.candidate))

  val invConquestImpliesWinnerPending: bool =
    // When only one empire survives it must either already be the winner
    // or be in VictoryCheckPhase.
    conquestWinner.size() > 0 implies
      winner.size() > 0 or phase == VictoryCheckPhase

  // ── Temporal properties ───────────────────────────────────────────────────

  temporal phaseProgressesForward =
    always(
      (phase == OrdersPhase     implies eventually(phase == ProductionPhase)) and
      (phase == ProductionPhase implies eventually(phase == MovementPhase))   and
      (phase == MovementPhase   implies eventually(phase == CombatPhase))     and
      (phase == CombatPhase     implies eventually(phase == InvasionPhase))   and
      (phase == InvasionPhase   implies eventually(phase == GrowthPhase))     and
      (phase == GrowthPhase     implies eventually(phase == SpyPhase))        and
      (phase == SpyPhase        implies eventually(phase == CouncilPhase))    and
      (phase == CouncilPhase    implies eventually(phase == VictoryCheckPhase))
    )

  temporal gameTerminates =
    eventually(winner.size() > 0 or turn > TURN_LIMIT)
}
