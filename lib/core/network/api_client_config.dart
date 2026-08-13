/// Timeouts applied to every [PterodactylApiClient] created by
/// [PterodactylApiClientFactory].
///
/// Kept as a plain value type rather than hard-coded constants so tests
/// (and, later, a settings screen) can override them per instance.
class ApiClientConfig {
  const ApiClientConfig({
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 15),
    this.sendTimeout = const Duration(seconds: 15),
  });

  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;
}
