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
      // "Error when reading /var/lib/rabbitmq/.erlang.cookie: eacces"
      // on GitHub Actions - root cause found live via a pre-crash
      // diagnostic (ls -la/id/mount captured in the container's brief
      // window before it crashes): on that runner, /var/lib/rabbitmq
      // is its own ext4 mount (`/dev/root on /var/lib/rabbitmq type
      // ext4`), not part of the container's normal overlay filesystem
      // - a runner-environment quirk unrelated to the image (four
      // earlier mitigations - longer timeout, anonymous volume,
      // explicit RABBITMQ_ERLANG_COOKIE, Debian instead of alpine
      // image - all hit the byte-identical error, ruling out the
      // image/config as the cause). The directory itself already
      // shows correct rabbitmq:rabbitmq ownership at the mount level,
      // but whatever mounted it doesn't preserve that all the way
      // through for the entrypoint's own later chown/file creation.
      // Overriding the entrypoint to explicitly re-chown right before
      // rabbitmq-server starts sidesteps that regardless of why it's
      // wrong - the default entrypoint already runs its own similar
      // chown internally as root before dropping to the rabbitmq
      // user, so this is strictly redundant on a normal host, only
      // load-bearing here.
      '-e RABBITMQ_DEFAULT_USER=pterocontrol_e2e -e RABBITMQ_DEFAULT_PASS=pterocontrol_e2e ' +
      `-p 127.0.0.1:${RABBITMQ_PORT}:5672 -p 127.0.0.1:${RABBITMQ_MGMT_PORT}:15672 ` +
      '--entrypoint sh rabbitmq:3-management ' +
      '-c "chown -R rabbitmq:rabbitmq /var/lib/rabbitmq && exec docker-entrypoint.sh rabbitmq-server"',
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

// 90s (was 30s - still not enough for RabbitMQ on GitHub Actions, see
// diagnostics() below) covers a cold image pull plus normal startup on
// a dev machine or CI runner. If a container is actually crash-looping
// rather than just slow, waiting longer only delays finding that out -
// diagnostics() on final timeout captures docker ps/logs so the failure
// message says WHY, not just THAT it timed out.
function diagnostics(containerName) {
  try {
    const status = sh(`docker inspect -f "{{.State.Status}} exitCode={{.State.ExitCode}}" ${containerName}`);
    const logs = sh(`docker logs --tail 30 ${containerName} 2>&1`);
    return `\n--- docker inspect: ${status.trim()} ---\n--- docker logs (last 30 lines) ---\n${logs}`;
  } catch (diagError) {
    return `\n(could not collect diagnostics: ${String(diagError)})`;
  }
}

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
  throw new Error(
    `Timed out waiting for the E2E Postgres container to become ready.${diagnostics(POSTGRES_CONTAINER)}`,
  );
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
  throw new Error(
    `Timed out waiting for the E2E RabbitMQ container to become ready.${diagnostics(RABBITMQ_CONTAINER)}`,
  );
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
