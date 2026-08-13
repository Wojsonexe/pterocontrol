/// Validates and normalizes panel URLs entered by the user when adding an
/// instance.
abstract final class InstanceUrlValidator {
  /// Returns a Polish error message if [input] is not a usable panel URL,
  /// or `null` if it is valid. Shaped to be used directly as a
  /// `FormFieldValidator<String>`.
  static String? validate(String? input) {
    final trimmed = (input ?? '').trim();
    if (trimmed.isEmpty) return 'Podaj adres URL panelu.';

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority) {
      return 'Podaj pełny adres, np. https://panel.example.com';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Adres musi zaczynać się od http:// lub https://';
    }
    return null;
  }

  /// Strips a trailing slash so stored/compared URLs are consistent.
  static String normalize(String input) {
    final trimmed = input.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
