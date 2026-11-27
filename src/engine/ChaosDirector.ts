import gsap from 'gsap';
import { useStudioStore } from '../store/useStudioStore';
import { runtime } from './runtime';
import { voiceFX } from './VoiceFXEngine';

/** Deterministic 3-stage water overflow. Same input -> same beat, every take. */
export const WATER_LEVELS = { stage2: 0.32, stage3: 0.82 };

let splashTimer: number | undefined;

function startSplashLoop(interval: number) {
  stopSplashLoop();
  splashTimer = window.setInterval(() => void voiceFX.sfx('splash'), interval);
}
function stopSplashLoop() {
  if (splashTimer) window.clearInterval(splashTimer);
  splashTimer = undefined;
}

export function setWaterStage(stage: 0 | 1 | 2 | 3) {
  const st = useStudioStore.getState();
  st.set({ waterStage: stage });
  gsap.killTweensOf(runtime);

  if (stage === 0) {
    stopSplashLoop();
    gsap.to(runtime, { waterLevel: 0, puddle: 0, rippleAmp: 0, dripRate: 0, debris: 0, duration: 1.6, ease: 'power2.inOut' });
    return;
  }
  if (stage === 1) {
    stopSplashLoop();
    gsap.to(runtime, { dripRate: 0.35, duration: 0.3 });
    gsap.to(runtime, { puddle: 1, duration: 2.5, ease: 'power1.out' });
    gsap.to(runtime, { waterLevel: 0, rippleAmp: 0.004, debris: 0, duration: 1 });
    void voiceFX.sfx('splash');
    return;
  }
  if (stage === 2) {
    gsap.to(runtime, { dripRate: 0.75, puddle: 1.4, duration: 0.4 });
    gsap.to(runtime, { waterLevel: WATER_LEVELS.stage2, rippleAmp: 0.018, duration: 3.2, ease: 'power2.inOut' });
    gsap.to(runtime, { debris: 0, duration: 0.5 });
    startSplashLoop(1300);
    void voiceFX.sfx('splash');
    return;
  }
  // stage 3: full flood & chaos
  void voiceFX.sfx('pipeBurst');
  gsap.to(runtime, { dripRate: 1, duration: 0.2 });
  gsap.to(runtime, { waterLevel: WATER_LEVELS.stage3, rippleAmp: 0.05, duration: 2.6, ease: 'power3.out' });
  gsap.to(runtime, { debris: 1, duration: 1.5, delay: 0.6 });
  startSplashLoop(800);
  // Every actor in the room panics.
  const actors = st.scene.objects.filter((o) => o.kind === 'actor');
  const expressions = { ...st.expressions };
  actors.forEach((a) => (expressions[a.id] = 'PANIC'));
  st.set({ expressions });
}

export function cutToDrone() {
  useStudioStore.getState().set({ camRig: 'drone' });
}

/** Put actors back on their marks and drain the room. */
export function resetTake() {
  const st = useStudioStore.getState();
  setWaterStage(0);
  st.scene.objects
    .filter((o) => o.kind === 'actor')
    .forEach((o) => {
      const m = runtime.actors.get(o.id);
      if (m) {
        m.pos.set(...o.pos);
        m.yaw = (o.rot[1] * Math.PI) / 180;
      }
    });
  runtime.sliderT = 0;
  runtime.look.yaw = runtime.look.pitch = 0;
  st.set({ expressions: {}, camRig: 'static', punchIn: false, autoGlide: false });
}

/** Interact / Chaos button: escalate one stage per tap, then drain. */
export function advanceChaos() {
  const s = useStudioStore.getState().waterStage;
  setWaterStage(s >= 3 ? 0 : ((s + 1) as 1 | 2 | 3));
}
