import { useState } from 'react'
import { useGameStore } from '../../store/gameStore'
import { totalPP, rpFromColony, taxIncome, grossPP, pollutionProduced, missileCap } from '../../engine/empire'
import type { SpendingAlloc, DesignId } from '../../types'

export function StarPanel() {
  const { game, selectFleet, moveFleet, colonise, setSpending, queueShip, dequeueShip } = useGameStore()
  const [activeTab, setActiveTab] = useState<'info'|'colony'|'fleet'>('info')

  if (!game || game.selectedStar === null) {
    return (
      <div className="side-panel">
        <div className="panel-section">
          <div className="panel-title">Galaxy Map</div>
          <p style={{fontSize:10,color:'var(--text-muted)'}}>Click a star to select it.</p>
          <p style={{fontSize:10,color:'var(--text-muted)',marginTop:6}}>
            Scroll to zoom · Drag to pan
          </p>
        </div>
        <LogSection />
      </div>
    )
  }

  const sid    = game.selectedStar
  const sys    = game.stars.get(sid)!
  const colony = game.colonies.find(c => c.star === sid)
  const isOwn  = colony?.owner === game.playerId
  const player = game.empires.get(game.playerId)!

  // Fleets at this star owned by player
  const myFleets = [...game.fleets.values()]
    .filter(f => f.location === sid && f.destination === sid && f.owner === game.playerId)

  // Selected fleet at this star
  const selFleet = game.selectedFleet !== null ? game.fleets.get(game.selectedFleet) : null
  const selHere  = selFleet?.location === sid && selFleet?.owner === game.playerId

  return (
    <div className="side-panel">
      {/* Tabs */}
      <div className="tabs">
        <button className={`tab-btn${activeTab==='info'?' active':''}`} onClick={()=>setActiveTab('info')}>Star</button>
        {colony && <button className={`tab-btn${activeTab==='colony'?' active':''}`} onClick={()=>setActiveTab('colony')}>Colony</button>}
        {myFleets.length>0 && <button className={`tab-btn${activeTab==='fleet'?' active':''}`} onClick={()=>setActiveTab('fleet')}>Fleets</button>}
      </div>

      {activeTab === 'info' && <StarInfoTab sid={sid} />}
      {activeTab === 'colony' && colony && isOwn && <ColonyTab sid={sid} />}
      {activeTab === 'fleet' && <FleetTab sid={sid} />}

      <LogSection />
    </div>
  )
}

// ── Star Info ─────────────────────────────────────────────────────────────
function StarInfoTab({ sid }: { sid: number }) {
  const { game, moveFleet, colonise } = useGameStore()
  if (!game) return null
  const sys    = game.stars.get(sid)!
  const colony = game.colonies.find(c => c.star === sid)
  const player = game.empires.get(game.playerId)!

  const selFleet = game.selectedFleet !== null ? game.fleets.get(game.selectedFleet) : null
  const selOwn   = selFleet?.owner === game.playerId
  const canMove  = selOwn && selFleet!.location !== sid

  const richLabels = ['Ultra Poor','Poor','Adequate','Rich','Ultra Rich']

  return (
    <div className="panel-section">
      <div className="panel-title">{sys.name}</div>
      <div className="stat-row"><label>Class</label><span>{sys.class_}</span></div>
      <div className="stat-row"><label>World</label><span style={{color:sys.planetType==='Barren'?'var(--text-muted)':undefined}}>{sys.planetType}</span></div>
      {sys.planetType !== 'Barren' && <>
        <div className="stat-row"><label>Size</label><span>{sys.size}</span></div>
        <div className="stat-row"><label>Richness</label><span>{richLabels[sys.richness]}</span></div>
        <div className="stat-row"><label>Max Pop</label><span>{sys.maxPopBase}M</span></div>
      </>}

      {colony && (
        <div style={{marginTop:8}}>
          <div className="stat-row">
            <label>Owner</label>
            <span style={{color:'#'+(game.empires.get(colony.owner)!.color.toString(16).padStart(6,'0'))}}>
              {game.empires.get(colony.owner)!.race}
            </span>
          </div>
          <div className="stat-row"><label>Pop</label><span>{colony.population}M / {colony.maxPop}M</span></div>
          <div className="stat-row"><label>Factories</label><span>{colony.factories}/{colony.maxFactories}</span></div>
        </div>
      )}

      {canMove && (
        <button className="btn" style={{marginTop:8,width:'100%'}}
          onClick={()=>moveFleet(game.selectedFleet!, sid)}>
          MOVE FLEET HERE
        </button>
      )}
      {selOwn && selFleet!.location === sid &&
       !colony && sys.planetType !== 'Barren' &&
       selFleet!.ships.some(s => game.designs.get(s.design)!.hull === 'ColonyShip') && (
        <button className="btn" style={{marginTop:8,width:'100%'}}
          onClick={()=>colonise(game.selectedFleet!)}>
          FOUND COLONY
        </button>
      )}
    </div>
  )
}

