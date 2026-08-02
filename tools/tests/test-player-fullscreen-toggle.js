const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const repoRoot = path.resolve(__dirname, '..', '..');
const playerSource = fs.readFileSync(path.join(repoRoot, 'gstwebrtc-api', 'dist', 'player.js'), 'utf8');

assert(!playerSource.includes('attemptAutoFullscreen'), 'fullscreen must never be requested automatically');
assert(!playerSource.includes("requestVideoFullscreen('auto')"), 'fullscreen requests require a direct viewer gesture');

function extractFunction(name) {
  const marker = `function ${name}`;
  const start = playerSource.indexOf(marker);
  assert(start >= 0, `missing ${name}`);
  const declarationStart = playerSource.slice(Math.max(0, start - 6), start) === 'async ' ? start - 6 : start;
  const bodyStart = playerSource.indexOf('{', start);
  assert(bodyStart >= 0, `missing body for ${name}`);
  let depth = 0;
  for (let index = bodyStart; index < playerSource.length; index += 1) {
    if (playerSource[index] === '{') depth += 1;
    if (playerSource[index] === '}') {
      depth -= 1;
      if (depth === 0) return playerSource.slice(declarationStart, index + 1);
    }
  }
  throw new Error(`unterminated body for ${name}`);
}

const calls = { rootRequest: 0, videoRequest: 0, exit: 0, toggle: [], gestures: [] };
const classNames = new Set();
const fullscreenButton = {
  textContent: '',
  title: '',
  attributes: {},
  setAttribute(name, value) { this.attributes[name] = value; }
};
const document = {
  fullscreenElement: null,
  webkitFullscreenElement: null,
  msFullscreenElement: null,
  documentElement: {},
  body: {
    classList: {
      add: (...names) => names.forEach((name) => classNames.add(name)),
      remove: (...names) => names.forEach((name) => classNames.delete(name)),
      contains: (name) => classNames.has(name),
      toggle: (name, enabled) => enabled ? classNames.add(name) : classNames.delete(name)
    }
  },
  exitFullscreen: async () => {
    calls.exit += 1;
    document.fullscreenElement = null;
  }
};
const video = {
  webkitDisplayingFullscreen: false,
  requestFullscreen: async () => {
    calls.videoRequest += 1;
    document.fullscreenElement = video;
  }
};
const playerRoot = {
  requestFullscreen: async () => {
    calls.rootRequest += 1;
    document.fullscreenElement = playerRoot;
  }
};

const context = vm.createContext({
  Date,
  Math,
  Promise,
  document,
  video,
  playerRoot,
  mobileBrowser: true,
  androidContainerFullscreen: true,
  fullscreenEnabled: () => true,
  pwaDisplayMode: () => 'fullscreen',
  setFullscreenState: () => {},
  syncScreenWakeLock: () => {},
  scheduleFullscreenRenderRecovery: () => {},
  log: () => {},
  state: {
    controller: { userPaused: false, fullscreenButton },
    videoZoom: { suppressTapUntil: 0 },
    manualResumeRequired: false
  },
  nativeMediaControlsEnabled: () => false,
  recordUserInteraction: () => {},
  syncMediaNotificationAnchor: () => {},
  toggleLogicalPause: () => {},
  noteUserGesture: (requestFullscreen) => calls.gestures.push(requestFullscreen)
});

[
  'elementFullscreenActive',
  'isFullscreen',
  'setFullscreenState',
  'fullscreenTarget',
  'requestVideoFullscreen',
  'exitPlayerFullscreen',
  'togglePlayerFullscreen',
  'handleVideoActivation'
].forEach((name) => vm.runInContext(extractFunction(name), context));

(async () => {
  assert.strictEqual(context.isFullscreen(), true, 'manifest fullscreen should remain immersive for styling');
  assert.strictEqual(context.elementFullscreenActive(), false, 'manifest fullscreen is not an element fullscreen session');
  context.setFullscreenState();
  assert.strictEqual(fullscreenButton.textContent, '⛶', 'the enter state should use the standard fullscreen glyph');

  assert.strictEqual(await context.togglePlayerFullscreen('test-enter'), true);
  assert.strictEqual(calls.rootRequest, 1, 'Android should retain its established container-fullscreen behavior');
  assert.strictEqual(context.elementFullscreenActive(), true);
  context.setFullscreenState();
  assert.strictEqual(fullscreenButton.textContent, '⛶', 'the exit state should retain the standard fullscreen glyph');
  assert.strictEqual(fullscreenButton.title, 'Exit fullscreen', 'the accessible label should still describe the exit action');

  assert.strictEqual(await context.togglePlayerFullscreen('test-exit'), true);
  assert.strictEqual(calls.exit, 1, 'the second toggle should exit element fullscreen');
  assert.strictEqual(context.elementFullscreenActive(), false);
  assert.strictEqual(context.isFullscreen(), true, 'exiting the element must not lose manifest immersive styling');

  context.androidContainerFullscreen = false;
  context.mobileBrowser = false;
  context.nativeMediaControlsEnabled = () => false;
  assert.strictEqual(context.fullscreenTarget(), playerRoot, 'desktop custom controls should fullscreen the complete Glass player');
  context.nativeMediaControlsEnabled = () => true;
  assert.strictEqual(context.fullscreenTarget(), video, 'desktop native controls should fullscreen the video surface');
  context.mobileBrowser = true;
  context.nativeMediaControlsEnabled = () => false;
  assert.strictEqual(context.fullscreenTarget(), video, 'non-Android mobile behavior should remain unchanged');

  context.togglePlayerFullscreen = (reason) => calls.toggle.push(reason);
  const touchEvent = {
    type: 'touchend',
    prevented: false,
    stopped: false,
    preventDefault() { this.prevented = true; },
    stopPropagation() { this.stopped = true; }
  };
  context.handleVideoActivation(touchEvent);
  assert.deepStrictEqual(calls.gestures, [true], 'video activation should use the idempotent enter-fullscreen gesture');
  assert.deepStrictEqual(calls.toggle, [], 'the video surface must not own fullscreen exit');
  assert.strictEqual(touchEvent.prevented, true, 'touchend must suppress its synthetic click');
  assert.strictEqual(touchEvent.stopped, true, 'the handled touch must not bubble into overlay controls');

  console.log('PWA video taps enter element fullscreen while the player-bar control owns exit.');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
