# Assets and Third-Party Code (SPEC section 3, L1 to L3)

Every file in `assets/` and every piece of borrowed code or tooling is listed here with its source and licence.
Game graphics are shapes drawn in code (decision D-21) and need no outside file.

## Game assets (`assets/`)

| File | Source | Licence | Notes |
| --- | --- | --- | --- |
| *(none yet)* | | | |

## Third-party code and tools

| Item | Version | Source | Licence | Used for |
| --- | --- | --- | --- | --- |
| GUT (Godot Unit Test), `addons/gut/` | 9.6.1 | https://github.com/bitwes/Gut (tag v9.6.1) | MIT (`addons/gut/LICENSE.md`) | Headless unit tests; excluded from the web export |
| Fonts bundled inside GUT, `addons/gut/fonts/` (Anonymous Pro, Courier Prime, Lobster Two) | with GUT 9.6.1 | https://github.com/bitwes/Gut | SIL Open Font License 1.1 (`addons/gut/fonts/OFL.txt`) | GUT's own test-runner GUI only; not used by the game |
| Godot Engine and web export templates | 4.7.2-stable | https://github.com/godotengine/godot/releases/tag/4.7.2-stable (SHA-512 verified) | MIT | Engine; downloaded at build time, not stored in the repo |
| nginx (unprivileged image) | `nginxinc/nginx-unprivileged:1.30.6-alpine3.24` | https://hub.docker.com/r/nginxinc/nginx-unprivileged | BSD-2-Clause (nginx) | Serves the web build in the container |
| Debian base image (build stage only) | `debian:bookworm-slim` | https://hub.docker.com/_/debian | Debian licences (DFSG) | Runs the export in the Docker build stage |
