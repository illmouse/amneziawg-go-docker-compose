# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [5.1.0] - 2026-10-29

Stable release. Rolls up all changes since v5.0.6, including the
v5.0.7b and v5.0.8b beta builds.

### Fixed

- Client-mode failover triggered on a single transient ping failure. Each
  failed health check immediately started peer probing, and since a backup
  peer's probe usually succeeds within a couple of seconds, a brief blip on
  the path to `MON_CHECK_IP` caused a full tunnel rebuild plus a 3proxy
  restart, dropping all client connections. The monitor now requires
  `MON_FAIL_THRESHOLD` (default 3) consecutive failed checks before probing
  peers. The debounce is bypassed immediately when the current peer's rx
  counter shows a dead session (no received traffic since the streak began),
  so genuinely dead tunnels still fail over without extra delay.
- Master-peer switchback relied on a handshake-only probe, which a server
  with broken forwarding still passes — producing failover/switchback flap
  loops (~30 s cycle in the wild): switch back to master, ping fails, fail
  over again. All probes (failover and switchback) now verify the **data
  path**: after a successful handshake the probe pings `MON_CHECK_IP`
  through the temporary probe interface; only a successful round-trip
  passes. A failed switchback probe keeps the tunnel on the backup.
- Switchback was attempted on every monitor iteration (10 s) with no
  hysteresis. `MON_SWITCHBACK_DELAY` (default 60 s) now enforces a minimum
  dwell on the backup peer before the master is probed for switchback; a
  failed master probe extends the dwell, a successful switchback clears it.
- Peer identification after a failover could pick the wrong peer template:
  the matcher resolved endpoint hostnames through the (possibly down)
  tunnel, and with peers sharing the same tunnel IP the IP-only fallback
  was ambiguous. The active peer is now identified by comparing the
  `Endpoint` of the built session config (`/etc/amneziawg/wg0.conf`)
  against the peer templates — literal string match, no DNS. IP+endpoint
  and IP-only matching remain as fallbacks.
- The current peer was part of the failover probe rotation, so its
  rx-liveness defense (v5.0.4) ran last — backups probed first and usually
  succeeded, making the defense dead code. The current peer is now excluded
  from probing (a probe interface with the same key would steal the wg0
  session); its liveness is judged by the rx-based fail-streak logic in the
  main loop instead.
- Client-mode health checks depended on a single ping target
  (`MON_CHECK_IP`, default `9.9.9.9`). When that one third-party address
  stopped answering ICMP — rate limiting, filtering, a dead anycast node —
  a perfectly healthy tunnel was marked down and pushed into failover; and
  since probe data-path verification pings the same address, a dead check
  target would also have blocked every failover and switchback.
  `MON_CHECK_IP` now accepts a comma-separated list
  (default `1.1.1.1,9.9.9.9,8.8.8.8`) checked in order, both by the health
  check and by the probe data-path verification: the tunnel counts as
  healthy when ANY target answers, so one misbehaving target can no longer
  trigger (or block) a failover.

### Added

- `MON_FAIL_THRESHOLD` (default 3): consecutive failed health checks
  required before client-mode failover probing starts.
- `MON_SWITCHBACK_DELAY` (default 60 s): minimum dwell on a backup peer
  before the master peer is probed for switchback.
- `MON_FALLBACK_PING_COUNT` (default 1): ping packets sent to
  health-check targets after the first. The primary target keeps the full
  `MON_PING_COUNT`, so the worst-case dead-tunnel check stays fast (~50 s
  with the default list) instead of growing with the list length.
- `MON_CHECK_IP` now accepts a comma-separated list of ping targets
  (default `1.1.1.1,9.9.9.9,8.8.8.8`).

### Changed

- `MON_FAIL_THRESHOLD=1` and `MON_SWITCHBACK_DELAY=0` restore the previous
  (5.0.6) switch-on-first-failure, probe-on-every-iteration behavior for
  users who need it.

## [5.0.8b] - 2026-10-26

### Fixed

