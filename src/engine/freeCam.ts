import * as THREE from 'three';
import { useStudioStore } from '../store/useStudioStore';
import { runtime } from './runtime';

/** Free-fly camera + saved camera views, per scene. */
export interface Pose {
  p: [number, number, number];
  yaw: number;
  pitch: number;
}

/** Copy the live camera's pose into the fly state (so switching to fly never jumps). */
export function captureFly() {
  const cam = runtime.three?.camera;
  if (!cam) return;
  const dir = new THREE.Vector3();
  cam.getWorldDirection(dir);
  runtime.fly.pos.copy(cam.position);
  runtime.fly.yaw = Math.atan2(-dir.x, -dir.z);
  runtime.fly.pitch = Math.asin(THREE.MathUtils.clamp(dir.y, -1, 1));
}

export function toggleFly() {
  const st = useStudioStore.getState();
  if (st.camRig === 'free') st.set({ camRig: 'static' });
  else {
    captureFly();
    st.set({ camRig: 'free' });
  }
}

export function currentPose(): Pose {
  if (useStudioStore.getState().camRig !== 'free') captureFly();
  const f = runtime.fly;
  return { p: [f.pos.x, f.pos.y, f.pos.z], yaw: f.yaw, pitch: f.pitch };
}

export function applyPose(pose: Pose) {
  runtime.fly.pos.set(...pose.p);
  runtime.fly.yaw = pose.yaw;
  runtime.fly.pitch = pose.pitch;
  useStudioStore.getState().set({ camRig: 'free' });
}

const key = (slug: string) => `robo-world:views:${slug}`;

export function loadViews(slug: string): (Pose | null)[] {
  try {
    const v = JSON.parse(localStorage.getItem(key(slug)) || '[]') as (Pose | null)[];
    return [v[0] ?? null, v[1] ?? null, v[2] ?? null];
  } catch {
    return [null, null, null];
  }
}

export function saveView(slug: string, slot: number) {
  const views = loadViews(slug);
  views[slot] = currentPose();
  try {
    localStorage.setItem(key(slug), JSON.stringify(views));
  } catch {
    /* storage blocked */
  }
  return views;
}
