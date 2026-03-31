# syntax=docker/dockerfile:1.7

ARG OPENCLAW_BUNDLED_PLUGIN_DIR=extensions

FROM node:24-alpine AS build
WORKDIR /app

RUN apk add --no-cache curl unzip bash python3 make g++

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts/postinstall-bundled-plugins.mjs ./scripts/postinstall-bundled-plugins.mjs

RUN NODE_OPTIONS=--max-old-space-size=1536 pnpm install --frozen-lockfile

COPY . .

RUN pnpm prune --prod && \
    find node_modules -name "*.d.ts" -delete 2>/dev/null || true && \
    find node_modules -name "*.map" -delete 2>/dev/null || true && \
    find node_modules -name "*.md" -delete 2>/dev/null || true && \
    find node_modules -name "test" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find node_modules -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find node_modules -name "__tests__" -type d -exec rm -rf {} + 2>/dev/null || true

FROM node:24-alpine AS runtime
ARG OPENCLAW_BUNDLED_PLUGIN_DIR
WORKDIR /app

RUN apk add --no-cache curl openssl ca-certificates

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
COPY --from=build /app/openclaw.mjs ./

ENV NODE_ENV=production
ENV OPENCLAW_BUNDLED_PLUGINS_DIR=/app/${OPENCLAW_BUNDLED_PLUGIN_DIR}

RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw && \
    chmod 755 /app/openclaw.mjs && \
    chown -R node:node /app

USER node

HEALTHCHECK --interval=3m --timeout=10s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["sh", "-c", "node openclaw.mjs gateway --allow-unconfigured --bind lan --port $PORT"]
