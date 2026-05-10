/* global React, GAME */
const { useState, useEffect, useRef, useMemo, useCallback } = React;
const { TIERS, PROGRESSION, PENIBER_INTRO, PENIBER_BARKS, MAP_VIGNETTES } = GAME;

// ─── Helpers ─────────────────────────────────────────────────
function fmt(n) {
  if (n < 1000) return String(n);
  const units = ["", "K", "M", "B", "T", "Qa", "Qi"];
  const i = Math.min(Math.floor(Math.log10(n) / 3), units.length - 1);
  const v = n / Math.pow(1000, i);
  return (v >= 100 ? v.toFixed(0) : v >= 10 ? v.toFixed(1) : v.toFixed(2)) + units[i];
}
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
function uid() { return Math.random().toString(36).slice(2, 9); }

// ─── Status bar ──────────────────────────────────────────────
function StatusBar() {
  return (
    <div className="status-bar">
      <span>9:30</span>
      <span className="punch" />
      <div className="icons">
        <svg viewBox="0 0 16 16"><path d="M8 13L1 6a10 10 0 0114 0L8 13z" /></svg>
        <svg viewBox="0 0 16 16"><rect x="3" y="2" width="10" height="13" rx="1" /></svg>
      </div>
    </div>
  );
}

// ─── HUD ─────────────────────────────────────────────────────
function HUD({ progress, tier }) {
  return (
    <div className="hud">
      <div className="currency gold">
        <div className="glyph">G</div>
        <div>
          <div className="lbl">GOLD</div>
          <div className="val">{fmt(progress.gold)}</div>
        </div>
      </div>
      <div className="currency rp">
        <div className="glyph">R</div>
        <div>
          <div className="lbl">RANCHER</div>
          <div className="val">{fmt(progress.rp)}</div>
        </div>
      </div>
      <div className="currency shiny">
        <div className="glyph">★</div>
        <div>
          <div className="lbl">SHINIES</div>
          <div className="val">{fmt(progress.shinies)}</div>
        </div>
      </div>
    </div>
  );
}

// ─── Tier ribbon ─────────────────────────────────────────────
function TierRibbon({ tier, progress }) {
  const pct = Math.round((progress.species.caught / progress.species.total) * 100);
  return (
    <div className="tier-ribbon">
      <div className="badge">T{tier.id}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="name">
          <b>{tier.name}</b> · {progress.species.caught}/{progress.species.total} SPECIES
        </div>
        <div className="progress"><span style={{ width: pct + "%" }} /></div>
      </div>
      <div className="pct">{pct}%</div>
    </div>
  );
}

// ─── Auto-net widget ─────────────────────────────────────────
function AutoNet({ progress }) {
  if (!progress.autoNet.owned) return null;
  return (
    <div className="autonet">
      <div className="head"><span className="dot" />AUTO·NET</div>
      <div className="bar"><span /></div>
      <div className="lvl">
        <span>LV {progress.autoNet.level}</span>
        <span>3.0s</span>
      </div>
    </div>
  );
}

// ─── Monster sprite ──────────────────────────────────────────
function Monster({ mon, x, y, onCatch, state }) {
  return (
    <div
      className="mon"
      data-state={state}
      style={{ left: `${x}%`, top: `${y}%`, "--h": mon.hue }}
      onClick={() => state !== "catching" && onCatch(mon)}
    >
      <div className="body" />
      <div className="label">{mon.label}</div>
      <div className="hp"><span style={{ width: state === "catching" ? "10%" : "100%" }} /></div>
    </div>
  );
}

// ─── Vignettes (decorative props) ────────────────────────────
function Vignettes({ tierId }) {
  const items = MAP_VIGNETTES[tierId] || [];
  return (
    <>
      {items.map((v, i) => (
        <div key={i} className="vignette" style={{ left: `${v.x}%`, top: `${v.y}%` }}>
          <div className="blob" />
          <div className="lbl">{v.label}</div>
        </div>
      ))}
    </>
  );
}

// ─── Catch screen ────────────────────────────────────────────
function CatchScreen({ progress, hudLayout, onCatch, mons, floats, toast }) {
  const tier = TIERS.find(t => t.id === progress.tierId);
  return (
    <div className="screen" data-hud={hudLayout}>
      {hudLayout === "topbar" && <HUD progress={progress} tier={tier} />}
      <TierRibbon tier={tier} progress={progress} />
      {hudLayout !== "topbar" && <HUD progress={progress} tier={tier} />}
      <div className="map">
        <Vignettes tierId={tier.id} />
        {mons.map(m => (
          <Monster
            key={m.key}
            mon={m.mon}
            x={m.x}
            y={m.y}
            state={m.state}
            onCatch={(mon) => onCatch(mon, m.key, m.x, m.y)}
          />
        ))}
        {floats.map(f => (
          <div
            key={f.key}
            className={`float-gain ${f.kind === "item" ? "item" : ""}`}
            style={{ left: `${f.x}%`, top: `${f.y}%` }}
          >{f.text}</div>
        ))}
        {toast && <div className="toast">{toast}</div>}
      </div>
      <AutoNet progress={progress} />
    </div>
  );
}

