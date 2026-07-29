# GStreamer Glass Authentication Gate: Debugging Handoff

Date: 2026-07-29

## Problem statement

GStreamer Glass has a built-in TLS-terminating proxy that is intended to act
as a persistent authentication gate in front of both:

- the protected player and its assets under `/live/`; and
- the HTTPS/WSS signaling endpoints.

The decisive reported behavior is session-state-dependent:

1. Restart GStreamer Glass and start the stream.
2. Visit `/auth/login` while unauthenticated. The login page works.
3. Log in successfully and reach `/live/`.
4. Visit `/auth/login` or `/auth/` again with the valid session cookie.
5. The request can return GStreamer's/static-server 404 instead of being
   handled by the authentication gate.

Logout showed the same class of failure. Navigating away from the player
closed WebRTC signaling because the page unloaded, but the server-side session
was not necessarily revoked. Several earlier logout URLs fell through to the
static upstream and returned 404.

The important clue is that the route works before authentication and fails
after authentication. That suggests the valid-session path is forwarding an
authentication route upstream, or that the request is reaching a proxy
instance whose authentication routing is no longer active.

## Intended architecture and invariants

Authentication should be an origin-level boundary, independent of the player
mount:

- Canonical login: `/auth/login`
- Canonical logout: `/auth/logout`
- Protected content: `/live/`

The entire `/auth` namespace must be permanently owned by the TLS gate:

- Unauthenticated `GET /auth/` should redirect to
  `/auth/login?return=%2Flive%2F`.
- Authenticated `GET /auth/` should redirect to `/live/`.
- Authenticated `GET /auth/login` should redirect to `/live/`.
- `GET /auth/logout` should revoke the session, expire the cookie, and
  redirect to `/live/`.
- Unknown `/auth/*` children should receive a local gate-owned 404 and must
  never be forwarded to GStreamer.
- An unauthenticated HTTP request for `/live/` or its assets should redirect
  to `/auth/login`.
- An unauthenticated WebSocket upgrade should receive `401`.
- A valid session authorizes only the current request. It must not disable,
  remove, or bypass the gate for later requests.

The browser must preserve the exact scheme, hostname/IP, and port used by the
viewer. Redirects therefore use origin-relative paths instead of hard-coded
domains.

## Important distinction: TLS gate versus PWA service worker

The PWA service worker is only a browser cache/offline layer. It is not and
must never become the authentication authority.

The actual gate is `TlsTerminatingProxy` in `src/00-Setup.ps1`. It must remain
alive for the lifetime of the TLS listeners and inspect every HTTPS/WSS
request.

Authenticated player pages currently unregister old PWA workers and clear old
PWA caches. Login/logout navigations bypass service-worker interception so
browser-native `303` processing is preserved. Because `/auth/` is outside the
service worker's `/live/` scope, the canonical gate routes should not be
controlled by the player service worker at all.

## Relevant files

- `src/00-Setup.ps1`
  - Contains the C# `TlsTerminatingProxy`.
  - Reads the HTTP request at the TLS edge.
  - Classifies authentication routes.
  - Validates session cookies.
  - Serves login/logout responses.
  - Relays authorized ordinary requests upstream.
- `src/33-LetsEncrypt.ps1`
  - Creates and retains the TLS proxy instances.
  - Configures authentication on every exposed TLS port.
  - Handles shared signaling/web-port topologies.
- `gstwebrtc-api/dist/logout.js`
  - Physical player asset.
  - Performs native top-level navigation to same-origin `/auth/logout`.
  - Does not use `fetch`.
- `gstwebrtc-api/dist/player.js`
  - Creates the Sign out control.
  - Invokes `window.GST_GLASS_LOGOUT`.
  - Cleans up obsolete PWA workers when viewer authentication is enabled.
- `gstwebrtc-api/dist/sw.js`
  - PWA cache worker.
  - Authentication navigations are excluded from interception.
- `tools/test-viewer-auth.ps1`
  - Loopback TLS integration test for login, cookie flags, WSS gating,
    cross-port sessions, endpoint ownership, logout, and rate limiting.

## Changes currently present in the working tree

The current implementation attempts to enforce the following:

1. `/auth/login` and `/auth/logout` are the canonical routes.
2. The older routes remain compatibility aliases:
   - `/__gstglass/auth/login`
   - `/__gstglass/auth/logout`
   - mounted forms such as `/live/__gstglass/auth/login`
   - the temporary `/live/logout` action
3. `IsAuthenticationEndpointPath` now treats `/auth` and every `/auth/*`
   request as gate-owned.
4. The outer TLS request dispatcher sends gate-owned routes to
   `HandleAuthenticationAsync` before ordinary authenticated forwarding.
5. If a route classified as authentication is not handled locally, the proxy
   emits a local `500` instead of forwarding it upstream.
6. `/auth/` redirects according to session state.
7. Unknown `/auth/*` children return the local body
   `Authentication endpoint not found.`
8. Ordinary requests continue through cookie validation on every request.
9. Logout:
   - removes the current session token;
   - currently clears all issued viewer sessions;
   - expires `GstGlassAuth` with `Max-Age=0` and an absolute 1970 expiry;
   - sends `Clear-Site-Data: "cookies", "storage"`; and
   - redirects to the configured viewer mount, normally `/live/`.
10. The player bundle is currently marked `3.8-viewer-auth-36`.

