/**
 * Raised by a handler for a failure that has nothing to do with
 * Pterodactyl's HTTP response (missing instance/credential row, envelope
 * missing a required field) but is still clearly non-retryable - the
 * job-classifier treats it exactly like PterodactylAuthError/
 * PterodactylNotFoundError: straight to DLQ, no retry.
 */
export class PermanentJobError extends Error {}
