import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/control_plane_session_controller.dart';
import '../../application/control_plane_url_validator.dart';

/// Login form for Control Plane mode: backend URL + email + password.
///
/// No "create account" option — see `ControlPlaneAuthApi`'s doc comment
/// for why tenant creation is deliberately not a self-service flow this
/// app exposes.
class ControlPlaneLoginForm extends ConsumerStatefulWidget {
  const ControlPlaneLoginForm({super.key});

  @override
  ConsumerState<ControlPlaneLoginForm> createState() => _ControlPlaneLoginFormState();
}

class _ControlPlaneLoginFormState extends ConsumerState<ControlPlaneLoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final error = await ref.read(controlPlaneSessionControllerProvider.notifier).login(
          baseUrl: _urlController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _errorMessage = error == null ? null : _messageFor(error);
    });
  }

  String _messageFor(AppException error) {
    // A raw `UnauthorizedException.message` ("Sesja wygasła lub klucz API
    // jest nieprawidłowy.") is written for an *expired session*, not a
    // first-time login attempt — this form gives login-appropriate copy
    // for that one case instead, the same way `AddInstanceScreen`'s
    // connection-test panel supplies its own contextual text rather than
    // always showing `error.message` verbatim.
    if (error is UnauthorizedException) return 'Nieprawidłowy e-mail lub hasło.';
    return error.message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zaloguj się do Control Plane', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Zarządzaj serwerami z wielu paneli Pterodactyl przez jedno konto.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            key: const Key('controlPlaneLogin.urlField'),
            controller: _urlController,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Adres Control Plane',
              hintText: 'https://control-plane.example.com',
            ),
            validator: ControlPlaneUrlValidator.validate,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('controlPlaneLogin.emailField'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'E-mail'),
            validator: (value) {
              final trimmed = (value ?? '').trim();
              if (trimmed.isEmpty) return 'Podaj adres e-mail.';
              if (!trimmed.contains('@')) return 'Podaj poprawny adres e-mail.';
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('controlPlaneLogin.passwordField'),
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Hasło',
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                tooltip: _obscurePassword ? 'Pokaż hasło' : 'Ukryj hasło',
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (value) => (value == null || value.isEmpty) ? 'Podaj hasło.' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_errorMessage case final message?) ...[
            const SizedBox(height: AppSpacing.md),
            Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const Key('controlPlaneLogin.submitButton'),
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Zaloguj się'),
          ),
        ],
      ),
    );
  }
}
