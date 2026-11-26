import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../../core/platform/device_bridge.dart';
import '../details/details_sheet.dart';
import '../players/mobile_players.dart';
import '../search/tmdb_client.dart';
import '../search/tmdb_matcher.dart';

enum _YearRangeFilter { all, y2020Plus, y2010s, y2000s, before2000 }

class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  final _queryController = TextEditingController();
  List<TmdbSearchCandidate> _results = const [];
  String _lastQuery = '';
  String _lastPhonetic = '';
  bool _searching = false;
  bool _searched = false;
  String? _errorMessage;
  MediaType? _typeFilter;
  int? _selectedGenre;
  double _minRating = 0;
  _YearRangeFilter _yearFilter = _YearRangeFilter.all;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _voiceSearch() async {
    final state = ref.read(appControllerProvider);
    final s = state.strings;
    final langTag =
        DeviceBridge.toSpeechLocaleTag(state.activeProfile.preferences.contentLanguage);
    final spoken = await DeviceBridge.startVoiceInput(
      languageTag: langTag,
      prompt: s.t('voice_input_tooltip'),
    );
    if (!mounted) return;
    if (spoken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.t('voice_unavailable'))),
      );
      return;
    }
    if (spoken.isNotEmpty) {
      _queryController.text = spoken;
      await _search();
    }
  }

  Future<void> _search() async {
    final state = ref.read(appControllerProvider);
    final raw = TmdbMatcher.cleanSearchQuery(_queryController.text);
    if (raw.isEmpty || state.tmdbKey.isEmpty) return;

    // Parse optional trailing year e.g. "Matrix 1999"
    int? yearHint;
    var query = raw;
    final match = RegExp(r'^(.*?)(?:\s+|\()((?:19|20)\d{2})\)?$').firstMatch(raw);
    if (match != null) {
      final candidateQuery =
          TmdbMatcher.cleanSearchQuery(match.group(1) ?? '');
      final parsedYear = int.tryParse(match.group(2) ?? '');
      if (candidateQuery.isNotEmpty && parsedYear != null) {
        query = candidateQuery;
        yearHint = parsedYear;
      }
    }

    // Always request titles/posters in the active profile's contentLanguage
    // (TMDB indexes both localized titles and original Latin titles).
    final lang = state.activeProfile.preferences.contentLanguage;
    final phonetic = TmdbMatcher.phoneticLatinQuery(query);

    setState(() {
      _searching = true;
      _searched = true;
      _errorMessage = null;
      _lastQuery = query;
      _lastPhonetic = phonetic;
    });
    try {
      final services = ref.read(appServicesProvider);
      final items = await services.tmdb.searchCatalog(
            apiKey: state.tmdbKey,
            query: query,
            contentLanguage: lang,
            yearHint: yearHint,
            kinopoisk: services.kinopoisk,
            kinopoiskApiKey: state.kinopoiskKey,
          );
      if (mounted) {
        setState(() {
          _results = items;
          _searching = false;
        });
      }
    } on TmdbHttpException catch (e) {
      if (mounted) {
        final s = ref.read(appControllerProvider).strings;
        setState(() {
          _results = const [];
          _searching = false;
          _errorMessage = e.statusCode == 401
              ? s.t('tmdb_error_401')
              : s.t('tmdb_error_http', {'msg': e.message});
        });
      }
    } catch (e) {
      if (mounted) {
        final s = ref.read(appControllerProvider).strings;
        setState(() {
          _results = const [];
          _searching = false;
          _errorMessage = s.t('tmdb_error_conn', {'e': '$e'});
        });
      }
    }
  }

  void _clearSearch() {
    _queryController.clear();
    setState(() {
      _results = const [];
      _lastQuery = '';
      _lastPhonetic = '';
      _searched = false;
      _errorMessage = null;
    });
  }

  void _resetFilters() {
    setState(() {
      _typeFilter = null;
      _selectedGenre = null;
      _minRating = 0;
      _yearFilter = _YearRangeFilter.all;
    });
  }

  bool _matchesYear(int? year) {
    if (_yearFilter == _YearRangeFilter.all) return true;
    if (year == null) return false;
    return switch (_yearFilter) {
      _YearRangeFilter.all => true,
      _YearRangeFilter.y2020Plus => year >= 2020,
      _YearRangeFilter.y2010s => year >= 2010 && year <= 2019,
      _YearRangeFilter.y2000s => year >= 2000 && year <= 2009,
      _YearRangeFilter.before2000 => year < 2000,
    };
  }

  String _yearLabel(dynamic s, _YearRangeFilter f) {
    return switch (f) {
      _YearRangeFilter.all => s.t('year_filter'),
      _YearRangeFilter.y2020Plus => s.t('year_2020_plus'),
      _YearRangeFilter.y2010s => s.t('year_2010s'),
      _YearRangeFilter.y2000s => s.t('year_2000s'),
      _YearRangeFilter.before2000 => s.t('year_before_2000'),
    };
  }

  Future<void> _quickWatch(TmdbSearchCandidate item) async {
    final state = ref.read(appControllerProvider);
    final target = PlayerLaunchPlanner.plan(
      player: state.preferredPlayer,
      mediaType: item.mediaType,
      title: item.title,
      originalTitle: item.originalTitle,
      year: item.year,
    );
    await Clipboard.setData(ClipboardData(text: target.clipboardText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.strings.t('copied_title', {'title': target.clipboardText})),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    await MobilePlayerLauncher.launch(target);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final s = state.strings;
    final libraryByKey = <String, LibraryEntry>{
      for (final e in state.entries) e.keyString: e,
    };

    final filtered = _results.where((item) {
      if (_typeFilter != null && item.mediaType != _typeFilter) return false;
      if (_selectedGenre != null && !item.genreIds.contains(_selectedGenre)) return false;
      if (_minRating > 0 && item.voteAverage < _minRating) return false;
      if (!_matchesYear(item.year)) return false;
      return true;
    }).toList();

    final hasPhonetic = _lastPhonetic.isNotEmpty &&
        _lastPhonetic.toLowerCase() != _lastQuery.toLowerCase();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _queryController,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: s.t('search_hint'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_queryController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _clearSearch,
                        ),
                      IconButton(
                        tooltip: s.t('voice_input_tooltip'),
                        icon: const Icon(Icons.mic_none),
                        onPressed: _voiceSearch,
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward, color: StarFilmColors.limeFocus),
                        onPressed: _search,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: Text(s.t('type_all')),
                    selected: _typeFilter == null,
                    onSelected: (_) => setState(() => _typeFilter = null),
                  ),
                  ChoiceChip(
                    label: Text(s.t('type_movie')),
                    selected: _typeFilter == MediaType.movie,
                    onSelected: (_) => setState(() => _typeFilter = MediaType.movie),
                  ),
                  ChoiceChip(
                    label: Text(s.t('type_tv')),
                    selected: _typeFilter == MediaType.tv,
                    onSelected: (_) => setState(() => _typeFilter = MediaType.tv),
                  ),
                  ChoiceChip(
                    label: const Text('7.0+'),
                    selected: _minRating >= 7.0,
                    onSelected: (on) => setState(() => _minRating = on ? 7.0 : 0),
                  ),
                  PopupMenuButton<_YearRangeFilter>(
                    onSelected: (y) => setState(() => _yearFilter = y),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _YearRangeFilter.all,
                        child: Text(s.t('year_all')),
                      ),
                      PopupMenuItem(
                        value: _YearRangeFilter.y2020Plus,
                        child: Text(s.t('year_2020_plus')),
                      ),
                      PopupMenuItem(
                        value: _YearRangeFilter.y2010s,
                        child: Text(s.t('year_2010s')),
                      ),
                      PopupMenuItem(
                        value: _YearRangeFilter.y2000s,
                        child: Text(s.t('year_2000s')),
                      ),
                      PopupMenuItem(
                        value: _YearRangeFilter.before2000,
                        child: Text(s.t('year_before_2000')),
                      ),
                    ],
                    child: Chip(
                      backgroundColor: _yearFilter != _YearRangeFilter.all
                          ? StarFilmColors.lime.withValues(alpha: 0.2)
                          : null,
                      label: Text(_yearLabel(s, _yearFilter)),
                    ),
                  ),
                  PopupMenuButton<int?>(
                    onSelected: (g) => setState(() => _selectedGenre = g),
                    itemBuilder: (_) => [
                      PopupMenuItem<int?>(value: null, child: Text(s.t('all_genres'))),
                      for (final g in kStandardGenres)
                        PopupMenuItem<int?>(
                          value: g.id,
                          child: Text(g.labelFor(state.uiLanguage)),
                        ),
                    ],
                    child: Chip(
                      backgroundColor: _selectedGenre != null
                          ? StarFilmColors.lime.withValues(alpha: 0.2)
                          : null,
                      label: Text(
                        _selectedGenre == null
                            ? s.t('genre')
                            : kStandardGenres
                                .firstWhere((g) => g.id == _selectedGenre)
                                .labelFor(state.uiLanguage),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_searching) const LinearProgressIndicator(color: StarFilmColors.lime),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _results.isNotEmpty && _errorMessage == null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                s.t('search_hidden_by_filters', {'n': _results.length}),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: StarFilmColors.textSecondary),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _resetFilters,
                                icon: const Icon(Icons.filter_alt_off),
                                label: Text(s.t('reset_filters')),
                              ),
                            ],
                          )
                        : Text(
                            _errorMessage ??
                                (state.tmdbKey.isEmpty
                                    ? s.t('pick_need_tmdb')
                                    : (_searched
                                        ? s.t('search_no_results')
                                        : s.t('search_empty'))),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _errorMessage != null
                                  ? StarFilmColors.error
                                  : StarFilmColors.textSecondary,
                            ),
                          ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (_, index) {
                    final item = filtered[index];
                    final keyStr = MediaKey(item.mediaType, item.tmdbId).value;
                    final existing = libraryByKey[keyStr];
                    final isWant = existing?.status == WatchStatus.watchlist;
                    final isSeen = existing?.status == WatchStatus.watched;
                    final isExact = _lastQuery.isNotEmpty &&
                        TmdbMatcher.isExactTitleMatch(
                          query: _lastQuery,
                          item: item,
                          phoneticQuery: hasPhonetic ? _lastPhonetic : null,
                        );
                    final showOriginal = item.originalTitle.isNotEmpty &&
                        TmdbMatcher.normalizeTitle(item.originalTitle) !=
                            TmdbMatcher.normalizeTitle(item.title);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => MediaDetailsSheet.show(
                          context,
                          mediaType: item.mediaType,
                          tmdbId: item.tmdbId,
                          title: item.title,
                          originalTitle: item.originalTitle,
                          year: item.year,
                          posterPath: item.posterPath,
                          genreIds: item.genreIds,
                          tmdbRating: item.voteAverage,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: item.posterPath.isNotEmpty
                                    ? Image.network(
                                        TmdbClient.posterUrl(item.posterPath, size: 'w185'),
                                        width: 56,
                                        height: 84,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const SizedBox(
                                          width: 56,
                                          height: 84,
                                          child: Icon(Icons.movie_outlined),
                                        ),
                                      )
                                    : const SizedBox(
                                        width: 56,
                                        height: 84,
                                        child: Icon(Icons.movie_outlined),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                        if (isExact)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: StarFilmColors.lime.withValues(alpha: 0.16),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: StarFilmColors.lime.withValues(alpha: 0.5),
                                              ),
                                            ),
                                            child: Text(
                                              s.t('exact_match_badge'),
                                              style: const TextStyle(
                                                color: StarFilmColors.lime,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (showOriginal) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.originalTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: StarFilmColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        if (item.year != null) '${item.year}',
                                        item.mediaType == MediaType.tv
                                            ? s.t('type_tv')
                                            : s.t('type_movie'),
                                        if (item.voteAverage > 0)
                                          'TMDB ${item.voteAverage.toStringAsFixed(1)}',
                                        if (existing?.userRating != null)
                                          '★ ${existing!.userRating}/10',
                                      ].join(' • '),
                                      style: const TextStyle(
                                        color: StarFilmColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _statusBtn(
                                          active: isWant,
                                          icon: isWant
                                              ? Icons.bookmark_added
                                              : Icons.bookmark_add_outlined,
                                          label: s.t('quick_want'),
                                          onTap: () => ref
                                              .read(appControllerProvider.notifier)
                                              .saveEntryAction(
                                                mediaType: item.mediaType,
                                                tmdbId: item.tmdbId,
                                                title: item.title,
                                                originalTitle: item.originalTitle,
                                                year: item.year,
                                                posterPath: item.posterPath,
                                                genreIds: item.genreIds,
                                                tmdbRating: item.voteAverage,
                                                status: isWant
                                                    ? WatchStatus.none
                                                    : WatchStatus.watchlist,
                                              ),
                                        ),
                                        _statusBtn(
                                          active: isSeen,
                                          icon: isSeen
                                              ? Icons.check_circle
                                              : Icons.check_circle_outline,
                                          label: s.t('quick_seen'),
                                          onTap: () => ref
                                              .read(appControllerProvider.notifier)
                                              .saveEntryAction(
                                                mediaType: item.mediaType,
                                                tmdbId: item.tmdbId,
                                                title: item.title,
                                                originalTitle: item.originalTitle,
                                                year: item.year,
                                                posterPath: item.posterPath,
                                                genreIds: item.genreIds,
                                                tmdbRating: item.voteAverage,
                                                status: isSeen
                                                    ? WatchStatus.none
                                                    : WatchStatus.watched,
                                              ),
                                        ),
                                        _statusBtn(
                                          active: false,
                                          icon: Icons.play_circle_outline,
                                          label: s.t('quick_watch'),
                                          onTap: () => _quickWatch(item),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _statusBtn({
    required bool active,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final borderColor = active ? StarFilmColors.lime : StarFilmColors.border;
    final fgColor = active ? StarFilmColors.lime : StarFilmColors.textPrimary;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        side: BorderSide(color: borderColor),
        backgroundColor:
            active ? StarFilmColors.lime.withValues(alpha: 0.14) : null,
        foregroundColor: fgColor,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
