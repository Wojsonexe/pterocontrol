/// Credentials required to authenticate against a single Pterodactyl
/// instance's Client API.
///
/// Today this is a single API key (a Pterodactyl "Client API" key, e.g.
/// `ptlc_...`). Kept as its own type rather than a raw [String] so the
/// storage/auth mechanism can evolve (e.g. a paired session token) without
/// changing every call site that needs "the credentials for this instance".
class InstanceCredentials {
  const InstanceCredentials({required this.apiKey});

  final String apiKey;
}
