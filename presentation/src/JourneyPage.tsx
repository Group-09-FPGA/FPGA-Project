import { useCallback, useEffect, useRef, useState } from 'react'
import * as THREE from 'three'
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js'
import { SCENES } from './data/journey'

const SCENE_COUNT = SCENES.length

// ─── helpers ──────────────────────────────────────────────────────────────────

function v3(t: [number, number, number]) {
  return new THREE.Vector3(t[0], t[1], t[2])
}

// ─── component ────────────────────────────────────────────────────────────────

export default function JourneyPage() {
  const canvasRef   = useRef<HTMLCanvasElement>(null)
  const [sceneIdx,  setSceneIdx]   = useState(0)
  const [scrollPct, setScrollPct]  = useState(0)
  const [loaded,    setLoaded]     = useState(false)

  // Three.js refs (not React state – live inside the render loop)
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null)
  const threeRef    = useRef<THREE.Scene | null>(null)
  const cameraRef   = useRef<THREE.PerspectiveCamera | null>(null)

  const camPos    = useRef(v3(SCENES[0].camPos))   // current (smoothed)
  const camLook   = useRef(v3(SCENES[0].camLook))
  const camPosT   = useRef(v3(SCENES[0].camPos))   // target
  const camLookT  = useRef(v3(SCENES[0].camLook))

  const sceneIdxRef = useRef(0)   // mirror without triggering re-renders

  // ── Three.js init ──────────────────────────────────────────────────────────
  useEffect(() => {
    const canvas = canvasRef.current!

    // renderer
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true })
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.setSize(window.innerWidth, window.innerHeight)
    renderer.shadowMap.enabled = true
    renderer.shadowMap.type    = THREE.PCFSoftShadowMap
    renderer.toneMapping       = THREE.ACESFilmicToneMapping
    renderer.toneMappingExposure = 1.1
    rendererRef.current = renderer

    // scene
    const scene = new THREE.Scene()
    scene.background = new THREE.Color('#060810')
    scene.fog = new THREE.FogExp2('#060810', 0.05)
    threeRef.current = scene

    // camera
    const camera = new THREE.PerspectiveCamera(42, window.innerWidth / window.innerHeight, 0.1, 200)
    camera.position.copy(camPos.current)
    camera.lookAt(camLook.current)
    cameraRef.current = camera

    // lights
    scene.add(new THREE.AmbientLight('#303050', 2.5))

    const key = new THREE.DirectionalLight('#fff8e7', 3.5)
    key.position.set(6, 12, 8)
    key.castShadow = true
    key.shadow.mapSize.set(2048, 2048)
    scene.add(key)

    const fill = new THREE.DirectionalLight('#3050ff', 1.0)
    fill.position.set(-6, 4, -6)
    scene.add(fill)

    const rim = new THREE.DirectionalLight('#00eebb', 0.5)
    rim.position.set(0, -4, 6)
    scene.add(rim)

    // warm glow on FPGA chip area
    const fpgaGlow = new THREE.PointLight('#7090ff', 3, 8)
    fpgaGlow.position.set(0, 2, 0)
    scene.add(fpgaGlow)

    // load GLB
    const loader = new GLTFLoader()
    loader.load('/board.glb', (gltf) => {
      const model = gltf.scene

      // auto-centre + normalise scale to ~8 units longest dimension
      const box    = new THREE.Box3().setFromObject(model)
      const center = box.getCenter(new THREE.Vector3())
      const size   = box.getSize(new THREE.Vector3())
      const maxDim = Math.max(size.x, size.y, size.z)
      const scale  = 8 / maxDim
      model.scale.setScalar(scale)
      model.position.sub(center.multiplyScalar(scale))

      model.traverse((child) => {
        if (child instanceof THREE.Mesh) {
          child.castShadow    = true
          child.receiveShadow = true
        }
      })

      scene.add(model)
      setLoaded(true)
    })

    // render loop
    let frameId: number
    const tick = () => {
      const k = 0.045   // lerp speed — lower = smoother/slower
      camPos.current.lerp(camPosT.current,   k)
      camLook.current.lerp(camLookT.current, k)
      camera.position.copy(camPos.current)
      camera.lookAt(camLook.current)
      renderer.render(scene, camera)
      frameId = requestAnimationFrame(tick)
    }
    tick()

    // resize
    const onResize = () => {
      camera.aspect = window.innerWidth / window.innerHeight
      camera.updateProjectionMatrix()
      renderer.setSize(window.innerWidth, window.innerHeight)
    }
    window.addEventListener('resize', onResize)

    return () => {
      cancelAnimationFrame(frameId)
      window.removeEventListener('resize', onResize)
      renderer.dispose()
    }
  }, [])

  // ── update camera target when scene changes ────────────────────────────────
  useEffect(() => {
    camPosT.current.set(...SCENES[sceneIdx].camPos)
    camLookT.current.set(...SCENES[sceneIdx].camLook)
  }, [sceneIdx])

  // ── scroll handler ─────────────────────────────────────────────────────────
  useEffect(() => {
    let raf = 0
    const onScroll = () => {
      cancelAnimationFrame(raf)
      raf = requestAnimationFrame(() => {
        const maxScroll = document.documentElement.scrollHeight - window.innerHeight
        const frac = maxScroll > 0 ? Math.min(window.scrollY / maxScroll, 1) : 0
        setScrollPct(frac)
        const idx = Math.min(Math.floor(frac * SCENE_COUNT), SCENE_COUNT - 1)
        if (idx !== sceneIdxRef.current) {
          sceneIdxRef.current = idx
          setSceneIdx(idx)
        }
      })
    }
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => { window.removeEventListener('scroll', onScroll); cancelAnimationFrame(raf) }
  }, [])

  // ── keyboard navigation ────────────────────────────────────────────────────
  const goTo = useCallback((target: number) => {
    const clamped    = Math.max(0, Math.min(SCENE_COUNT - 1, target))
    const maxScroll  = document.documentElement.scrollHeight - window.innerHeight
    const frac       = (clamped + 0.5) / SCENE_COUNT
    window.scrollTo({ top: frac * maxScroll, behavior: 'smooth' })
  }, [])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowDown' || e.key === 'PageDown' || e.key === ' ') {
        e.preventDefault(); goTo(sceneIdx + 1)
      } else if (e.key === 'ArrowUp' || e.key === 'PageUp') {
        e.preventDefault(); goTo(sceneIdx - 1)
      } else if (e.key === 'Home') { goTo(0) }
      else if (e.key === 'End')  { goTo(SCENE_COUNT - 1) }
      else if ((e.key === 'Enter' || e.key === 'f' || e.key === 'F') && sceneIdx === SCENE_COUNT - 1) {
        window.location.href = '/?slides#1'
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [sceneIdx, goTo])

  const scene  = SCENES[sceneIdx]
  const isLast = sceneIdx === SCENE_COUNT - 1

  return (
    <div className="journey-root">
      {/* ── scroll height track (creates page scroll depth) ── */}
      <div style={{ height: `${SCENE_COUNT * 100}vh` }} aria-hidden="true" />

      {/* ── WebGL canvas (fixed, behind everything) ── */}
      <canvas ref={canvasRef} className="journey-canvas" />

      {/* ── loading indicator ── */}
      {!loaded && (
        <div className="journey-loading">
          <div className="journey-loading-ring" />
          <span>LOADING BOARD MODEL</span>
        </div>
      )}

      {/* ── progress bar ── */}
      <div className="journey-progress">
        <div className="journey-progress-fill" style={{ width: `${scrollPct * 100}%` }} />
      </div>

      {/* ── scene counter (top-right) ── */}
      <div className="journey-counter">
        <span className="journey-counter-idx">{String(sceneIdx).padStart(2, '0')}</span>
        <span className="journey-counter-sep"> / </span>
        <span className="journey-counter-total">{String(SCENE_COUNT - 1).padStart(2, '0')}</span>
      </div>

      {/* ── text overlay (remounts on scene change → triggers .rise animations) ── */}
      <div className="journey-overlay" key={scene.id}>
        <div className={`journey-content journey-accent--${scene.accent}`}>

          {/* kicker row */}
          <div className="journey-kicker rise" style={{ animationDelay: '0.05s' }}>
            <span className="journey-kicker-num">{scene.sceneNum}</span>
            <span className="journey-kicker-dot">·</span>
            <span className="journey-kicker-label">{scene.label}</span>
          </div>

          {/* title */}
          <h2 className="journey-title rise" style={{ animationDelay: '0.14s' }}>
            {scene.title}
          </h2>

          {/* body */}
          <p className="journey-body rise" style={{ animationDelay: '0.22s' }}>
            {scene.body}
          </p>

          {/* signal badges */}
          <div className="journey-signals">
            {scene.signals.map((sig, i) => (
              <div
                key={sig.name}
                className="journey-signal rise"
                style={{ animationDelay: `${0.30 + i * 0.07}s` }}
              >
                <span className="journey-sig-name">{sig.name}</span>
                <span className="journey-sig-sep"> = </span>
                <span className="journey-sig-val">{sig.value}</span>
              </div>
            ))}
          </div>

          {/* CTA on the final scene */}
          {isLast && (
            <button
              className="journey-cta rise"
              style={{ animationDelay: '0.55s' }}
              onClick={() => { window.location.href = '/?slides#1' }}
            >
              Enter Technical Deep-Dive
              <svg
                width="16" height="16" viewBox="0 0 24 24"
                fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round"
              >
                <path d="M5 12h14M12 5l7 7-7 7" />
              </svg>
            </button>
          )}
        </div>

        {/* ── step dots (bottom centre) ── */}
        <div className="journey-dots">
          {SCENES.map((_, i) => (
            <button
              key={i}
              className={`journey-dot${i === sceneIdx ? ' on' : ''}`}
              onClick={() => goTo(i)}
              title={`Scene ${i}`}
              aria-label={`Go to scene ${i}`}
            />
          ))}
        </div>
      </div>

      {/* ── first-visit scroll hint ── */}
      <div
        className="journey-hint"
        style={{ opacity: scrollPct < 0.03 ? 1 : 0, transition: 'opacity 0.6s' }}
      >
        scroll · ↓ · spacebar to follow the packet
      </div>
    </div>
  )
}
