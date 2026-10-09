import 'dart:async';

import 'package:flutter/material.dart';
import 'package:limenia/limenia.dart';

import 'strings.dart';

/// The longest a single timer waits for the end of a suspension, as in
/// [SubjectStatusWatcher]: browsers fire longer `setTimeout` delays at once.
const _maxTimerWait = Duration(days: 1);

/// A notice about the restriction of the user's account, to place inline,
/// e.g. at the top of a feed or the profile:
///
/// * [SanctionStatus.warned]: a soft banner,
/// * [SanctionStatus.suspended]: a prominent notice with the end of the
///   suspension in the local time of the device,
/// * [SanctionStatus.banned]: a prominent notice,
/// * [SanctionStatus.active]: nothing.
///
/// The notice uses [SubjectStatus.effectiveAt] with [now]: a suspension that
/// has ended shows nothing, and a notice on screen disappears by itself when
/// the suspension ends. Like the status in the app it is advisory only; the
/// backend of the app enforces restrictions.
///
/// For a page that replaces the app while the account is suspended or banned,
/// see [LimeniaRestrictionScreen]; to follow the status of the logged-in user,
/// [LimeniaSubjectStatusBuilder].
class LimeniaRestrictionNotice extends StatelessWidget {
  /// Creates a notice for [status].
  const LimeniaRestrictionNotice({
    super.key,
    required this.status,
    this.now,
    this.onShowReasons,
    this.onAppeal,
    this.strings,
  });

  /// The status of the user, e.g. [SubjectStatusWatcher.current].
  final SubjectStatus status;

  /// The clock, [DateTime.now] by default.
  final DateTime Function()? now;

  /// Shows a button "Show reasons" that calls it, e.g. to show the statement
  /// of reasons of the decision ([LimeniaStatementOfReasonsView]). Null for no
  /// button.
  final VoidCallback? onShowReasons;

  /// Shows a button "Submit a complaint" that calls it, e.g. to open
  /// [showLimeniaAppealSheet]. Null for no button.
  final VoidCallback? onAppeal;

  /// Texts of the notice. Null for [LimeniaUiStrings.of].
  final LimeniaUiStrings? strings;

  @override
  Widget build(BuildContext context) => _EffectiveStatus(
        status: status,
        now: now,
        builder: (context, effective) {
          final strings = this.strings ?? LimeniaUiStrings.of(context);
          final colors = Theme.of(context).colorScheme;
          return switch (effective.status) {
            SanctionStatus.active => const SizedBox.shrink(),
            SanctionStatus.warned => _Banner(
                icon: Icons.info_outline,
                title: strings.warnedTitle,
                message: strings.warnedMessage,
                background: colors.secondaryContainer,
                foreground: colors.onSecondaryContainer,
                strings: strings,
                onShowReasons: onShowReasons,
                onAppeal: onAppeal,
              ),
            SanctionStatus.suspended => _Banner(
                icon: Icons.lock_clock_outlined,
                title: strings.suspendedTitle,
                message: _suspendedMessage(strings, effective),
                background: colors.errorContainer,
                foreground: colors.onErrorContainer,
                strings: strings,
                onShowReasons: onShowReasons,
                onAppeal: onAppeal,
              ),
            SanctionStatus.banned => _Banner(
                icon: Icons.block,
                title: strings.bannedTitle,
                message: strings.bannedMessage,
                background: colors.errorContainer,
                foreground: colors.onErrorContainer,
                strings: strings,
                onShowReasons: onShowReasons,
                onAppeal: onAppeal,
              ),
          };
        },
      );
}

/// A full page for a suspended or banned account, e.g. in place of the home
/// screen. Shows nothing for an active or warned user; use
/// [LimeniaRestrictionNotice] for the warning.
///
/// Like [LimeniaRestrictionNotice] it uses [SubjectStatus.effectiveAt] with
/// [now] and disappears when a suspension ends. Put it in the body of a
/// [Scaffold]; it scrolls if the screen is too small.
class LimeniaRestrictionScreen extends StatelessWidget {
  /// Creates the page for [status].
  const LimeniaRestrictionScreen({
    super.key,
    required this.status,
    this.now,
    this.onShowReasons,
    this.onAppeal,
    this.footer,
    this.strings,
  });

  /// The status of the user, e.g. [SubjectStatusWatcher.current].
  final SubjectStatus status;

  /// The clock, [DateTime.now] by default.
  final DateTime Function()? now;

  /// Shows a button "Show reasons" that calls it. Null for no button.
  final VoidCallback? onShowReasons;

  /// Shows a button "Submit a complaint" that calls it. Null for no button.
  final VoidCallback? onAppeal;

  /// Shown below the buttons, e.g. a button to log out or a way to contact
  /// the app.
  final Widget? footer;

  /// Texts of the page. Null for [LimeniaUiStrings.of].
  final LimeniaUiStrings? strings;

