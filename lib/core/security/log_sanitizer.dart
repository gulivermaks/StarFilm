import 'dart:collection';

/// Masks API keys, Bearer tokens, and PIN codes before storing or displaying logs.
class LogSanitizer {
  const LogSanitizer._();

  static final RegExp _bearerPattern = RegExp(r'(Bearer\s+)[A-Za-z0-9._\-]+', caseSensitive: false);
  static final RegExp _queryKeyPattern = RegExp(
    r'([?&](?:api_key|key|pin|token)=)([^&\s]+)',
    caseSensitive: false,
  );
  static final RegExp _googleKeyPattern = RegExp(r'AIza[0-9A-Za-z\-_]{20,}');
  static final RegExp _hexTokenPattern = RegExp(r'\b[a-fA-F0-9]{32,}\b');

  static String mask(String input) {
    var out = input;
    out = out.replaceAllMapped(_bearerPattern, (m) => '${m[1]}***');
    out = out.replaceAllMapped(_queryKeyPattern, (m) => '${m[1]}***');
    out = out.replaceAll(_googleKeyPattern, 'AIza***');
    out = out.replaceAll(_hexTokenPattern, '***');
    return out;
  }
}

class DiagnosticsLog {
  DiagnosticsLog({this.maxEntries = 200});

  final int maxEntries;
  final ListQueue<String> _entries = ListQueue<String>();

  List<String> get entries => List.unmodifiable(_entries);

  void add(String level, String message) {
    final ts = DateTime.now().toIso8601String();
    final sanitized = LogSanitizer.mask(message);
    if (_entries.length >= maxEntries) {
      _entries.removeFirst();
    }
    _entries.add('[$ts][$level] $sanitized');
  }

  void info(String message) => add('INFO', message);
  void warn(String message) => add('WARN', message);
  void error(String message) => add('ERR', message);

  String exportText() => _entries.join('\n');

  void clear() => _entries.clear();
}