- Client-mode health checks depended on a single ping target
  (`MON_CHECK_IP`, default `9.9.9.9`). When that one third-party address
  stopped answering ICMP — rate limiting, filtering, a dead anycast node —
  a perfectly healthy tunnel was marked down and pushed into failover; and
  under 5.0.7b probe semantics a dead check target would also have blocked
  every failover and switchback, since probe data-path verification pings
  the same address. `MON_CHECK_IP` now accepts a comma-separated list
  (default `1.1.1.1,9.9.9.9,8.8.8.8`) checked in order, both by the health
  check and by the probe data-path verification: the tunnel counts as
  healthy when ANY target answers, so one misbehaving target can no longer
  trigger (or block) a failover.

### Added

- `MON_FALLBACK_PING_COUNT` (default `1`): ping packets sent to
  health-check targets after the first. The primary target keeps the full
  `MON_PING_COUNT`, so the worst-case dead-tunnel check stays fast (~50 s
  with the default list) instead of growing with the list length.

## [5.0.7b] - 2026-10-09

### Fixed

- Client-mode failover triggered on a single transient ping failure. Each
  failed health check immediately started peer probing, and since a backup
  peer's probe usually succeeds within a couple of seconds, a brief blip on
  the path to `MON_CHECK_IP` caused a full tunnel rebuild plus a 3proxy
  restart, dropping all client connections. The monitor now requires
  `MON_FAIL_THRESHOLD` (default 3) consecutive failed checks before probing
  peers. The debounce is bypassed immediately when the current peer's rx
  counter shows a dead session (no received traffic since the streak began),
  so genuinely dead tunnels still fail over without extra delay.
- Master-peer switchback relied on a handshake-only probe, which a server
  with broken forwarding still passes — producing failover/switchback flap
  loops (~30 s cycle in the wild): switch back to master, ping fails, fail
  over again. All probes (failover and switchback) now verify the **data
  path**: after a successful handshake the probe pings `MON_CHECK_IP`
  through the temporary probe interface; only a successful round-trip
  passes. A failed switchback probe keeps the tunnel on the backup.
- Switchback was attempted on every monitor iteration (10 s) with no
  hysteresis. `MON_SWITCHBACK_DELAY` (default 60 s) now enforces a minimum
  dwell on the backup peer before the master is probed for switchback; a
  failed master probe extends the dwell, a successful switchback clears it.
- Peer identification after a failover could pick the wrong peer template:
  the matcher resolved endpoint hostnames through the (possibly down)
  tunnel, and with peers sharing the same tunnel IP the IP-only fallback
  was ambiguous. The active peer is now identified by comparing the
  `Endpoint` of the built session config (`/etc/amneziawg/wg0.conf`)
  against the peer templates — literal string match, no DNS. IP+endpoint
  and IP-only matching remain as fallbacks.
- The current peer was part of the failover probe rotation, so its
  rx-liveness defense (v5.0.4) ran last — backups probed first and usually
  succeeded, making the defense dead code. The current peer is now excluded
  from probing (a probe interface with the same key would steal the wg0
  session); its liveness is judged by the rx-based fail-streak logic in the
  main loop instead.

### Changed

- `MON_FAIL_THRESHOLD=1` and `MON_SWITCHBACK_DELAY=0` restore the previous
  (5.0.6) switch-on-first-failure, probe-on-every-iteration behavior for
  users who need it.

## [5.0.6] - 2026-10-02

### Fixed

- Client-mode `wg_peers_active` / `wg_peers_stale` still counted a healthy peer
  as stale after v5.0.5: in client mode the 3.1 timing params never live in
  `.env` (they are a server-wizard artifact) — they live in the active session
  config built from the server-generated peer config. The auto-scaling only
  read `.env`, so the threshold stayed at 180 s while real handshakes occur
  every ~50-67 min. The threshold is now also derived from the active session
  config (`/etc/amneziawg/wg0.conf`) when the env vars are absent.
  Precedence: explicit `PEER_HANDSHAKE_TIMEOUT` > `.env` timing vars >
  session config > 180 s default. Server mode is unaffected (its `.env`
  carries the timings and its config is regenerated from them).

## [5.0.5] - 2026-10-02

### Fixed

