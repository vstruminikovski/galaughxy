import { useFrame } from '@react-three/fiber';
import { Bloom, DepthOfField, EffectComposer, Noise, ToneMapping, Vignette } from '@react-three/postprocessing';
import { BlendFunction, ToneMappingMode, type DepthOfFieldEffect } from 'postprocessing';
import { useEffect, useMemo, useRef, type ReactElement } from 'react';
import * as THREE from 'three';
import { DrawnLookEffect } from '../engine/DrawnLookEffect';
import { runtime } from '../engine/runtime';
import { useStudioStore } from '../store/useStudioStore';

/**
 * Lens + art-direction stack, baked into recordings & PNGs:
 *  cinematic → depth of field auto-focused on the active actor, bloom, vignette, grain
 *  drawn     → grease-pencil ink outlines with 12fps line boil, shadow hatching, paper
 */
export function CinematicFX({ nature, cinematic, drawn }: { nature: boolean; cinematic: boolean; drawn: boolean }) {
  const focus = useMemo(() => new THREE.Vector3(), []);
  const dof = useRef<DepthOfFieldEffect>(null);
  const drawnFx = useMemo(() => new DrawnLookEffect({ thickness: nature ? 1.3 : 1.6 }), [nature]);
  const ink = useStudioStore((s) => s.drawnInk);
  const hatch = useStudioStore((s) => s.drawnHatch);
  const boil = useStudioStore((s) => s.drawnBoil);
  useEffect(() => drawnFx.set({ ink, hatch, boil }), [drawnFx, ink, hatch, boil]);

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

  const fx: ReactElement[] = [];
  if (cinematic)
    fx.push(
      <DepthOfField key="dof" ref={dof} target={focus} worldFocusRange={nature ? 1.6 : 4} bokehScale={nature ? 3 : 1.2} resolutionScale={0.5} />,
      <Bloom key="bloom" intensity={nature ? 0.35 : 0.6} luminanceThreshold={0.78} luminanceSmoothing={0.2} mipmapBlur />,
    );
  fx.push(<ToneMapping key="tm" mode={ToneMappingMode.AGX} />);
  if (drawn) fx.push(<primitive key="drawn" object={drawnFx} />);
  if (cinematic)
    fx.push(
      <Vignette key="vig" offset={0.28} darkness={nature ? 0.62 : 0.4} />,
      <Noise key="grain" opacity={nature ? 0.045 : 0.02} blendFunction={BlendFunction.OVERLAY} />,
    );

  return <EffectComposer multisampling={4}>{fx}</EffectComposer>;
}
