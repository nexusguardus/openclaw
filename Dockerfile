# syntax=docker/dockerfile:1.7

ARG OPENCLAW_NODE_BOOKWORM_IMAGE="node:24-bookworm@sha256:3a09aa6354567619221ef6c45a5051b671f953f0a1924d1f819ffb236e520e6b"
ARG OPENCLAW_BUNDLED_PLUGIN_DIR=extensions

# ── Stage 1: Install deps ─────────────────────────────────────────
FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS build
WORKDIR /app

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable

# Copy package files first (layer cache)
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts/postinstall-bundled-plugins.mjs ./scripts/postinstall-bundled-plugins.mjs

# Install with limited memory to avoid OOM during build
RUN NODE_OPTIONS=--max-old-space-size=1536 pnpm install --frozen-lockfile

# Copy full source AFTER install (avoids cache invalidation)
COPY . .

# ── Stage 2: Runtime ──────────────────────────────────────────────
FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS runtime
ARG OPENCLAW_BUNDLED_PLUGIN_DIR
WORKDIR /app

# System deps
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      procps hostname curl git lsof openssl && \
    rm -rf /var/lib/apt/lists/*

# Copy everything from build (no pre-compilation needed — openclaw.mjs runs directly)
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
COPY --from=build /app/openclaw.mjs ./
COPY --from=build /app/${OPENCLAW_BUNDLED_PLUGIN_DIR} ./${OPENCLAW_BUNDLED_PLUGIN_DIR}
COPY --from=build /app/skills ./skills
COPY --from=build /app/docs ./docs

ENV NODE_ENV=production
ENV OPENCLAW_BUNDLED_PLUGINS_DIR=/app/${OPENCLAW_BUNDLED_PLUGIN_DIR}

RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw && \
    chmod 755 /app/openclaw.mjs && \
    chown -R node:node /app

USER node

HEALTHCHECK --interval=3m --timeout=10s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["sh", "-c", "node openclaw.mjs gateway --allow-unconfigured --bind lan --port $PORT"]
```

**What this fixes vs Gemini's version:**
- No `COPY --from=build /app/dist` — that folder doesn't exist without the build step, which would crash silently
- Copies `skills` and `docs` which OpenClaw needs at runtime
- Still skips the heavy `pnpm build:docker` and `pnpm ui:build` that were OOMing Railway
- `openclaw.mjs` runs directly without needing a compiled `dist/` — it's already a runnable entry point

Also make sure your Railway variables include:
```
NVIDIA_API_KEY=your_key
OPENAI_API_KEY=your_key  
OPENAI_BASE_URL=https://integrate.api.nvidia.com/v1
MODEL=z-ai/glm-5
PORT=18789
