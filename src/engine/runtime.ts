import * as THREE from 'three';

/**
 * Mutable per-frame state that must NOT trigger React renders.
 * Read and written inside useFrame / gsap tweens / input handlers.
 */
export const runtime = {
  /** Flood plane height in metres (gsap-tweened by ChaosDirector). */
  waterLevel: 0,
  /** Puddle radius for stage 1. */
  puddle: 0,
  /** Wave ripple amplitude. */
  rippleAmp: 0,
  /** Drip emitter intensity 0..1. */
  dripRate: 0,
  /** Debris visibility 0..1. */
  debris: 0,
  /** Slider rig progress 0..1. */
  sliderT: 0,
  /** Virtual thumbstick vector (-1..1). */
  stick: { x: 0, z: 0 },
  /** Keys currently held for movement. */
  keys: new Set<string>(),
  /** Live actor marks during performance. */
  actors: new Map<string, { pos: THREE.Vector3; yaw: number; moving: number }>(),
  /** Scene object id -> mounted Object3D (for gizmos, floating, sockets). */
  objects: new Map<string, THREE.Object3D>(),
  /** Right-zone look drag: orbit offset applied on top of the active camera rig. */
  look: { yaw: 0, pitch: 0 },
  /** Free-fly camera pose (used when camRig === 'free'). */
  fly: { pos: new THREE.Vector3(0, 1.2, 4), yaw: 0, pitch: -0.2 },
  /** Renderer handles for PNG export. */
  three: null as { gl: THREE.WebGLRenderer; scene: THREE.Scene; camera: THREE.Camera } | null,
  /** Canvas used by the recorder. */
  canvas: null as HTMLCanvasElement | null,
};

export function getActorMark(id: string, fallback: [number, number, number]) {
  let m = runtime.actors.get(id);
  if (!m) {
    m = { pos: new THREE.Vector3(...fallback), yaw: 0, moving: 0 };
    runtime.actors.set(id, m);
  }
  return m;
}
