import { useEffect } from 'react';
import { hop } from '../actors/RoboActor';
import { useStudioStore } from '../store/useStudioStore';
import { EXPRESSIONS } from '../types';
import { advanceChaos, setWaterStage } from './ChaosDirector';
import { exportPNG } from './FrameExport';
import { runtime } from './runtime';
import { SFX_PADS, voiceFX } from './VoiceFXEngine';

const MOVE_KEYS = new Set(['w', 'a', 's', 'd', 'arrowup', 'arrowdown', 'arrowleft', 'arrowright']);

/** Desktop keyboard parity: every key hits the same store actions the touch HUD uses. */
export function useKeyboard() {
  useEffect(() => {
    const isTyping = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      return !!t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable);
    };

    const down = (e: KeyboardEvent) => {
      if (isTyping(e)) return;
      const st = useStudioStore.getState();
      const k = e.key.toLowerCase();

      if ((e.metaKey || e.ctrlKey) && k === 'z') {
        e.preventDefault();
        if (e.shiftKey) st.redo();
        else st.undo();
        return;
      }
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      void voiceFX.ensure();

      if (k === ' ') {
        e.preventDefault();
        if (!e.repeat) st.set({ talkHeld: true });
        return;
      }
      if (MOVE_KEYS.has(k)) {
        e.preventDefault();
        runtime.keys.add(k);
        return;
      }
      if (e.repeat) return;
      const n = Number(k);
      if (n >= 1 && n <= 6) return st.setExpression(EXPRESSIONS[n - 1]);

      const pad = SFX_PADS.find((p) => p.key.toLowerCase() === k);
      if (pad) {
        e.preventDefault();
        void voiceFX.sfx(pad.id);
        return;
      }

      switch (k) {
        case 'tab':
          e.preventDefault();
          st.set({ mode: st.mode === 'game' ? 'studio' : 'game', selectedId: null, brush: 'off' });
          break;
        case 'h':
          st.set({ uiHidden: !st.uiHidden });
          break;
        case 'l':
          st.set({ drawn: !st.drawn });
          break;
        case 'o':
          st.set({ onTwos: !st.onTwos });
          break;
        case 'p':
          void exportPNG(2);
          break;
        case 'z':
          st.set({ camRig: 'static', punchIn: st.camRig === 'static' ? !st.punchIn : false });
          break;
        case 'x':
          st.set({ camRig: 'slider' });
          break;
        case 'c':
          st.set({ camRig: 'drone' });
          break;
        case 'q':
          setWaterStage(1);
          break;
        case 'e':
          setWaterStage(2);
          break;
        case 'r':
          setWaterStage(3);
          break;
        case 't':
          setWaterStage(0);
          break;
        case 'f':
          hop(st.activeActorId);
          break;
        case 'g':
          advanceChaos();
          break;
        case 'escape':
          st.set({ selectedId: null, brush: 'off', drawer: null });
          break;
        case 'delete':
        case 'backspace':
          if (st.mode === 'studio' && st.selectedId) st.removeObject(st.selectedId);
          break;
      }
    };

    const up = (e: KeyboardEvent) => {
      const k = e.key.toLowerCase();
      if (k === ' ') useStudioStore.getState().set({ talkHeld: false });
      runtime.keys.delete(k);
    };
    const blur = () => {
      runtime.keys.clear();
      useStudioStore.getState().set({ talkHeld: false });
    };

    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    window.addEventListener('blur', blur);
    return () => {
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
      window.removeEventListener('blur', blur);
    };
  }, []);
}
