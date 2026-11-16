import 'dart:convert';
import 'dart:typed_data';

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

  static String decodeBytesWithFallback(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return _decodeWindows1251(bytes);
    }
  }

  static String _decodeWindows1251(Uint8List bytes) {
    const map128to191 = [
      0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
      0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
      0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
      0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
      0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
      0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
      0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
      0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
    ];
    final sb = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        sb.writeCharCode(b);
      } else if (b >= 0xC0) {
        sb.writeCharCode(0x0410 + (b - 0xC0));
      } else {
        sb.writeCharCode(map128to191[b - 0x80]);
      }
    }
    return sb.toString();
  }

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
    String? lockedSep;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final candidateSep = line.contains('\t')
          ? '\t'
          : (line.contains(';') ? ';' : (line.contains(',') ? ',' : ''));
      lockedSep ??= candidateSep.isNotEmpty ? candidateSep : null;
      final activeSep =
          (lockedSep != null && line.contains(lockedSep)) ? lockedSep : candidateSep;

      final cols = activeSep.isNotEmpty ? splitCsvLine(line, activeSep) : <String>[];

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
        // Guard against text lines with a comma like "One, Two - 8/10"
        final dashCheck = _dashRatingPattern.firstMatch(line);
        if (dashCheck != null && activeSep == ',') {
          title = dashCheck.group(1)!;
          ratingStr = dashCheck.group(2)!;
        } else {
          title = cols[0];
          ratingStr = cols[1];
        }
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
    String resultContentLanguage = 'uk',
    void Function(int done, int total)? onProgress,
  }) async {
    final resolved = <ResolvedRatingImportItem>[];
    final skipped = <String>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      onProgress?.call(i, rows.length);

      // Search in profile's contentLanguage first so titles/posters localize automatically
      // even for Latin queries like "The Matrix", with fallback to query script language.
      final queryLang = RatingCsvParser.detectSearchLanguage(row.title);
      List<TmdbSearchCandidate> candidates = await _searchWithRetry(
        tmdbApiKey: tmdbApiKey,
        row: row,
        contentLanguage: resultContentLanguage,
      );
      if (candidates.isEmpty && queryLang != resultContentLanguage) {
        candidates = await _searchWithRetry(
          tmdbApiKey: tmdbApiKey,
          row: row,
          contentLanguage: queryLang,
        );
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
      // Only fall back to candidates.first when year is explicitly provided and matches closely;
      // never guess an arbitrary title when year is missing and titles did not match.
      if (best == null &&
          row.year != null &&
          candidates.isNotEmpty &&
          TmdbMatcher.yearsCompatible(row.year, candidates.first.year)) {
        best = candidates.first;
      }

      if (best != null) {
        resolved.add(ResolvedRatingImportItem(candidate: best, rating: row.rating));
      } else {
        skipped.add(row.year != null ? '${row.title} (${row.year})' : row.title);
      }
    }
    onProgress?.call(rows.length, rows.length);

    return RatingImportBatchResult(resolved: resolved, skippedTitles: skipped);
  }

  Future<List<TmdbSearchCandidate>> _searchWithRetry({
    required String tmdbApiKey,
    required RatingImportRow row,
    required String contentLanguage,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (row.mediaType != null) {
          return await _tmdb.searchTyped(
            apiKey: tmdbApiKey,
            mediaType: row.mediaType!,
            query: row.title,
            contentLanguage: contentLanguage,
            year: row.year,
          );
        }
        return await _tmdb.searchMulti(
          apiKey: tmdbApiKey,
          query: row.title,
          contentLanguage: contentLanguage,
          yearHint: row.year,
        );
      } on TmdbHttpException catch (e) {
        if (e.statusCode == 429 && attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          continue;
        }
        return const [];
      } catch (_) {
        return const [];
      }
    }
    return const [];
  }
}
