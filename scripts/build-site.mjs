import { copyFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const staticFiles = [
  'index.html', 'style.css', 'app.js', 'matching.js', 'directory.js', 'classes.js',
  'beta.html', 'beta.js', 'timeline.js', 'capsules.js', 'pilot-school.js',
];

const url = process.env.JADIS_SUPABASE_URL?.trim();
const publishableKey = process.env.JADIS_SUPABASE_PUBLISHABLE_KEY?.trim();
const directoryAccess = process.env.JADIS_BETA_EXTERNAL_DIRECTORY?.trim();
if (directoryAccess && directoryAccess !== 'true' && directoryAccess !== 'false') {
  throw Error('JADIS_BETA_EXTERNAL_DIRECTORY must be true or false.');
}
const minimalPilot = process.env.JADIS_BETA_MINIMAL_PILOT?.trim();
if (minimalPilot && minimalPilot !== 'true' && minimalPilot !== 'false') {
  throw Error('JADIS_BETA_MINIMAL_PILOT must be true or false.');
}
if (minimalPilot === 'true' && directoryAccess === 'true') {
  throw Error('The minimal pilot cannot use the external directory.');
}
let config = null;

if (url || publishableKey) {
  if (!url || !/^sb_publishable_[A-Za-z0-9_-]+$/.test(publishableKey ?? '')) {
    throw Error('Set both JADIS_SUPABASE_URL and a Supabase publishable key.');
  }
  const target = new URL(url);
  const local = ['localhost', '127.0.0.1'].includes(target.hostname);
  if ((target.protocol !== 'https:' && !(local && target.protocol === 'http:'))
      || target.username || target.password || target.pathname !== '/' || target.search || target.hash) {
    throw Error('JADIS_SUPABASE_URL must be an HTTPS origin or a local HTTP origin.');
  }
  config = {
    url: target.origin, publishableKey,
    externalDirectory: directoryAccess === 'true', minimalPilot: minimalPilot === 'true',
  };
}

const output = resolve(process.argv[2] ?? 'site');
await mkdir(output, { recursive: true });
await Promise.all(staticFiles.map(file =>
  copyFile(new URL('../' + file, import.meta.url), resolve(output, file))));
await writeFile(resolve(output, 'beta-config.js'), 'export const betaConfig = ' + JSON.stringify(config) + ';\n');