// ─── Stub screens ────────────────────────────────────────────
function BattleStub({ progress }) {
  if (progress.pets === 0) {
    return (
      <div className="stub">
        <h2>PET ARENA</h2>
        <div className="stub-empty">
          <div className="glyph">⚔</div>
          Complete a tier to earn a pet companion. Then pets battle while you nap.
        </div>
      </div>
    );
  }
  const tier = TIERS.find(t => t.id === progress.tierId);
  const pets = TIERS.flatMap(t => t.monsters).slice(0, progress.pets);
  return (
    <div className="stub">
      <h2>PET ARENA · ROUND 14</h2>
      {pets.slice(0, 3).map((p, i) => (
        <div key={p.id} className="row">
          <div className="thumb" style={{ "--h": p.hue }} />
          <div className="meta">
            <div className="nm">PET · {p.label}</div>
            <div className="ct">LV {7 + i * 3} · {["TANK","SCOUT","MAGE"][i]} · IDLE 3.4s</div>
          </div>
          <div className="qty">+{fmt(8 + i * 14)} RP</div>
        </div>
      ))}
      <div className="row" style={{ marginTop: 8, opacity: 0.6 }}>
        <div className="thumb" style={{ "--h": 0, background: "#3a2d6f", borderColor: "#2a1f4a" }} />
        <div className="meta">
          <div className="nm">SLOT · LOCKED</div>
          <div className="ct">REACH TIER {progress.tierId + 1}</div>
        </div>
      </div>
    </div>
  );
}

function InventoryStub({ progress }) {
  const items = [
    { name: "Slime Slime",       qty: 1240, h: 158 },
    { name: "Crackle Jelly",     qty: 482,  h: 48  },
    { name: "Lunar Goo",         qty: 96,   h: 268 },
    { name: "Wisplet Ectoplasm", qty: 159,  h: 196 },
    { name: "Pixie Dust",        qty: 24,   h: 296 },
  ].slice(0, progress.tierId === 1 ? 1 : progress.tierId === 2 ? 4 : 5);
  return (
    <div className="stub">
      <h2>SATCHEL · {items.length} KIND{items.length === 1 ? "" : "S"}</h2>
      {items.map(it => (
        <div key={it.name} className="row">
          <div className="thumb" style={{ "--h": it.h }} />
          <div className="meta">
            <div className="nm">{it.name.toUpperCase()}</div>
            <div className="ct">CRAFT · TRADE · CONSUME</div>
          </div>
          <div className="qty">×{fmt(it.qty)}</div>
        </div>
      ))}
    </div>
  );
}

function UpgradesStub({ progress }) {
  const ups = [
    { n: "Reinforced Net",   c: "12 RP",  d: "+1 catch slot" },
    { n: "Slime Magnet",     c: "40 RP",  d: "Auto-claim drops" },
    { n: "Wisplet Whistle",  c: "80 RP",  d: "+25% T2 spawn" },
    { n: "Glassblown Vial",  c: "200 RP", d: "Shinies × 2" },
  ];
  return (
    <div className="stub">
      <h2>RANCHER UPGRADES</h2>
      <div style={{ fontFamily: "var(--font-body)", fontSize: 16, color: "var(--ink-dim)", marginBottom: 10 }}>
        Permanent. Survive prestige. Spend wisely or don't — I won't supervise.
      </div>
      {ups.map((u, i) => (
        <div key={u.n} className="row">
          <div className="thumb" style={{ "--h": 48 + i * 60 }} />
          <div className="meta">
            <div className="nm">{u.n.toUpperCase()}</div>
            <div className="ct">{u.d.toUpperCase()}</div>
          </div>
          <button className="pixel-btn pixel-btn--gold" style={{ fontSize: 9, padding: "6px 8px" }}>{u.c}</button>
        </div>
      ))}
    </div>
  );
}

