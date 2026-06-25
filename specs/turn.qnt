// ============================================================================
// turn.qnt — Galactic Expanse: master turn state machine (MOO1 model)
//
// Nine turn phases per turn:
//   Orders → Production → Movement → Combat → Invasion →
//   Growth → Spy → Council → VictoryCheck
//
// Victory: Conquest (all rivals eliminated) OR Galactic Council election.
//
// Diplomacy: simple four-step relation ladder (War/Neutral/Peace/Alliance).
// ============================================================================

module turn {

  import types.*
  import galaxy.*
  import empire.*
  import combat.*

  // ── Configuration ─────────────────────────────────────────────────────────

  const COUNCIL_POP_THRESHOLD_PCT: int  // % of total pop that opens a session (e.g. 33)
  const SPY_SUCCESS_BASE_PCT:      int  // base % success for a spy mission
  const TURN_LIMIT:                int  // hard cap; prevents infinite games

  // ── State ─────────────────────────────────────────────────────────────────

  var turn:          int
  var phase:         TurnPhase

  // Nested bilateral relation map: relations.get(a).get(b) = A's stance toward B.
  // Kept symmetric via setRelation helper.
  var relations:     EmpireId -> (EmpireId -> Relation)

  var pendingOffers: Set[{ sender: EmpireId, recipient: EmpireId, offer: DiplomaticOffer }]
  var council:       Set[CouncilSession]
  var winner:        Set[VictoryResult]

  // ── Diplomatic helpers ────────────────────────────────────────────────────

  def relationBetween(a: EmpireId, b: EmpireId): Relation =
    if (a == b) { Alliance } else { relations.get(a).get(b) }

  def areAtWar(a: EmpireId, b: EmpireId): bool =
    relationBetween(a, b) == AtWar

  def areAllied(a: EmpireId, b: EmpireId): bool =
    relationBetween(a, b) == Alliance

