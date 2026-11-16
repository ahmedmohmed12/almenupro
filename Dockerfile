FROM node:22-bookworm-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY apiServer.js nixpacks.toml railway.json railway.toml Procfile ./
COPY lib ./lib
COPY data ./data
COPY scripts ./scripts
COPY public ./public

ENV NODE_ENV=production
ENV HOST=0.0.0.0

EXPOSE 3000

CMD ["node", "apiServer.js"]