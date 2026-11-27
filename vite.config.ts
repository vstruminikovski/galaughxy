import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import fs from 'node:fs';
import path from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';

/**
 * Dev-only disk endpoints so the studio can persist original assets straight into the repo:
 *   POST /api/save-prop   { name, recipe }   -> src/props/library/<name>.json
 *   POST /api/save-scene  { slug, scene }    -> src/scenes/<slug>/scene.json
 * Names are slugified so nothing can escape those folders.
 */
function studioSaveApi(): Plugin {
  const root = process.cwd();
  const slugify = (s: unknown) =>
    String(s ?? '')
      .toLowerCase()
      .replace(/[^a-z0-9-]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 64);

  const readJson = (req: IncomingMessage) =>
    new Promise<Record<string, unknown>>((resolve, reject) => {
      let body = '';
      req.on('data', (c: Buffer) => {
        body += c;
        if (body.length > 4_000_000) reject(new Error('payload too large'));
      });
      req.on('end', () => {
        try {
          resolve(JSON.parse(body || '{}'));
        } catch (e) {
          reject(e);
        }
      });
    });

  const send = (res: ServerResponse, code: number, data: unknown) => {
    res.statusCode = code;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(data));
  };

  const handler =
    (resolveTarget: (body: Record<string, unknown>) => { file: string; data: unknown } | null) =>
    async (req: IncomingMessage, res: ServerResponse) => {
      if (req.method !== 'POST') return send(res, 405, { error: 'POST only' });
      try {
        const body = await readJson(req);
        const target = resolveTarget(body);
        if (!target) return send(res, 400, { error: 'missing name/slug' });
        fs.mkdirSync(path.dirname(target.file), { recursive: true });
        fs.writeFileSync(target.file, JSON.stringify(target.data, null, 2) + '\n');
        send(res, 200, { ok: true, file: path.relative(root, target.file) });
      } catch (e) {
        send(res, 500, { error: String(e) });
      }
    };

  return {
    name: 'galaughxy-save-api',
    configureServer(server) {
      server.middlewares.use(
        '/api/save-prop',
        handler((b) => {
          const name = slugify(b.name);
          if (!name) return null;
          const recipe = { ...(b.recipe as object), name };
          return { file: path.join(root, 'src/props/library', `${name}.json`), data: recipe };
        }),
      );
      server.middlewares.use(
        '/api/save-scene',
        handler((b) => {
          const slug = slugify(b.slug);
          if (!slug) return null;
          return { file: path.join(root, 'src/scenes', slug, 'scene.json'), data: b.scene };
        }),
      );
    },
  };
}

export default defineConfig({
  plugins: [react(), studioSaveApi()],
  server: {
    host: true,
    allowedHosts: true,
    port: 5173,
  },
  build: {
    chunkSizeWarningLimit: 2000,
  },
});
