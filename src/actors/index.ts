import { FrogActor } from './FrogActor';
import { RoboActor } from './RoboActor';

/** Actor registry: SceneObject.ref -> component. */
export const ACTOR_TYPES = { robo: RoboActor, frog: FrogActor } as const;
