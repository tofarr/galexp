import { useGameStore } from '../../store/gameStore'
import { researchPctDone } from '../../engine/empire'

export function TopBar() {
  const { game, endTurn } = useGameStore()
  if (!game) return null

  const player = game.empires.get(game.playerId)!
  const myPop  = game.colonies.filter(c => c.owner === game.playerId)
                              .reduce((a, c) => a + c.population, 0)
  const rpPct  = researchPctDone(player)

  return (
    <div className="hud">
      <span className="hud-title">GALACTIC EXPANSE</span>

      <div className="hud-stat">
        <label>Turn</label>
        <span>{game.turn}</span>
      </div>
      <div className="hud-stat">
        <label>BC</label>
        <span style={{ color: player.bc < 20 ? '#ff4444' : undefined }}>{player.bc}</span>
      </div>
      <div className="hud-stat">
        <label>Pop</label>
        <span>{myPop}M</span>
      </div>
      <div className="hud-stat">
        <label>Race</label>
        <span style={{ fontSize: 11 }}>{player.race}</span>
      </div>
      <div className="hud-stat" title={`Researching: ${player.researching}`}>
        <label>Research</label>
        <span>{rpPct}%</span>
      </div>

      <div className="hud-spacer" />
      <span className="hud-phase">{game.phase.replace('Phase','').toUpperCase()}</span>
      <button className="btn" onClick={endTurn} disabled={!!game.winner}>
        END TURN
      </button>
    </div>
  )
}