- `wg_peers_active` / `wg_peers_stale` regression from v5.0.4: the setup wizard
  writes 3.1 timings as literal ranges (e.g. `RekeyAfterTime=3000-4000`), which
  bash arithmetic evaluated as subtraction (`3000-4000 = -1000`), producing a
  negative staleness threshold and counting every healthy peer as stale. The
  threshold now takes the upper bound of each range and adds the rekey retry
  window (`MaxHandshakeAttempts × RekeyTimeout`), floored at 180 s and capped
  at 7200 s. Explicit `PEER_HANDSHAKE_TIMEOUT` values still win.
- Handshake-age alerts (`WireGuardHandshakeStale`, `WireGuardHandshakeAgeing`)
  fired permanently under AmneziaWG 3.1 long session timings, where a healthy
  peer goes 50-67 min between handshakes by design. Replaced with the rx-based
  `WireGuardPeerUnreachable` (see Added).
- Grafana dashboard handshake panels used hardcoded 180 s red thresholds
  (stat and timeseries "Handshake Age"), which painted healthy 3.1 sessions
  red. Panels are now neutral; descriptions explain the cadence difference.
- READMEs referenced a non-existent `wireguard_combined_dashboard.json`; the
  actual file is `wireguard_dashboard.json`.

### Changed

- Alert severity label `critical` renamed to `high` across all rules — update
  notification routing that matches on the old value.

### Added

- `WireGuardPeerUnreachable` alert: fires when a peer with an established
  session receives no traffic for ~5 minutes (rx-based, handshake-cadence
  independent; keepalives deliver rx at ~25 s legacy / 10-15 s under 3.1).
- Grafana dashboard panels "Peers RX Active" / "Peers RX Idle" in the Peer
  Status row, showing handshake-independent peer liveness.

## [5.0.4] - 2026-10-02

### Fixed

- `wg_peers_active` / `wg_peers_stale` reported healthy long-lived peers as stale
  under the 3.1 profile. Both metrics compare handshake age against
  `PEER_HANDSHAKE_TIMEOUT`, which defaulted to 180 s — calibrated for legacy
  WireGuard's 120 s `RekeyAfterTime`. With 3.1 timings (`RekeyAfterTime=3000-4000`)
  a healthy peer goes 50-67 min between handshakes, so it was counted as stale
  almost all the time. `PEER_HANDSHAKE_TIMEOUT` now auto-derives from the
  configured 3.1 `RekeyAfterTime` (+ `RekeyTimeout` + `KeepaliveTimeout` +
  60 s slack, capped at 7200 s) when the variable is not pinned explicitly;
  the 180 s default is preserved when 3.1 timings are unset.
- Client failover on transient ping failures. When the tunnel check failed, the
  monitor judged the *current* peer by handshake age with a 40 s window
  (`MON_CHECK_TIMEOUT * 4`), because a probe interface using the same key would
  steal the session from `wg0`. Under 3.1 timings that window almost never
  matched a healthy session, so a single transient ping failure failed the
  current peer over to a backup peer (and back again, when `MASTER_PEER` was
  set). The check now uses rx traffic growth — PersistentKeepalive packets keep
  the rx counter moving roughly every 25 s for as long as the session works,
  independent of handshake cadence. A backwards-moving counter (daemon restart
  or peer switch) resets the baseline instead of being read as liveness.

### Changed

- `docs/architecture.md` referenced the peer-count metrics as
  `wg_server_peers_total` / `wg_server_peers_active` / `wg_server_peers_stale`;
  the actual metric names have no `server_` prefix. Corrected.

## [5.0.3] - 2026-09-28

### Fixed

- Handshakes still occurred every ~3 minutes despite long session timings
  (`RekeyAfterTime=3000-4000`, `RejectAfterTime=9000-10000`). Root cause: the
  server's `wg0.conf` never received the timing parameters — the upstream
  daemon then applies its built-in default `RejectAfterTime=180s` on the
  server, silently dropping client data after 180 s and forcing a
  re-handshake. The server config now also receives the 3.1 timing params
  (`RekeyAfterTime`, `RekeyTimeout`, `RejectAfterTime`, `KeepaliveTimeout`,
  `MaxHandshakeAttempts`) when set; the effective session lifetime is the
  minimum of both ends' `RejectAfterTime`, so long sessions now actually
  take effect (rekey every ~50-67 min, session cap ~2.5-2.8 h).
