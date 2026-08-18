# Build context is the repo root - see services/control-plane-api/Dockerfile's
# own doc comment for why (npm workspaces).
#
#   docker build -f services/federation-worker/Dockerfile -t pterocontrol-federation-worker .
#
# No EXPOSE/listening port - federation-worker is a background consumer
# process (NestFactory.createApplicationContext, no HTTP), not a server;
# see IMPLEMENTATION_STATUS.md, FAZA 9b.

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
# federation-worker's own Prisma schema is the one in control-plane-api
# (see IMPLEMENTATION_STATUS.md, FAZA 9b: "services/control-plane-api/
# prisma/schema.prisma pozostaje jedynym źródłem prawdy") - it consumes
# the generated @prisma/client through npm workspace hoisting, it has no
# migrations of its own to run.
COPY services/control-plane-api/prisma ./services/control-plane-api/prisma
COPY services/federation-worker ./services/federation-worker

RUN npm run build --workspace=@pterocontrol/pterodactyl-sdk
RUN npm run build --workspace=@pterocontrol/rabbitmq
RUN npm run build --workspace=@pterocontrol/secrets
RUN npx prisma generate --schema services/control-plane-api/prisma/schema.prisma
RUN npm run build --workspace=federation-worker

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
COPY --from=build /repo/services/federation-worker/dist services/federation-worker/dist
COPY --from=build /repo/node_modules/.prisma node_modules/.prisma

USER pterocontrol
CMD ["node", "services/federation-worker/dist/main.js"]
