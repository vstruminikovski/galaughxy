import { useFrame } from '@react-three/fiber';
import { Bloom, DepthOfField, EffectComposer, Noise, ToneMapping, Vignette } from '@react-three/postprocessing';
import { BlendFunction, ToneMappingMode, type DepthOfFieldEffect } from 'postprocessing';
import { useMemo, useRef } from 'react';
import * as THREE from 'three';
import { runtime } from '../engine/runtime';
import { useStudioStore } from '../store/useStudioStore';

/**
 * Nature-documentary lens stack: shallow depth of field that auto-focuses on the active actor,
 * soft bloom, filmic tone mapping, vignette and fine film grain. Baked into recordings & PNGs.
 */
export function CinematicFX({ nature }: { nature: boolean }) {
  const focus = useMemo(() => new THREE.Vector3(), []);
  const dof = useRef<DepthOfFieldEffect>(null);
  useFrame(() => {
    const id = useStudioStore.getState().activeActorId;
    const o = id ? runtime.objects.get(id) : undefined;
    if (o) {
      o.getWorldPosition(focus);
      focus.y += 0.22;
    }
    // The wrapper copies `target` once; drive the live effect's autofocus target directly.
    dof.current?.target?.copy(focus);
  });
  return (
    <EffectComposer multisampling={4}>
      <DepthOfField ref={dof} target={focus} worldFocusRange={nature ? 1.6 : 4} bokehScale={nature ? 3 : 1.2} resolutionScale={0.5} />
      <Bloom intensity={nature ? 0.35 : 0.6} luminanceThreshold={0.78} luminanceSmoothing={0.2} mipmapBlur />
      <ToneMapping mode={ToneMappingMode.AGX} />
      <Vignette offset={0.28} darkness={nature ? 0.62 : 0.4} />
      <Noise opacity={nature ? 0.045 : 0.02} blendFunction={BlendFunction.OVERLAY} />
    </EffectComposer>
  );
}
