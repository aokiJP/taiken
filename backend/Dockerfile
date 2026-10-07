# syntax=docker/dockerfile:1
# 実行時の依存パッケージは無い (Node.js の型除去で TypeScript をそのまま実行する)。
FROM node:22-alpine AS runtime

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8787 \
    DATA_DIR=/data

WORKDIR /app
COPY package.json ./
COPY src ./src

RUN mkdir -p /data && chown node:node /data
USER node

EXPOSE 8787
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT}/health" >/dev/null || exit 1

CMD ["node", "src/index.ts"]