- `ContentPaddingAddition` is now also written to the server config for
  symmetric padding of server-to-client bulk traffic (opt-in, empty = not
  emitted = vanilla behavior).

## [5.0.2] - 2026-09-23

Complete changes since the previous stable release (v4.9.1). Includes
everything from the beta builds 5.0.0b and 5.0.1b.

### ⚠️ Breaking

- AmneziaWG core upgraded from 2.x to **3.1** (amneziawg-go `v3.1.20260828`,
  amneziawg-tools `v3.1.20260812`). Newly generated peer configs include the
  previously missing `I5` obfuscation parameter; AmneziaWG 2.x client apps
  may reject it. Existing configs on disk are not modified by the upgrade.
- Enabling the new 3.1 parameters requires AmneziaWG **3.1-capable client
  apps** and re-distribution of peer configs.

### Added

- AmneziaWG 3.1 obfuscation parameters (opt-in, empty = disabled, 2.x-compatible):
  `HeaderProtectionKey` (base64 32-byte key; encrypts packet headers, requires
  `S1`–`S4` ≥ 12), `ContentPaddingAddition`, `RekeyAfterTime`, `RekeyTimeout`,
  `RejectAfterTime`, `KeepaliveTimeout`, `MaxHandshakeAttempts` (ranges `a` or
  `a-b`), `RandomTrailers`, `DisableCookies` (`on`/`off`). Validated at
  container start; persisted in `config.json`; written to generated configs
  per server/client side.
- Setup wizard: optional "3.1 profile" — generates `HeaderProtectionKey`,
  S1–S4 within the fragmentation-safe 12–20 range (header-protection nonce
  requirement at the low end, no IPv4 fragmentation of full-size data packets
  at the high end), standard H1–H4 compatibility values (1/2/3/4), randomized
  padding/rekey ranges and `RandomTrailers=on`.
- Wizard 3.1 profile: long randomized sessions — `RejectAfterTime=9000-10000`
  (session cap) with `RekeyAfterTime=3000-4000`; handshakes occur every
  ~50-67 min on a randomized cadence (anti-fingerprinting). Older clients
  ignore the parameters and keep their own cadence.
- Optional `WG_MTU` env var (default empty = 1420) for constrained paths
  (PPPoE, IPv6 outer, nested tunnels); startup warning when `S4 > 20`
  (fragmentation risk).
- Daemon crash revival (server and client modes): the monitor now detects a
  dead/zombie `amneziawg-go` process (OOM kill, missing UAPI socket) and
  revives it **in place** — SIGTERM→SIGKILL, stale interface and UAPI socket
  removal, PID-tracked restart, config re-apply, listen verification.
  Revival is continuous and unbounded: the monitor retries forever and no
  longer kills/restarts the container after repeated failures.
- Handshake-independent liveness metrics: `wg_peers_rx_active` /
  `wg_peers_rx_idle` (peers with/without received traffic since the last
  scrape; rx grows at least every ~25 s via PersistentKeepalive). Handshake
  metrics (`wg_peer_last_handshake_timestamp_seconds`, `wg_peers_active`,
  `wg_peers_stale`) are kept unchanged for compatibility.
- Upstream versions pinned in the Dockerfile (`AWG_GO_VERSION`,
  `AWG_TOOLS_VERSION`) with OCI image labels.
- Release CI: tag pushes of `vX.Y.Z`/`vX.Y.Zb` now create a GitHub release
  (marked pre-release for beta `b` suffix) with the release description taken
  from this changelog. Beta tags never receive the `latest` image tag —
  `latest` always points at the newest stable release.

### Fixed

- Wizard 3.1 profile generated `S1`–`S4` up to 64: values above 20 made every
  full-size data packet (`1480 + S4` bytes) exceed a 1500-byte path MTU,
  causing IPv4 fragmentation and severe throughput degradation. The wizard
  now caps the range at 12–20.
