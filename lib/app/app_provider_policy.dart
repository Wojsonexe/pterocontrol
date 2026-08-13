/// Riverpod 3's default provider behavior silently retries a failed
/// provider up to 10 times with exponential backoff
/// (`ProviderContainer.defaultRetry`). This app opts out of that.
///
/// Every retry in this app is either user-initiated (the "Spróbuj ponownie"
/// button on `ErrorView`, pull-to-refresh) or an explicit, visible action
/// (`ServerListController.loadNextPage`) — never silent. Automatic retries
/// would multiply requests against a Panel that enforces a shared 256
/// requests/minute budget per user across every client the user is signed
/// into (see README, "Znane ograniczenia") — for a real failure (e.g. a
/// revoked API key), that means up to 11 rapid 401s instead of one, for no
/// benefit to the user.
///
/// Passed as `retry:` to the root `ProviderScope` in `main.dart`, and to
/// every `ProviderContainer`/`ProviderScope` built in tests, so behavior
/// stays the same in both.
Duration? noAutomaticProviderRetry(int retryCount, Object error) => null;
