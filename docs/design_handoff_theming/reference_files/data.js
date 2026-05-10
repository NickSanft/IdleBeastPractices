// Game data — tiers, monsters, drops, Peniber lines.
// Original IP, generic placeholder names. Tier-keyed so HUD reflects progression.
(function () {
const TIERS = [
  {
    id: 1,
    name: "Bog Hollow",
    sub: "Tier I · Slimes",
    accent: "#5fd3c2",
    monsters: [
      { id: "slime-bog",   label: "SLIME · BOG",   drop: "Slime Slime",      gold: 3,    hue: 158 },
      { id: "slime-spark", label: "SLIME · SPARK", drop: "Crackle Jelly",    gold: 7,    hue: 48  },
      { id: "slime-moon",  label: "SLIME · MOON",  drop: "Lunar Goo",        gold: 21,   hue: 268 },
    ],
  },
  {
    id: 2,
    name: "Whisper Glade",
    sub: "Tier II · Fairies",
    accent: "#d96fb8",
    monsters: [
      { id: "wisplet",     label: "WISPLET · T2",  drop: "Wisplet Ectoplasm", gold: 84,   hue: 196 },
      { id: "pixie-dusk",  label: "PIXIE · DUSK",  drop: "Pixie Dust",        gold: 240,  hue: 296 },
      { id: "fae-thorn",   label: "FAE · THORN",   drop: "Thorn Pollen",      gold: 600,  hue: 332 },
    ],
  },
  {
    id: 3,
    name: "Ash Reach",
    sub: "Tier III · Drakelings",
    accent: "#f5c46b",
    monsters: [
      { id: "drake-ember", label: "DRAKE · EMBER", drop: "Ember Scale",       gold: 1800,  hue: 24  },
      { id: "drake-soot",  label: "DRAKE · SOOT",  drop: "Soot Ash",          gold: 5400,  hue: 12  },
      { id: "drake-glass", label: "DRAKE · GLASS", drop: "Glass Tooth",       gold: 16000, hue: 340 },
    ],
  },
];

// Tier progression presets — used by the "Tier state" tweak.
const PROGRESSION = {
  early: {
    tierId: 1,
    gold: 412,
    rp: 0,
    shinies: 2,
    species: { caught: 1, total: 3 },
    autoNet: { owned: false, level: 0 },
    pets: 0,
  },
  mid: {
    tierId: 2,
    gold: 42_000_000,
    rp: 242,
    shinies: 17,
    species: { caught: 6, total: 9 }, // T1 done + 3 of T2
    autoNet: { owned: true, level: 3 },
    pets: 3,
  },
  late: {
    tierId: 3,
    gold: 12_400_000_000,
    rp: 5840,
    shinies: 124,
    species: { caught: 8, total: 9 },
    autoNet: { owned: true, level: 14 },
    pets: 6,
  },
};

// Peniber lines — sarcastic, dry, snappy. Original character.
const PENIBER_INTRO = [
  {
    mood: "weary",
    text: "Oh. You're awake. Marvelous. I had begun to suspect the contract was void."
  },
  {
    mood: "explaining",
    text: "I am Peniber. Your wizard, technically. Your supervisor, functionally. Try not to make either fact embarrassing."
  },
  {
    mood: "dry",
    text: "These are slimes. They are stupid. You catch them by tapping. Yes — that is the whole of it. We will work up to harder verbs."
  },
  {
    mood: "exiting",
    text: "I'll be hovering. Nominally helpful. Spiritually appalled. Begin."
  },
];

const PENIBER_BARKS = {
  // Random ambient lines that appear in the dialog ribbon during play.
  idle: [
    "Returned, and just in time. The auto-net is, as ever, indifferent to whether anyone is watching, but I am.",
    "If you stare at the slimes any longer they will, at minimum, file a complaint.",
    "A productive silence. Treasure it. I won't.",
    "Your nets are working. This is what 'idle' means. Yes, I had to look it up too.",
  ],
  caught: [
    "One down. Approximately several thousand to go. Good pace.",
    "A clean catch. I'm withholding pride on principle.",
    "Acceptable. Don't let it become a habit of competence.",
  ],
  tierUp: [
    "Oh good — you've graduated. Try not to get eaten by the next ones.",
    "A new tier. The old monsters weep with relief.",
  ],
  prestige: [
    "You'd like to start over? Bold. Let me find the lever marked 'humility'.",
  ],
};

// Map ambient lore — small environment vignettes labeled as placeholders.
const MAP_VIGNETTES = {
  1: [
    { x: 12, y: 22, label: "BOG · LANTERN" },
    { x: 78, y: 34, label: "STONE · MOSS"  },
    { x: 22, y: 72, label: "REED · CLUMP"  },
    { x: 70, y: 78, label: "PUDDLE · MOON" },
  ],
  2: [
    { x: 18, y: 18, label: "TOADSTOOL · RING" },
    { x: 76, y: 28, label: "WILLOW · OLD" },
    { x: 26, y: 76, label: "FAERIE · CIRCLE" },
    { x: 72, y: 82, label: "GLADE · SHRINE" },
  ],
  3: [
    { x: 14, y: 24, label: "OBSIDIAN · SPIRE" },
    { x: 80, y: 32, label: "ASH · DRIFT" },
    { x: 24, y: 78, label: "EMBER · VENT" },
    { x: 74, y: 80, label: "BONE · ARCH" },
  ],
};

window.GAME = { TIERS, PROGRESSION, PENIBER_INTRO, PENIBER_BARKS, MAP_VIGNETTES };
})();
