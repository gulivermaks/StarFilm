/// Parses and compares StarFilm/StarTV two-component hundredths versions
/// such as `0.6`, `0.61`, `0.69`, `0.70`, `0.99`, `1.00`, `1.01`.
class VersionComparator {
  const VersionComparator._();

  /// Normalizes a version string (with optional `v` prefix) into comparable integer
  /// hundredths (`major * 100 + hundredths`).
  ///
  /// Single-digit fractional parts are treated as tenths (`0.6` -> `60`, `0.7` -> `70`)
  /// so `0.70` and `0.7` both compare greater than `0.69`.
  static int? parseToCode(String raw) {
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
      cleaned = cleaned.substring(1).trim();
    }
    final plusIndex = cleaned.indexOf('+');
    if (plusIndex >= 0) {
      cleaned = cleaned.substring(0, plusIndex);
    }
    final dashIndex = cleaned.indexOf('-');
    if (dashIndex >= 0) {
      cleaned = cleaned.substring(0, dashIndex);
    }

    final parts = cleaned.split('.');
    if (parts.isEmpty || parts.length > 3) return null;

    final major = int.tryParse(parts[0]);
    if (major == null || major < 0) return null;

    if (parts.length == 1) {
      return major * 100;
    }

    final fracStr = parts[1];
    if (fracStr.isEmpty) return null;
    final fracVal = int.tryParse(fracStr);
    if (fracVal == null || fracVal < 0) return null;

    final hundredths = fracStr.length == 1 ? fracVal * 10 : fracVal;
    if (parts.length == 2) {
      return major * 100 + hundredths;
    }

    // Optional 3-part fallback (e.g., 1.02.3 -> 10203 scaled if needed)
    final patch = int.tryParse(parts[2]);
    if (patch == null || patch < 0) return null;
    return major * 100 + hundredths + patch;
  }

  /// Formats an integer versionCode (`>= 1`) into `major.hundredths` (`0.01`, `0.70`, `1.00`).
  static String formatFromCode(int code) {
    final safeCode = code < 0 ? 0 : code;
    final major = safeCode ~/ 100;
    final hundredths = safeCode % 100;
    return '$major.${hundredths.toString().padLeft(2, '0')}';
  }

  /// Returns negative if `a < b`, 0 if equal, positive if `a > b`.
  static int compare(String a, String b) {
    final codeA = parseToCode(a);
    final codeB = parseToCode(b);
    if (codeA != null && codeB != null) {
      return codeA.compareTo(codeB);
    }
    return a.compareTo(b);
  }

  static bool isNewer({required String candidate, required String current}) {
    return compare(candidate, current) > 0;
  }
}
