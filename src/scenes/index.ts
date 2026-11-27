import type { Episode } from '../types';
import { overflowingKitchen } from './overflowing-kitchen/episode';
import { pondLife } from './pond-life/episode';

/** Episode registry. Each room is self-contained so Phase 2 can stitch them via <ScenePortal />. */
export const EPISODES: Episode[] = [pondLife, overflowingKitchen];