The initial native authentication implementation was committed as:

`9a6d912 feat: native viewer authentication at the TLS edge`

The subsequent gate/logout work described here is currently uncommitted.

## What has been verified

- The embedded C# TLS gate compiles successfully from `src/00-Setup.ps1`.
- JavaScript syntax checks pass for `player.js`, `logout.js`, and `sw.js`.
- The full application and installer build succeeds.
- URL-generation tests confirm that the logout asset preserves each original
  origin and navigates to:
  - `https://live.netlabwork.net:8889/auth/logout?...`
  - `https://stream.netlabwork.net:8889/auth/logout?...`
  - `https://10.0.0.26:8889/auth/logout?...`
- The rebuilt application is installed.
- Public TLS listeners and loopback upstream listeners are active on ports
  `8189` and `8889`.
- A real browser verified:
  - unauthenticated `/live/` redirects to
    `/auth/login?return=%2Flive%2F`;
  - unauthenticated `/auth/` redirects to the same login page;
  - login succeeds and reaches `/live/`;
  - the player loads `logout.js?v=3.8.36`;
  - WSS signaling connects;
  - the stream reaches `Live`; and
  - media was observed on a direct P2P ICE pair.

## Verification limitations

The in-app automation browser blocks direct post-login navigation into
`/auth/` with `net::ERR_BLOCKED_BY_CLIENT`. It also suppresses the automated
logout navigation. The automated click did not revoke the session, but this
cannot distinguish an application failure from the browser harness preventing
the sensitive navigation.

The PowerShell TLS integration test currently fails during
`SslStream.AuthenticateAsClient('localhost')` before sending HTTP. The inner
Windows Schannel error observed earlier was:

`SEC_E_NO_CREDENTIALS: No credentials are available in the security package`

This appears to be a host TLS-client problem rather than a test assertion
failure. The real browser can still connect to the live TLS listener.

No viewer password is included in this document. Use the value supplied
separately by the operator when manual authentication is required.

## Remaining question

The operator reports that after successful authentication, `/auth/` and
routes beneath it still appear to fall through or fail. If that reproduces on
the `3.8-viewer-auth-36` build, the most useful next step is not another path
rename. Instrument the live TLS dispatcher and determine which decision is
actually taken for the authenticated request.

Log these fields without logging the cookie or token:

- proxy label;
- external listening port;
- extracted request path;
- whether the path was classified as gate-owned;
- `authenticationEnabled`;
- whether a valid authentication cookie was present;
- whether the gate handled, rejected, or authorized the request; and
- selected upstream port, if forwarding occurs.

For `/auth/` or `/auth/*`, selecting any upstream port is a bug.

## High-value reproduction matrix

Run these requests on the same origin and same TLS port:

| State | Request | Expected result |
|---|---|---|
| No cookie | `GET /auth/` | `303` to `/auth/login?return=%2Flive%2F` |
| No cookie | `GET /auth/login` | `200` login page |
| No cookie | `GET /live/` | `303` to `/auth/login?return=...` |
| No cookie | WSS upgrade under `/live/` | `401` |
| Valid cookie | `GET /auth/` | `303` to `/live/` |
| Valid cookie | `GET /auth/login` | `303` to `/live/` |
| Valid cookie | `GET /auth/not-real` | Local `404`, never upstream |
| Valid cookie | `GET /live/` | Viewer content from upstream |
| Valid cookie | Authorized WSS upgrade | Relayed upstream |
| Valid cookie | `GET /auth/logout` | `303`, expired cookie, session revoked |
| Revoked cookie | `GET /live/` | `303` to `/auth/login?return=...` |
| Revoked cookie | WSS upgrade | `401` |

## Likely areas to inspect if authenticated `/auth/` still falls through

1. **Runtime/source mismatch**
   - Confirm the public listener belongs to the newly installed executable.
   - Confirm every old GStreamer Glass process was terminated before launch.
   - `TlsTerminatingProxy` is loaded through an `Add-Type` guard. Restarting
     only the stream inside an existing GUI process does not replace an
     already-loaded C# type; a full application-process restart is required.

2. **Wrong proxy instance on a shared port**
   - Port `8889` may serve web and signaling through one reused TLS proxy.
   - Confirm the instance owning the public port received authentication
     configuration and the `/auth` classification logic.

3. **Proxy restart/configuration transition**
   - `Start-LetsEncryptTlsProxies` uses a configuration signature and can stop
     and replace proxy instances.
   - Confirm the replacement instance is configured before it accepts
     requests and retains a strong reference in
     `$script:LetsEncryptTlsProxies`.

4. **Outer dispatcher classification**
   - For an authenticated `GET /auth/`, confirm
     `IsAuthenticationEndpointPath` returns `true`.
   - Confirm the dispatcher returns after local handling and never reaches
     the upstream relay loop.

5. **Request-path parsing**
   - Log the exact result of `ExtractHttpRequestPath`.
   - Check trailing slashes, query strings, casing, and absolute-form request
     targets.

6. **Multiple origins**
   - Cookies are host-scoped. Test `live.netlabwork.net`,
     `stream.netlabwork.net`, and `10.0.0.26` independently.
   - The gate itself must behave identically on every origin; only cookie
     possession should differ.

## Git hygiene

Do not stage unrelated user files currently present under:

- `.claude/`
- `tools/examples/Profiles/`

