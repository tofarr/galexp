import * as PIXI from 'pixi.js'
import type { GameState, StarId, FleetId } from '../types'
import { distSq } from '../engine/galaxy'

// Star colours per star class
const STAR_COLORS: Record<string, number> = {
  Blue:      0x6699ff,
  White:     0xffffff,
  Yellow:    0xffee88,
  Orange:    0xff9944,
  Red:       0xff5533,
  Neutron:   0x99ccee,
  BlackHole: 0x550077,
}
const STAR_RADIUS: Record<string, number> = {
  Blue:3.5, White:3, Yellow:2.8, Orange:2.5, Red:2.2, Neutron:1.8, BlackHole:2,
}

export class GalaxyMapRenderer {
  private app:      PIXI.Application
  private mapRoot:  PIXI.Container    // zoomed/panned container
  private starLayer: PIXI.Container
  private labelLayer: PIXI.Container
  private fleetLayer: PIXI.Container
  private hlLayer:   PIXI.Container   // highlight / range rings

  private state:     GameState | null = null
  private zoom = 1
  private panX = 0
  private panY = 0
  private dragging = false
  private dragStart = { x: 0, y: 0 }
  private dragPanStart = { x: 0, y: 0 }

  private onStarClick:  (id: StarId) => void
  private onFleetClick: (id: FleetId) => void

  constructor(
    canvas: HTMLDivElement,
    onStarClick:  (id: StarId) => void,
    onFleetClick: (id: FleetId) => void,
  ) {
    this.onStarClick  = onStarClick
    this.onFleetClick = onFleetClick

    this.app = new PIXI.Application({
      resizeTo:        canvas,
      backgroundColor: 0x010810,
      antialias:       true,
      resolution:      window.devicePixelRatio || 1,
      autoDensity:     true,
    })
    canvas.appendChild(this.app.view as HTMLCanvasElement)

    this.mapRoot   = new PIXI.Container()
    this.starLayer  = new PIXI.Container()
    this.labelLayer = new PIXI.Container()
    this.fleetLayer = new PIXI.Container()
    this.hlLayer    = new PIXI.Container()
    this.mapRoot.addChild(this.hlLayer, this.starLayer, this.fleetLayer, this.labelLayer)
    this.app.stage.addChild(this.mapRoot)

    this.bindEvents()

    // Draw a starfield background
    this.drawStarfield()
  }

  private drawStarfield() {
    const g = new PIXI.Graphics()
    for (let i = 0; i < 300; i++) {
      const x = Math.random() * 2000
      const y = Math.random() * 2000
      const a = 0.1 + Math.random() * 0.4
      g.beginFill(0xffffff, a)
      g.drawCircle(x, y, 0.5)
      g.endFill()
    }
    this.mapRoot.addChildAt(g, 0)
  }

  // ── Input events ─────────────────────────────────────────────────────────
  private bindEvents() {
    const view = this.app.view as HTMLCanvasElement
    view.addEventListener('wheel', this.onWheel.bind(this), { passive: false })
    view.addEventListener('mousedown', this.onMouseDown.bind(this))
    window.addEventListener('mousemove', this.onMouseMove.bind(this))
    window.addEventListener('mouseup', this.onMouseUp.bind(this))
  }

  private onWheel(e: WheelEvent) {
    e.preventDefault()
    const factor = e.deltaY < 0 ? 1.1 : 0.9
    this.zoom = Math.max(0.3, Math.min(4, this.zoom * factor))
    this.applyTransform()
  }

  private onMouseDown(e: MouseEvent) {
    this.dragging = true
    this.dragStart     = { x: e.clientX, y: e.clientY }
    this.dragPanStart  = { x: this.panX, y: this.panY }
  }

  private onMouseMove(e: MouseEvent) {
    if (!this.dragging) return
    this.panX = this.dragPanStart.x + (e.clientX - this.dragStart.x)
    this.panY = this.dragPanStart.y + (e.clientY - this.dragStart.y)
    this.applyTransform()
  }

  private onMouseUp() { this.dragging = false }

  private applyTransform() {
    this.mapRoot.scale.set(this.zoom)
    this.mapRoot.position.set(this.panX, this.panY)
  }

  // Convert game-space coords to screen for initial centering
  centreOn(gx: number, gy: number) {
    const sw = this.app.screen.width
    const sh = this.app.screen.height
    const scale = Math.min(sw, sh) / 110 * this.zoom
    this.mapRoot.scale.set(scale)
    this.panX = sw / 2 - gx * scale
    this.panY = sh / 2 - gy * scale
    this.zoom = scale
    this.applyTransform()
  }

