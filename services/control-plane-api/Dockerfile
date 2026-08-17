# Build context is the repo root, not this directory - npm workspaces
# means control-plane-api's own dependencies include sibling packages
# (packages/pterodactyl-sdk, packages/rabbitmq, packages/secrets) that
# only resolve correctly with the whole monorepo present:
#
#   docker build -f services/control-plane-api/Dockerfile -t pterocontrol-control-plane-api .
#
# Kept as one full `npm ci` (dev dependencies included) in the runtime
# stage rather than a pruned production-only node_modules - workspace
# hoisting + Prisma's generated client + `npx prisma migrate deploy`
# (run against this same image, see infra/docker-compose.prod.yml) make a
# correct dependency-pruning step fragile enough that it isn't worth the
# image-size win without being able to verify it doesn't silently drop
# something Prisma or a workspace package needs at runtime.

FROM node:22-alpine AS build
WORKDIR /repo

COPY package.json package-lock.json ./
COPY packages/pterodactyl-sdk/package.json packages/pterodactyl-sdk/package.json
COPY packages/rabbitmq/package.json packages/rabbitmq/package.json
COPY packages/secrets/package.json packages/secrets/package.json
COPY services/control-plane-api/package.json services/control-plane-api/package.json
COPY services/federation-worker/package.json services/federation-worker/package.json
RUN npm ci

COPY tsconfig.base.json ./
COPY packages ./packages
COPY services/control-plane-api ./services/control-plane-api

RUN npm run build --workspace=@pterocontrol/pterodactyl-sdk
RUN npm run build --workspace=@pterocontrol/rabbitmq
RUN npm run build --workspace=@pterocontrol/secrets
RUN npx prisma generate --schema services/control-plane-api/prisma/schema.prisma
RUN npm run build --workspace=control-plane-api

FROM node:22-alpine AS runtime
WORKDIR /repo
ENV NODE_ENV=production

RUN addgroup -S pterocontrol && adduser -S pterocontrol -G pterocontrol

COPY --from=build /repo/package.json /repo/package-lock.json ./
COPY --from=build /repo/packages/pterodactyl-sdk/package.json packages/pterodactyl-sdk/package.json
COPY --from=build /repo/packages/rabbitmq/package.json packages/rabbitmq/package.json
COPY --from=build /repo/packages/secrets/package.json packages/secrets/package.json
COPY --from=build /repo/services/control-plane-api/package.json services/control-plane-api/package.json
COPY --from=build /repo/services/federation-worker/package.json services/federation-worker/package.json
RUN npm ci

COPY --from=build /repo/packages/pterodactyl-sdk/dist packages/pterodactyl-sdk/dist
COPY --from=build /repo/packages/rabbitmq/dist packages/rabbitmq/dist
COPY --from=build /repo/packages/secrets/dist packages/secrets/dist
COPY --from=build /repo/services/control-plane-api/dist services/control-plane-api/dist
COPY --from=build /repo/services/control-plane-api/prisma services/control-plane-api/prisma
# The Prisma client generated in the build stage (query engine binary +
# generated JS) lives under node_modules/.prisma - `npm ci` above only
# reinstalls declared dependencies, it does not regenerate this.
COPY --from=build /repo/node_modules/.prisma node_modules/.prisma

USER pterocontrol
EXPOSE 3000
# nest build (sourceRoot: "src" in nest-cli.json) nests output under
# dist/src/, unlike federation-worker's plain `tsc` build which flattens
# dist/ directly to main.js - found live, the first version of this
# Dockerfile pointed at the wrong path and the container failed to start
# with MODULE_NOT_FOUND.
CMD ["node", "services/control-plane-api/dist/src/main.js"]
