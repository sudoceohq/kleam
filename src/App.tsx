import { useEffect, useRef, useState } from "react";
import { KleamEngine, type EngineOptions, type Played } from "./audio/engine.ts";
import { KEY_ROWS, keyLabel } from "./keyboard.ts";
import { DEFAULT_SWITCH_SLUG, SWITCHES, switchBySlug, type SwitchPack } from "./switches.ts";

const INITIAL: EngineOptions = {
  enabled: true,
  volume: 0.82,
  randomPitch: true,
  spatial: true,
  upDown: true,
};

const PREVIEW = ["KeyS", "KeyU", "KeyP", "KeyE", "KeyR"];
const GITHUB_URL = "https://github.com/sudoceohq/kleam";

type LastHit = {
  code: string;
  label: string;
  cents: number;
  id: number;
};

function isField(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable;
}

function formatCents(cents: number): string {
  if (cents > 0) return `+${cents}¢`;
  if (cents < 0) return `−${Math.abs(cents)}¢`;
  return "0¢";
}

function formatClock(date: Date): string {
  const day = date.toLocaleDateString("en-US", { weekday: "short" });
  const time = date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", hour12: false });
  return `${day} ${time}`;
}

export default function App() {
  const engineRef = useRef<KleamEngine | null>(null);
  const optionsRef = useRef(INITIAL);
  const heldRef = useRef(new Set<string>());
  const timersRef = useRef<number[]>([]);
  const meterRef = useRef<HTMLSpanElement>(null);
  const hitId = useRef(0);

  const [options, setOptions] = useState(INITIAL);
  const [selectedSlug, setSelectedSlug] = useState(DEFAULT_SWITCH_SLUG);
  const [pressed, setPressed] = useState<Set<string>>(() => new Set());
  const [last, setLast] = useState<LastHit | null>(null);
  const [history, setHistory] = useState<number[]>([]);
  const [now, setNow] = useState(() => new Date());

  const selected = switchBySlug(selectedSlug);

  useEffect(() => {
    const engine = new KleamEngine(INITIAL, DEFAULT_SWITCH_SLUG);
    engineRef.current = engine;

    const syncPressed = () => setPressed(new Set(heldRef.current));

    const note = (played: Played | null) => {
      if (!played || played.stroke !== "down") return;
      hitId.current += 1;
      setLast({
        code: played.code,
        label: keyLabel(played.code),
        cents: played.cents,
        id: hitId.current,
      });
      if (optionsRef.current.randomPitch) {
        setHistory((items) => [...items, played.cents].slice(-18));
      }
    };

    const onPointer = () => engine.resume();

    const onDown = (event: KeyboardEvent) => {
      if (event.repeat || isField(event.target) || heldRef.current.has(event.code)) return;
      const target = event.target;
      if (
        (target === document.body || target === document.documentElement) &&
        (event.code === "Space" || event.code.startsWith("Arrow"))
      ) {
        event.preventDefault();
      }
      heldRef.current.add(event.code);
      syncPressed();
      engine.setOptions(optionsRef.current);
      note(engine.keyDown(event.code));
    };

    const onUp = (event: KeyboardEvent) => {
      if (!heldRef.current.has(event.code)) return;
      heldRef.current.delete(event.code);
      syncPressed();
      engine.setOptions(optionsRef.current);
      engine.keyUp(event.code);
    };

    const releaseAll = () => {
      for (const code of heldRef.current) engine.keyUp(code);
      heldRef.current.clear();
      syncPressed();
    };

    window.addEventListener("pointerdown", onPointer);
    window.addEventListener("keydown", onDown);
    window.addEventListener("keyup", onUp);
    window.addEventListener("blur", releaseAll);

    let frame = 0;
    const paintMeter = () => {
      const level = engine.getLevel();
      if (meterRef.current) meterRef.current.style.transform = `scaleX(${0.06 + level * 0.94})`;
      frame = window.requestAnimationFrame(paintMeter);
    };
    frame = window.requestAnimationFrame(paintMeter);

    const clock = window.setInterval(() => setNow(new Date()), 10_000);

    return () => {
      window.cancelAnimationFrame(frame);
      window.clearInterval(clock);
      window.removeEventListener("pointerdown", onPointer);
      window.removeEventListener("keydown", onDown);
      window.removeEventListener("keyup", onUp);
      window.removeEventListener("blur", releaseAll);
      for (const id of timersRef.current) window.clearTimeout(id);
      engine.close();
      engineRef.current = null;
    };
  }, []);

  useEffect(() => {
    optionsRef.current = options;
    engineRef.current?.setOptions(options);
  }, [options]);

  const patch = (partial: Partial<EngineOptions>) => {
    setOptions((current) => ({ ...current, ...partial }));
  };

  const runPreview = () => {
    const engine = engineRef.current;
    if (!engine) return;
    engine.setOptions(optionsRef.current);
    engine.resume();
    const played = engine.preview(PREVIEW);
    for (const id of timersRef.current) window.clearTimeout(id);
    timersRef.current = [];
    PREVIEW.forEach((code, index) => {
      const hit = played[index];
      const downAt = window.setTimeout(() => {
        heldRef.current.add(code);
        setPressed(new Set(heldRef.current));
        if (!hit) return;
        hitId.current += 1;
        setLast({ code, label: keyLabel(code), cents: hit.cents, id: hitId.current });
        if (optionsRef.current.randomPitch) setHistory((items) => [...items, hit.cents].slice(-18));
      }, index * 200);
      const upAt = window.setTimeout(() => {
        heldRef.current.delete(code);
        setPressed(new Set(heldRef.current));
      }, index * 200 + 90);
      timersRef.current.push(downAt, upAt);
    });
  };

  const selectSwitch = (pack: SwitchPack) => {
    setSelectedSlug(pack.slug);
    const engine = engineRef.current;
    if (!engine) return;
    engine.resume();
    engine.setSwitch(pack.slug);
    engine.setOptions(optionsRef.current);
    runPreview();
  };

  const pressKey = (code: string) => {
    if (heldRef.current.has(code)) return;
    heldRef.current.add(code);
    setPressed(new Set(heldRef.current));
    const engine = engineRef.current;
    if (!engine) return;
    engine.setOptions(optionsRef.current);
    const played = engine.keyDown(code);
    if (!played || played.stroke !== "down") return;
    hitId.current += 1;
    setLast({ code, label: keyLabel(code), cents: played.cents, id: hitId.current });
    if (optionsRef.current.randomPitch) setHistory((items) => [...items, played.cents].slice(-18));
  };

  const releaseKey = (code: string) => {
    if (!heldRef.current.has(code)) return;
    heldRef.current.delete(code);
    setPressed(new Set(heldRef.current));
    engineRef.current?.setOptions(optionsRef.current);
    engineRef.current?.keyUp(code);
  };

  const heroDown = last ? pressed.has(last.code) : false;
  const volumePercent = `${Math.round(options.volume * 100)}%`;

  return (
    <div className="page">
      <div className="atmosphere" aria-hidden="true">
        <span className="bloom bloom-a" />
        <span className="bloom bloom-b" />
        <span className="grain" />
      </div>

      <header className="nav">
        <a className="brand" href="#play" aria-label="Kleam home">
          <span className="mark-k">K</span>
          <span className="brand-word">Kleam</span>
        </a>
        <div className="nav-actions">
          <span className="nav-note">Free &amp; open source</span>
          <a className="ghost-cta" href={GITHUB_URL} target="_blank" rel="noreferrer">
            GitHub
          </a>
        </div>
      </header>

      <main id="play">
        <section className="hero" aria-labelledby="brand-title">
          <p className="kicker">
            <span className="kicker-dot" />
            Menubar key sounds for Mac
          </p>
          <h1 id="brand-title" className="brand-title">
            Kleam
          </h1>
          <p className="lede">
            Free open-source keystroke sounds — seven original switch packs, spatial audio, and a quiet
            menubar presence.
          </p>
          <div className="cta-row">
            <a className="cta" href={GITHUB_URL} target="_blank" rel="noreferrer">
              Get the source
            </a>
            <button className="cta soft" type="button" onClick={runPreview}>
              Hear a preview
            </button>
          </div>
        </section>

        <section className="stage" aria-label="Kleam preview">
          <div className="disc disc-a" />
          <div className="disc disc-b" />
          <div className="vignette" />

          <div className="menubar">
            <span className="menubar-k" aria-hidden="true">
              K
            </span>
            <span className="menubar-right">
              <span className="menubar-pill">K</span>
              <time dateTime={now.toISOString()}>{formatClock(now)}</time>
            </span>
          </div>

          <div className="stage-grid">
            <div className="switch-menu" role="listbox" aria-label="Switch packs">
              <p className="switch-brand">Switch pack</p>
              <div className="switch-list">
                {SWITCHES.map((pack) => {
                  const active = pack.slug === selectedSlug;
                  return (
                    <button
                      key={pack.slug}
                      className={active ? "switch-row on" : "switch-row"}
                      type="button"
                      role="option"
                      aria-selected={active}
                      onClick={() => selectSwitch(pack)}
                    >
                      <Swatch pack={pack} />
                      <span className="switch-copy">
                        <span className="switch-name">
                          {pack.name}
                          {pack.isNew ? <span className="badge">New</span> : null}
                        </span>
                        <span className="switch-feel">{pack.feel}</span>
                      </span>
                      {active ? (
                        <svg className="play" viewBox="0 0 16 16" aria-hidden="true">
                          <path d="M6 4.2v7.6l6.2-3.8L6 4.2z" fill="currentColor" />
                        </svg>
                      ) : null}
                    </button>
                  );
                })}
              </div>
            </div>

            <div className="hero-wrap">
              <div className={heroDown ? "hero-key down" : "hero-key"} aria-hidden="true">
                <span className={last && last.label.length > 1 ? "hero-label small" : "hero-label"}>
                  {last?.label ?? "K"}
                </span>
              </div>
              <p className={last && last.cents < 0 ? "cents neg" : "cents"} key={last?.id ?? 0}>
                {options.randomPitch ? (last ? formatCents(last.cents) : "a new pitch each press") : "pitch locked"}
              </p>
              <p className="hint">Psst… press any key</p>
            </div>

            <div className="panel">
              <div className="panel-row">
                <strong>Kleam</strong>
                <button
                  className={options.enabled ? "toggle on" : "toggle"}
                  type="button"
                  role="switch"
                  aria-checked={options.enabled}
                  aria-label="Toggle sound"
                  onClick={() => patch({ enabled: !options.enabled })}
                >
                  <span />
                </button>
              </div>
              <div className="rule" />
              <label className="slider-block">
                <span className="panel-label">
                  Sound
                  <span className="meter" aria-hidden="true">
                    <span ref={meterRef} />
                  </span>
                </span>
                <input
                  type="range"
                  min={0}
                  max={1}
                  step={0.01}
                  value={options.volume}
                  aria-label="Sound volume"
                  aria-valuetext={volumePercent}
                  style={{ ["--fill" as string]: volumePercent }}
                  onChange={(event) => patch({ volume: Number(event.target.value) })}
                />
              </label>
              <div className="rule" />
              <Option
                label="Randomized pitching"
                checked={options.randomPitch}
                onChange={(randomPitch) => {
                  patch({ randomPitch });
                  if (!randomPitch) setHistory([]);
                }}
              />
              <div className="spark" aria-hidden="true">
                {options.randomPitch && history.length > 0
                  ? history.map((cents, index) => (
                      <span className="spark-slot" key={`${index}-${cents}`}>
                        <i
                          className={cents >= 0 ? "spark-bar up" : "spark-bar down"}
                          style={{ height: `${Math.max(2, Math.min(16, Math.abs(cents) / 5))}px` }}
                        />
                      </span>
                    ))
                  : null}
              </div>
              <Option label="Spatial audio" checked={options.spatial} onChange={(spatial) => patch({ spatial })} />
              <Option
                label="Up/down keystrokes"
                checked={options.upDown}
                onChange={(upDown) => patch({ upDown })}
              />
              <div className="rule" />
              <p className="panel-status">
                <span className="status-dot" />
                {selected.name}
              </p>
              <p className="panel-hotkey">Mac mute · ⌃⌥⌘K</p>
            </div>
          </div>
        </section>

        <section className="board-wrap" aria-label="Keyboard">
          <div className="board">
            {KEY_ROWS.map((row) => (
              <div className="board-row" key={row[0]?.code ?? "row"}>
                {row.map((key) => (
                  <button
                    key={key.code}
                    type="button"
                    tabIndex={-1}
                    className={`key${key.label.length > 1 ? " word" : ""}${pressed.has(key.code) ? " down" : ""}`}
                    style={{ flexGrow: key.w }}
                    aria-label={keyLabel(key.code)}
                    onPointerDown={(event) => {
                      event.preventDefault();
                      event.currentTarget.setPointerCapture(event.pointerId);
                      pressKey(key.code);
                    }}
                    onPointerUp={() => releaseKey(key.code)}
                    onPointerCancel={() => releaseKey(key.code)}
                  >
                    {key.label}
                  </button>
                ))}
              </div>
            ))}
          </div>
        </section>

        <section className="features" aria-label="What you get">
          <Feature icon="packs" title={"Seven switch\npacks"} />
          <Feature icon="hotkey" title={"Mute hotkey\non Mac"} />
          <Feature icon="orb" title={"Immersive\nspatial audio"} />
          <Feature icon="arrows" title={"Up/down\nkeystrokes"} />
          <Feature icon="menubar" title={"Quiet menubar\ncompanion"} accent />
          <Feature icon="oss" title={"Free &\nopen source"} accent />
        </section>

        <footer className="legal">
          <p>
            Kleam is free and open source under the Apache License 2.0.{" "}
            <a href={GITHUB_URL} target="_blank" rel="noreferrer">
              Source on GitHub
            </a>
            .
          </p>
          <p>
            Independent project — not affiliated with Klack, Keychron, Cherry, Gateron, NovelKeys,
            Everglide, or Flurples. Switch packs are descriptive profiles · original synthesis.
          </p>
        </footer>
      </main>
    </div>
  );
}

