/* global React, ReactDOM, GAME, IBP_UI, useTweaks, TweaksPanel, TweakSection, TweakRadio, TweakSelect, TweakToggle, TweakColor */
const { useState, useEffect, useRef, useCallback } = React;
const { TIERS, PROGRESSION, PENIBER_BARKS } = GAME;
const {
  StatusBar, CatchScreen, BattleStub, InventoryStub, UpgradesStub, MoreStub,
  TabBar, PeniberRibbon, Intro, pick, uid,
} = IBP_UI;

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "theme": "amethyst",
  "hudLayout": "topbar",
  "tier": "mid",
  "introOnLoad": false,
  "showAutoNet": true
}/*EDITMODE-END*/;

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [tab, setTab] = useState("catch");
  const [introOpen, setIntroOpen] = useState(t.introOnLoad);
  const [floats, setFloats] = useState([]);
  const [toast, setToast] = useState(null);
  const [bark, setBark] = useState(PENIBER_BARKS.idle[0]);
  const [barkOpen, setBarkOpen] = useState(true);

  // Re-open intro from tweaks
  useEffect(() => {
    if (t.introOnLoad) setIntroOpen(true);
  }, [t.introOnLoad]);

  const progress = PROGRESSION[t.tier];
  const tier = TIERS.find(x => x.id === progress.tierId);

  // Generate spawned monsters per tier
  const spawnPositions = [
    { x: 28, y: 30 },
    { x: 64, y: 22 },
    { x: 50, y: 56 },
    { x: 22, y: 60 },
    { x: 74, y: 64 },
  ];
  const [mons, setMons] = useState([]);
  useEffect(() => {
    const fresh = spawnPositions.slice(0, tier.id === 1 ? 3 : tier.id === 2 ? 4 : 5).map((p, i) => ({
      key: uid(),
      mon: tier.monsters[i % tier.monsters.length],
      x: p.x, y: p.y,
      state: "idle",
    }));
    setMons(fresh);
  }, [tier.id]);

  // Re-spawn monsters every few seconds when there's room
  useEffect(() => {
    const id = setInterval(() => {
      setMons(curr => {
        const max = tier.id === 1 ? 3 : tier.id === 2 ? 4 : 5;
        if (curr.filter(m => m.state === "idle").length >= max) return curr;
        const slot = pick(spawnPositions);
        const m = pick(tier.monsters);
        // avoid stacking
        if (curr.some(c => Math.abs(c.x - slot.x) < 8 && Math.abs(c.y - slot.y) < 8)) return curr;
        return [...curr.filter(m => m.state !== "gone"), {
          key: uid(), mon: m, x: slot.x, y: slot.y, state: "idle",
        }];
      });
    }, 2200);
    return () => clearInterval(id);
  }, [tier.id]);

  const handleCatch = useCallback((mon, key, x, y) => {
    setMons(curr => curr.map(m => m.key === key ? { ...m, state: "catching" } : m));
    setFloats(f => [
      ...f,
      { key: uid(), x, y: y - 4, text: `+${mon.gold} G`, kind: "gold" },
      { key: uid(), x, y: y + 4, text: `+1 ${mon.drop}`, kind: "item" },
    ]);
    setToast(`CAUGHT · ${mon.label}`);
    setBark(pick(PENIBER_BARKS.caught));
    setBarkOpen(true);
    setTimeout(() => {
      setMons(curr => curr.filter(m => m.key !== key));
    }, 380);
    setTimeout(() => setToast(null), 1900);
    setTimeout(() => {
      setFloats(f => f.filter(x => Date.now() - x.born < 1200));
    }, 1200);
  }, []);

  // Idle bark rotation
  useEffect(() => {
    const id = setInterval(() => {
      if (Math.random() < 0.4) {
        setBark(pick(PENIBER_BARKS.idle));
        setBarkOpen(true);
      }
    }, 11000);
    return () => clearInterval(id);
  }, []);

  const screen = (() => {
    if (tab === "catch") return (
      <CatchScreen
        progress={progress}
        hudLayout={t.hudLayout}
        onCatch={handleCatch}
        mons={mons}
        floats={floats}
        toast={toast}
      />
    );
    if (tab === "battle") return <BattleStub progress={progress} />;
    if (tab === "inventory") return <InventoryStub progress={progress} />;
    if (tab === "upgrades") return <UpgradesStub progress={progress} />;
    return <MoreStub progress={progress} />;
  })();

  return (
    <div className="phone-stage" data-theme={t.theme === "amethyst" ? null : t.theme}>
      <div className="phone">
        <div className="phone-screen">
          <StatusBar />
          {screen}
          {tab === "catch" && barkOpen && (
            <PeniberRibbon
              line={bark}
              onDismiss={() => setBarkOpen(false)}
            />
          )}
          <TabBar active={tab} onChange={(id) => { setTab(id); setBarkOpen(false); }} />
          {introOpen && <Intro onDone={() => { setIntroOpen(false); setTweak("introOnLoad", false); }} />}
        </div>
        <div className="gesture-pill" />
      </div>

      <TweaksPanel title="Tweaks">
        <TweakSection label="Theme">
          <TweakRadio
            label="Palette"
            value={t.theme}
            options={[
              { value: "amethyst",  label: "Amethyst" },
              { value: "twilight",  label: "Twilight" },
              { value: "ember",     label: "Ember"    },
            ]}
            onChange={(v) => setTweak("theme", v)}
          />
        </TweakSection>

        <TweakSection label="HUD layout">
          <TweakRadio
            label="Currency placement"
            value={t.hudLayout}
            options={[
              { value: "topbar",   label: "Top bar"  },
              { value: "floating", label: "Floating" },
              { value: "rail",     label: "Side rail" },
            ]}
            onChange={(v) => setTweak("hudLayout", v)}
          />
        </TweakSection>

        <TweakSection label="Progression">
          <TweakRadio
            label="Tier state"
            value={t.tier}
            options={[
              { value: "early", label: "Early" },
              { value: "mid",   label: "Mid"   },
              { value: "late",  label: "Late"  },
            ]}
            onChange={(v) => setTweak("tier", v)}
          />
        </TweakSection>

        <TweakSection label="Flow">
          <TweakToggle
            label="Replay Peniber's intro"
            value={introOpen}
            onChange={(v) => { setIntroOpen(v); }}
          />
        </TweakSection>
      </TweaksPanel>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