- Crash-revival failure observed 2026-09-03 (`awg setconf` failing after
  daemon restart): a stale UAPI socket left behind by the killed daemon was
  never removed, so the restarted daemon could not bind it. The socket is now
  swept on every stop/revival.
- Server monitor ignored the "zombie" state (interface present, daemon dead),
  looping forever without a recovery attempt. It is now detected and revived.
- Client monitor did not react to `amneziawg-go` process death at all; the
  daemon is now revived in place with the active peer config re-applied.
- `start_wg_iface` returned success even when the daemon exited immediately
  during startup; it now waits for process + interface + UAPI socket and
  reports failure.
- Generated peer configs were missing the `I5` obfuscation packet parameter.

### Changed

- `amneziawg-go` is now started with `-f` (foreground) under a PID file,
  making the daemon trackable for health checks and revival.
- `docker compose pull && docker compose up -d` remains the upgrade path;
  server keys and peer configs in `./config/` are preserved.

## [5.0.1b] - 2026-09-23

### Fixed

- Wizard 3.1 profile now generates `S1`–`S4` within **12–20** (was 12–64):
  values above 20 made every full-size data packet (`1480 + S4` bytes)
  exceed a 1500-byte path MTU, causing IPv4 fragmentation and severe
  throughput degradation (observed with v5.0.0b).

### Added

- Optional `WG_MTU` env var (default empty = 1420) for constrained paths
  (PPPoE, IPv6 outer, nested tunnels); startup warning when `S4 > 20`
  (fragmentation risk).

## [5.0.0b] - 2026-09-04

### ⚠️ Breaking

- AmneziaWG core upgraded from 2.x to **3.1** (amneziawg-go `v3.1.20260828`,
  amneziawg-tools `v3.1.20260812`). Newly generated peer configs include the
  previously missing `I5` obfuscation parameter; AmneziaWG 2.x client apps
  may reject it. Existing configs on disk are not modified by the upgrade.
- Enabling the new 3.1 parameters requires AmneziaWG **3.1-capable client
  apps** and re-distribution of peer configs.

### Added

- AmneziaWG 3.1 obfuscation parameters (opt-in, empty = disabled, 2.x-compatible):
  `HeaderProtectionKey` (base64 32-byte key; encrypts packet headers, requires
  `S1`–`S4` ≥ 12), `ContentPaddingAddition`, `RekeyAfterTime`, `RekeyTimeout`,
  `RejectAfterTime`, `KeepaliveTimeout`, `MaxHandshakeAttempts` (ranges `a` or
  `a-b`), `RandomTrailers`, `DisableCookies` (`on`/`off`). Validated at
  container start; persisted in `config.json`; written to generated configs
  per server/client side.
- Setup wizard: optional "3.1 profile" — generates `HeaderProtectionKey`,
  S1–S4 in 12–64 range (header-protection nonce requirement), standard
  H1–H4 compatibility values (1/2/3/4), randomized padding/rekey ranges
  and `RandomTrailers=on`.
- Daemon crash revival (server and client modes): the monitor now detects a
  dead/zombie `amneziawg-go` process (OOM kill, missing UAPI socket) and
  revives it **in place** — SIGTERM→SIGKILL, stale interface and UAPI socket
  removal, PID-tracked restart, config re-apply, listen verification.
  Revival is continuous and unbounded: the monitor retries forever and no
  longer kills/restarts the container after repeated failures.
- Upstream versions pinned in the Dockerfile (`AWG_GO_VERSION`,
  `AWG_TOOLS_VERSION`) with OCI image labels.
- Release CI: tag pushes of `vX.Y.Z`/`vX.Y.Zb` now create a GitHub release
  (marked pre-release for beta `b` suffix) with the release description taken
  from this changelog. Beta tags never receive the `latest` image tag —
  `latest` always points at the newest stable release. Release runbook in
  `llm_wiki/release.md`, referenced from `AGENTS.md`.
- This changelog file.

### Fixed

