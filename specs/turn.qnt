// ============================================================================
// turn.qnt — Galactic Expanse: master turn state machine (MOO1 model)
//
// Phase 1 additions vs previous version:
//   • contacts state variable — tracks which pairs of empires have met (Gap 20)
//   • updateContacts — establishes contact when fleets share a star (Gap 20)
//   • deductShipUpkeep — subtracts per-ship maintenance BC each turn (Gap 11)
//   • collectTradeIncome — trade BC between contacted, non-hostile empires (Gap 10)
//   • OrdersPhase note — all empires submit orders simultaneously before
//     ProductionPhase resolution begins (Gap 1)
//
// Orders phase simultaneity: the spec models OrdersPhase as a window during
// which any empire can execute any OrdersPhase action.  The browser engine
// enforces that the phase does not advance until every living empire has
// confirmed their orders; this is an implementation constraint, not a formal
// state constraint (adding it to the spec would require modelling per-empire
// order-submission flags, which adds complexity without changing invariants).
// ============================================================================

module turn {

  import types.*
  import galaxy.*
  import empire.*
  import combat.*

  // ── Configuration ─────────────────────────────────────────────────────────

  const COUNCIL_POP_THRESHOLD_PCT: int   // % of total pop that opens a council session
  const SPY_SUCCESS_BASE_PCT:      int
  const TURN_LIMIT:                int

  // ── State ─────────────────────────────────────────────────────────────────

  var turn:          int
  var phase:         TurnPhase
  var relations:     EmpireId -> (EmpireId -> Relation)
  var pendingOffers: Set[{ sender: EmpireId, recipient: EmpireId, offer: DiplomaticOffer }]
  var council:       Set[CouncilSession]
  var winner:        Set[VictoryResult]

  // Gap 20: bilateral contact tracking.
  // contacts.get(a) is the set of empire IDs that empire A has made contact with.
  // Contacts are established whenever fleets from two empires share the same star.
  // Contact is required for trade income, diplomacy offers, and council votes.
  var contacts: EmpireId -> Set[EmpireId]

  // ── Contact helpers ───────────────────────────────────────────────────────

  def areInContact(a: EmpireId, b: EmpireId): bool =
    contacts.get(a).contains(b)

  // Establish bilateral contact between two empires.
  pure def addContact(
    c:   EmpireId -> Set[EmpireId],
    a:   EmpireId,
    b:   EmpireId
  ): EmpireId -> Set[EmpireId] =
    c.put(a, c.get(a).union(Set(b)))
     .put(b, c.get(b).union(Set(a)))

  // Scan all stars: wherever two different empires both have fleets, establish contact.
  // Also establishes contact when a fleet arrives at a star with an enemy colony.
  action updateContacts: bool = {
    val newContacts =
      stars.keys().fold(contacts, (acc, sid) => {
        val owners = fleetsAtStar(sid).map(fid => fleets.get(fid).owner)
        // Add contacts for all pairs of owners at this star.
        val pairsAdded = owners.fold(acc, (acc2, a) =>
          owners.filter(b => b != a).fold(acc2, (acc3, b) => addContact(acc3, a, b))
        )
        // Fleet owner meets the colony owner at this star (if any).
        colonies.filter(c => c.star == sid).fold(pairsAdded, (acc2, c) =>
          owners.fold(acc2, (acc3, fleetOwner) =>
            if (fleetOwner != c.owner) { addContact(acc3, fleetOwner, c.owner) }
            else { acc3 }
          )
        )
      })
    // Also propagate contacts to Empire.contacts field.
    val newEmpires = empires.keys().fold(empires, (acc, eid) =>
      acc.put(eid, { ...acc.get(eid), contacts: newContacts.get(eid) })
    )
    all {
      contacts'      = newContacts,
      empires'       = newEmpires,
      colonies'      = colonies,
      techOptions'   = techOptions,
      fleets'        = fleets,
      combatRound'   = combatRound,
      stars'         = stars,
      relations'     = relations,
      pendingOffers' = pendingOffers,
      council'       = council,
      winner'        = winner,
      turn'          = turn,
      phase'         = phase
    }
  }

  // ── Diplomatic helpers ────────────────────────────────────────────────────

  def relationBetween(a: EmpireId, b: EmpireId): Relation =
    if (a == b) { Alliance } else { relations.get(a).get(b) }

