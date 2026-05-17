import { useEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import {
  getCurrentWindow,
  currentMonitor,
  PhysicalPosition,
} from "@tauri-apps/api/window";

type HudPayload = {
  trigger: string;
  combo: string;
  caption: string;
  duration: number;
};

const MOD_WORD_TO_GLYPH: Record<string, string> = {
  Cmd: "⌘",
  Ctrl: "⌃",
  Alt: "⌥",
  Shift: "⇧",
};

// Split a trigger/combo string into keycap tokens.
function tokenize(s: string): string[] {
  if (!s) return [];
  // "⌘L ×2" / "Caps ×2" → space-separated; everything else is "+"-joined.
  const parts = s.includes("+") ? s.split("+") : s.split(" ");
  return parts
    .map((p) => p.trim())
    .filter(Boolean)
    .map((p) => MOD_WORD_TO_GLYPH[p] ?? p);
}

const FALLBACK_HOLD_MS = 1350;

export default function Hud() {
  const [data, setData] = useState<HudPayload | null>(null);
  const hideTimer = useRef<number | null>(null);

  useEffect(() => {
    // The HUD window is transparent — strip the inherited app background.
    document.documentElement.style.background = "transparent";
    document.body.style.background = "transparent";
    document.body.style.margin = "0";
    document.body.style.overflow = "hidden";
  }, []);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let disposed = false;

    (async () => {
      const win = getCurrentWindow();
      const off = await listen<HudPayload>("hud-show", async (e) => {
        if (disposed) return;
        setData(e.payload);

        // Reposition bottom-center of the active monitor, then show.
        try {
          const mon = await currentMonitor();
          if (mon) {
            const outer = await win.outerSize();
            const x =
              mon.position.x +
              Math.round((mon.size.width - outer.width) / 2);
            const y =
              mon.position.y + mon.size.height - outer.height - 160;
            await win.setPosition(new PhysicalPosition(x, y));
          }
          await win.show();
        } catch {
          /* positioning/showing is best-effort */
        }

        if (hideTimer.current) window.clearTimeout(hideTimer.current);
        const hold =
          e.payload.duration && e.payload.duration > 0
            ? e.payload.duration
            : FALLBACK_HOLD_MS;
        hideTimer.current = window.setTimeout(() => {
          getCurrentWindow()
            .hide()
            .catch(() => {});
          setData(null);
        }, hold);
      });
      // If the component unmounted before listen() resolved (StrictMode
      // double-invoke in dev), tear the listener down immediately.
      if (disposed) {
        off();
      } else {
        unlisten = off;
      }
    })();

    return () => {
      disposed = true;
      if (unlisten) unlisten();
      if (hideTimer.current) window.clearTimeout(hideTimer.current);
    };
  }, []);

  if (!data) return <div style={{ width: "100%", height: "100%" }} />;

  const triggerKeys = tokenize(data.trigger);
  const comboKeys = tokenize(data.combo);

  return (
    <>
      <style>{CSS}</style>
      <div className="hud-root">
        <div className="hud-panel">
          <div className="hud-line">
            <div className="hud-grp">
              {triggerKeys.map((k, i) => (
                <span key={i} className="hud-tok">
                  {i > 0 && <span className="hud-plus">+</span>}
                  <span className="hud-kc">{k}</span>
                </span>
              ))}
            </div>

            <svg className="hud-arrow" viewBox="0 0 46 22" fill="none">
              <path d="M2 11h36" stroke="#7c89a0" strokeWidth="2.5" strokeLinecap="round" />
              <path d="M33 5l9 6-9 6" stroke="#7c89a0" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>

            <div className="hud-grp">
              {comboKeys.map((k, i) => (
                <span key={i} className="hud-tok">
                  {i > 0 && <span className="hud-plus">+</span>}
                  <span className="hud-kc hud-accent">{k}</span>
                </span>
              ))}
            </div>
          </div>
          {data.caption && <div className="hud-cap">{data.caption}</div>}
        </div>
      </div>
    </>
  );
}

const CSS = `
.hud-root{
  width:100vw;height:100vh;display:flex;align-items:center;justify-content:center;
  background:transparent;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display",sans-serif;
}
.hud-panel{
  display:flex;flex-direction:column;align-items:center;gap:12px;
  padding:18px 26px;border-radius:22px;
  background:rgba(20,26,42,.62);
  -webkit-backdrop-filter:blur(28px) saturate(160%);
  backdrop-filter:blur(28px) saturate(160%);
  border:1px solid rgba(255,255,255,.10);
  box-shadow:0 18px 50px rgba(0,0,0,.55),0 1px 0 rgba(255,255,255,.08) inset;
  animation:hud-rise .24s cubic-bezier(.22,1,.36,1);
}
@keyframes hud-rise{from{opacity:0;transform:translateY(14px) scale(.96)}to{opacity:1;transform:none}}
/* The keycap line: trigger → action, all caps share one baseline. */
.hud-line{display:flex;align-items:center;gap:16px}
.hud-grp{display:flex;align-items:center;gap:7px}
.hud-tok{display:inline-flex;align-items:center}
.hud-plus{color:#64748b;font-weight:600;font-size:14px;margin:0 2px}
.hud-kc{
  display:inline-flex;align-items:center;justify-content:center;
  min-width:40px;height:40px;padding:0 11px;border-radius:10px;
  font-weight:600;font-size:16px;color:#f8fafc;
  background:linear-gradient(180deg,#475569 0%,#334155 48%,#293548 100%);
  box-shadow:0 1px 0 rgba(255,255,255,.18) inset,0 -2px 3px rgba(0,0,0,.35) inset,
    0 3px 0 #1e293b,0 6px 10px rgba(0,0,0,.45);
}
.hud-accent{
  background:linear-gradient(180deg,#6366f1 0%,#4f46e5 50%,#4338ca 100%);
  box-shadow:0 1px 0 rgba(255,255,255,.25) inset,0 -2px 3px rgba(0,0,0,.3) inset,
    0 3px 0 #3730a3,0 6px 14px rgba(79,70,229,.5);
}
.hud-arrow{width:46px;height:22px}
.hud-cap{font-size:11.5px;color:#a7b2c6;max-width:220px;text-align:center;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
`;
