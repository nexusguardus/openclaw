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

RUN pnpm prune --prod && \
    find node_modul