// ── Colony management ─────────────────────────────────────────────────────
function ColonyTab({ sid }: { sid: number }) {
  const { game, setSpending, queueShip, dequeueShip } = useGameStore()
  if (!game) return null

  const colony = game.colonies.find(c => c.star === sid)!
  const sys    = game.stars.get(sid)!
  const player = game.empires.get(game.playerId)!
  const pp     = totalPP(player, colony, sys)
  const rp     = rpFromColony(player, colony, sys)
  const poll   = pollutionProduced(player, colony)

  function handleSlider(key: keyof SpendingAlloc, val: number) {
    const s = { ...colony.spending, [key]: val }
    const keys: (keyof SpendingAlloc)[] = ['ships','defense','industry','ecology','research']
    const others = keys.filter(k => k !== key)
    const total  = Object.values(s).reduce((a: number, v: number) => a + v, 0)
    const diff   = total - 100
    // Distribute diff across others proportionally
    let rem = diff
    for (const k of others) {
      if (rem === 0) break
      const adj = rem > 0 ? -1 : 1
      if (s[k] - adj >= 0 && s[k] - adj <= 100) { s[k] -= adj; rem -= adj > 0 ? -1 : 1 }
    }
    const finalTotal = (Object.values(s) as number[]).reduce((a,v)=>a+v,0)
    if (finalTotal === 100) setSpending(sid, s)
  }

  const playerDesigns = [...game.designs.values()].filter(d => d.owner === game.playerId)

  return (
    <div>
      <div className="panel-section">
        <div className="panel-title">Colony — {sys.name}</div>
        <div className="stat-row"><label>Pop</label><span>{colony.population}M / {colony.maxPop}M</span></div>
        <div className="stat-row"><label>Factories</label><span>{colony.factories} / {colony.maxFactories}</span></div>
        <div className="stat-row"><label>Gross PP</label><span>{pp} / turn</span></div>
        <div className="stat-row"><label>Research</label><span>+{rp} RP</span></div>
        <div className="stat-row"><label>Pollution</label><span style={{color:poll>2?'var(--warn)':undefined}}>{colony.pollution}</span></div>
        <div className="stat-row"><label>Missile Bases</label><span>{colony.missileBases}/{missileCap(colony)}</span></div>
      </div>

      <div className="panel-section">
        <div className="panel-title">Production</div>
        <div className="slider-group">
          {(['ships','defense','industry','ecology','research'] as (keyof SpendingAlloc)[]).map(k => (
            <div className="slider-row" key={k}>
              <label>{k}</label>
              <input type="range" min="0" max="100" step="5"
                value={colony.spending[k]}
                onChange={e => handleSlider(k, +e.target.value)} />
              <span className="val">{colony.spending[k]}%</span>
            </div>
          ))}
          <div className="stat-row" style={{marginTop:4}}>
            <label>Total</label>
            <span style={{color:(Object.values(colony.spending) as number[]).reduce((a,v)=>a+v,0)!==100?'var(--danger)':undefined}}>
              {(Object.values(colony.spending) as number[]).reduce((a,v)=>a+v,0)}%
            </span>
          </div>
        </div>
      </div>

      <div className="panel-section">
        <div className="panel-title">Ship Queue</div>
        <div className="build-queue">
          {colony.buildQueue.map((did, i) => {
            const d = game.designs.get(did)
            return d ? (
              <div className="queue-item" key={i}>
                <span>{d.hull}</span>
                <span>
                  {i === 0 ? `${colony.ppAccrued}/${d.cost} PP` : `${d.cost} PP`}
                  <span className="remove" onClick={()=>dequeueShip(sid,i)}>✕</span>
                </span>
              </div>
            ) : null
          })}
          {colony.buildQueue.length === 0 && (
            <span style={{fontSize:10,color:'var(--text-muted)'}}>No ships queued</span>
          )}
        </div>
        <div style={{marginTop:6,display:'flex',flexWrap:'wrap',gap:4}}>
          {playerDesigns.map(d => (
            <button key={d.id} className="btn" style={{fontSize:9,padding:'3px 8px'}}
              onClick={()=>queueShip(sid, d.id)}>
              +{d.hull}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}

// ── Fleet list at star ────────────────────────────────────────────────────
function FleetTab({ sid }: { sid: number }) {
  const { game, selectFleet, moveFleet, bombard } = useGameStore()
  if (!game) return null

  const myFleets = [...game.fleets.values()]
    .filter(f => f.location === sid && f.destination === sid && f.owner === game.playerId)

  return (
    <div className="panel-section">
      <div className="panel-title">Fleets at {game.stars.get(sid)!.name}</div>
      {myFleets.map(f => {
        const totalHp  = f.ships.reduce((a, s) => a + s.currentHp, 0)
        const maxHp    = f.ships.reduce((a, s) => a + s.maxHp, 0)
        const hulls    = f.ships.map(s => game.designs.get(s.design)!.hull).join(', ')
        const isSelected = game.selectedFleet === f.id
        return (
          <div key={f.id}
            className={`fleet-item${isSelected?' sel':''}`}
            onClick={()=>selectFleet(isSelected ? null : f.id)}>
            <div style={{fontWeight:'bold',fontSize:10}}>{hulls}</div>
            <div style={{fontSize:9,color:'var(--text-muted)'}}>HP: {totalHp}/{maxHp}</div>
            {isSelected && (
              <div style={{marginTop:4,display:'flex',gap:4}}>
                <button className="btn danger" style={{fontSize:9,padding:'2px 6px'}}
                  onClick={e=>{e.stopPropagation();bombard(f.id)}}>
                  BOMBARD
                </button>
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}

// ── Event log ─────────────────────────────────────────────────────────────
function LogSection() {
  const { game } = useGameStore()
  if (!game) return null
  return (
    <div className="panel-section" style={{marginTop:'auto'}}>
      <div className="panel-title">Log</div>
      <div className="log-list">
        {[...game.log].reverse().slice(0, 12).map((msg, i) => (
          <p key={i}>{msg}</p>
        ))}
      </div>
    </div>
  )
}
