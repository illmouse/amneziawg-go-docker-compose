# AGENTS.md

Guidelines for coding agents working in this repository.

## Project

Dockerized AmneziaWG (userspace Go implementation) VPN server/client with UDP
obfuscation (CPS protocol imitation), peer config generation, health monitoring
with self-healing, optional 3proxy and Prometheus metrics.

- Upstream core: https://github.com/amnezia-vpn/amneziawg-go (pinned in Dockerfile `ARG`s)
- Upstream tools: https://github.com/amnezia-vpn/amneziawg-tools (pinned in Dockerfile `ARG`s)

## Layout

```
Dockerfile              two-stage build: compile AWG core+tools, alpine runtime
docker-compose.yaml     service definition (env_file .env, NET_ADMIN, /dev/net/tun)
setup.sh                root entry: installs docker, configures sysctl, runs wizard
scripts/                host-side helpers (setup wizard, env generation)
entrypoint/main.sh      in-container entry: dispatches by WG_MODE (server|client)
entrypoint/lib/         shared: env.sh (defaults), functions.sh (primitives), config_parser.sh
entrypoint/server/      keys, peers, init_db (config.json via jq), generate_configs, start, monitor
entrypoint/client/      assemble_config, start, proxy, monitor (peer failover)
entrypoint/metrics/     Prometheus exporter + collector
docs/                   architecture.md, configuration.md, deploy.md
README.md / README-RU.md  bilingual user docs
CHANGELOG.md            release history (keepachangelog.com format)
llm_wiki/               agent runbooks (release.md - release process)
```

## Conventions

- Bash everywhere (container runs bash; scripts use `set -euo pipefail` where
  appropriate). Validate with `bash -n <file>` before committing.
- Entrypoint scripts must work under Alpine busybox utilities: no GNU-only
  flags; `jq` is available; `awk`/`grep`/`sed` are busybox versions.
- Logging goes through `info/success/warn/error/debug` helpers from
  `entrypoint/lib/functions.sh`, never raw `echo`.
- User-tunable behavior is driven by environment variables with safe defaults
  declared in `entrypoint/lib/env.sh`. New vars must be added there, to
  `.env.example`, and to `docs/configuration.md`.
- Server state (keys, params) is persisted in `config/config.json` (volume) via
  `entrypoint/server/init_db.sh`; the process is stateless and regenerates
  configs on start. Never assume a prior container's memory.
- AmneziaWG obfuscation params in env (`Jc Jmin Jmax S1 S2 S3 S4 H1 H2 H3 H4`,
  3.1 params like `HeaderProtectionKey`) must match between server and its
  generated peer configs. Client-side-only params live in peer configs only.
- Any change visible to users must be reflected in BOTH READMEs (en + ru) and
  the relevant `docs/*.md` file(s), plus a CHANGELOG.md entry under the
  upcoming version.
- Before every commit, sync local work with origin:
  `git stash && git pull --rebase && git stash pop` then `git add -A` — this
  avoids divergence between the local repo and origin (see
  `llm_wiki/release.md`, "Sync before committing").

## Release process

Releases are driven by tags. Follow the full runbook in `llm_wiki/release.md`
whenever preparing or pushing a release — call it before touching tags.

Versioning: `X.0.0` = major/breaking, `X.Y.0` = feature, `X.Y.Z` = fix,
`X.Y.Zb` = beta (published as a pre-release). Key rules from the runbook:

- Update `CHANGELOG.md` (new version section at top, keepachangelog format);
  CI takes the GitHub release description from that section.
- **Always show the user the full release info (version, tag, pre-release
  flag, changelog section) and get explicit confirmation before pushing.**
- **Never delete or re-push a tag whose build succeeded** — cut a new version
  instead. Re-creating a tag is allowed only when its previous CI build failed.
- On tag push CI (`.github/workflows/build.yaml`) builds and pushes
  `ghcr.io/<owner>/amneziawg-go:{tag,latest}`, then creates the GitHub release
  from the changelog section (skipped if the release already exists).
  **Beta tags (`X.Y.Zb`) never receive the `latest` image tag** — `latest`
  always points at the newest stable release.
- Breaking changes (config format, peer config regen required, client app
  upgrade required) demand a major version bump and explicit upgrade notes in
  `docs/deploy.md`.

## Build & verification

```bash
bash -n entrypoint/main.sh            # syntax-check every touched script
docker compose build                  # rebuild image (uses pinned upstream tags)
docker compose up -d && docker compose logs -f
# crash-revival drill (server mode): daemon must be auto-revived in place
docker compose exec amneziawg sh -c 'kill -9 "$(cat /tmp/amneziawg/amneziawg-wg0.pid)"'
```

Do not commit `.env`, `config/`, `logs/` (gitignored state directories).