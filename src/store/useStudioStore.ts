import { create } from 'zustand';
import type {
  AspectMode,
  CamRig,
  Drawer,
  Expression,
  Mode,
  SceneDoc,
  SceneObject,
  VoicePreset,
  VoxelModel,
} from '../types';
import { initialLibrary } from '../props/library';

const HISTORY_LIMIT = 20;

/** Undoable document: the scene being staged + the voxel asset library. */
interface Doc {
  scene: SceneDoc;
  library: Record<string, VoxelModel>;
}

export const uid = (p = 'id') => `${p}_${Math.random().toString(36).slice(2, 8)}`;

export type BrushMode = 'off' | 'paint' | 'add' | 'erase';

interface StudioState extends Doc {
  past: Doc[];
  future: Doc[];

  mode: Mode;
  /** World map overlay open. */
  map: boolean;
  drawer: Drawer | null;
  aspect: AspectMode;
  uiHidden: boolean;
  episodeSlug: string;

  // timing
  /** Cinematic post stack (DOF, bloom, grain). */
  cinematic: boolean;
  /** Grease-pencil hand-drawn look. */
  drawn: boolean;
  drawnInk: number;
  drawnHatch: number;
  drawnBlocks: boolean;
  drawnBoil: number;
  onTwos: boolean;
  /** Turn spring stiffness (higher = snappier). */
  snappiness: number;
  /** 0 = critically damped, 1 = big overshoot. */
  overshoot: number;

  // performance
  activeActorId: string | null;
  expressions: Record<string, Expression>;
  talkHeld: boolean;
  camRig: CamRig;
  punchIn: boolean;
  autoGlide: boolean;
  glideSpeed: number;
  autoTrack: boolean;
  voicePreset: VoicePreset;
  waterStage: 0 | 1 | 2 | 3;
  recording: boolean;
  micOn: boolean;
  monitor: boolean;
  ducking: boolean;
  musicPlaying: boolean;
  musicLoop: boolean;
  musicName: string;

  // studio editing
  selectedId: string | null;
  brush: BrushMode;
  brushColor: string;
  brushGlow: boolean;

  set: (p: Partial<StudioState>) => void;
  commit: (fn: (d: Doc) => Partial<Doc>) => void;
  undo: () => void;
  redo: () => void;
  loadScene: (scene: SceneDoc) => void;
  addObject: (o: Omit<SceneObject, 'id'>) => string;
  updateObject: (id: string, p: Partial<SceneObject>) => void;
  removeObject: (id: string) => void;
  duplicateObject: (id: string) => void;
  setWorldVoxel: (key: string, value: string | null | undefined) => void;
  setModel: (m: VoxelModel) => void;
  setExpression: (e: Expression, actorId?: string) => void;
}

const clone = <T,>(v: T): T => structuredClone(v);

export const useStudioStore = create<StudioState>((set, get) => ({
  scene: { slug: '', objects: [], voxels: {} },
  library: initialLibrary,
  past: [],
  future: [],

  mode: 'game',
  map: false,
  drawer: null,
  aspect: '16:9',
  uiHidden: false,
  episodeSlug: '',

  cinematic: true,
  drawn: true,
  drawnInk: 1,
  drawnHatch: 0,
  /** Show block (voxel seam) outlines. Also forced on while painting. */
  drawnBlocks: false,
  drawnBoil: 1,
  onTwos: true,
  snappiness: 140,
  overshoot: 0.45,

  activeActorId: null,
  expressions: {},
  talkHeld: false,
  camRig: 'static',
  punchIn: false,
  autoGlide: false,
  glideSpeed: 0.08,
  autoTrack: true,
  voicePreset: 'normal',
  waterStage: 0,
  recording: false,
  micOn: false,
  monitor: false,
  ducking: true,
  musicPlaying: false,
  musicLoop: true,
  musicName: 'Robo Groove (built-in)',

  selectedId: null,
  brush: 'off',
  brushColor: '#ff4f6d',
  brushGlow: false,

  set: (p) => set(p),

  commit: (fn) => {
    const { scene, library, past } = get();
    const snapshot = { scene: clone(scene), library: clone(library) };
    const next = fn({ scene, library });
    set({ ...next, past: [...past, snapshot].slice(-HISTORY_LIMIT), future: [] });
  },

  undo: () => {
    const { past, future, scene, library } = get();
    const prev = past[past.length - 1];
    if (!prev) return;
    set({ ...prev, past: past.slice(0, -1), future: [{ scene, library }, ...future].slice(0, HISTORY_LIMIT) });
  },

  redo: () => {
    const { past, future, scene, library } = get();
    const next = future[0];
    if (!next) return;
    set({ ...next, future: future.slice(1), past: [...past, { scene, library }].slice(-HISTORY_LIMIT) });
  },

  loadScene: (scene) => {
    const actor = scene.objects.find((o) => o.kind === 'actor');
    set({
      scene: clone(scene),
      episodeSlug: scene.slug,
      past: [],
      future: [],
      selectedId: null,
      activeActorId: actor?.id ?? null,
    });
  },

  addObject: (o) => {
    const id = uid(o.kind);
    get().commit(({ scene }) => ({ scene: { ...scene, objects: [...scene.objects, { ...o, id }] } }));
    set({ selectedId: id });
    return id;
  },

  updateObject: (id, p) =>
    get().commit(({ scene }) => ({
      scene: { ...scene, objects: scene.objects.map((o) => (o.id === id ? { ...o, ...p } : o)) },
    })),

  removeObject: (id) => {
    get().commit(({ scene }) => ({ scene: { ...scene, objects: scene.objects.filter((o) => o.id !== id) } }));
    if (get().selectedId === id) set({ selectedId: null });
  },

  duplicateObject: (id) => {
    const src = get().scene.objects.find((o) => o.id === id);
    if (!src || src.kind === 'actor') return;
    const { id: _omit, ...rest } = clone(src);
    void _omit;
    get().addObject({ ...rest, name: `${src.name} copy`, pos: [src.pos[0] + 0.3, src.pos[1], src.pos[2] + 0.3] });
  },

  setWorldVoxel: (key, value) =>
    get().commit(({ scene }) => {
      const voxels = { ...scene.voxels };
      if (value === undefined) delete voxels[key];
      else voxels[key] = value;
      return { scene: { ...scene, voxels } };
    }),

  setModel: (m) => get().commit(({ library }) => ({ library: { ...library, [m.name]: clone(m) } })),

  setExpression: (e, actorId) => {
    const id = actorId ?? get().activeActorId;
    if (!id) return;
    set({ expressions: { ...get().expressions, [id]: e } });
  },
}));
