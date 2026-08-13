import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/presentation/widgets/app_status_badge.dart';
import '../../../../core/presentation/widgets/error_view.dart';
import '../../../../core/theme/app_console_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../application/console_controller.dart';
import '../../application/console_state.dart';
import '../../domain/console_connection_state.dart';
import '../../domain/console_event.dart';
import '../../domain/console_target.dart';
import 'ansi_text.dart';

/// How close to the bottom (in logical pixels) the user has to already be
/// for new console output to auto-scroll them further. Keeps the "don't
/// yank the view while the user is reading scrollback" requirement from
/// being pixel-perfect-fragile — a few pixels of residual scroll momentum
/// should not count as "the user scrolled up".
const kConsoleAutoScrollThreshold = 48.0;

/// Bounds for the terminal output panel's height. This widget is
/// typically embedded inside an already-scrollable screen
/// (`ServerDetailScreen`'s `ListView`), below several other sections
/// (status/info/power actions), so its own output list needs a bounded
/// height rather than trying to size itself to the remaining viewport —
/// but a single fixed number regardless of device size wastes space on
/// small phones and under-uses it on large ones/landscape, so the actual
/// height (see [consolePanelHeight]) is a fraction of the viewport
/// clamped to this range instead of one constant.
///
/// Deliberately on the compact side: this section is not the only thing
/// on the screen, and a panel tall enough to push the command input field
/// below the fold — forcing a scroll before the user can type anything —
/// defeats the point of the input being right there under the terminal.
const kConsoleOutputMinHeight = 220.0;
const kConsoleOutputMaxHeight = 340.0;

/// The terminal panel's height for the current viewport: 28% of the
/// screen height, clamped to [kConsoleOutputMinHeight]/
/// [kConsoleOutputMaxHeight] so it never becomes unusably short on a
/// small phone or crowds out the rest of the screen (and the command
/// input below it) on a tablet/landscape.
double consolePanelHeight(BuildContext context) {
  final viewportHeight = MediaQuery.sizeOf(context).height;
  return (viewportHeight * 0.28).clamp(kConsoleOutputMinHeight, kConsoleOutputMaxHeight);
}

/// Live, WebSocket-backed console for one server.
///
/// Owns only UI-local state (the scroll position, the command text field,
/// whether the "jump to bottom" button is showing) — everything about the
/// connection itself lives in [ConsoleController]/[ConsoleRepository],
/// reachable here purely through `consoleControllerProvider(target)`.
/// Disposing this widget disposes the scroll/text controllers; the
/// WebSocket itself is torn down by Riverpod when
/// `consoleControllerProvider` (and, cascading from it,
/// `consoleRepositoryProvider`) loses its last watcher — see
/// `ConsoleController`'s doc comment.
class ConsoleView extends ConsumerStatefulWidget {
  const ConsoleView({
    super.key,
    required this.instanceId,
    required this.serverIdentifier,
    this.fullscreen = false,
  });

  final String instanceId;
  final String serverIdentifier;

  /// `true` when this console is the entire content of its own screen/tab
  /// (the dedicated "Konsola" tab in `ServerDetailScreen`) rather than one
  /// section embedded among others — the output panel then fills all
  /// available vertical space (`Expanded`) instead of a fixed/clamped
  /// height, and the redundant "Konsola" row label is dropped since the
  /// tab itself already says that.
  final bool fullscreen;

  @override
  ConsumerState<ConsoleView> createState() => _ConsoleViewState();
}

class _ConsoleViewState extends ConsumerState<ConsoleView> {
  final _scrollController = ScrollController();
  final _commandController = TextEditingController();
  int _lastEventCount = 0;
  bool _showJumpToBottom = false;

