import 'dart:async';

import 'decision.dart';
import 'events.dart';
import 'status.dart';
import 'transport.dart';

/// The longest a single timer waits for the end of a suspension. Browsers
/// keep the delay of `setTimeout` in 32 bits of milliseconds (about 24.8
/// days) and fire a longer one far too early or at once. A timer that fires
/// before the end waits again.
const _maxTimerWait = Duration(days: 1);

/// Follows the sanction status of one user, usually the one logged in to the
/// app, e.g. to show a notice when the account is suspended.
///
/// The status comes from [refresh] (via [LimeniaTransport.getSubjectStatus])
/// and from events the app gets through its backend ([handleEvent],
/// [handleDecision]). The status of Limenia is authoritative: after an event
/// the watcher applies it at once and then fetches the status again.
///
/// Events can arrive late, out of order or twice. As in Limenia, a
/// suspension, a ban, a restore of the account and `subject.status_changed`
/// set the status whatever it was, so the watcher applies one only if it is
/// newer than the last of them. A warning changes only an active user and
/// counts only if it is newer than that last one; a suspension that has ended
/// by the time of the warning counts as lifted, so the warning makes the user
/// warned. A restore of the content ([RestoreScope.content]) and a decision
/// about a review request keep the status. If one of the four arrives older
/// than the last, or a decision has an action or a restore scope this version
/// of the package does not know, the watcher asks Limenia instead
/// ([refreshOnEvent]).
///
/// A suspension ends on time even without a new event: [current] and the
/// streams switch to active at `suspendedUntil`. [current] and [isRestricted]
/// go by the clock of the device and are only advisory: the backend of the app
/// must enforce restrictions itself.
final class SubjectStatusWatcher {
  SubjectStatusWatcher({
    required LimeniaTransport transport,
    required this.externalUserId,
    this.refreshOnEvent = true,
    this.onRefreshError,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? createTimer,
  })  : _transport = transport,
        _now = now ?? DateTime.now,
        _createTimer = createTimer ?? Timer.new;

  final LimeniaTransport _transport;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _createTimer;

  final String externalUserId;

  /// Whether events about this user trigger a [refresh]: every applied one,
  /// and the ones the watcher cannot apply (see the class comment).
  final bool refreshOnEvent;

  /// Errors of [tryRefresh], including the refreshes after an event.
  final void Function(Object error, StackTrace stackTrace)? onRefreshError;

  final _changes = StreamController<SubjectStatus>.broadcast(sync: true);
  SubjectStatus? _status;
  SubjectStatus? _emitted;
  Timer? _expiry;

  // Time of the newest applied event that sets the status whatever it was
  // (suspension, ban, restore, subject.status_changed), and of the newest
  // warning. See _applyStatus and _applyWarning.
  DateTime? _statusAt;
  DateTime? _warnAt;

  // Refreshes started before the last applied event return an older status
  // and are discarded (see refresh).
  int _refreshSeq = 0;
  int _appliedSeq = 0;
  int _eventMark = 0;

  /// The status now, null before the first [refresh] or event.
  SubjectStatus? get current => _status?.effectiveAt(_now());

  /// Every change of the status. Does not repeat the current status.
  Stream<SubjectStatus> get changes => _changes.stream;

