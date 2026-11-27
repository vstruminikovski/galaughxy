import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useKeyboard } from './engine/useKeyboard';
import { EPISODES } from './scenes';
import { useStudioStore } from './store/useStudioStore';
import { GameHUD } from './ui/GameHUD';
import { SafeZoneOverlay } from './ui/SafeZoneOverlay';
import { Stage } from './ui/Stage';
import { loadEpisode } from './scenes/loadEpisode';
import { StudioDrawers } from './ui/StudioDrawers';
import { TopClaws } from './ui/TopClaws';
import { WorldMap } from './ui/WorldMap';

/** Pixel-identical letterboxed frame: same framing on Galaxy S25 and desktop. */
function useFrameBox(aspect: number) {
  const ref = useRef<HTMLDivElement>(null);
  const [box, setBox] = useState({ w: 0, h: 0 });
  useLayoutEffect(() => {
    const el = ref.current!;
    const ro = new ResizeObserver(() => {
      const W = el.clientWidth;
      const H = el.clientHeight;
      const w = Math.min(W, H * aspect);
      setBox({ w: Math.floor(w), h: Math.floor(w / aspect) });
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [aspect]);
  return { ref, box };
}

export default function App() {
  useKeyboard();
  const aspect = useStudioStore((s) => s.aspect);
  const mode = useStudioStore((s) => s.mode);
  const uiHidden = useStudioStore((s) => s.uiHidden);
  const recording = useStudioStore((s) => s.recording);
  const mapOpen = useStudioStore((s) => s.map);
  const set = useStudioStore((s) => s.set);
  const episodeSlug = useStudioStore((s) => s.episodeSlug);
  const episode = EPISODES.find((e) => e.slug === episodeSlug) ?? EPISODES[0];
  const ratio = aspect === '9:16' ? 9 / 16 : 16 / 9;
  const { ref, box } = useFrameBox(ratio);

  // Render at the export target resolution (1920 wide for 16:9, 1080 for 9:16).
  const targetW = aspect === '9:16' ? 1080 : 1920;
  const dpr = box.w ? Math.min(3, Math.max(2, targetW / box.w)) : 2;

  useEffect(() => loadEpisode(EPISODES[0].slug), []);

  return (
    <div className={`app mode-${mode}`}>
      <div className="viewport" ref={ref}>
        <div className="frame" style={{ width: box.w, height: box.h }}>
          {box.w > 0 && episodeSlug && <Stage key={episode.slug} episode={episode} dpr={dpr} />}
          {!uiHidden && <SafeZoneOverlay />}
          {recording && <div className="rec-dot" />}
        </div>
      </div>

      {!uiHidden ? (
        <div className="hud">
          <GameHUD />
          <TopClaws />
          {mode === 'studio' && <StudioDrawers />}
          {mapOpen && <WorldMap />}
          <div className="title-tag">
            {episode.title} · <span>{mode === 'game' ? episode.tagline : 'studio'}</span>
          </div>
        </div>
      ) : (
        <button className="unhide" onClick={() => set({ uiHidden: false })} aria-label="Show HUD">
          H
        </button>
      )}
    </div>
  );
}