function MoreStub({ progress }) {
  const rows = [
    { n: "Bestiary",      d: `${progress.species.caught}/${progress.species.total} discovered` },
    { n: "Achievements",  d: "12 / 60 unlocked" },
    { n: "Prestige",      d: `Available · ${fmt(progress.gold)} → ${fmt(Math.floor(progress.gold / 1e6))} RP` },
    { n: "Settings",      d: "Sound · Haptics · Save" },
    { n: "Codex",         d: "Lore · monster notes (Peniber's, mostly)" },
  ];
  return (
    <div className="stub">
      <h2>MORE</h2>
      {rows.map(r => (
        <div key={r.n} className="row">
          <div className="thumb" style={{ "--h": Math.floor(Math.random() * 360) }} />
          <div className="meta">
            <div className="nm">{r.n.toUpperCase()}</div>
            <div className="ct">{r.d.toUpperCase()}</div>
          </div>
          <div className="qty" style={{ color: "var(--ink-mute)", fontSize: 14 }}>›</div>
        </div>
      ))}
    </div>
  );
}

// ─── Tab bar ─────────────────────────────────────────────────
const TABS = [
  { id: "catch",     label: "CATCH",    glyph: "⌖" },
  { id: "battle",    label: "BATTLE",   glyph: "⚔" },
  { id: "inventory", label: "INV",      glyph: "▣" },
  { id: "upgrades",  label: "UPGRADE",  glyph: "↑" },
  { id: "more",      label: "MORE",     glyph: "≡" },
];
function TabBar({ active, onChange }) {
  return (
    <div className="tabbar">
      {TABS.map(t => (
        <button
          key={t.id}
          data-active={active === t.id}
          onClick={() => onChange(t.id)}
        >
          <span className="ico">{t.glyph}</span>
          <span>{t.label}</span>
        </button>
      ))}
    </div>
  );
}

// ─── Peniber dialog ribbon (in-game) ─────────────────────────
function PeniberRibbon({ line, onDismiss }) {
  const [shown, setShown] = useState("");
  useEffect(() => {
    setShown("");
    let i = 0;
    const id = setInterval(() => {
      i++;
      setShown(line.slice(0, i));
      if (i >= line.length) clearInterval(id);
    }, 18);
    return () => clearInterval(id);
  }, [line]);
  const time = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  return (
    <div className="peniber dismissable" onClick={onDismiss}>
      <button className="close" onClick={(e) => { e.stopPropagation(); onDismiss(); }}>×</button>
      <div className="pen-head">
        <div className="portrait" />
        <div className="name">PENIBER</div>
        <div className="timestamp">{time}</div>
      </div>
      <div className="text">
        {shown}{shown.length < line.length && <span className="caret" />}
      </div>
    </div>
  );
}

// ─── Intro overlay ──────────────────────────────────────────
function Intro({ onDone }) {
  const [i, setI] = useState(0);
  const [shown, setShown] = useState("");
  const line = PENIBER_INTRO[i].text;
  useEffect(() => {
    setShown("");
    let n = 0;
    const id = setInterval(() => {
      n++;
      setShown(line.slice(0, n));
      if (n >= line.length) clearInterval(id);
    }, 22);
    return () => clearInterval(id);
  }, [i, line]);

  const next = () => {
    if (shown.length < line.length) { setShown(line); return; }
    if (i < PENIBER_INTRO.length - 1) setI(i + 1);
    else onDone();
  };

  return (
    <div className="intro-overlay" onClick={next}>
      <div className="title">
        <h1>IDLE BEAST PRACTICES</h1>
        <div className="sub">A WIZARD'S RELUCTANT TUTORIAL</div>
      </div>
      <button className="skip" onClick={(e) => { e.stopPropagation(); onDone(); }}>SKIP ›</button>

      <div className="pen-stage">
        <div className="pen">
          <div className="hat" />
          <div className="head" />
          <div className="beard" />
          <div className="robe" />
        </div>
      </div>

      <div className="pen-bubble" onClick={(e) => e.stopPropagation()}>
        <div className="pin">PENIBER</div>
        <div className="text">
          {shown}{shown.length < line.length && <span className="caret" style={{
            display: "inline-block", width: 6, height: 14,
            background: "var(--gold)", marginLeft: 2, verticalAlign: -2,
          }} />}
        </div>
        <div className="controls">
          <div className="dots">
            {PENIBER_INTRO.map((_, k) => <i key={k} className={k <= i ? "on" : ""} />)}
          </div>
          <button className="pixel-btn pixel-btn--gold" onClick={next}>
            {shown.length < line.length ? "FAST ›" : i === PENIBER_INTRO.length - 1 ? "BEGIN" : "NEXT ›"}
          </button>
        </div>
      </div>
    </div>
  );
}

window.IBP_UI = {
  StatusBar, HUD, TierRibbon, AutoNet, Monster, Vignettes,
  CatchScreen, BattleStub, InventoryStub, UpgradesStub, MoreStub,
  TabBar, PeniberRibbon, Intro, TABS, fmt, pick, uid,
};
