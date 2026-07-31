// SPDX-License-Identifier: AGPL-3.0-only

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const playerPath = path.join(repoRoot, 'gstwebrtc-api', 'dist', 'player.js');
const source = fs.readFileSync(playerPath, 'utf8');

function extractFunction(name) {
  const marker = `  function ${name}(`;
  const start = source.indexOf(marker);
  if (start < 0) throw new Error(`Missing ${name} in player.js`);
  const next = source.indexOf('\n  function ', start + marker.length);
  if (next < 0) throw new Error(`Could not isolate ${name} in player.js`);
  return source.slice(start, next).trim();
}

const definitions = [
  'isPrivateIceAddress',
  'isValidIpv4Address',
  'parseAdditionalIceHosts',
  'additionalIceHosts',
  'additionalIceHost',
  'mappedRtpPortBound',
  'mappedHostIcePriority',
  'rewriteCandidateForMappedHost',
  'expandRemoteIceCandidates',
  'routeIcePriority'
].map(extractFunction).join('\n\n');

const queryValues = new Map();
const config = {
  additionalIceHost: '203.0.113.9',
  additionalIceHosts: ['203.0.113.9', '198.51.100.44'],
  minRtpPort: 50000,
  maxRtpPort: 50100
};
const query = (name) => queryValues.has(name) ? queryValues.get(name) : null;
const configValue = (name, fallback) => config[name] === undefined ? fallback : config[name];
const connectionMode = () => 'proxy';
const jbufDebugEnabled = () => false;
const log = () => {};
const api = new Function('query', 'configValue', 'connectionMode', 'jbufDebugEnabled', 'log', `${definitions}\nreturn { additionalIceHosts, additionalIceHost, rewriteCandidateForMappedHost, expandRemoteIceCandidates, routeIcePriority };`)(query, configValue, connectionMode, jbufDebugEnabled, log);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const privateHost = 'candidate:1 1 UDP 2122260223 10.0.0.26 50042 typ host generation 0 ufrag glass';
const mapped = api.rewriteCandidateForMappedHost(privateHost);
const mappedParts = mapped.split(/\s+/);
assert(mappedParts[4] === '203.0.113.9', 'Private candidate was not translated to the configured public host.');
assert(mappedParts[5] === '50042', '1:1 candidate translation changed the UDP port.');
assert(mappedParts[mappedParts.indexOf('typ') + 1] === 'host', 'Mapped candidate stopped being a host candidate.');
const secondMappedParts = api.rewriteCandidateForMappedHost(privateHost, '198.51.100.44', 1).split(/\s+/);
assert(Number(mappedParts[3]) > Number(secondMappedParts[3]), 'Configured host list order did not produce descending ICE priority.');
assert(secondMappedParts[4] === '198.51.100.44', 'Second configured host was not translated into a candidate.');
const fallbackRelayPriority = api.routeIcePriority('relay', 2130706431, '192.0.2.20');
const fallbackSrflxPriority = api.routeIcePriority('srflx', 2122317823, '192.0.2.21');
assert(Number(secondMappedParts[3]) > fallbackRelayPriority, 'Last configured host does not outrank the highest automatic relay fallback.');
assert(fallbackRelayPriority > fallbackSrflxPriority, 'Fallback relay/srflx ordering was not preserved below mapped hosts.');
const expanded = api.expandRemoteIceCandidates({ candidate: privateHost, sdpMLineIndex: 0 }, 'test remote');
assert(expanded.length === 3, 'Ordered host list did not create two mapped candidates plus the original candidate.');
assert(expanded[0].candidate.split(/\s+/)[4] === '203.0.113.9', 'First expanded candidate does not use the first configured host.');
assert(expanded[1].candidate.split(/\s+/)[4] === '198.51.100.44', 'Second expanded candidate does not use the second configured host.');
assert(expanded[2].candidate === privateHost, 'Original private candidate was not retained after expansion.');
assert(api.rewriteCandidateForMappedHost(privateHost.replace('50042', '49999')) === '', 'Candidate outside the configured RTP range was translated.');
assert(api.rewriteCandidateForMappedHost(privateHost.replace('typ host', 'typ srflx')) === '', 'Non-host candidate was translated.');
assert(api.rewriteCandidateForMappedHost(privateHost.replace(' UDP ', ' TCP ')) === '', 'TCP candidate was translated through the UDP mapping.');
assert(api.rewriteCandidateForMappedHost(privateHost.replace('10.0.0.26', '198.51.100.20')) === '', 'Already-public candidate was translated.');

queryValues.set('additionalIceHost', '198.51.100.44');
assert(api.additionalIceHost() === '198.51.100.44', 'Explicit query override did not win over runtime config.');
queryValues.set('additionalIceHost', 'not a candidate');
assert(api.additionalIceHost() === '', 'Unsafe query text was accepted as a candidate address.');
queryValues.delete('additionalIceHost');
queryValues.set('additionalIceHosts', '198.51.100.44,203.0.113.9,198.51.100.44');
assert(api.additionalIceHosts().join(',') === '198.51.100.44,203.0.113.9', 'Ordered host query list was not preserved and de-duplicated.');

assert(source.includes("expandRemoteIceCandidates(ice, 'primary remote')"), 'Primary trickle ICE does not expand mapped candidates.');
assert(source.includes("expandRemoteIceCandidates(ice, 'split audio remote')"), 'Split-audio trickle ICE does not expand mapped candidates.');
assert(source.includes("injectMappedIceCandidatesIntoDescription(rawDesc, 'primary remote')"), 'Primary embedded SDP candidates are not mapped.');
assert(source.includes("injectMappedIceCandidatesIntoDescription(rawDesc, 'split audio remote')"), 'Split-audio embedded SDP candidates are not mapped.');
assert(source.includes("if (connectionMode() !== 'proxy') return [candidate];"), 'Mapped trickle candidates are not scoped to WAN/proxy mode.');
assert(source.includes("if (connectionMode() !== 'proxy' || !description"), 'Mapped SDP candidates are not scoped to WAN/proxy mode.');
assert(source.includes('additionalIceHosts().map((host, index)'), 'Trickle ICE does not create a candidate for every ordered host.');
assert(source.includes('hosts.forEach((host, index)'), 'Embedded SDP does not create a candidate for every ordered host.');

console.log('Additional 1:1 ICE host candidate checks passed.');
