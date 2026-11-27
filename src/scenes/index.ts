import type { Episode } from '../types';
import { overflowingKitchen } from './overflowing-kitchen/episode';

/** Episode registry. Each room is self-contained so Phase 2 can stitch them via <ScenePortal />. */
export const EPISODES: Episode[] = [overflowingKitchen];
