import { Component, type ErrorInfo, type ReactNode, useEffect, useRef, useState } from 'react'
import { useGameStore } from '../store/gameStore'
import { GalaxyMapRenderer } from '../renderer/GalaxyMap'
import { TopBar } from './hud/TopBar'
import { StarPanel } from './panels/StarPanel'
import { ResearchPanel } from './panels/ResearchPanel'
import type { Race } from '../types'
import { ALL_RACES } from '../types'

type SideTab = 'star' | 'research'

// ── Error Boundary ────────────────────────────────────────────────────────
class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null }
  static getDerivedStateFromError(error: Error) { return { error } }
  componentDidCatch(error: Error, info: ErrorInfo) { console.error('Render error:', error, info) }
  render() {
    if (this.state.error) {
      return (
        <div style={{padding:20,background:'#300',color:'#f88',fontFamily:'monospace',whiteSpace:'pre-wrap'}}>
          <strong>Game Error:</strong>{'\n'}
          {(this.state.error as Error).message}{'\n\n'}
          {(this.state.error as Error).stack}
        </div>
      )
    }
    return this.props.children
  }
}

// ── New Game Screen ───────────────────────────────────────────────────────
function NewGameScreen({ onStart }: { onStart: () => void }) {
  const { newGame } = useGameStore()
  const [race, setRace]       = useState<Race>('Humans')
  const [rivals, setRivals]   = useState(3)
  const [size, setSize]       = useState(36)

  function start() {
    newGame({ playerRace: race, numEmpires: rivals + 1, numStars: size })
    onStart()
  }

  return (
    <div className="new-game">
      <h1>GALACTIC EXPANSE</h1>
      <p>A 4X space strategy game</p>

      <div className="form-row">
        <label>Your Race</label>
        <select value={race} onChange={e => setRace(e.target.value as Race)}>
          {ALL_RACES.map(r => <option key={r} value={r}>{r}</option>)}
        </select>
      </div>

      <div className="form-row">
        <label>Rival Empires ({rivals})</label>
        <input type="range" min="1" max="7" value={rivals}
          onChange={e => setRivals(+e.target.value)} />
      </div>

      <div className="form-row">
        <label>Galaxy Size</label>
        <select value={size} onChange={e => setSize(+e.target.value)}>
          <option value={24}>Small (24 stars)</option>
          <option value={36}>Medium (36 stars)</option>
          <option value={54}>Large (54 stars)</option>
          <option value={108}>Huge (108 stars)</option>
        </select>
      </div>

      <button className="btn" style={{marginTop:8,padding:'10px 40px',fontSize:13}} onClick={start}>
        LAUNCH GAME
      </button>
    </div>
  )
}

// ── Victory Overlay ───────────────────────────────────────────────────────
function VictoryOverlay({ onNewGame }: { onNewGame: () => void }) {
  const { game } = useGameStore()
  if (!game?.winner) return null
  const winner = game.empires.get(game.winner.winner)!
  const isPlayer = game.winner.winner === game.playerId
  return (
    <div className="overlay">
      <h1>{isPlayer ? '🏆 VICTORY!' : '💀 DEFEATED'}</h1>
      <p>{winner.race} wins by {game.winner.kind.replace('Victory','')} on turn {game.winner.turnNumber}</p>
      <button className="btn" onClick={onNewGame}>NEW GAME</button>
    </div>
  )
}

// ── Main App ──────────────────────────────────────────────────────────────
export function App() {
  const { game, selectStar, selectFleet } = useGameStore()
  const mapRef      = useRef<HTMLDivElement>(null)
  const rendererRef = useRef<GalaxyMapRenderer | null>(null)
  const [started, setStarted] = useState(false)
  const [sideTab, setSideTab] = useState<SideTab>('star')

  // Init renderer once game starts
  useEffect(() => {
    if (!started || !game || !mapRef.current) return
    if (rendererRef.current) return  // already initialised

    try {
      const renderer = new GalaxyMapRenderer(
        mapRef.current,
        id => { selectStar(id); setSideTab('star') },
        id => selectFleet(id),
      )
      rendererRef.current = renderer
      renderer.render(game)
      // Delay fitToScreen until after first paint to ensure container has size
      requestAnimationFrame(() => renderer.fitToScreen())
    } catch (e) {
      console.error('PixiJS init failed:', e)
    }

    return () => {
      rendererRef.current?.destroy()
      rendererRef.current = null
    }
  }, [started])

  // Re-render on state changes
  useEffect(() => {
    if (game && rendererRef.current) {
      rendererRef.current.render(game)
    }
  }, [game])

  // Resize handler
  useEffect(() => {
    const onResize = () => rendererRef.current?.resize()
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [])

  if (!started) {
    return (
      <div className="app">
        <NewGameScreen onStart={() => setStarted(true)} />
      </div>
    )
  }

  if (!game) return null

  return (
    <ErrorBoundary>
      <div className="app">
        <TopBar />
        <div className="main-area">
          <div className="map-container" ref={mapRef} />

          <div className="side-panel" style={{borderLeft:'1px solid var(--panel-border)'}}>
            <div className="tabs">
              <button className={`tab-btn${sideTab==='star'?' active':''}`}    onClick={()=>setSideTab('star')}>Map</button>
              <button className={`tab-btn${sideTab==='research'?' active':''}`} onClick={()=>setSideTab('research')}>Science</button>
            </div>
            <div style={{flex:1,overflowY:'auto',display:'flex',flexDirection:'column'}}>
              {sideTab === 'star'     && <StarPanel />}
              {sideTab === 'research' && <ResearchPanel />}
            </div>
          </div>

          <VictoryOverlay onNewGame={() => setStarted(false)} />
        </div>
      </div>
    </ErrorBoundary>
  )
}
