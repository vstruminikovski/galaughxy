import type { Expression } from '../types';

/**
 * 8x8 pixel-LED faces. Rows 0–4 = eyes/brows, rows 5–7 = mouth.
 * Every expression has a closed + open mouth so lip-sync stays expression-locked.
 */
interface Face {
  color: string;
  eyes: string[];
  closed: string[];
  open: string[];
}

export const LED_FACES: Record<Expression, Face> = {
  DEADPAN: {
    color: '#38e8ff',
    eyes: ['........', '........', '###..###', '........', '........'],
    closed: ['........', '..####..', '........'],
    open: ['..####..', '..#..#..', '..####..'],
  },
  SMIRK: {
    color: '#c6ff3a',
    eyes: ['......##', '.....#..', '.##..##.', '.##..##.', '........'],
    closed: ['........', '.....##.', '..###...'],
    open: ['.....##.', '..##..#.', '...###..'],
  },
  PANIC: {
    color: '#ff5a2a',
    eyes: ['#......#', '###..###', '#.#..#.#', '###..###', '........'],
    closed: ['.#.#.#.#', '#.#.#.#.', '........'],
    open: ['.######.', '#......#', '.######.'],
  },
  ANGRY: {
    color: '#ff2340',
    eyes: ['##....##', '..#..#..', '........', '.##..##.', '.##..##.'],
    closed: ['........', '..####..', '.#....#.'],
    open: ['.######.', '.#.##.#.', '.######.'],
  },
  HAPPY: {
    color: '#3dff7a',
    eyes: ['........', '.#....#.', '#.#..#.#', '........', '........'],
    closed: ['.#....#.', '..####..', '........'],
    open: ['#......#', '.######.', '..####..'],
  },
  SHOCKED: {
    color: '#f2f6ff',
    eyes: ['###..###', '#.#..#.#', '###..###', '........', '........'],
    closed: ['........', '...##...', '........'],
    open: ['..####..', '..#..#..', '..####..'],
  },
};

/** Returns 64 booleans, row-major from the top-left pixel. */
export function ledPixels(expr: Expression, open: boolean): boolean[] {
  const f = LED_FACES[expr];
  const rows = [...f.eyes, ...(open ? f.open : f.closed)];
  return rows.flatMap((r) => [...r].map((ch) => ch === '#'));
}
