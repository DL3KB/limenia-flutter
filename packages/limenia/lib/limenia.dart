/// The headless API for apps that integrate Limenia, without widgets. The
/// widgets are in `package:limenia/ui.dart`.
///
/// The app talks to Limenia only through its own backend, which holds the API
/// key: implement [LimeniaTransport] for that way. See README.md.
library;

export 'src/appeal.dart';
export 'src/categories.dart';
export 'src/client.dart';
export 'src/decision.dart';
export 'src/device.dart';
export 'src/errors.dart';
export 'src/events.dart';
export 'src/idempotency.dart';
export 'src/json.dart' show JsonMap;
export 'src/pending.dart';
export 'src/report.dart';
export 'src/report_feedback.dart';
export 'src/reporter.dart';
export 'src/review.dart';
export 'src/signal.dart';
export 'src/status.dart';
export 'src/transport.dart';
export 'src/validation.dart';
export 'src/watcher.dart';