function Swatch({ pack }: { pack: SwitchPack }) {
  const id = `grad-${pack.slug}`;
  return (
    <svg className="swatch" viewBox="0 0 26 26" aria-hidden="true">
      <defs>
        <linearGradient id={id} x1="50%" x2="50%" y1="0%" y2="100%">
          <stop offset="0%" stopColor={pack.gradient[0]} />
          <stop offset="100%" stopColor={pack.gradient[1]} />
        </linearGradient>
      </defs>
      <rect width="26" height="26" rx="7" fill={`url(#${id})`} />
      <path fill="#fff" d="M12 6.2h2v5.6h5.6v2H14v5.6h-2v-5.6H6.4v-2H12V6.2z" opacity="0.92" />
    </svg>
  );
}

function Option({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <div className="panel-row option">
      <span>{label}</span>
      <button
        className={checked ? "toggle on" : "toggle"}
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        onClick={() => onChange(!checked)}
      >
        <span />
      </button>
    </div>
  );
}

type FeatureIconName = "packs" | "hotkey" | "orb" | "arrows" | "menubar" | "oss";

function Feature({
  icon,
  title,
  accent = false,
}: {
  icon: FeatureIconName;
  title: string;
  accent?: boolean;
}) {
  const [first, second] = title.split("\n");
  return (
    <div className={accent ? "feature accent" : "feature"}>
      <FeatureIcon name={icon} />
      <h2>
        {first}
        <br />
        {second}
      </h2>
    </div>
  );
}

