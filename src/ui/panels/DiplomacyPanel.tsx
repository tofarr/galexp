import { useGameStore } from '../../store/gameStore'
import { tradeIncomePair } from '../../engine/empire'

export function DiplomacyPanel() {
  const { game, declareWar, proposePeace } = useGameStore()
  if (!game) return null

  const pid    = game.playerId
  const player = game.empires.get(pid)!
  const known  = [...player.contacts]

  const myPop = game.colonies
    .filter(c => c.owner === pid)
    .reduce((a, c) => a + c.population, 0)

  return (
    <div>
      <div className="panel-section">
        <div className="panel-title">Diplomatic Relations</div>
        {known.length === 0 && (
          <p style={{ fontSize: 10, color: 'var(--text-muted)', lineHeight: 1.6 }}>
            No contacts yet.<br />
            Send scouts to explore and establish first contact.
          </p>
        )}
      </div>

      {known.map(eid => {
        const emp = game.empires.get(eid)
        if (!emp || emp.eliminated) return (
          <div key={eid} className="panel-section diplo-row">
            <div style={{ color: 'var(--text-muted)', fontSize: 11 }}>
              Empire {eid} — <em>eliminated</em>
            </div>
          </div>
        )

        const rel    = game.relations.get(pid)?.get(eid) ?? 'Neutral'
        const empCol = '#' + emp.color.toString(16).padStart(6, '0')
        const oPop   = game.colonies
          .filter(c => c.owner === eid)
          .reduce((a, c) => a + c.population, 0)
        const trade  = rel !== 'AtWar' ? tradeIncomePair(player, myPop, oPop) : 0
        const oCols  = game.colonies.filter(c => c.owner === eid).length

        const relColor = rel === 'AtWar' ? 'var(--danger)'
                       : rel === 'Alliance' ? 'var(--success)'
                       : 'var(--text-muted)'

        return (
          <div key={eid} className="panel-section diplo-row">
            {/* Empire header */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
              <span style={{ color: empCol, fontWeight: 'bold', fontSize: 12, letterSpacing: 1 }}>
                {emp.race}
              </span>
              <span style={{ color: relColor, fontSize: 10, letterSpacing: 1 }}>
                {rel.toUpperCase()}
              </span>
            </div>

            {/* Empire stats */}
            <div className="stat-row">
              <label>Colonies</label>
              <span>{oCols}</span>
            </div>
            <div className="stat-row">
              <label>Population</label>
              <span>{oPop}M</span>
            </div>
            {trade > 0 && (
              <div className="stat-row">
                <label>Trade income</label>
                <span style={{ color: 'var(--success)' }}>+{trade} BC/turn</span>
              </div>
            )}

            {/* Action buttons */}
            <div style={{ display: 'flex', gap: 4, marginTop: 8 }}>
              {rel !== 'AtWar' && (
                <button
                  className="btn danger"
                  style={{ flex: 1, fontSize: 9, padding: '4px 6px' }}
                  onClick={() => declareWar(eid)}>
                  DECLARE WAR
                </button>
              )}
              {rel === 'AtWar' && (
                <button
                  className="btn warn"
                  style={{ flex: 1, fontSize: 9, padding: '4px 6px' }}
                  onClick={() => proposePeace(eid)}>
                  PROPOSE PEACE
                </button>
              )}
              {rel === 'Alliance' && (
                <span style={{ fontSize: 9, color: 'var(--success)' }}>✓ Allied</span>
              )}
            </div>
          </div>
        )
      })}

      {/* Empire scores summary */}
      {known.length > 0 && (
        <div className="panel-section">
          <div className="panel-title">Empire Scores</div>
          {[pid, ...known]
            .map(eid => {
              const e = game.empires.get(eid)
              if (!e || e.eliminated) return null
              const pop = game.colonies.filter(c => c.owner === eid).reduce((a, c) => a + c.population, 0)
              const cols = game.colonies.filter(c => c.owner === eid).length
              const col = '#' + e.color.toString(16).padStart(6, '0')
              return (
                <div key={eid} style={{ display: 'flex', justifyContent: 'space-between',
                  fontSize: 10, marginBottom: 3, alignItems: 'center' }}>
                  <span style={{ color: eid === pid ? 'var(--accent2)' : col }}>
                    {e.race}{eid === pid ? ' ★' : ''}
                  </span>
                  <span style={{ color: 'var(--text-muted)' }}>
                    {cols} col · {pop}M pop
                  </span>
                </div>
              )
            })}
        </div>
      )}
    </div>
  )
}
