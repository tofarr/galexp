import { useRef, useState, useEffect, useMemo, useCallback } from 'react'
import { useGameStore } from '../store/gameStore'
import { distSq } from '../engine/galaxy'
import type { StarId, FleetId } from '../types'

const STAR_FILL: Record<string, string> = {
  Blue: '#6699ff', White: '#ffffff', Yellow: '#ffee88',
  Orange: '#ff9944', Red: '#ff5533', Neutron: '#99ccee', BlackHole: '#aa44cc',
}
const STAR_R: Record<string, number> = {
  Blue: 3.5, White: 3.0, Yellow: 2.8, Orange: 2.5,
  Red: 2.2, Neutron: 1.8, BlackHole: 2.0,
}

// Deterministic starfield background (seeded)
function seededRng(seed: number) {
  let s = seed >>> 0
  return () => {
    s = Math.imul(s + 0x6D2B79F5, 1) | 0
    let t = Math.imul(s ^ (s >>> 15), 1 | s)
    t = t + Math.imul(t ^ (t >>> 7), 61 | t) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

interface Props {
  onStarClick:  (id: StarId)  => void
  onFleetClick: (id: FleetId) => void
}

export function GalaxyMapSVG({ onStarClick, onFleetClick }: Props) {
  const { game } = useGameStore()
  const svgRef   = useRef<SVGSVGElement>(null)

  // { x, y } = pan offset in screen px; s = pixels per game unit
  const [tr, setTr] = useState({ x: 0, y: 0, s: 8 })
  const trRef = useRef(tr)
  trRef.current = tr  // always current without stale-closure issues

  const drag = useRef<{ ox: number; oy: number; tx: number; ty: number } | null>(null)

  // ── Static starfield (computed once, seeded) ──────────────────────────────
  const bgStars = useMemo(() => {
    const rng = seededRng(0xc0ffee42)
    return Array.from({ length: 380 }, () => ({
      x: rng() * 100, y: rng() * 100,
      r: rng() * 0.3 + 0.1, a: rng() * 0.35 + 0.08,
    }))
  }, [])

  // ── Fit galaxy to viewport on new game ───────────────────────────────────
  useEffect(() => {
    if (!game || !svgRef.current) return
    const svg = svgRef.current
    const w = svg.clientWidth || svg.getBoundingClientRect().width
    const h = svg.clientHeight || svg.getBoundingClientRect().height
    if (w < 10 || h < 10) return

    const coords = [...game.stars.values()].map(s => s.coords)
    const xs = coords.map(c => c.x), ys = coords.map(c => c.y)
    const [x0, x1] = [Math.min(...xs), Math.max(...xs)]
    const [y0, y1] = [Math.min(...ys), Math.max(...ys)]
    const pad  = 16
    const scale = Math.min(w / (x1 - x0 + pad * 2), h / (y1 - y0 + pad * 2)) * 0.9
    setTr({
      s: scale,
      x: (w  - (x0 + x1) * scale) / 2,
      y: (h  - (y0 + y1) * scale) / 2,
    })
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [game?.stars.size])

  // ── Zoom toward cursor ────────────────────────────────────────────────────
  const onWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault()
    const f  = e.deltaY < 0 ? 1.12 : 0.89
    const svg = svgRef.current
    if (!svg) return
    const r  = svg.getBoundingClientRect()
    const mx = e.clientX - r.left, my = e.clientY - r.top
    setTr(t => {
      const ns = Math.max(1.5, Math.min(80, t.s * f))
      return { s: ns, x: mx - (mx - t.x) * (ns / t.s), y: my - (my - t.y) * (ns / t.s) }
    })
  }, [])

  // ── Drag pan ──────────────────────────────────────────────────────────────
  const onMouseDown = useCallback((e: React.MouseEvent) => {
    drag.current = { ox: e.clientX, oy: e.clientY, tx: trRef.current.x, ty: trRef.current.y }
  }, [])
  const onMouseMove = useCallback((e: React.MouseEvent) => {
    if (!drag.current) return
    const { ox, oy, tx, ty } = drag.current
    setTr(t => ({ ...t, x: tx + (e.clientX - ox), y: ty + (e.clientY - oy) }))
  }, [])
  const onMouseUp = useCallback(() => { drag.current = null }, [])

  // ── Early return (after all hooks) ───────────────────────────────────────
  if (!game) return (
    <svg ref={svgRef} style={{ width: '100%', height: '100%', display: 'block', background: '#010810' }}>
      <text x="50%" y="50%" textAnchor="middle" fill="#4a6880" fontFamily="monospace" fontSize={12}>
        No game loaded
      </text>
    </svg>
  )

  const pid = game.playerId
  const { x: px, y: py, s } = tr

  // Screen coordinate helpers
  const sx = (gx: number) => px + gx * s
  const sy = (gy: number) => py + gy * s

  // Star body radius (screen px)
  const srad = (cls: string) => Math.max(2.5, (STAR_R[cls] ?? 2.5) * s / 7)

  // Label font size (clamp so labels stay readable)
  const lblPx = Math.min(13, Math.max(7, s * 0.75))
  // Fleet triangle half-size
  const fHalf = Math.max(3.5, s * 0.42)

  // ── Range ring / reachable stars ─────────────────────────────────────────
  let rangeRing: { cx: number; cy: number; r: number; reach: Set<StarId> } | null = null
  if (game.selectedFleet !== null) {
    const f = game.fleets.get(game.selectedFleet)
    if (f?.owner === pid) {
      const src = game.stars.get(f.location)
      if (src) {
        const reach = new Set<StarId>(
          [...game.stars.keys()].filter(sid => {
            if (sid === f.location) return false
            const sys = game.stars.get(sid)!
            return distSq(src.coords, sys.coords) <= f.fuelRangeSq
          })
        )
        rangeRing = { cx: sx(src.coords.x), cy: sy(src.coords.y), r: Math.sqrt(f.fuelRangeSq) * s, reach }
      }
    }
  }

  return (
    <svg
      ref={svgRef}
      style={{ width: '100%', height: '100%', display: 'block', background: '#010810', cursor: drag.current ? 'grabbing' : 'crosshair' }}
      onWheel={onWheel}
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      onMouseUp={onMouseUp}
      onMouseLeave={onMouseUp}
    >
      {/* ── Background starfield (fixed to viewport, not galaxy coords) ──── */}
      <g style={{ pointerEvents: 'none' }}>
        {bgStars.map((bs, i) => (
          <circle key={i} cx={`${bs.x}%`} cy={`${bs.y}%`} r={bs.r} fill="white" opacity={bs.a} />
        ))}
      </g>

      {/* ── Range ring + reachable highlights ────────────────────────────── */}
      {rangeRing && (
        <g style={{ pointerEvents: 'none' }}>
          <circle cx={rangeRing.cx} cy={rangeRing.cy} r={rangeRing.r}
            fill="none" stroke="#4488ff" strokeWidth={1} opacity={0.3} />
          {[...rangeRing.reach].map(sid => {
            const sys = game.stars.get(sid)!
            return (
              <circle key={sid}
                cx={sx(sys.coords.x)} cy={sy(sys.coords.y)}
                r={srad(sys.class_) + Math.max(2, s * 0.35)}
                fill="none" stroke="#4488ff" strokeWidth={1} opacity={0.5} />
            )
          })}
        </g>
      )}

      {/* ── Stars ────────────────────────────────────────────────────────── */}
      {[...game.stars.entries()].map(([sid, sys]) => {
        const explored  = sys.explored.has(pid)
        const cx        = sx(sys.coords.x)
        const cy        = sy(sys.coords.y)

        if (!explored) {
          return (
            <circle key={sid} cx={cx} cy={cy}
              r={Math.max(1, s * 0.08)} fill="#334455" opacity={0.6} />
          )
        }

        const col      = STAR_FILL[sys.class_] ?? '#ffffff'
        const r        = srad(sys.class_)
        const colony   = game.colonies.find(c => c.star === sid)
        const selected = game.selectedStar === sid

        return (
          <g key={sid} onClick={() => onStarClick(sid)} style={{ cursor: 'pointer' }}>
            {/* Glow */}
            <circle cx={cx} cy={cy} r={r * 2.8} fill={col} opacity={0.09} />
            {/* Star body */}
            <circle cx={cx} cy={cy} r={r} fill={col} />
            {/* Colony ownership ring */}
            {colony && (() => {
              const ownerEmp = game.empires.get(colony.owner)!
              const empCol = '#' + ownerEmp.color.toString(16).padStart(6, '0')
              return (
                <circle cx={cx} cy={cy}
                  r={r + Math.max(2.5, s * 0.32)}
                  fill="none" stroke={empCol} strokeWidth={1.8} opacity={0.9} />
              )
            })()}
            {/* Selection ring */}
            {selected && (
              <circle cx={cx} cy={cy}
                r={r + Math.max(5, s * 0.65)}
                fill="none" stroke="white" strokeWidth={1.5} opacity={0.8} />
            )}
            {/* Label (hidden when very zoomed out) */}
            {s > 2.5 && (
              <text
                x={cx} y={cy + r + lblPx * 1.4}
                textAnchor="middle"
                fill="#aabbcc"
                fontSize={lblPx}
                fontFamily="monospace"
                style={{ pointerEvents: 'none', userSelect: 'none' }}
              >
                {sys.name}
              </text>
            )}
          </g>
        )
      })}

      {/* ── Fleets ───────────────────────────────────────────────────────── */}
      {[...game.fleets.entries()].map(([fid, f]) => {
        const sys = game.stars.get(f.location)
        if (!sys) return null
        if (!sys.explored.has(pid) && f.owner !== pid) return null

        const emp = game.empires.get(f.owner)
        if (!emp) return null
        const col  = '#' + emp.color.toString(16).padStart(6, '0')
        const bx   = sx(sys.coords.x)
        const by   = sy(sys.coords.y)
        // Offset player fleets left, enemy fleets right of star
        const xOff = f.owner === pid ? -(fHalf * 2.2) : (fHalf * 2.2)
        const tx   = bx + xOff
        // Upward-pointing triangle: apex top, base bottom
        const pts  = `${tx},${by - fHalf} ${tx - fHalf * 0.7},${by + fHalf * 0.7} ${tx + fHalf * 0.7},${by + fHalf * 0.7}`
        const sel  = game.selectedFleet === fid

        return (
          <g key={fid}
            onClick={e => { e.stopPropagation(); onFleetClick(fid) }}
            style={{ cursor: 'pointer' }}>
            <polygon points={pts} fill={col} opacity={0.9} />
            {sel && (
              <circle cx={tx} cy={by} r={fHalf * 1.8}
                fill="none" stroke="white" strokeWidth={1} opacity={0.9} />
            )}
          </g>
        )
      })}

      {/* ── Zoom hint (shown when very zoomed out) ────────────────────────── */}
      {s < 3 && (
        <text x="50%" y="98%" textAnchor="middle" fill="#4a6880"
          fontSize={10} fontFamily="monospace" style={{ pointerEvents: 'none' }}>
          Scroll to zoom · Drag to pan
        </text>
      )}
    </svg>
  )
}
