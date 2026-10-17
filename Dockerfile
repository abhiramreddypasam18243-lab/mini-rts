# Mini RTS web build (SPEC section 10, D1-D5).
# Stage 1 exports the game with the pinned Godot version; its downloads are
# checked against the official SHA-512 sums. Stage 2 serves the static files
# with unprivileged nginx (non-root, port 8080).

ARG GODOT_VERSION=4.7.2

FROM debian:bookworm-slim AS build
ARG GODOT_VERSION
ENV GODOT_RELEASE=${GODOT_VERSION}-stable
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/godot
RUN set -eux; \
    B="https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE}"; \
    curl -fsSLo godot.zip "$B/Godot_v${GODOT_RELEASE}_linux.x86_64.zip"; \
    curl -fsSLo templates.tpz "$B/Godot_v${GODOT_RELEASE}_export_templates.tpz"; \
    curl -fsSLo SUMS.txt "$B/SHA512-SUMS.txt"; \
    grep -E " Godot_v${GODOT_RELEASE}_(linux\.x86_64\.zip|export_templates\.tpz)$" SUMS.txt \
      | sed -e "s/Godot_v${GODOT_RELEASE}_linux.x86_64.zip/godot.zip/" \
            -e "s/Godot_v${GODOT_RELEASE}_export_templates.tpz/templates.tpz/" \
      | sha512sum -c -; \
    unzip -q godot.zip; \
    mv "Godot_v${GODOT_RELEASE}_linux.x86_64" /usr/local/bin/godot; \
    T="/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable"; \
    mkdir -p "$T"; \
    unzip -qj templates.tpz 'templates/web_nothreads_*' 'templates/version.txt' -d "$T"; \
    rm -f godot.zip templates.tpz

WORKDIR /src
COPY . .
RUN set -eux; \
    godot --headless --import >/dev/null 2>&1 || true; \
    mkdir -p build/web; \
    godot --headless --export-release "Web" build/web/index.html; \
    test -f build/web/index.wasm && test -f build/web/index.pck; \
    godot --headless --script res://tools/csp_hash.gd -- build/web/index.html build/csp.conf; \
    test -s build/csp.conf

FROM nginxinc/nginx-unprivileged:1.30.6-alpine3.24
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/build/csp.conf /etc/nginx/csp.conf
COPY --from=build /src/build/web/ /usr/share/nginx/html/
COPY deploy/healthz /usr/share/nginx/html/healthz
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
