# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
  from this changelog. Release runbook in `llm_wiki/release.md`, referenced
  from `AGENTS.md`.
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