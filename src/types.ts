export type Vec3 = [number, number, number];

/** One 0.1-unit micro-voxel. Integer grid coords; `e` = emissive glow. */
export interface Voxel {
  x: number;
  y: number;
  z: number;
  c: string;
  e?: boolean;
  group?: string;
}

/** Reusable voxel asset (prop or robot accessory), saved as compact local JSON. */
export interface VoxelModel {
  name: string;
  version: 1;
  voxels: Voxel[];
  /** Lightweight props bob on flood water. */
  floats?: boolean;
  /** Named attachment points in voxel units. */
  sockets?: Record<string, Vec3>;
}

export interface SceneObject {
  id: string;
  kind: 'prop' | 'actor';
  /** VoxelModel name, or actor type ("robo"). */
  ref: string;
  name: string;
  pos: Vec3;
  /** Degrees. */
  rot: Vec3;
  scale: Vec3;
  visible: boolean;
  color?: string;
}

/**
 * Persisted scene — placements + world voxel deltas only (base room is procedural).
 * Delta value: "#rrggbb", "*#rrggbb" (emissive) or null (erased base voxel).
 */
export interface SceneDoc {
  slug: string;
  objects: SceneObject[];
  voxels: Record<string, string | null>;
}

export type Expression = 'DEADPAN' | 'SMIRK' | 'PANIC' | 'ANGRY' | 'HAPPY' | 'SHOCKED';
export const EXPRESSIONS: Expression[] = ['DEADPAN', 'SMIRK', 'PANIC', 'ANGRY', 'HAPPY', 'SHOCKED'];

export type CamRig = 'static' | 'slider' | 'drone' | 'free';
export type AspectMode = '16:9' | '9:16' | 'dual';
export type VoicePreset = 'normal' | 'radio' | 'phone' | 'scary' | 'squeaky';
export type Mode = 'game' | 'studio';
export type Drawer = 'models' | 'scene' | 'voice' | 'cameras' | 'timing' | 'export';

export interface CameraConfig {
  static: { pos: Vec3; target: Vec3; fov: number; punchFov: number };
  slider: { start: Vec3; end: Vec3; lookOffset: Vec3; fov: number };
  drone: { center: Vec3; radius: number; height: number; orbitSpeed: number; fov: number };
}

export interface Episode {
  slug: string;
  title: string;
  tagline: string;
  /** Position on the world map, in percent of the map (x, y from top-left). */
  mapPos: [number, number];
  mapIcon: string;
  cameras: CameraConfig;
  bounds: { minX: number; maxX: number; minZ: number; maxZ: number };
  /** The room, built from square voxels. */
  buildBaseVoxels: () => Map<string, string>;
  /** Ground height under (x, z) for actors, where it differs from y = 0. */
  ground?: (x: number, z: number) => number;
  /** Resting water surface height; undefined = dry room that floods from 0. */
  waterRest?: number;
  /** Multiplier on chaos flood heights. */
  floodScale?: number;
  /** Doorways to other scenes (walk up and tap to go). */
  portals?: { to: string; position: Vec3; rotationY?: number }[];
  scene: SceneDoc;
  skyColor: string;
}
