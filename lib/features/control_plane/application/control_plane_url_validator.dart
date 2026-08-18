/// Validates and normalizes the Control Plane backend URL entered on the
/// login screen. A small, deliberate duplicate of
/// `features/instances/domain/instance_url_validator.dart` rather than a
/// shared import — see `control_plane_session.dart` for why this feature
/// stays independent of the Pterodactyl-direct one.
abstract final class ControlPlaneUrlValidator {
  static String? validate(String? input) {
    final trimmed = (input ?? '').trim();
    if (trimmed.isEmpty) return 'Podaj adres URL Control Plane.';

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority) {
      return 'Podaj pełny adres, np. https://control-plane.example.com';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Adres musi zaczynać się od http:// lub https://';
    }
    return null;
  }

  static String normalize(String input) {
    final trimmed = input.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
