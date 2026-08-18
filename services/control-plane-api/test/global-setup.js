/**
 * Jest globalSetup for the E2E suite (`npm run test:e2e`).
 *
 * Spins up the same kind of throwaway Docker Postgres+RabbitMQ this whole
 * session used for every manual "live verification" pass, but as a
 * repeatable script instead of one-off commands - the point of this phase
 * (see IMPLEMENTATION_STATUS.md, "Testy E2E") is exactly to turn that
 * manual methodology into something anyone (or CI) can run without having
 * read this file's history first.
 *
 * Requires Docker on PATH. Fails loudly (not silently skipped) if it
 * isn't available - a security/correctness-relevant test suite that
 * quietly no-ops is worse than one that refuses to run.
 */
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const POSTGRES_CONTAINER = 'pterocontrol-e2e-postgres';
const POSTGRES_PORT = 5479;
const RABBITMQ_CONTAINER = 'pterocontrol-e2e-rabbitmq';
const RABBITMQ_PORT = 5679;
const RABBITMQ_MGMT_PORT = 15679;
const ENV_FILE = path.join(__dirname, '.env.e2e');

function sh(command, options) {
  return execSync(command, { stdio: 'pipe', encoding: 'utf8', ...options });
}

function randomBase64Key() {
  return crypto.randomBytes(32).toString('base64');
}

module.exports = async function globalSetup() {
  try {
    sh('docker info');
  } catch {
    throw new Error(
      'Docker is required to run the E2E suite (it spins up a throwaway Postgres+RabbitMQ) - Docker does not appear to be running or installed.',
    );
  }

  // Clean up any leftovers from a previous run that crashed before teardown.
  try {
    sh(`docker rm -f ${POSTGRES_CONTAINER} ${RABBITMQ_CONTAINER}`);
  } catch {
    // Fine if they didn't exist.
  }

  sh(
    `docker run -d --name ${POSTGRES_CONTAINER} ` +
      '-e POSTGRES_USER=pterocontrol_e2e -e POSTGRES_PASSWORD=pterocontrol_e2e -e POSTGRES_DB=pterocontrol_e2e ' +
      `-p 127.0.0.1:${POSTGRES_PORT}:5432 postgres:16-alpine`,
  );
  sh(
    `docker run -d --name ${RABBITMQ_CONTAINER} ` +
      '-e RABBITMQ_DEFAULT_USER=pterocontrol_e2e -e RABBITMQ_DEFAULT_PASS=pterocontrol_e2e ' +
      `-p 127.0.0.1:${RABBITMQ_PORT}:5672 -p 127.0.0.1:${RABBITMQ_MGMT_PORT}:15672 rabbitmq:3-management-alpine`,
  );

  await waitForPostgres();
  await waitForRabbitMq();

  const databaseUrl = `postgresql://pterocontrol_e2e:pterocontrol_e2e@localhost:${POSTGRES_PORT}/pterocontrol_e2e?schema=public`;
  const rabbitmqUrl = `amqp://pterocontrol_e2e:pterocontrol_e2e@localhost:${RABBITMQ_PORT}`;

  sh('npx prisma migrate deploy', {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, DATABASE_URL: databaseUrl },
  });

  const envContent = [
    `DATABASE_URL="${databaseUrl}"`,
    `SECRETS_MASTER_KEY="${randomBase64Key()}"`,
    `JWT_SECRET="${randomBase64Key()}"`,
    `BOOTSTRAP_TOKEN="e2e-bootstrap-token-${crypto.randomBytes(8).toString('hex')}"`,
    `RABBITMQ_URL="${rabbitmqUrl}"`,
    '',
  ].join('\n');
  fs.writeFileSync(ENV_FILE, envContent, 'utf8');
};

// 90s, not 30s: found live on GitHub Actions' shared runners - a cold
// pull of rabbitmq:3-management-alpine plus its own Erlang VM/plugin
// boot time routinely exceeds 30s there, even though 30s was plenty on
// a dev machine with the image already cached. Postgres gets the same
// generous deadline for consistency, even though it wasn't the one that
// actually timed out.
async function waitForPostgres() {
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    try {
      sh(`docker exec ${POSTGRES_CONTAINER} pg_isready -U pterocontrol_e2e`);
      return;
    } catch {
      await sleep(500);
    }
  }
  throw new Error('Timed out waiting for the E2E Postgres container to become ready.');
}

async function waitForRabbitMq() {
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    try {
      sh(`docker exec ${RABBITMQ_CONTAINER} rabbitmq-diagnostics -q ping`);
      return;
    } catch {
      await sleep(500);
    }
  }
  throw new Error('Timed out waiting for the E2E RabbitMQ container to become ready.');
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
