import { EPISODES } from '../scenes';
import { loadEpisode } from '../scenes/loadEpisode';
import { useStudioStore } from '../store/useStudioStore';

/** GTA-style world map: every scene is a district, doorways are the roads between them. */
export function WorldMap() {
  const slug = useStudioStore((s) => s.episodeSlug);
  const set = useStudioStore((s) => s.set);
  const close = () => set({ map: false });
  const at = (s: string) => EPISODES.find((e) => e.slug === s)!.mapPos;
  const roads: [string, string][] = [];
  for (const ep of EPISODES)
    for (const p of ep.portals ?? []) {
      const pair = [ep.slug, p.to].sort() as [string, string];
      if (!roads.some(([a, b]) => a === pair[0] && b === pair[1])) roads.push(pair);
    }

  return (
    <div className="worldmap" onPointerDown={(e) => e.stopPropagation()}>
      <div className="wm-head">
        <b>WORLD MAP</b>
        <span>tap a district to fly there</span>
        <button onClick={close}>✕</button>
      </div>
      <div className="wm-board">
        <svg className="wm-roads" viewBox="0 0 100 100" preserveAspectRatio="none">
          {roads.map(([a, b]) => (
            <line key={a + b} x1={at(a)[0]} y1={at(a)[1]} x2={at(b)[0]} y2={at(b)[1]} vectorEffect="non-scaling-stroke" />
          ))}
        </svg>
        {EPISODES.map((ep) => (
          <button
            key={ep.slug}
            className={`wm-node ${ep.slug === slug ? 'here' : ''}`}
            style={{ left: `${ep.mapPos[0]}%`, top: `${ep.mapPos[1]}%` }}
            onClick={() => {
              loadEpisode(ep.slug);
              close();
            }}
          >
            <span className="wm-icon">{ep.mapIcon}</span>
            <b>{ep.title}</b>
            <small>{ep.tagline}</small>
            {ep.slug === slug && <em>you are here</em>}
          </button>
        ))}
      </div>
      <div className="wm-foot">Tap a district to teleport · doorways connect neighbouring scenes · M to close</div>
    </div>
  );
}