- Crash-revival failure observed 2026-09-03 (`awg setconf` failing after
  daemon restart): a stale UAPI socket left behind by the killed daemon was
  never removed, so the restarted daemon could not bind it. The socket is now
  swept on every stop/revival.
- Server monitor ignored the "zombie" state (interface present, daemon dead),
  looping forever without a recovery attempt. It is now detected and revived.
- Client monitor did not react to `amneziawg-go` process death at all; the
  daemon is now revived in place with the active peer config re-applied.
- `start_wg_iface` returned success even when the daemon exited immediately
  during startup; it now waits for process + interface + UAPI socket and
  reports failure.
- Generated peer configs were missing the `I5` obfuscation packet parameter.

### Changed

- `amneziawg-go` is now started with `-f` (foreground) under a PID file,
  making the daemon trackable for health checks and revival.
- `docker compose pull && docker compose up -d` remains the upgrade path;
  server keys and peer configs in `./config/` are preserved.

## [4.9.1] - 2026-04-16

- Fix probing of current interface stealing the session.

## [4.9.0] - 2026-04-13

- Add Prometheus metrics exporter with Grafana dashboard, alert rules and
  scrape job example (#35).

## [4.8.3] - 2026-04-13

- Move config check after `setconf` to make sure the UAPI socket exists when
  running `awg show`.

## [4.8.2] - 2026-04-13

- Move protocol message to debug log level.

## [4.8.1] - 2026-04-13

- Fix probing loop when only a single peer is available (#34).

## [4.7.1] - 2026-04-05

- Add Prometheus metrics collection (#33).

## [4.6.2] - 2026-04-03

- Fix collector crash (#32).

## [4.6.1] - 2026-04-03

- Fix health metric (#31).

## [4.6.0] - 2026-03-30

- Add smart switchover in client mode (#30).

## [4.5.2] - 2026-03-28

- Fix setup issues (#29).

## [4.5.1] - 2026-03-27

- Fix setup issues (#28).

## [4.5.0] - 2026-03-27

- Move log rotation inside the container and add Prometheus metrics (#27).

## [4.4.1] - 2026-03-12

- Fix 3proxy log rotation (#25).

## [4.4.0] - 2026-03-12

- Fix 3proxy log rotation (#25).

## [4.3.1] - 2026-02-25

- Fix log rotation pattern.

## [4.3.0] - 2026-02-13

- Minor fixes (#24).

## [4.2.0] - 2026-02-13

- Change `setup.sh` flow (#23).

## [4.1.1] - 2026-02-13

- Fix 3proxy instability (#22).

## [4.1.0] - 2026-02-12

- Add 3proxy setup (#21).

## [4.0.3] - 2026-02-12

- Fix peer DNS name (#19).

## [4.0.2] - 2026-02-12

- Allow DNS names as peer endpoints (#18).

## [4.0.1] - 2026-02-10

- Fix slow speed (#16).

## [4.0.0] - 2026-02-09

- Update Docker image tag to latest version.

## [3.0.4] - 2026-02-09

- Change logic to populate all peer routes on startup.

## [3.0.3] - 2026-02-09

- Fix peer detection for peers with the same IP address.

## [3.0.2] - 2026-02-09

- Fix health check flaw in client mode (#12).

## [3.0.1] - 2026-02-09

- Refactoring (#11).

## [3.0.0] - 2026-02-08

- Add 3proxy integration (#10).

## [2.2.0] - 2026-02-08

- Fix envs, bash execution, config generation (#9).

## [2.1.0] - 2026-01-13

- Add AmneziaWG 1.5 obfuscation support (#8).

## [2.0.5] - 2025-11-25

- Persist proxy logs (#6).

## [2.0.4] - 2025-11-25

- Rename routing function (#5).

## [2.0.3] - 2025-11-25

- Fix client routing.

## [2.0.2] - 2025-11-24

- Change build workflow (#3).

## [2.0.1] - 2025-11-24

- Fix server mode (#2).

## [2.0.0] - 2025-11-24

- Add Docker build (#1).

## [1.0.1] - 2025-11-15

- Remove Dockerfile from main branch.

## [1.0.0] - 2025-11-14

- Cleanup working version.