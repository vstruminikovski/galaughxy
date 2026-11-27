import type { CapacitorConfig } from '@capacitor/cli';

// Native wrapper for Phase 2 (Android / iOS). Run `npm run cap:sync` after `npx cap add android|ios`.
const config: CapacitorConfig = {
  appId: 'com.galaughxy.studio',
  appName: 'Galaughxy Studio',
  webDir: 'dist',
  backgroundColor: '#000000',
};

export default config;
