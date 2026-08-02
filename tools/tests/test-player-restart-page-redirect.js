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

const scheduled = new Map();
let nextTimer = 1;
const navigations = [];
const context = vm.createContext({
  URL,
  RESTART_PAGE_GRACE_MS: 7000,
  state: { restartPageTimer: null, restartPending: true },
  window: { location: { href: 'https://stream.example.test:8889/watch/?quality=high#debug' } },
  location: { replace: (target) => navigations.push(target) },
  log: () => {},
  writeStreamStateSnapshot: () => {},
  setTimeout: (callback, delay) => {
    const id = nextTimer++;
    scheduled.set(id, { callback, delay, cleared: false });
    return id;
  },
  clearTimeout: (id) => {
    const timer = scheduled.get(id);
    if (timer) timer.cleared = true;
  }
});

vm.runInContext([
  extractFunction('cancelRestartPageRedirect'),
  extractFunction('scheduleRestartPageRedirect')
].join('\n'), context);

context.scheduleRestartPageRedirect();
const firstTimerId = context.state.restartPageTimer;
assert(firstTimerId, 'restart page redirect was not scheduled');
assert.strictEqual(scheduled.get(firstTimerId).delay, 7000, 'restart grace period is not seven seconds');
context.scheduleRestartPageRedirect();
assert.strictEqual(scheduled.size, 1, 'duplicate restart polls scheduled duplicate redirects');

scheduled.get(firstTimerId).callback();
assert.deepStrictEqual(navigations, ['https://stream.example.test:8889/watch/'], 'restart navigation did not preserve the accessed origin and viewer mount');

context.state.restartPending = true;
context.scheduleRestartPageRedirect();
const cancelledTimerId = context.state.restartPageTimer;
context.cancelRestartPageRedirect();
assert.strictEqual(context.state.restartPageTimer, null, 'cancel did not clear restart timer state');
assert.strictEqual(scheduled.get(cancelledTimerId).cleared, true, 'cancel did not clear the browser timer');

assert(source.includes("if (data.restarting) {"), 'stream-state restart branch is missing');
assert(source.includes('scheduleRestartPageRedirect();'), 'restart branch no longer schedules the holding page');
assert(source.includes("res.status === 503 && /^\\s*2\\s*;\\s*url=/i.test(refreshHeader)"), 'proxy holding responses no longer schedule prolonged restart navigation');
assert(source.includes('function finishRestart() {\n    cancelRestartPageRedirect();'), 'successful restart no longer cancels the holding-page redirect');

console.log('Player delayed restart-page redirect checks passed.');