  @override
  Widget build(BuildContext context) => _EffectiveStatus(
        status: status,
        now: now,
        builder: (context, effective) {
          final strings = this.strings ?? LimeniaUiStrings.of(context);
          final (icon, title, message) = switch (effective.status) {
            SanctionStatus.suspended => (
                Icons.lock_clock_outlined,
                strings.suspendedTitle,
                _suspendedMessage(strings, effective),
              ),
            SanctionStatus.banned => (Icons.block, strings.bannedTitle, strings.bannedMessage),
            SanctionStatus.active || SanctionStatus.warned => (null, '', ''),
          };
          if (icon == null) return const SizedBox.shrink();
          final theme = Theme.of(context);
          final onShowReasons = this.onShowReasons;
          final onAppeal = this.onAppeal;
          final footer = this.footer;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      container: true,
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(icon, size: 64, color: theme.colorScheme.error),
                          const SizedBox(height: 24),
                          Semantics(
                            header: true,
                            child: Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            message,
                            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    if (onShowReasons != null) ...[
                      const SizedBox(height: 32),
                      FilledButton.tonal(onPressed: onShowReasons, child: Text(strings.showReasons)),
                    ],
                    if (onAppeal != null) ...[
                      SizedBox(height: onShowReasons == null ? 32 : 12),
                      OutlinedButton(onPressed: onAppeal, child: Text(strings.submitComplaint)),
                    ],
                    if (footer != null) ...[
                      const SizedBox(height: 24),
                      footer,
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
}

/// Builds with the current status of a [SubjectStatusWatcher] and again on
/// every change, including the end of a suspension.
///
/// ```dart
/// LimeniaSubjectStatusBuilder(
///   watcher: watcher,
///   builder: (context, status) => status != null && status.isRestrictedAt(DateTime.now())
///       ? Scaffold(body: LimeniaRestrictionScreen(status: status))
///       : const HomeScreen(),
/// )
/// ```
///
/// Unlike a [StreamBuilder] on [SubjectStatusWatcher.stream], it subscribes
/// once per watcher, not on every build.
class LimeniaSubjectStatusBuilder extends StatefulWidget {
  /// Creates a builder for [watcher].
  const LimeniaSubjectStatusBuilder({super.key, required this.watcher, required this.builder});

  /// The watcher, e.g. from `Limenia.watchSubject`. The app refreshes and
  /// disposes it.
  final SubjectStatusWatcher watcher;

  /// Builds with [SubjectStatusWatcher.current]: null before the first
  /// refresh or event, a suspension that has ended as active.
  final Widget Function(BuildContext context, SubjectStatus? status) builder;

  @override
  State<LimeniaSubjectStatusBuilder> createState() => _LimeniaSubjectStatusBuilderState();
}

class _LimeniaSubjectStatusBuilderState extends State<LimeniaSubjectStatusBuilder> {
  StreamSubscription<SubjectStatus>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(LimeniaSubjectStatusBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.watcher != widget.watcher) {
      unawaited(_subscription?.cancel());
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _listen() {
    _subscription = widget.watcher.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.watcher.current);
}

String _suspendedMessage(LimeniaUiStrings strings, SubjectStatus status) {
  final until = status.suspendedUntil;
  return strings.suspendedMessage(until == null ? null : strings.formatDateTime(until));
}

/// Builds with [status] at the time of [now] and builds again when a
/// suspension ends.
class _EffectiveStatus extends StatefulWidget {
  const _EffectiveStatus({required this.status, required this.now, required this.builder});

  final SubjectStatus status;
  final DateTime Function()? now;
  final Widget Function(BuildContext context, SubjectStatus effective) builder;

  @override
  State<_EffectiveStatus> createState() => _EffectiveStatusState();
}

class _EffectiveStatusState extends State<_EffectiveStatus> {
  Timer? _timer;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _scheduleEnd();
  }

  @override
  void didUpdateWidget(_EffectiveStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status || oldWidget.now != widget.now) _scheduleEnd();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Builds again at the end of a suspension. A timer that fires before the
  /// end (capped or early) waits again.
  void _scheduleEnd() {
    _timer?.cancel();
    _timer = null;
    final effective = widget.status.effectiveAt(_now());
    final until = effective.status == SanctionStatus.suspended ? effective.suspendedUntil : null;
    if (until == null) return;
    final wait = until.difference(_now());
    if (wait <= Duration.zero) return;
    _timer = Timer(wait < _maxTimerWait ? wait : _maxTimerWait, () {
      if (!mounted) return;
      setState(() {});
      _scheduleEnd();
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.status.effectiveAt(_now()));
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.title,
    required this.message,
    required this.background,
    required this.foreground,
    required this.strings,
    required this.onShowReasons,
    required this.onAppeal,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color background;
  final Color foreground;
  final LimeniaUiStrings strings;
  final VoidCallback? onShowReasons;
  final VoidCallback? onAppeal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onShowReasons = this.onShowReasons;
    final onAppeal = this.onAppeal;
    final buttonStyle = TextButton.styleFrom(foregroundColor: foreground);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: foreground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(title, style: theme.textTheme.titleMedium?.copyWith(color: foreground)),
                        ),
                        const SizedBox(height: 4),
                        Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: foreground)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (onShowReasons != null || onAppeal != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  children: [
                    if (onShowReasons != null)
                      TextButton(onPressed: onShowReasons, style: buttonStyle, child: Text(strings.showReasons)),
                    if (onAppeal != null)
                      TextButton(onPressed: onAppeal, style: buttonStyle, child: Text(strings.submitComplaint)),
                  ],
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
