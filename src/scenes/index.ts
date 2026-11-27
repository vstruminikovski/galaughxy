import type { Episode } from '../types';
import { garden } from './garden/episode';
import { overflowingKitchen } from './overflowing-kitchen/episode';
import { pondLife } from './pond-life/episode';

/** The world: every scene is one node on the world map, linked by portals. */
export const EPISODES: Episode[] = [overflowingKitchen, pondLife, garden];
