import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/instance_list_controller.dart';
import '../../domain/instance_url_validator.dart';

enum _ConnectionTestState { idle, testing, success, failed }

/// Multi-step "Add Panel" wizard: URL -> API key -> name + a **real**
/// connection test (not a fake progress bar — it actually calls
/// `InstanceListController.testConnection`, which hits
/// `GET /api/client` with the entered credentials and reports back
/// exactly the [AppException] that call produced) -> success.
///
/// The panel is only ever persisted (`addInstance`) after the test step
/// succeeds — a broken URL or wrong key is caught before it is saved,
/// not after the first time the user tries to use it.
class AddInstanceScreen extends ConsumerStatefulWidget {
  const AddInstanceScreen({super.key});

  @override
  ConsumerState<AddInstanceScreen> createState() => _AddInstanceScreenState();
}

class _AddInstanceScreenState extends ConsumerState<AddInstanceScreen> {
  static const _stepCount = 4;

  final _pageController = PageController();
  final _urlFormKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _nameController = TextEditingController();

  int _step = 0;
  bool _obscureApiKey = true;
  _ConnectionTestState _testState = _ConnectionTestState.idle;
  String? _testErrorMessage;
  bool _isSaving = false;

  @override
  void dispose() {
    _pageController.dispose();
    _urlController.dispose();
    _apiKeyController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String get _normalizedUrl => InstanceUrlValidator.normalize(_urlController.text);

  void _goToStep(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(step, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  void _next() {
    if (_step == 0 && !(_urlFormKey.currentState?.validate() ?? false)) return;
    if (_step < _stepCount - 1) _goToStep(_step + 1);
  }

  void _back() {
    if (_step > 0) _goToStep(_step - 1);
  }

  Future<void> _testConnection() async {
    setState(() {
      _testState = _ConnectionTestState.testing;
      _testErrorMessage = null;
    });

    final error = await ref.read(instanceListControllerProvider.notifier).testConnection(
          baseUrl: _normalizedUrl,
          apiKey: _apiKeyController.text.trim(),
        );

    if (!mounted) return;
    setState(() {
      if (error == null) {
        _testState = _ConnectionTestState.success;
      } else {
        _testState = _ConnectionTestState.failed;
        _testErrorMessage = error.message;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(instanceListControllerProvider.notifier).addInstance(
            name: _nameController.text.trim().isEmpty ? _defaultName() : _nameController.text.trim(),
            baseUrl: _normalizedUrl,
            apiKey: _apiKeyController.text.trim(),
          );
      if (!mounted) return;
      _goToStep(3);
    } catch (error) {
      if (!mounted) return;
      final message = error is AppException ? error.message : 'Nie udało się dodać panelu.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _defaultName() {
    final uri = Uri.tryParse(_normalizedUrl);
    return uri?.host ?? 'Mój panel';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dodaj panel'),
        leading: _step == 0 || _step == 3
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        automaticallyImplyLeading: _step == 0 || _step == 3,
      ),
      body: Column(
        children: [
          if (_step < 3)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: LinearProgressIndicator(
                value: (_step + 1) / (_stepCount - 1),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _UrlStep(formKey: _urlFormKey, controller: _urlController, onNext: _next),
                _ApiKeyStep(
                  controller: _apiKeyController,
                  obscure: _obscureApiKey,
                  onToggleObscure: () => setState(() => _obscureApiKey = !_obscureApiKey),
                  onNext: _next,
                ),
                _NameAndTestStep(
                  nameController: _nameController,
                  defaultName: _defaultName(),
                  testState: _testState,
                  testErrorMessage: _testErrorMessage,
                  isSaving: _isSaving,
                  onTest: _testConnection,
                  onSave: _save,
                ),
                _SuccessStep(panelName: _nameController.text.trim().isEmpty ? _defaultName() : _nameController.text.trim()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WizardStepScaffold extends StatelessWidget {
  const _WizardStepScaffold({
    required this.title,
    required this.description,
    required this.child,
    this.primaryAction,
  });

  final String title;
  final String description;
  final Widget child;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.lg),
          child,
          const Spacer(),
          ?primaryAction,
        ],
      ),
    );
  }
}

class _UrlStep extends StatelessWidget {
  const _UrlStep({required this.formKey, required this.controller, required this.onNext});

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _WizardStepScaffold(
      title: 'Adres panelu',
      description: 'Podaj adres URL swojego panelu Pterodactyl.',
      primaryAction: FilledButton(onPressed: onNext, child: const Text('Dalej')),
      child: Form(
        key: formKey,
        child: TextFormField(
          key: const Key('addPanel.urlField'),
          controller: controller,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Adres URL panelu', hintText: 'https://panel.example.com'),
          validator: InstanceUrlValidator.validate,
          onFieldSubmitted: (_) => onNext(),
        ),
      ),
    );
  }
}

class _ApiKeyStep extends StatelessWidget {
  const _ApiKeyStep({
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    required this.onNext,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _WizardStepScaffold(
      title: 'Klucz API',
      description: 'Panel → Account Settings → API Credentials. Klucz zaczyna się od "ptlc_".',
      primaryAction: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final canContinue = controller.text.trim().length >= 10;
          return FilledButton(onPressed: canContinue ? onNext : null, child: const Text('Dalej'));
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('addPanel.apiKeyField'),
            controller: controller,
            obscureText: obscure,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Klucz API klienta',
              hintText: 'ptlc_...',
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                tooltip: obscure ? 'Pokaż klucz' : 'Ukryj klucz',
                onPressed: onToggleObscure,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 18, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Klucz jest szyfrowany i przechowywany wyłącznie na tym urządzeniu.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NameAndTestStep extends StatelessWidget {
  const _NameAndTestStep({
    required this.nameController,
    required this.defaultName,
    required this.testState,
    required this.testErrorMessage,
    required this.isSaving,
    required this.onTest,
    required this.onSave,
  });

  final TextEditingController nameController;
  final String defaultName;
  final _ConnectionTestState testState;
  final String? testErrorMessage;
  final bool isSaving;
  final VoidCallback onTest;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final canSave = testState == _ConnectionTestState.success && !isSaving;

    return _WizardStepScaffold(
      title: 'Nazwa i test połączenia',
      description: 'Nadaj panelowi nazwę i sprawdź, czy dane logowania są poprawne.',
      primaryAction: FilledButton(
        onPressed: canSave ? onSave : null,
        child: isSaving
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Zapisz i zakończ'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('addPanel.nameField'),
            controller: nameController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: 'Nazwa', hintText: defaultName),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ConnectionTestPanel(state: testState, errorMessage: testErrorMessage, onTest: onTest),
        ],
      ),
    );
  }
}

class _ConnectionTestPanel extends StatelessWidget {
  const _ConnectionTestPanel({required this.state, required this.errorMessage, required this.onTest});

  final _ConnectionTestState state;
  final String? errorMessage;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = AppSemanticColors.of(context);

    final (icon, iconColor, title, subtitle) = switch (state) {
      _ConnectionTestState.idle => (
          Icons.wifi_tethering,
          theme.colorScheme.onSurfaceVariant,
          'Gotowe do testu',
          'Sprawdź połączenie przed zapisaniem panelu.',
        ),
      _ConnectionTestState.testing => (
          Icons.sync,
          theme.colorScheme.primary,
          'Testowanie połączenia…',
          'Łączenie z panelem i weryfikacja klucza API.',
        ),
      _ConnectionTestState.success => (
          Icons.check_circle,
          AppSemanticColors.of(context).success,
          'Połączono pomyślnie',
          'Adres i klucz API są poprawne.',
        ),
      _ConnectionTestState.failed => (
          Icons.error,
          danger.danger,
          'Nie udało się połączyć',
          errorMessage ?? 'Sprawdź adres URL i klucz API.',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state == _ConnectionTestState.testing)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: iconColor),
                )
              else
                Icon(icon, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: state == _ConnectionTestState.testing ? null : onTest,
            icon: const Icon(Icons.wifi_tethering),
            label: Text(state == _ConnectionTestState.failed ? 'Spróbuj ponownie' : 'Testuj połączenie'),
          ),
        ],
      ),
    );
  }
}

class _SuccessStep extends StatelessWidget {
  const _SuccessStep({required this.panelName});

  final String panelName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = AppSemanticColors.of(context).success;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: success.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(Icons.check_circle, size: 48, color: success),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Panel dodany', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '"$panelName" jest gotowy do zarządzania.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.dashboard),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Przejdź do panelu'),
            ),
          ],
        ),
      ),
    );
  }
}
