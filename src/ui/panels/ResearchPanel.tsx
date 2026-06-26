import { useGameStore } from '../../store/gameStore'
import { hasPrerequisite, researchPctDone } from '../../engine/empire'
import { TECH_COST, TECH_FIELD } from '../../engine/constants'
import type { TechName } from '../../types'

const FIELD_ORDER = ['Physics','Biology','Computers','Construction','ForceFields','Planetology']

export function ResearchPanel() {
  const { game, setResearching } = useGameStore()
  if (!game) return null

  const player = game.empires.get(game.playerId)!
  const pctDone = researchPctDone(player)
  const options = game.techOptions.get(game.playerId) ?? []

  return (
    <div className="side-panel">
      <div className="panel-section">
        <div className="panel-title">Research</div>
        <div className="stat-row"><label>Researching</label>
          <span style={{color:'var(--accent2)'}}>{player.researching}</span></div>
        <div className="stat-row"><label>Progress</label>
          <span>{player.rpAccum}/{TECH_COST[player.researching] ?? '?'} RP</span></div>
        <div className="progress-bar">
          <div className="progress-fill" style={{width:`${pctDone}%`}} />
        </div>
      </div>

      {options.length > 0 && (
        <div className="panel-section">
          <div className="panel-title" style={{color:'var(--warn)'}}>Choose Next Tech</div>
          <div className="tech-list">
            {options.map(t => (
              <div key={t} className="tech-item active" onClick={()=>setResearching(t)}>
                {t} <span className="cost">{TECH_COST[t]} RP</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {FIELD_ORDER.map(field => {
        const techs = (Object.keys(TECH_COST) as TechName[])
          .filter(t => TECH_FIELD[t] === field)
          .sort((a, b) => (TECH_COST[a] ?? 0) - (TECH_COST[b] ?? 0))
        return (
          <div key={field} className="panel-section">
            <div className="panel-title">{field}</div>
            <div className="tech-list">
              {techs.map(t => {
                const owned   = player.techs.has(t)
                const active  = player.researching === t && !owned
                const prereq  = hasPrerequisite(player.techs, t)
                const locked  = !prereq && !owned
                return (
                  <div key={t}
                    className={`tech-item ${owned?'owned':active?'active':locked?'locked':''}`}
                    onClick={() => { if (!owned && prereq && !locked) setResearching(t) }}>
                    {owned ? '✓ ' : ''}{t}
                    {!owned && <span className="cost">{TECH_COST[t]}</span>}
                  </div>
                )
              })}
            </div>
          </div>
        )
      })}
    </div>
  )
}
