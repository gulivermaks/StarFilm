import '../../core/models/media_key.dart';
import '../search/tmdb_client.dart';
import '../search/tmdb_matcher.dart';

class RatingImportRow {
  const RatingImportRow({
    required this.title,
    required this.rating,
    this.year,
    this.mediaType,
  });

  final String title;
  final int? year;
  final int rating;
  final MediaType? mediaType;
}

class ResolvedRatingImportItem {
  const ResolvedRatingImportItem({
    required this.candidate,
    required this.rating,
  });

  final TmdbSearchCandidate candidate;
  final int rating;
}

class RatingImportBatchResult {
  const RatingImportBatchResult({
    required this.resolved,
    required this.skippedTitles,
  });

  final List<ResolvedRatingImportItem> resolved;
  final List<String> skippedTitles;
}

/// Parses CSV/TSV or "Title (Year) - 8/10" rating lists matching StarTV RatingImport rules.
class RatingCsvParser {
  const RatingCsvParser._();

  static const int maxRows = 100;

  static final RegExp _dashRatingPattern =
      RegExp(r'^(.+?)\s+[—–-]\s*(10|[1-9])(?:/10)?\s*$');
  static final RegExp _trailingYearPattern = RegExp(r'^(.+?)\s*\((\d{4})\)\s*$');
  static final RegExp _validRating = RegExp(r'^(?:10|[1-9])$');
  static final RegExp _validYear = RegExp(r'^(?:18|19|20|21)\d{2}$');

  static List<RatingImportRow> parse(String rawText) {
    if (rawText.length > 120000) {
      throw const FormatException('CSV list is too large');
    }
    final lines = rawText.replaceAll('\ufeff', '').split(RegExp(r'\r?\n'));
    final rows = <RatingImportRow>[];

    var titleCol = -1;
    var yearCol = -1;
    var ratingCol = -1;
    var typeCol = -1;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final sep = line.contains('\t')
          ? '\t'
          : (line.contains(';') ? ';' : (line.contains(',') ? ',' : ''));

      final cols = sep.isNotEmpty ? splitCsvLine(line, sep) : <String>[];

      if (rows.isEmpty && titleCol < 0 && cols.isNotEmpty) {
        var foundTitle = -1;
        var foundYear = -1;
        var foundRating = -1;
        var foundType = -1;
        for (var i = 0; i < cols.length; i++) {
          final h = cols[i].trim().toLowerCase();
          if (const {'title', 'original title', 'name', 'название', 'назва', 'фильм', 'фільм'}
              .contains(h)) {
            foundTitle = i;
          } else if (const {'year', 'год', 'рік'}.contains(h)) {
            foundYear = i;
          } else if (const {'your rating', 'rating', 'оценка', 'оцінка', 'моя оценка'}
              .contains(h)) {
            foundRating = i;
          } else if (const {'mediatype', 'title type', 'type', 'тип'}.contains(h)) {
            foundType = i;
          }
        }
        if (foundTitle >= 0 && foundRating >= 0) {
          titleCol = foundTitle;
          yearCol = foundYear;
          ratingCol = foundRating;
          typeCol = foundType;
          continue;
        }
      }

      String title;
      String ratingStr;
      var yearStr = '';
      var typeStr = '';

      if (cols.isEmpty) {
        final match = _dashRatingPattern.firstMatch(line);
        if (match == null) {
          throw const FormatException('Expected CSV/TSV columns (Title;Year;Rating)');
        }
        title = match.group(1)!;
        ratingStr = match.group(2)!;
      } else if (titleCol >= 0) {
        if (cols.length >= 2 && (titleCol >= cols.length || ratingCol >= cols.length)) {
          // Fallback for mixed separator rows (e.g., TSV row after semicolon CSV header)
          if (cols.length == 3) {
            title = cols[0];
            yearStr = cols[1];
            ratingStr = cols[2];
          } else if (cols.length == 2) {
            title = cols[0];
            ratingStr = cols[1];
          } else {
            throw const FormatException('Missing required CSV column');
          }
        } else if (titleCol >= cols.length || ratingCol >= cols.length) {
          throw const FormatException('Missing required CSV column');
        } else {
          title = cols[titleCol];
          ratingStr = cols[ratingCol];
          if (yearCol >= 0 && yearCol < cols.length) yearStr = cols[yearCol];
          if (typeCol >= 0 && typeCol < cols.length) typeStr = cols[typeCol];
        }
      } else if (cols.length >= 4) {
        typeStr = cols[0];
        title = cols[1];
        yearStr = cols[2];
        ratingStr = cols[3];
      } else if (cols.length == 3) {
        title = cols[0];
        yearStr = cols[1];
        ratingStr = cols[2];
      } else if (cols.length == 2) {
        title = cols[0];
        ratingStr = cols[1];
      } else {
        throw const FormatException('Expected CSV/TSV columns (Title;Year;Rating)');
      }

      final yearMatch = _trailingYearPattern.firstMatch(title.trim());
      if (yearMatch != null) {
        title = yearMatch.group(1)!;
        if (yearStr.trim().isEmpty) yearStr = yearMatch.group(2)!;
      }

      title = title.trim();
      yearStr = yearStr.trim();
      ratingStr = ratingStr.trim().replaceFirst(RegExp(r'(?:/10|[.,]0)$'), '');

      if (title.isEmpty ||
          title.length > 300 ||
          !_validRating.hasMatch(ratingStr) ||
          (yearStr.isNotEmpty && !_validYear.hasMatch(yearStr))) {
        throw FormatException('Invalid row: $line');
      }

      final normalizedType = typeStr.trim().toLowerCase();
      MediaType? mediaType;
      if (const {'tv', 'series', 'tv series', 'tv mini series', 'show', 'сериал', 'серіал'}
          .contains(normalizedType)) {
        mediaType = MediaType.tv;
      } else if (const {'movie', 'film', 'фильм', 'фільм'}.contains(normalizedType)) {
        mediaType = MediaType.movie;
      } else if (normalizedType.isNotEmpty) {
        throw FormatException('Unsupported type "$typeStr" (use movie or tv)');
      }

      rows.add(
        RatingImportRow(
          title: title,
          year: yearStr.isEmpty ? null : int.parse(yearStr),
          rating: int.parse(ratingStr),
          mediaType: mediaType,
        ),
      );
      if (rows.length > maxRows) {
        throw const FormatException('Maximum 100 rows per import batch');
      }
    }

