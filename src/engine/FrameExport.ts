import * as THREE from 'three';
import { useStudioStore } from '../store/useStudioStore';
import { runtime } from './runtime';

/**
 * HUD-free high-res PNG: re-renders the WebGL scene at `scale`× pixel ratio, grabs the canvas,
 * then restores. Only the 3D canvas is captured — never the React overlays.
 */
export async function exportPNG(scale = 2) {
  const three = runtime.three;
  if (!three) return;
  const { gl, scene, camera } = three;
  const prev = gl.getPixelRatio();
  const size = gl.getSize(new THREE.Vector2());
  gl.setPixelRatio(prev * scale);
  gl.setSize(size.x, size.y, false);
  gl.render(scene, camera);
  const blob = await new Promise<Blob | null>((res) => gl.domElement.toBlob(res, 'image/png'));
  gl.setPixelRatio(prev);
  gl.setSize(size.x, size.y, false);
  if (!blob) return;
  const st = useStudioStore.getState();
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `${st.episodeSlug || 'frame'}_${st.aspect.replace(':', 'x')}_${Date.now()}.png`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 10_000);
}

/** Save/load helpers for local-first JSON persistence. */
export function downloadJSON(name: string, data: unknown) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }));
  a.download = `${name}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 10_000);
}

/** POST to the Vite dev endpoint when available; silently skipped in packaged builds. */
export async function saveToDisk(endpoint: '/api/save-scene' | '/api/save-prop', body: unknown) {
  try {
    const r = await fetch(endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    return r.ok;
  } catch {
    return false;
  }
}