  // ── Render ────────────────────────────────────────────────────────────────
  render(state: GameState) {
    this.state = state
    this.starLayer.removeChildren()
    this.labelLayer.removeChildren()
    this.fleetLayer.removeChildren()
    this.hlLayer.removeChildren()

    const pid = state.playerId
    const player = state.empires.get(pid)!

    // Draw range ring if a fleet is selected
    if (state.selectedFleet !== null) {
      const f = state.fleets.get(state.selectedFleet)
      if (f && f.owner === pid) {
        this.drawRangeRing(state, f.location, f.fuelRangeSq)
      }
    }

    // Stars
    for (const [sid, sys] of state.stars) {
      const explored = sys.explored.has(pid)
      if (!explored) {
        // Unexplored: tiny dim dot, no label
        const g = new PIXI.Graphics()
        g.beginFill(0x334455, 0.5)
        g.drawCircle(sys.coords.x, sys.coords.y, 1)
        g.endFill()
        this.starLayer.addChild(g)
        continue
      }

      const col = STAR_COLORS[sys.class_] ?? 0xffffff
      const rad = STAR_RADIUS[sys.class_] ?? 2.5
      const g   = new PIXI.Graphics()

      // Glow
      g.beginFill(col, 0.15)
      g.drawCircle(sys.coords.x, sys.coords.y, rad * 2.5)
      g.endFill()

      // Body
      g.beginFill(col)
      g.drawCircle(sys.coords.x, sys.coords.y, rad)
      g.endFill()

      // Colony indicator ring
      const colony = state.colonies.find(c => c.star === sid)
      if (colony) {
        const empColor = state.empires.get(colony.owner)!.color
        g.lineStyle(1.5, empColor, 0.9)
        g.drawCircle(sys.coords.x, sys.coords.y, rad + 2.5)
      }

      // Selection highlight
      if (state.selectedStar === sid) {
        g.lineStyle(1.5, 0xffffff, 0.8)
        g.drawCircle(sys.coords.x, sys.coords.y, rad + 5)
      }

      g.interactive = true
      g.cursor = 'pointer'
      g.on('pointerdown', (ev: PIXI.FederatedPointerEvent) => {
        ev.stopPropagation()
        this.onStarClick(sid)
      })
      this.starLayer.addChild(g)

      // Label
      const label = new PIXI.Text(sys.name, {
        fontSize:  6,
        fill:      explored ? 0xaabbcc : 0x334455,
        fontFamily: 'monospace',
      })
      label.anchor.set(0.5, 0)
      label.position.set(sys.coords.x, sys.coords.y + rad + 2)
      this.labelLayer.addChild(label)
    }

    // Fleets
    for (const [fid, f] of state.fleets) {
      const sys = state.stars.get(f.location)
      if (!sys?.explored.has(pid) && f.owner !== pid) continue

      const empColor = state.empires.get(f.owner)!.color
      const x = sys ? sys.coords.x : 0
      const y = sys ? sys.coords.y : 0
      const offset = f.owner === pid ? -6 : 6

      const g = new PIXI.Graphics()
      g.beginFill(empColor, 0.9)
      // Small triangle pointing up
      g.moveTo(x + offset, y - 4)
      g.lineTo(x + offset - 3, y + 2)
      g.lineTo(x + offset + 3, y + 2)
      g.closePath()
      g.endFill()

      if (state.selectedFleet === fid) {
        g.lineStyle(1, 0xffffff)
        g.drawCircle(x + offset, y - 1, 5)
      }

      g.interactive = true
      g.cursor = 'pointer'
      g.on('pointerdown', (ev: PIXI.FederatedPointerEvent) => {
        ev.stopPropagation()
        this.onFleetClick(fid)
      })
      this.fleetLayer.addChild(g)
    }
  }

  private drawRangeRing(state: GameState, src: StarId, rangeSq: number) {
    const srcSys = state.stars.get(src)!
    const g = new PIXI.Graphics()
    g.lineStyle(0.5, 0x4488ff, 0.25)
    g.drawCircle(srcSys.coords.x, srcSys.coords.y, Math.sqrt(rangeSq))
    // Highlight reachable stars
    for (const [sid, sys] of state.stars) {
      if (sid === src) continue
      if (distSq(srcSys.coords, sys.coords) <= rangeSq) {
        g.lineStyle(0.8, 0x4488ff, 0.5)
        g.drawCircle(sys.coords.x, sys.coords.y, 4)
      }
    }
    this.hlLayer.addChild(g)
  }

  // Fit the entire galaxy on screen
  fitToScreen() {
    if (!this.state) return
    const coords = [...this.state.stars.values()].map(s => s.coords)
    const minX = Math.min(...coords.map(c => c.x))
    const maxX = Math.max(...coords.map(c => c.x))
    const minY = Math.min(...coords.map(c => c.y))
    const maxY = Math.max(...coords.map(c => c.y))
    const gw = maxX - minX + 20, gh = maxY - minY + 20
    const sw = this.app.screen.width, sh = this.app.screen.height
    const scale = Math.min(sw / gw, sh / gh) * 0.9
    this.zoom = scale
    this.panX = (sw - gw * scale) / 2 - minX * scale + 10 * scale
    this.panY = (sh - gh * scale) / 2 - minY * scale + 10 * scale
    this.applyTransform()
  }

  resize() { this.app.resize() }

  destroy() {
    const view = this.app.view as HTMLCanvasElement
    view.removeEventListener('wheel', this.onWheel.bind(this))
    this.app.destroy(true)
  }
}