    if (rows.isEmpty) {
      throw const FormatException('Empty rating list');
    }
    return rows;
  }

  static List<String> splitCsvLine(String line, String sep) {
    final out = <String>[];
    final buf = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == sep && !quoted) {
        out.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    if (quoted) {
      throw const FormatException('Unclosed CSV quote');
    }
    out.add(buf.toString().trim());
    return out;
  }

  static String detectSearchLanguage(String title) {
    if (RegExp(r'[іїєґІЇЄҐ]').hasMatch(title)) return 'uk';
    if (RegExp(r'[А-Яа-яЁё]').hasMatch(title)) return 'ru';
    return 'en';
  }
}

class RatingCsvImporter {
  const RatingCsvImporter(this._tmdb);

  final TmdbClient _tmdb;

  Future<RatingImportBatchResult> resolveRows({
    required String tmdbApiKey,
    required List<RatingImportRow> rows,
    void Function(int done, int total)? onProgress,
  }) async {
    final resolved = <ResolvedRatingImportItem>[];
    final skipped = <String>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      onProgress?.call(i, rows.length);

      final lang = RatingCsvParser.detectSearchLanguage(row.title);
      List<TmdbSearchCandidate> candidates;
      try {
        if (row.mediaType != null) {
          candidates = await _tmdb.searchTyped(
            apiKey: tmdbApiKey,
            mediaType: row.mediaType!,
            query: row.title,
            contentLanguage: lang,
            year: row.year,
          );
        } else {
          candidates = await _tmdb.searchMulti(
            apiKey: tmdbApiKey,
            query: row.title,
            contentLanguage: lang,
            yearHint: row.year,
          );
        }
      } catch (_) {
        candidates = const [];
      }

      TmdbSearchCandidate? best;
      for (final c in candidates) {
        if (!TmdbMatcher.yearsCompatible(row.year, c.year)) continue;
        if (TmdbMatcher.titlesMatch(row.title, c.title) ||
            TmdbMatcher.titlesMatch(row.title, c.originalTitle)) {
          best = c;
          break;
        }
      }
      best ??= candidates.isNotEmpty && TmdbMatcher.yearsCompatible(row.year, candidates.first.year)
          ? candidates.first
          : null;

      if (best != null) {
        resolved.add(ResolvedRatingImportItem(candidate: best, rating: row.rating));
      } else {
        skipped.add(row.year != null ? '${row.title} (${row.year})' : row.title);
      }
    }
    onProgress?.call(rows.length, rows.length);

    return RatingImportBatchResult(resolved: resolved, skippedTitles: skipped);
  }
}
