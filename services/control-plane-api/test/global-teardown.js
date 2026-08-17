/**
 * Jest globalTeardown for the E2E suite - mirrors global-setup.js: always
 * removes the throwaway containers and the generated .env.e2e, even if the
 * tests themselves failed (Jest still runs globalTeardown on failure).
 */
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const POSTGRES_CONTAINER = 'pterocontrol-e2e-postgres';
const RABBITMQ_CONTAINER = 'pterocontrol-e2e-rabbitmq';
const ENV_FILE = path.join(__dirname, '.env.e2e');

module.exports = async function globalTeardown() {
  try {
    execSync(`docker rm -f ${POSTGRES_CONTAINER} ${RABBITMQ_CONTAINER}`, { stdio: 'pipe' });
  } catch {
    // Best-effort - nothing else to do if this fails.
  }

  try {
    fs.unlinkSync(ENV_FILE);
  } catch {
    // Fine if it was never created (e.g. setup failed before writing it).
  }
};
