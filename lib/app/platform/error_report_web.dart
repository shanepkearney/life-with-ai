import 'dart:js_interop';

@JS('lifeReportError')
external JSFunction? get _lifeReportError;

/// Hands the error to web/index.html's lifeReportError: [visible] shows the
/// notice (once a visit), otherwise it's only counted. A page without it (a
/// test harness, say) is left alone.
void reportAppError(String kind, String message, {required bool visible}) {
  final report = _lifeReportError;
  if (report == null) return;
  report.callAsFunction(null, kind.toJS, message.toJS, visible.toJS);
}