function FeatureIcon({ name }: { name: FeatureIconName }) {
  switch (name) {
    case "packs":
      return (
        <svg viewBox="0 0 48 48" aria-hidden="true">
          <rect x="6" y="10" width="16" height="16" rx="4" />
          <rect x="26" y="10" width="16" height="16" rx="4" opacity="0.7" />
          <rect x="16" y="24" width="16" height="16" rx="4" opacity="0.45" />
        </svg>
      );
    case "hotkey":
      return (
        <svg viewBox="0 0 48 48" aria-hidden="true">
          <rect x="6" y="14" width="36" height="22" rx="6" fill="none" stroke="currentColor" strokeWidth="3.2" />
          <path d="M14 25h6M24 25h4M32 25h4" stroke="currentColor" strokeWidth="3.2" strokeLinecap="round" />
        </svg>
      );
    case "orb":
      return (
        <svg viewBox="0 0 48 48" aria-hidden="true">
          <circle cx="24" cy="24" r="14" fill="none" stroke="currentColor" strokeWidth="3.2" />
          <circle cx="30" cy="20" r="5" />
        </svg>
      );
    case "arrows":
      return (
        <svg viewBox="0 0 48 48" aria-hidden="true">
          <path
            fill="none"
            stroke="currentColor"
            strokeWidth="3.4"
            strokeLinecap="round"
            strokeLinejoin="round"
            d="M16 20V8m0 0-6 6m6-6 6 6M32 28v12m0 0-6-6m6 6 6-6"
          />
        </svg>
      );
    case "menubar":
      return (
        <svg viewBox="0 0 48 48" aria-hidden="true">
          <rect x="6" y="10" width="36" height="28" rx="6" fill="none" stroke="currentColor" strokeWidth="3.2" />
          <path d="M6 18h36" stroke="currentColor" strokeWidth="3.2" />
          <rect x="30" y="12" width="8" height="4" rx="1.5" />
        </svg>
      );
    case "oss":
      return (
        <svg viewBox="0 0 48 48" aria-hidden="true">
          <path d="M24 8c-8.8 0-16 7.2-16 16s7.2 16 16 16 16-7.2 16-16S32.8 8 24 8zm0 6a4 4 0 1 1 0 8 4 4 0 0 1 0-8zm-7.5 18.2c1.9-2.6 4.5-4.2 7.5-4.2s5.6 1.6 7.5 4.2A11.9 11.9 0 0 1 24 36a11.9 11.9 0 0 1-7.5-3.8z" />
        </svg>
      );
    default: {
      const _exhaustive: never = name;
      return _exhaustive;
    }
  }
}
