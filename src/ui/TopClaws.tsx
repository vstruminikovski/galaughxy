import { dualRecorder } from '../engine/DualRecorder';
import { exportPNG } from '../engine/FrameExport';
import { useStudioStore } from '../store/useStudioStore';
import { EPISODES } from '../scenes';
import { loadEpisode } from '../scenes/loadEpisode';
import type { AspectMode, CamRig } from '../types';

const ASPECTS: AspectMode[] = ['16:9', '9:16', 'dual'];
const RIGS: { id: CamRig; label: string; key: string }[] = [
  { id: 'static', label: 'Static', key: 'Z' },
  { id: 'slider', label: 'Slider', key: 'X' },
  { id: 'drone', label: 'Drone', key: 'C' },
];

/** Corner quick toggles (left: mode/timing/framing/HUD, right: camera cuts + capture). */
export function TopClaws() {
  const s = useStudioStore();
  return (
    <>
      <div className="claws claws-left">
        <button
          className={`claw ${s.mode === 'studio' ? 'on' : ''}`}
          onClick={() => s.set({ mode: s.mode === 'game' ? 'studio' : 'game', selectedId: null, brush: 'off' })}
          title="Tab"
        >
          {s.mode === 'game' ? '🎮 Game' : '🎬 Studio'}
        </button>
        <button className={`claw ${s.onTwos ? 'on' : ''}`} onClick={() => s.set({ onTwos: !s.onTwos })} title="O">
          {s.onTwos ? '12fps Twos' : '60fps'}
        </button>
        <button className="claw" onClick={() => s.set({ aspect: ASPECTS[(ASPECTS.indexOf(s.aspect) + 1) % 3] })}>
          {s.aspect === 'dual' ? 'Dual' : s.aspect}
        </button>
        <button
          className="claw"
          onClick={() => {
            const i = EPISODES.findIndex((e) => e.slug === s.episodeSlug);
            loadEpisode(EPISODES[(i + 1) % EPISODES.length].slug);
          }}
        >
          🎞 {EPISODES.find((e) => e.slug === s.episodeSlug)?.title ?? 'Episode'}
        </button>
        <button className={`claw ${s.drawn ? 'on' : ''}`} onClick={() => s.set({ drawn: !s.drawn })} title="L">
          ✏️ Drawn
        </button>
        <button className="claw" onClick={() => s.set({ uiHidden: true })} title="H">
          Clean HUD
        </button>
      </div>
      <div className="claws claws-right">
        {RIGS.map((r) => (
          <button
            key={r.id}
            className={`claw ${s.camRig === r.id ? 'on' : ''}`}
            onClick={() => s.set({ camRig: r.id, punchIn: r.id === 'static' && s.camRig === 'static' ? !s.punchIn : false })}
          >
            {r.label}
            {r.id === 'static' && s.punchIn ? ' +' : ''}
            <kbd>{r.key}</kbd>
          </button>
        ))}
        <button className="claw" onClick={() => void exportPNG(2)} title="P">
          PNG
        </button>
        <button className={`claw rec ${s.recording ? 'on' : ''}`} onClick={() => dualRecorder.toggle()}>
          {s.recording ? '■ Stop' : '● Rec'}
        </button>
      </div>
    </>
  );
}
