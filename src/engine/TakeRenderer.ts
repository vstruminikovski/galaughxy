import { advance } from '@react-three/fiber';
import { ArrayBufferTarget, Muxer } from 'mp4-muxer';
import * as THREE from 'three';
import { useStudioStore } from '../store/useStudioStore';
import type { CamRig } from '../types';
import { applyPose, currentPose, type Pose } from './freeCam';
import { runtime } from './runtime';

/**
 * Offline "Render Take": the scene is stepped frame-by-frame at an exact time step and each frame
 * is drawn at the chosen output size (not the phone's screen), then encoded to H.264 MP4.
 * Because every frame is rendered at full resolution, detail is set by the output size you pick.
 */

export interface Shot {
  id: string;
  name: string;
  seconds: number;
  /** 'pose' = camera frozen at a captured position; 'rig' = a moving rig (static / slider / drone). */
  mode: 'pose' | 'rig';
  pose?: Pose;
  rig?: CamRig;
}

export const RESOLUTIONS = [
  { id: '1080', label: '1920×1080 · 16:9 HD', w: 1920, h: 1080 },
  { id: '4k', label: '3840×2160 · 16:9 4K', w: 3840, h: 2160 },
  { id: 'shorts', label: '1080×1920 · 9:16 Shorts', w: 1080, h: 1920 },
  { id: 'square', label: '1080×1080 · Square', w: 1080, h: 1080 },
] as const;

export const FPS_OPTIONS = [12, 24, 30, 60] as const;

const shotsKey = (slug: string) => `robo-world:shots:${slug}`;

export function loadShots(slug: string): Shot[] {
  try {
    return JSON.parse(localStorage.getItem(shotsKey(slug)) || '[]') as Shot[];
  } catch {
    return [];
  }
}

export function saveShots(slug: string, shots: Shot[]) {
  try {
    localStorage.setItem(shotsKey(slug), JSON.stringify(shots));
  } catch {
    /* storage blocked */
  }
}

let cancelled = false;
export function cancelRender() {
  cancelled = true;
}

const nextFrame = () => new Promise<void>((r) => requestAnimationFrame(() => r()));
const yieldToUI = () => new Promise<void>((r) => setTimeout(r, 0));

async function pickCodec(w: number, h: number, fps: number): Promise<string> {
  const candidates = ['avc1.640034', 'avc1.640033', 'avc1.42E032', 'avc1.42001f'];
  for (const codec of candidates) {
    const r = await VideoEncoder.isConfigSupported({ codec, width: w, height: h, bitrate: bitrateFor(w, h, fps), framerate: fps });
    if (r.supported) return codec;
  }
  throw new Error(`This browser can't encode ${w}×${h} H.264 video. Try Chrome on a desktop or a recent Android Chrome.`);
}

/** ~0.15 bits per pixel per frame, capped: sharp at 4K without huge files. */
const bitrateFor = (w: number, h: number, fps: number) => Math.min(50_000_000, Math.round(w * h * fps * 0.15));

export interface RenderProgress {
  shotIndex: number;
  shotName: string;
  frame: number;
  total: number;
}

export async function renderTake(opts: {
  w: number;
  h: number;
  fps: number;
  shots: Shot[];
  onProgress: (p: RenderProgress) => void;
}): Promise<Blob> {
  const three = runtime.three;
  if (!three) throw new Error('Renderer not ready yet.');
  if (typeof VideoEncoder === 'undefined') throw new Error('MP4 encoding needs WebCodecs (Chrome / Edge).');
  if (!opts.shots.length) throw new Error('Add at least one shot.');

  const { gl, clock } = three;
  const camera = three.camera as THREE.PerspectiveCamera;
  const { w, h, fps } = opts;
  const codec = await pickCodec(w, h, fps);
  const total = opts.shots.reduce((n, s) => n + Math.max(1, Math.round(s.seconds * fps)), 0);

  // remember what the editor was showing so we can put it back
  const st0 = useStudioStore.getState();
  const prevRig = st0.camRig;
  const prevPose = currentPose();
  const prevPR = gl.getPixelRatio();
  const prevSize = gl.getSize(new THREE.Vector2());

  cancelled = false;
  let encodeError: Error | null = null;
  const target = new ArrayBufferTarget();
  const muxer = new Muxer({ target, video: { codec: 'avc', width: w, height: h }, fastStart: 'in-memory' });
  const enc = new VideoEncoder({
    output: (chunk, meta) => muxer.addVideoChunk(chunk, meta),
    error: (e) => {
      encodeError = e;
    },
  });
  enc.configure({ codec, width: w, height: h, bitrate: bitrateFor(w, h, fps), framerate: fps });

  // Hand the frame loop to us: time only advances when we say so.
  st0.set({ rendering: true });
  await nextFrame();
  await nextFrame();

  gl.setPixelRatio(1);
  gl.setSize(w, h, false);
  runtime.composer?.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();

  let frame = 0;
  let t = clock.elapsedTime; // continue from the live clock, never jump backwards
  const dt = 1 / fps;
  try {
    for (let si = 0; si < opts.shots.length; si++) {
      const shot = opts.shots[si];
      if (shot.mode === 'pose' && shot.pose) applyPose(shot.pose);
      else useStudioStore.getState().set({ camRig: shot.rig ?? 'static' });
      const n = Math.max(1, Math.round(shot.seconds * fps));
      for (let f = 0; f < n; f++) {
        if (cancelled) throw new Error('Render cancelled.');
        if (encodeError) throw encodeError;
        t += dt;
        advance(t); // steps every animation, then draws the full post-processed frame at w×h
        const vf = new VideoFrame(gl.domElement, { timestamp: Math.round((frame * 1e6) / fps), duration: Math.round(1e6 / fps) });
        while (enc.encodeQueueSize > 4) await yieldToUI();
        enc.encode(vf, { keyFrame: frame % (fps * 2) === 0 });
        vf.close();
        frame++;
        opts.onProgress({ shotIndex: si, shotName: shot.name, frame, total });
        if (frame % 3 === 0) await yieldToUI();
      }
    }
    await enc.flush();
    muxer.finalize();
    return new Blob([target.buffer], { type: 'video/mp4' });
  } finally {
    if (enc.state !== 'closed') enc.close();
    // put the editor back the way it was
    gl.setPixelRatio(prevPR);
    gl.setSize(prevSize.x, prevSize.y, false);
    runtime.composer?.setSize(prevSize.x, prevSize.y, false);
    camera.aspect = prevSize.x / prevSize.y;
    camera.updateProjectionMatrix();
    applyPose(prevPose);
    useStudioStore.getState().set({ camRig: prevRig, rendering: false });
  }
}

export function downloadBlob(blob: Blob, name: string) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 20_000);
}
