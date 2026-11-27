import { useStudioStore } from '../store/useStudioStore';

/** Framing guides drawn as DOM over the canvas — never captured by the recorder. */
export function SafeZoneOverlay() {
  const aspect = useStudioStore((s) => s.aspect);
  if (aspect === '16:9') return null; // no always-on grid
  if (aspect === '9:16')
    return (
      <>
        <div className="guide shorts-bottom">captions / title</div>
        <div className="guide shorts-right">♥ 💬 ↗</div>
        <div className="guide shorts-top" />
      </>
    );
  return (
    <div className="guide dual-crop">
      <span>9:16</span>
    </div>
  );
}
