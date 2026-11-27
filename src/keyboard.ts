export type KeyCap = {
  code: string;
  label: string;
  w: number;
  x: number;
  y: number;
};

type RawKey = {
  code: string;
  label: string;
  w?: number;
};

const ROWS: RawKey[][] = [
  [
    { code: "Backquote", label: "`" },
    { code: "Digit1", label: "1" },
    { code: "Digit2", label: "2" },
    { code: "Digit3", label: "3" },
    { code: "Digit4", label: "4" },
    { code: "Digit5", label: "5" },
    { code: "Digit6", label: "6" },
    { code: "Digit7", label: "7" },
    { code: "Digit8", label: "8" },
    { code: "Digit9", label: "9" },
    { code: "Digit0", label: "0" },
    { code: "Minus", label: "-" },
    { code: "Equal", label: "=" },
    { code: "Backspace", label: "del", w: 2 },
  ],
  [
    { code: "Tab", label: "tab", w: 1.5 },
    { code: "KeyQ", label: "Q" },
    { code: "KeyW", label: "W" },
    { code: "KeyE", label: "E" },
    { code: "KeyR", label: "R" },
    { code: "KeyT", label: "T" },
    { code: "KeyY", label: "Y" },
    { code: "KeyU", label: "U" },
    { code: "KeyI", label: "I" },
    { code: "KeyO", label: "O" },
    { code: "KeyP", label: "P" },
    { code: "BracketLeft", label: "[" },
    { code: "BracketRight", label: "]" },
    { code: "Backslash", label: "\\", w: 1.5 },
  ],
  [
    { code: "CapsLock", label: "caps", w: 1.75 },
    { code: "KeyA", label: "A" },
    { code: "KeyS", label: "S" },
    { code: "KeyD", label: "D" },
    { code: "KeyF", label: "F" },
    { code: "KeyG", label: "G" },
    { code: "KeyH", label: "H" },
    { code: "KeyJ", label: "J" },
    { code: "KeyK", label: "K" },
    { code: "KeyL", label: "L" },
    { code: "Semicolon", label: ";" },
    { code: "Quote", label: "'" },
    { code: "Enter", label: "enter", w: 2.25 },
  ],
  [
    { code: "ShiftLeft", label: "shift", w: 2.25 },
    { code: "KeyZ", label: "Z" },
    { code: "KeyX", label: "X" },
    { code: "KeyC", label: "C" },
    { code: "KeyV", label: "V" },
    { code: "KeyB", label: "B" },
    { code: "KeyN", label: "N" },
    { code: "KeyM", label: "M" },
    { code: "Comma", label: "," },
    { code: "Period", label: "." },
    { code: "Slash", label: "/" },
    { code: "ShiftRight", label: "shift", w: 2.75 },
  ],
  [
    { code: "ControlLeft", label: "ctrl", w: 1.4 },
    { code: "AltLeft", label: "opt", w: 1.25 },
    { code: "MetaLeft", label: "cmd", w: 1.4 },
    { code: "Space", label: "", w: 6.1 },
    { code: "MetaRight", label: "cmd", w: 1.4 },
    { code: "AltRight", label: "opt", w: 1.25 },
    { code: "ControlRight", label: "ctrl", w: 1.4 },
  ],
];

const FALLBACK: Record<string, { x: number; y: number }> = {
  Escape: { x: 0.02, y: 0 },
  ArrowLeft: { x: 0.72, y: 1 },
  ArrowDown: { x: 0.82, y: 1 },
  ArrowRight: { x: 0.92, y: 1 },
  ArrowUp: { x: 0.82, y: 0.82 },
};

function buildRows(): KeyCap[][] {
  return ROWS.map((row, rowIndex) => {
    const total = row.reduce((sum, key) => sum + (key.w ?? 1), 0);
    let cursor = 0;
    return row.map((key) => {
      const w = key.w ?? 1;
      const cap: KeyCap = {
        code: key.code,
        label: key.label,
        w,
        x: (cursor + w / 2) / total,
        y: rowIndex / (ROWS.length - 1),
      };
      cursor += w;
      return cap;
    });
  });
}

export const KEY_ROWS = buildRows();

const BY_CODE = new Map<string, KeyCap>();
for (const row of KEY_ROWS) {
  for (const key of row) BY_CODE.set(key.code, key);
}

export function keyLabel(code: string): string {
  const cap = BY_CODE.get(code);
  if (cap) {
    if (code === "Space") return "space";
    return cap.label;
  }
  if (code.startsWith("Key") && code.length === 4) return code.slice(3);
  if (code.startsWith("Digit")) return code.slice(5);
  return code.replace(/([A-Z])/g, " $1").trim();
}

export function keyPosition(code: string): { x: number; y: number } {
  const cap = BY_CODE.get(code);
  if (cap) return { x: cap.x, y: cap.y };
  return FALLBACK[code] ?? { x: 0.5, y: 0.45 };
}
