import gsap from 'gsap';
import { runtime } from '../engine/runtime';
import { useStudioStore } from '../store/useStudioStore';
import type { SceneDoc } from '../types';
import { EPISODES } from './index';

export const sceneKey = (slug: string) => `robo-world:scene:${slug}`;

/** Switch episode: device-saved edits win over the repo's scene.json. */
export function loadEpisode(slug: string) {
  const ep = EPISODES.find((e) => e.slug === slug) ?? EPISODES[0];
  let saved: SceneDoc | null = null;
  try {
    const raw = localStorage.getItem(sceneKey(ep.slug));
    saved = raw ? JSON.parse(raw) : null;
  } catch {
    saved = null;
  }
  gsap.killTweensOf(runtime);
  Object.assign(runtime, { waterLevel: 0, puddle: 0, rippleAmp: 0, dripRate: 0, debris: 0, sliderT: 0 });
  runtime.look.yaw = runtime.look.pitch = 0;
  runtime.actors.clear();
  const st = useStudioStore.getState();
  st.loadScene(saved ?? ep.scene);
  st.set({ waterStage: 0, expressions: {}, camRig: 'static', punchIn: false, autoGlide: false });
}