  /// The current status (if known) followed by every change, for example
  /// for a `StreamBuilder`.
  Stream<SubjectStatus> get stream {
    StreamSubscription<SubjectStatus>? subscription;
    late final StreamController<SubjectStatus> controller;
    controller = StreamController<SubjectStatus>(
      onListen: () {
        if (current case final status?) controller.add(status);
        subscription = _changes.stream.listen(controller.add, onDone: controller.close);
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  /// Whether the account may not be used now (suspended or banned).
  bool get isRestricted => current?.isRestrictedAt(_now()) ?? false;

  /// Fetches the status. Call it after login and when the app comes back to
  /// the foreground. Throws the errors of the transport.
  Future<SubjectStatus> refresh() async {
    _checkOpen();
    final seq = ++_refreshSeq;
    final fetched = await _transport.getSubjectStatus(externalUserId);
    if (_changes.isClosed) return fetched.effectiveAt(_now());
    if (seq > _appliedSeq && seq > _eventMark) {
      _appliedSeq = seq;
      _set(fetched);
    }
    return current!;
  }

  /// Like [refresh], but never throws: errors go to [onRefreshError] and the
  /// result is null. Meant for `AppLifecycleListener(onResume: ...)`.
  Future<SubjectStatus?> tryRefresh() async {
    if (_changes.isClosed) return null;
    try {
      return await refresh();
    } on Exception catch (e, st) {
      onRefreshError?.call(e, st);
      return null;
    }
  }

  /// Applies [event] if it concerns this user. Returns whether it was
  /// applied: false for a redelivered or outdated event (see the class
  /// comment). A warning to a suspended or banned user is applied but keeps
  /// the status. After [dispose], an event that changes the status of this
  /// user throws a [StateError].
  bool handleEvent(LimeniaEvent event) => switch (event) {
        DecisionCreatedEvent(:final decision) => handleDecision(decision),
        SubjectStatusChangedEvent(:final subject) when subject.externalUserId == externalUserId =>
          _applyStatus(event.createdAt, subject),
        _ => false,
      };

  /// Applies [decision] like [handleEvent] if it changes the status of this
  /// user ([ModerationDecision.changesUserStatus]). A decision about a review
  /// request and a restore of the content ([RestoreScope.content]) never do,
  /// so they are ignored.
  bool handleDecision(ModerationDecision decision) {
    if (decision.externalUserId != externalUserId) return false;
    if (!decision.changesUserStatus) {
      if (_mayChangeStatus(decision)) _reconcile();
      return false;
    }
    final at = decision.decidedAt;
    return switch (decision.action) {
      ModerationAction.warnUser => _applyWarning(at),
      ModerationAction.suspendUser => _applyStatus(at, _statusOf(SanctionStatus.suspended, decision.suspendUntil)),
      ModerationAction.banUser => _applyStatus(at, _statusOf(SanctionStatus.banned)),
      ModerationAction.restore => _applyStatus(at, _statusOf(SanctionStatus.active)),
      _ => false, // keeps the status, see ModerationAction.changesUserStatus
    };
  }

  /// Stops the timer and closes the streams.
  void dispose() {
    _expiry?.cancel();
    _changes.close();
  }

  /// Whether [decision], which does not change the status as far as this
  /// version of the package knows, may still change it: an action or a
  /// restore scope it does not know. A decision about a review request never
  /// does.
  static bool _mayChangeStatus(ModerationDecision decision) =>
      decision.reviewId == null &&
      switch (decision.action) {
        null => true,
        ModerationAction.restore => decision.restoreScopeName != null && decision.restoreScope == null,
        _ => false,
      };

  /// Applies an event at [at] that sets [status] whatever the status was
  /// before. A newer warning still applies if the user is active at its time,
  /// also after the end of a suspension.
  bool _applyStatus(DateTime at, SubjectStatus status) {
    _checkOpen();
    final last = _statusAt;
    if (last != null && !at.isAfter(last)) {
      // Limenia may have applied the two in the other order (the times of a
      // lift and a decision can cross), so ask it. A redelivery has the same
      // time and needs nothing.
      if (at.isBefore(last)) _reconcile();
      return false;
    }
    _statusAt = at;
    final warnAt = _warnAt;
    final warnedLater =
        warnAt != null && warnAt.isAfter(at) && status.effectiveAt(warnAt).status == SanctionStatus.active;
    _accept(warnedLater ? _statusOf(SanctionStatus.warned) : status);
    return true;
  }

  /// Applies a warning at [at]. It counts only if it is newer than the last
  /// event that set the status, and like in Limenia it changes only an active
  /// user: a suspension that has ended by [at] counts as lifted, and a status
  /// not known yet counts as active.
  bool _applyWarning(DateTime at) {
    _checkOpen();
    final lastWarning = _warnAt;
    if (lastWarning != null && !at.isAfter(lastWarning)) return false;
    _warnAt = at;
    final statusAt = _statusAt;
    if (statusAt != null && !at.isAfter(statusAt)) return false;
    final status = _status?.effectiveAt(at);
    _accept(switch (status?.status) {
      SanctionStatus.suspended || SanctionStatus.banned => status!,
      SanctionStatus.active || SanctionStatus.warned || null => _statusOf(SanctionStatus.warned),
    });
    return true;
  }

  /// Takes [status] from an event: a refresh started before it must not
  /// overwrite it.
  void _accept(SubjectStatus status) {
    _eventMark = _refreshSeq;
    _set(status);
    _reconcile();
  }

  /// Asks Limenia for the status after an event, if [refreshOnEvent].
  void _reconcile() {
    if (refreshOnEvent) unawaited(tryRefresh());
  }

  SubjectStatus _statusOf(SanctionStatus status, [DateTime? suspendedUntil]) =>
      SubjectStatus(externalUserId: externalUserId, status: status, suspendedUntil: suspendedUntil);

  void _set(SubjectStatus status) {
    _status = status;
    _scheduleExpiry();
    _emitIfChanged();
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    _expiry = null;
    final until = _status?.status == SanctionStatus.suspended ? _status?.suspendedUntil : null;
    if (until == null) return;
    final wait = until.difference(_now());
    if (wait.isNegative || wait == Duration.zero) return;
    _expiry = _createTimer(wait < _maxTimerWait ? wait : _maxTimerWait, () {
      if (_changes.isClosed) return;
      _emitIfChanged();
      _scheduleExpiry(); // a timer that fires before the end (capped or a little early) waits again
    });
  }

  void _emitIfChanged() {
    final status = current;
    if (status == null || status == _emitted) return;
    _emitted = status;
    _changes.add(status);
  }

  void _checkOpen() {
    if (_changes.isClosed) throw StateError('The SubjectStatusWatcher has been disposed.');
  }
}
