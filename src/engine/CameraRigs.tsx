import { useFrame, useThree } from '@react-three/fiber';
import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { useStudioStore } from '../store/useStudioStore';
import type { CameraConfig } from '../types';
import { runtime } from './runtime';

const tmpPos = new THREE.Vector3();
const tmpTarget = new THREE.Vector3();

/**
 * Deterministic Static / Slider / Drone rigs. Switching rigs is an instant cut;
 * motion inside a rig is smooth and fully predictable (no physics, no free-fly).
 */
export function CameraRigs({ config }: { config: CameraConfig }) {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  const droneAngle = useRef(0);
  const trackX = useRef(0);
  const fov = useRef(config.static.fov);
  const lastRig = useRef<string>('');

  // Hard cut on rig change.
  useEffect(
    () =>
      useStudioStore.subscribe((s, p) => {
        if (s.camRig !== p.camRig) lastRig.current = '';
      }),
    [],
  );

  useFrame((state, dt) => {
    const st = useStudioStore.getState();
    const t = state.clock.elapsedTime;
    const cut = lastRig.current !== st.camRig;
    lastRig.current = st.camRig;
    let targetFov = 38;

    if (st.camRig === 'static') {
      const c = config.static;
      tmpPos.set(...c.pos);
      tmpTarget.set(...c.target);
      targetFov = st.punchIn ? c.punchFov : c.fov;
    } else if (st.camRig === 'slider') {
      const c = config.slider;
      if (st.autoGlide) {
        runtime.sliderT += dt * st.glideSpeed * (runtime.sliderT >= 1 ? 0 : 1);
        if (runtime.sliderT >= 1) {
          runtime.sliderT = 1;
          st.set({ autoGlide: false });
        }
      }
      const k = THREE.MathUtils.smoothstep(runtime.sliderT, 0, 1);
      tmpPos.set(...c.start).lerp(new THREE.Vector3(...c.end), k);
      tmpTarget.copy(tmpPos).add(new THREE.Vector3(...c.lookOffset));
      targetFov = c.fov;
    } else {
      const c = config.drone;
      droneAngle.current += dt * c.orbitSpeed;
      const a = droneAngle.current;
      tmpPos.set(
        c.center[0] + Math.sin(a) * c.radius + Math.sin(t * 0.7) * 0.08,
        c.center[1] + c.height + Math.sin(t * 1.3) * 0.06,
        c.center[2] + Math.cos(a) * c.radius + Math.cos(t * 0.9) * 0.08,
      );
      tmpTarget.set(...c.center);
      targetFov = c.fov;
    }

    // 9:16 Auto-Track Speaker: pan horizontally to keep the active actor in the vertical crop.
    const actorId = st.activeActorId;
    const mark = actorId ? runtime.actors.get(actorId) : undefined;
    const wantTrack = st.aspect === '9:16' && st.autoTrack && mark && st.camRig !== 'drone';
    const desiredX = wantTrack ? mark!.pos.x - tmpTarget.x : 0;
    trackX.current = cut ? desiredX : THREE.MathUtils.damp(trackX.current, desiredX, 3, dt);
    tmpPos.x += trackX.current;
    tmpTarget.x += trackX.current;

    // Right-thumb look drag: orbit the rig around its target (clamped, eases back on release).
    if (runtime.look.yaw || runtime.look.pitch) {
      const off = tmpPos.clone().sub(tmpTarget);
      off.applyAxisAngle(new THREE.Vector3(0, 1, 0), runtime.look.yaw);
      const side = new THREE.Vector3(0, 1, 0).cross(off).normalize();
      off.applyAxisAngle(side, runtime.look.pitch);
      tmpPos.copy(tmpTarget).add(off);
    }

    fov.current = cut ? targetFov : THREE.MathUtils.damp(fov.current, targetFov, 6, dt);
    camera.position.copy(tmpPos);
    camera.lookAt(tmpTarget);
    if (Math.abs(camera.fov - fov.current) > 0.01) {
      camera.fov = fov.current;
      camera.updateProjectionMatrix();
    }
  });

  return null;
}
