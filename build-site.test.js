import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const builder = fileURLToPath(new URL('./scripts/build-site.mjs', import.meta.url));

async function build(t, url = '', key = '') {
  const output = await mkdtemp(join(tmpdir(), 'jadis-build-'));
  t.after(() => rm(output, { recursive: true, force: true }));
  const result = spawnSync(process.execPath, [builder, output], {
    encoding: 'utf8',
    env: { ...process.env, JADIS_SUPABASE_URL: url, JADIS_SUPABASE_PUBLISHABLE_KEY: key },
  });
  return { output, result };
}

test('the static site has no beta target by default', async t => {
  const { output, result } = await build(t);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(await readFile(join(output, 'beta-config.js'), 'utf8'), 'export const betaConfig = null;\n');
  assert.match(await readFile(join(output, 'beta.html'), 'utf8'), /id="auth" method="post" hidden/);
});

test('the build includes only the explicit isolated beta target and public key', async t => {
  const { output, result } = await build(t, 'https://jadis-fixture.example.test/', 'sb_publishable_fixture');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(await readFile(join(output, 'beta-config.js'), 'utf8'),
    'export const betaConfig = {"url":"https://jadis-fixture.example.test","publishableKey":"sb_publishable_fixture"};\n');
});

test('the build rejects incomplete, non-public and invalid target configurations', async t => {
  for (const [url, key] of [
    ['https://jadis-fixture.example.test', ''],
    ['https://jadis-fixture.example.test', 'private-fixture-value'],
    ['http://jadis-fixture.example.test', 'sb_publishable_fixture'],
    ['https://jadis-fixture.example.test/path', 'sb_publishable_fixture'],
  ]) {
    const { output, result } = await build(t, url, key);
    assert.equal(result.status, 1);
    await assert.rejects(readFile(join(output, 'beta-config.js')), { code: 'ENOENT' });
  }
});