  def areAtWar(a: EmpireId, b: EmpireId): bool =
    relationBetween(a, b) == AtWar

  def areAllied(a: EmpireId, b: EmpireId): bool =
    relationBetween(a, b) == Alliance

  pure def setRelation(
    r: EmpireId -> (EmpireId -> Relation),
    a: EmpireId, b: EmpireId, rel: Relation
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
      areInContact(sender, recipient),   // can only offer to empires you have met
      pendingOffers' = pendingOffers.union(
        Set({ sender: sender, recipient: recipient, offer: offer })
      ),
      turn'          = turn,   phase'         = phase,
      relations'     = relations, contacts'  = contacts,
      council'       = council,   winner'    = winner,
      empires'       = empires,   colonies'  = colonies,
      techOptions'   = techOptions, fleets'  = fleets,
      combatRound'   = combatRound, stars'   = stars
    }
  }

  action resolveOffer(
    o:        { sender: EmpireId, recipient: EmpireId, offer: DiplomaticOffer },
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
      turn'          = turn,   phase'       = phase,
      contacts'      = contacts, council'   = council,  winner'    = winner,
      empires'       = empires,   colonies' = colonies,
      techOptions'   = techOptions, fleets' = fleets,
      combatRound'   = combatRound, stars'  = stars
    }
  }

  // ── Ship upkeep (Gap 11) ──────────────────────────────────────────────────
  //
  // Each turn every empire pays BC equal to the sum of upkeep costs for all
  // its ships.  If an empire cannot pay (bc < upkeep total), it pays what it
  // can and goes to 0 BC; the engine may then auto-scrap ships in order of
  // highest upkeep first until balanced.  The spec models the deduction only.

  def totalUpkeep(eid: EmpireId, designs: DesignId -> ShipDesign): int =
    empiresFleets(eid).fold(0, (acc, fid) =>
      acc + fleets.get(fid).ships.foldl(0, (a2, s) => a2 + designs.get(s.design).upkeep)
    )

  action deductShipUpkeep(eid: EmpireId, designs: DesignId -> ShipDesign): bool = {
    val e      = empires.get(eid)
    val cost   = totalUpkeep(eid, designs)
    val newBc  = if (e.bc - cost < 0) { 0 } else { e.bc - cost }
    all {
      empires'       = empires.put(eid, { ...e, bc: newBc }),
      colonies'      = colonies,
      techOptions'   = techOptions,
      fleets'        = fleets,
      combatRound'   = combatRound,
      stars'         = stars,
      relations'     = relations,
      pendingOffers' = pendingOffers,
      contacts'      = contacts,
      council'       = council,
      winner'        = winner,
      turn'          = turn,
      phase'         = phase
    }
  }

  // ── Trade income (Gap 10) ─────────────────────────────────────────────────
  //
  // Empires that are in contact and not at war earn mutual trade income each
  // turn.  We credit the income to the empire once per contacted pair (the
  // loop in the engine ensures each pair is processed exactly once).

  action collectTradeIncome(eid: EmpireId): bool = {
    val e       = empires.get(eid)
    val tradeBC = contacts.get(eid)
                    .filter(other =>
                      not(areAtWar(eid, other)) and
                      not(empires.get(other).eliminated)
                    )
                    .fold(0, (acc, other) =>
                      acc + tradeIncomePair(e, empirePop(other))
                    )
    all {
      empires'       = empires.put(eid, { ...e, bc: e.bc + tradeBC }),
      colonies'      = colonies,
      techOptions'   = techOptions,
      fleets'        = fleets,
      combatRound'   = combatRound,
      stars'         = stars,
      relations'     = relations,
      pendingOffers' = pendingOffers,
      contacts'      = contacts,
      council'       = council,
      winner'        = winner,
      turn'          = turn,
      phase'         = phase
    }
  }

  // ── Spy phase ─────────────────────────────────────────────────────────────

  pure def spySuccessRange(spy: Spy, e: Empire): int =
    SPY_SUCCESS_BASE_PCT + spyBonus(e.race)

  action resolveSpyMission(spyId: SpyId): bool = {
    nondet spy  = spies.filter(s => s.id == spyId).oneOf()
    val owner   = empires.get(spy.owner)
    nondet roll = 1.to(100).oneOf()
    val success = roll <= spySuccessRange(spy, owner)
    all {
      spies' = spies.exclude(Set(spy)).union(Set(
        { ...spy, level: if (success and spy.level < 10) { spy.level + 1 } else { spy.level } }
      )),
      empires'       = empires,
      colonies'      = colonies,
      techOptions'   = techOptions,
      fleets'        = fleets,
      combatRound'   = combatRound,
      relations'     = relations,
      pendingOffers' = pendingOffers,
      contacts'      = contacts,
      council'       = council,
      winner'        = winner,
      turn'          = turn,
      phase'         = phase,
      stars'         = stars
    }
  }

  // ── Galactic Council ──────────────────────────────────────────────────────

  def councilThresholdMet: bool =
    val tot = totalPop
    empires.keys().exists(eid =>
      not(empires.get(eid).eliminated) and
      empirePop(eid) * 100 >= tot * COUNCIL_POP_THRESHOLD_PCT
    )

  def councilCandidate: EmpireId =
    empires.keys()
           .filter(eid => not(empires.get(eid).eliminated))
           .fold(-1, (best, eid) =>
             if (best == -1 or empirePop(eid) > empirePop(best)) { eid } else { best }
           )

  def votesFor(voter: EmpireId, candidate: EmpireId): int =
    // Only empires in contact with the candidate can vote.
    if (not(areInContact(voter, candidate)) and voter != candidate) { 0 }
    else if (voter == candidate or areAllied(voter, candidate)) { empirePop(voter) }
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
      contacts'      = contacts,  winner'        = winner,
      stars'         = stars,     empires'       = empires,
      colonies'      = colonies,  techOptions'   = techOptions,
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
        contacts'      = contacts,  stars'         = stars,
        empires'       = empires,   colonies'      = colonies,
        techOptions'   = techOptions, fleets'      = fleets,
        combatRound'   = combatRound
      }
    } else {
      all {
        council' = Set(),
        winner'        = winner,    turn'          = turn,
        phase'         = phase,     relations'     = relations,
        pendingOffers' = pendingOffers, contacts'  = contacts,
        stars'         = stars,     empires'       = empires,
        colonies'      = colonies,  techOptions'   = techOptions,
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
      techOptions'   = techOptions,
      fleets'        = fleets,
      combatRound'   = if (np == CombatPhase) { 0 } else { combatRound },
      relations'     = relations,
      pendingOffers' = pendingOffers,
      contacts'      = contacts,
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
    val result = if (cw.size() > 0) {
      cw.map(eid => { winner: eid, kind: ConquestVictory, turnNumber: turn })
    } else { Set() }
    all {
      winner'        = result,
      turn'          = turn,   phase'         = phase,
      relations'     = relations, pendingOffers' = pendingOffers,
      contacts'      = contacts,  council'       = council,
      stars'         = stars,     empires'       = empires,
      colonies'      = colonies,  techOptions'   = techOptions,
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
      relations'     = empireIds.mapBy(_ => neutralInner),
      contacts'      = empireIds.mapBy(_ => Set()),
      // techOptions seeded empty for all empires.
      techOptions'   = empireIds.mapBy(_ => Set())
    }
  }

  // ── Top-level step ────────────────────────────────────────────────────────

  action stepMovement: bool =
    all {
      phase == MovementPhase,
      advanceFleets,
      stars'         = stars,
      empires'       = empires,
      colonies'      = colonies,
      techOptions'   = techOptions,
      turn'          = turn,
      phase'         = phase,
      relations'     = relations,
      pendingOffers' = pendingOffers,
      contacts'      = contacts,
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

  val invTurnPositive: bool = turn >= 1

  val invTurnBounded: bool = turn <= TURN_LIMIT + 1

  val invAtMostOneWinner: bool = winner.size() <= 1

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

  val invContactSymmetry: bool =
    empires.keys().forall(a =>
      contacts.get(a).forall(b => contacts.get(b).contains(a))
    )

  val invDiplomacyRequiresContact: bool =
    pendingOffers.forall(o => areInContact(o.sender, o.recipient))

  val invPendingOffersValid: bool =
    pendingOffers.forall(o =>
      empires.keys().contains(o.sender) and
      empires.keys().contains(o.recipient) and
      o.sender != o.recipient
    )

  val invAtMostOneCouncilSession: bool = council.size() <= 1

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