  ConsoleTarget get _target => (instanceId: widget.instanceId, serverIdentifier: widget.serverIdentifier);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateJumpToBottomVisibility);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateJumpToBottomVisibility);
    _scrollController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - kConsoleAutoScrollThreshold;
  }

  void _updateJumpToBottomVisibility() {
    final shouldShow = !_isNearBottom;
    if (shouldShow != _showJumpToBottom) {
      setState(() => _showJumpToBottom = shouldShow);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _sendCommand() {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;
    ref.read(consoleControllerProvider(_target).notifier).sendCommand(command);
    _commandController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final asyncState = ref.watch(consoleControllerProvider(target));
    final panelHeight = consolePanelHeight(context);

    // Only ever auto-scroll when the buffer actually *grew* (never on a
    // buffer clear from a fresh reconnect, and never just because some
    // unrelated field like connectionState changed), and only when the
    // user was already at (or very near) the bottom before the new lines
    // arrived — checked from the scroll position captured *before* this
    // frame's rebuild, then applied *after* it via a post-frame callback
    // once the new content has actually been laid out.
    ref.listen(consoleControllerProvider(target), (previous, next) {
      final events = next.value?.events;
      if (events == null) return;
      final grew = events.length > _lastEventCount;
      _lastEventCount = events.length;
      if (!grew) return;
      if (!_isNearBottom) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

    return asyncState.when(
      data: (state) => _ConsoleBody(
        state: state,
        panelHeight: panelHeight,
        fullscreen: widget.fullscreen,
        scrollController: _scrollController,
        commandController: _commandController,
        showJumpToBottom: _showJumpToBottom,
        onSendCommand: _sendCommand,
        onReconnect: () => ref.read(consoleControllerProvider(target).notifier).reconnect(),
        onJumpToBottom: _scrollToBottom,
      ),
      loading: () => widget.fullscreen
          ? const Center(child: CircularProgressIndicator())
          : SizedBox(height: panelHeight, child: const Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) {
        final view = ErrorView(message: error is AppException ? error.message : 'Nie udało się uruchomić konsoli.');
        return widget.fullscreen ? view : SizedBox(height: panelHeight, child: view);
      },
    );
  }
}

class _ConsoleBody extends StatelessWidget {
  const _ConsoleBody({
    required this.state,
    required this.panelHeight,
    required this.fullscreen,
    required this.scrollController,
    required this.commandController,
    required this.showJumpToBottom,
    required this.onSendCommand,
    required this.onReconnect,
    required this.onJumpToBottom,
  });

  final ConsoleState state;
  final double panelHeight;
  final bool fullscreen;
  final ScrollController scrollController;
  final TextEditingController commandController;
  final bool showJumpToBottom;
  final VoidCallback onSendCommand;
  final VoidCallback onReconnect;
  final VoidCallback onJumpToBottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSendCommands = state.connectionState == ConsoleConnectionState.connected;
    final canReconnect = state.connectionState == ConsoleConnectionState.disconnected ||
        state.connectionState == ConsoleConnectionState.error;

    final output = _ConsoleOutput(
      state: state,
      scrollController: scrollController,
      showJumpToBottom: showJumpToBottom,
      onJumpToBottom: onJumpToBottom,
    );

    return Padding(
      padding: fullscreen ? const EdgeInsets.all(AppSpacing.md) : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (!fullscreen) ...[
                Text('Konsola', style: theme.textTheme.titleMedium),
                const Spacer(),
              ],
              AppStatusBadge(visual: consoleConnectionStatusVisual(state.connectionState), dense: true),
              if (fullscreen) const Spacer(),
              if (canReconnect)
                IconButton(
                  onPressed: onReconnect,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Połącz ponownie',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (fullscreen) Expanded(child: output) else SizedBox(height: panelHeight, child: output),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: commandController,
                  enabled: canSendCommands,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Wpisz komendę…',
                  ),
                  onSubmitted: (_) => onSendCommand(),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton.filled(
                onPressed: canSendCommands ? onSendCommand : null,
                icon: const Icon(Icons.send),
                tooltip: 'Wyślij komendę',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Maps the WebSocket transport's own lifecycle state to the shared
/// status-badge visual — kept next to [ConsoleView] (not in `domain/`)
/// because [AppStatusVisual]/[Icons] are Flutter/presentation concepts,
/// same reasoning as `ServerStatusChip`'s/`ConnectionStatusChip`'s own
/// mapping functions.
AppStatusVisual consoleConnectionStatusVisual(ConsoleConnectionState state) {
  return switch (state) {
    ConsoleConnectionState.disconnected =>
      const AppStatusVisual(icon: Icons.link_off, label: 'Rozłączono', tone: AppStatusTone.neutral),
    ConsoleConnectionState.connecting => const AppStatusVisual(
        icon: Icons.sync,
        label: 'Łączenie…',
        tone: AppStatusTone.pending,
        isAnimated: true,
      ),
    ConsoleConnectionState.connected =>
      const AppStatusVisual(icon: Icons.check_circle, label: 'Połączono', tone: AppStatusTone.success),
    ConsoleConnectionState.reconnecting => const AppStatusVisual(
        icon: Icons.sync,
        label: 'Ponowne łączenie…',
        tone: AppStatusTone.pending,
        isAnimated: true,
      ),
    ConsoleConnectionState.error =>
      const AppStatusVisual(icon: Icons.error, label: 'Błąd połączenia', tone: AppStatusTone.danger),
  };
}

/// The dark terminal-style output panel — deliberately not theme-aware
/// (fixed dark palette via [AppConsoleColors] regardless of app theme),
/// matching how every reference terminal UI (including the Panel's own
/// web console) looks: console output is conventionally always dark,
/// independent of the surrounding app chrome. See [AppConsoleColors]'s
/// doc comment for why that is its own theme extension instead of being
/// pulled from [ColorScheme].
class _ConsoleOutput extends StatelessWidget {
  const _ConsoleOutput({
    required this.state,
    required this.scrollController,
    required this.showJumpToBottom,
    required this.onJumpToBottom,
  });

  final ConsoleState state;
  final ScrollController scrollController;
  final bool showJumpToBottom;
  final VoidCallback onJumpToBottom;

  @override
  Widget build(BuildContext context) {
    final consoleColors = AppConsoleColors.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: consoleColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(
          children: [
            Builder(
              builder: (context) {
                if (state.events.isEmpty) {
                  final message = switch (state.connectionState) {
                    ConsoleConnectionState.connecting => 'Łączenie z konsolą…',
                    ConsoleConnectionState.reconnecting => 'Ponowne łączenie…',
                    ConsoleConnectionState.error => 'Nie udało się połączyć z konsolą.',
                    ConsoleConnectionState.disconnected => 'Konsola rozłączona.',
                    ConsoleConnectionState.connected => 'Brak danych z konsoli.',
                  };
                  return Center(
                    child: Text(
                      message,
                      style: AppTypography.terminal.copyWith(color: consoleColors.mutedText),
                    ),
                  );
                }

                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  itemCount: state.events.length,
                  itemBuilder: (context, index) => _ConsoleLine(event: state.events[index]),
                );
              },
            ),
            if (showJumpToBottom)
              Positioned(
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: _JumpToBottomButton(onPressed: onJumpToBottom),
              ),
          ],
        ),
      ),
    );
  }
}

class _JumpToBottomButton extends StatelessWidget {
  const _JumpToBottomButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final consoleColors = AppConsoleColors.of(context);

    return Material(
      color: consoleColors.mutedText.withValues(alpha: 0.24),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(Icons.arrow_downward, color: consoleColors.outputText),
        tooltip: 'Przejdź na dół',
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _ConsoleLine extends StatelessWidget {
  const _ConsoleLine({required this.event});

  final ConsoleEvent event;

  @override
  Widget build(BuildContext context) {
    final consoleColors = AppConsoleColors.of(context);
    final color = switch (event.type) {
      ConsoleEventType.output => consoleColors.outputText,
      ConsoleEventType.daemonMessage => consoleColors.daemonMessageText,
      ConsoleEventType.daemonError => consoleColors.daemonErrorText,
      ConsoleEventType.unknown => consoleColors.mutedText,
    };
    final baseStyle = AppTypography.terminal.copyWith(color: color);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text.rich(
        TextSpan(children: parseAnsiToSpans(event.message, baseStyle)),
      ),
    );
  }
}