  // Write rel to both (a→b) and (b→a).
  pure def setRelation(
    r:   EmpireId -> (EmpireId -> Relation),
    a:   EmpireId, b: EmpireId, rel: Relation
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
      pendingOffers' = pendingOffers.union(
        Set({ sender: sender, recipient: recipient, offer: offer })
      ),
      turn'     = turn,   phase'    = phase,
      relations' = relations, council'  = council, winner' = winner
    }
  }

  action resolveOffer(
    o: { sender: EmpireId, recipient: EmpireId, offer: DiplomaticOffer },
    accepted: bool
  ): bool = {
    val cur    = relations.get(o.sender).get(o.recipient)
    val newRel =
      if      (o.offer == DeclareWar)    { AtWar }
      else if (o.offer == OfferPeace)    { if (accepted) { Neutral }  else { cur } }
      else if (o.offer == OfferAlliance) { if (accepted) { Alliance } else { cur } }
      else if (o.offer == BreakAlliance) { Neutral }
      else                               { cur }
    all {
      pendingOffers' = pendingOffers.exclude(Set(o)),
      relations'     = setRelation(relations, o.sender, o.recipient, newRel),
      turn'     = turn,   phase'   = phase,
      council'  = council, winner' = winner
    }
  }

  // ── Spy phase ─────────────────────────────────────────────────────────────

  pure def spySuccessRange(spy: Spy, e: Empire): int =
    if (e.race == Darlok) { SPY_SUCCESS_BASE_PCT + 50 } else { SPY_SUCCESS_BASE_PCT }

  action resolveSpyMission(spyId: SpyId): bool = {
    nondet spy  = spies.filter(s => s.id == spyId).oneOf()
    val owner   = empires.get(spy.owner)
    nondet roll = 1.to(100).oneOf()
    val success = roll <= spySuccessRange(spy, owner)
    all {
      spies' = spies.exclude(Set(spy)).union(Set(
        { ...spy, level: if (success and spy.level < 10) { spy.level + 1 } else { spy.level } }
      )),
      // Other state unchanged by spy resolution.
      empires'       = empires,
      colonies'      = colonies,
      fleets'        = fleets,
      combatRound'   = combatRound,
      relations'     = relations,
      pendingOffers' = pendingOffers,
      council'       = council,
      winner'        = winner,
      turn'          = turn,
      phase'         = phase,
      stars'         = stars
    }
  }

  // ── Galactic Council ──────────────────────────────────────────────────────
  //
  // Triggered when any empire controls ≥ COUNCIL_POP_THRESHOLD_PCT of total pop.
  // Candidate = empire with highest population.
  // Votes = each empire's own population; allies of the candidate vote for them.
  // Win condition: candidate receives ≥ 2/3 of galaxy-wide total population.

  def councilThresholdMet: bool =
    val tot = totalPop
    empires.keys().exists(eid =>
      not(empires.get(eid).eliminated) and
      empirePop(eid) * 100 >= tot * COUNCIL_POP_THRESHOLD_PCT
    )

  // Use −1 as "no empire" sentinel (EmpireId = int).
  def councilCandidate: EmpireId =
    empires.keys()
           .filter(eid => not(empires.get(eid).eliminated))
           .fold(-1, (best, eid) =>
             if (best == -1 or empirePop(eid) > empirePop(best)) { eid } else { best }
           )

  def votesFor(voter: EmpireId, candidate: EmpireId): int =
    if (voter == candidate or areAllied(voter, candidate)) { empirePop(voter) }
    else { 0 }

  def totalVotesForCandidate(candidate: EmpireId): int =
    empires.keys()
           .filter(eid => not(empires.get(eid).eliminated))
           .fold(0, (acc, eid) => acc + votesFor(eid, candidate))

  def hasCouncilMajority(candidate: EmpireId): bool =
    totalVotesForCandidate(candidate) * 3 >= totalPop * 2

  action openCouncilSession: bool = {
    val cand = councilCandidate
    all {
      phase == CouncilPhase,
      council.size() == 0,
      councilThresholdMet,
      council'       = Set({ candidate: cand, votes: empires.keys().mapBy(_ => 0) }),
      turn'          = turn,   phase'         = phase,
      relations'     = relations, pendingOffers' = pendingOffers,
      winner'        = winner,    stars'         = stars,
      empires'       = empires,   colonies'      = colonies,
      fleets'        = fleets,    combatRound'   = combatRound
    }
  }

  action resolveCouncilVote: bool = {
    nondet sesh = council.oneOf()
    if (hasCouncilMajority(sesh.candidate)) {
      all {
        winner'  = Set({ winner: sesh.candidate, kind: CouncilVictory, turnNumber: turn }),
        council' = Set(),
        turn'          = turn,   phase'         = phase,
        relations'     = relations, pendingOffers' = pendingOffers,
        stars'         = stars,     empires'       = empires,
        colonies'      = colonies,  fleets'        = fleets,
        combatRound'   = combatRound
      }
    } else {
      all {
        council' = Set(),
        winner'        = winner,    turn'          = turn,
        phase'         = phase,     relations'     = relations,
        pendingOffers' = pendingOffers, stars'     = stars,
        empires'       = empires,   colonies'      = colonies,
        fleets'        = fleets,    combatRound'   = combatRound
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
    else                             { OrdersPhase }

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

  // ── Victory check ─────────────────────────────────────────────────────────

  def conquestWinner: Set[EmpireId] =
    val alive = empires.keys().filter(eid => not(empires.get(eid).eliminated))
    if (alive.size() == 1) { alive } else { Set() }

  action checkVictory: bool = {
    val cw     = conquestWinner
    val result =
      if (cw.size() > 0) {
        cw.map(eid => { winner: eid, kind: ConquestVictory, turnNumber: turn })
      } else { Set() }
    all {
      winner'        = result,
      turn'          = turn,   phase'         = phase,
      relations'     = relations, pendingOffers' = pendingOffers,
      council'       = council,   stars'         = stars,
      empires'       = empires,   colonies'      = colonies,
      fleets'        = fleets,    combatRound'   = combatRound
    }
  }

  // ── Initialisation ────────────────────────────────────────────────────────

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

  // advanceFleets only touches `fleets` and `combatRound`; stamp the rest.
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
