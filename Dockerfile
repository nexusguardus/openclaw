# syntax=docker/dockerfile:1.7

ARG OPENCLAW_BUNDLED_PLUGIN_DIR=extensions

FROM node:24-bookworm-slim AS build
WORKDIR /app

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      curl ca-certificates unzip && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts/postinstall-bundled-plugins.mjs ./scripts/postinstall-bundled-plugins.mjs

RUN NODE_OPTIONS=--max-old-space-size=1536 \
    SKIP_LLAMA_BUILD=1 \
    NODE_LLAMA_CPP_SKIP_DOWNLOAD=true \
    pnpm install --frozen-lockfile --ignore-scripts

COPY . .

RUN CI=true pnpm prune --prod && \
    find node_modules -name "*.d.ts" -delete 2>/dev/null || true && \
    find node_modules -name "*.map" -delete 2>/dev/null || true && \
    find node_modules -name "*.md" -delete 2>/dev/null || true && \
    find node_modules -name "test" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find node_modules -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find node_modules -name "__tests__" -type d -exec rm -rf {} + 2>/dev/null || true && \
    rm -rf node_modules/node-llama-cpp/llama 2>/dev/null || true

FROM node:24-bookworm-slim AS runtime
ARG OPENCLAW_BUNDLED_PLUGIN_DIR
WORKDIR /app

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      curl ca-certificates openssl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
COPY --from=build /app/openclaw.mjs ./

ENV NODE_ENV=production
ENV OPENCLAW_BUNDLED_PLUGINS_DIR=/app/${OPENCLAW_BUNDLED_PLUGIN_DIR}

RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw && \
    chmod 755 /app/openclaw.mjs && \
    chown -R node:node /app

USER node

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 18789) + '/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["sh", "-c", "node openclaw.mjs gateway --allow-unconfigured --bind lan --port ${PORT:-18789}"]
