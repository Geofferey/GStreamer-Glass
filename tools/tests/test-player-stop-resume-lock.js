// SPDX-License-Identifier: AGPL-3.0-only
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const repoRoot = path.resolve(__dirname, '..', '..');
const source = fs.readFileSync(path.join(repoRoot, 'gstwebrtc-api', 'dist', 'player.js'), 'utf8');

function extractFunction(name) {
  const start = source.indexOf(`  function ${name}(`);
  assert(start >= 0, `${name} was not found`);
  const bodyStart = source.indexOf('{', start);
  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(start, index + 1);
    }
  }
  throw new Error(`${name} has no closing brace`);
}

const storedState = {
  intentionalStop: true,
  restarting: false,
  transition: 'stop',
  transitionToken: 'stop-token',
  authRevokedToken: 'auth-token',
  writtenUtc: '2026-08-02T12:00:00.000Z',
  manualResumeRequired: true
};
const values = new Map([['gstglass-stream-state-snapshot-v1', JSON.stringify(storedState)]]);
const context = vm.createContext({
  STREAM_STATE_SNAPSHOT_KEY: 'gstglass-stream-state-snapshot-v1',
  state: { stopResumeLocked: false, intentionalStopMarker: false, restartPending: false, streamTransitionToken: null, authRevokedToken: null, lastStreamStateSnapshot: storedState },
  sessionStorage: {
    getItem: (key) => values.has(key) ? values.get(key) : null,
    setItem: (key, value) => values.set(key, value),
    removeItem: (key) => values.delete(key)
  }
});

vm.runInContext([
  extractFunction('normalizeStreamStateSnapshot'),
  extractFunction('loadStreamStateSnapshot'),
  extractFunction('writeStreamStateSnapshot'),
  extractFunction('setStopResumeLock')
].join('\n'), context);

const restored = context.loadStreamStateSnapshot();
assert.strictEqual(restored.intentionalStop, true, 'the prior state document was not restored after navigation');
assert.strictEqual(restored.transitionToken, 'stop-token', 'the prior transition identity was lost across navigation');
assert.strictEqual(restored.manualResumeRequired, true, 'the prior manual-resume decision was not restored after navigation');
context.setStopResumeLock(true);
assert.strictEqual(context.state.stopResumeLocked, true, 'locking did not update live player state');
assert.strictEqual(JSON.parse(values.get('gstglass-stream-state-snapshot-v1')).manualResumeRequired, true, 'locking was not persisted with the state snapshot');
context.setStopResumeLock(false);
assert.strictEqual(context.state.stopResumeLocked, false, 'explicit resume did not unlock live player state');
assert.strictEqual(JSON.parse(values.get('gstglass-stream-state-snapshot-v1')).manualResumeRequired, false, 'explicit resume did not clear the snapshot resume lock');

assert(source.includes('const restoredStreamState = loadStreamStateSnapshot();'), 'player startup does not load the saved state document');
assert(source.includes('streamTransitionToken: restoredStreamState ? restoredStreamState.transitionToken : null'), 'player startup discards the saved transition identity');
assert(source.includes('manualResumeRequired: restoredStopResumeLock'), 'a reloaded player does not begin in manual-resume mode');
assert(source.includes('stopResumeLocked: restoredStopResumeLock'), 'a reloaded player does not restore the stop lock');
assert(source.includes('const data = await res.json();\n      rememberStreamState(data);'), 'successful state polls are not saved before restart navigation');
assert(source.includes('writeStreamStateSnapshot(state.lastStreamStateSnapshot);\n      const viewerUrl'), 'restart navigation does not preserve the last state document first');
assert((source.match(/setStopResumeLock\(true\);/g) || []).length === 2, 'both intentional-stop detection paths must persist the lock');
assert(source.includes('state.manualResumeRequired = false;\n      setStopResumeLock(false);'), 'the explicit Play path no longer clears the persisted lock');

console.log('Player stop/resume lock persistence checks passed.');
