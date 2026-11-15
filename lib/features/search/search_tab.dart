import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../core/models/media_key.dart';
import '../details/details_sheet.dart';
import '../search/tmdb_client.dart';
import '../search/tmdb_matcher.dart';

class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  final _queryController = TextEditingController();
  List<TmdbSearchCandidate> _results = const [];
  bool _searching = false;
  bool _searched = false;
  String? _errorMessage;
  MediaType? _typeFilter;
  int? _selectedGenre;
  double _minRating = 0;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final state = ref.read(appControllerProvider);
    final raw = _queryController.text.trim();
    if (raw.isEmpty || state.tmdbKey.isEmpty) return;

    // Parse optional trailing year e.g. "Matrix 1999"
    int? yearHint;
    var query = raw;
    final match = RegExp(r'^(.*?)(?:\s+|\()((?:19|20)\d{2})\)?$').firstMatch(raw);
    if (match != null) {
      final candidateQuery = match.group(1)?.trim() ?? '';
      final parsedYear = int.tryParse(match.group(2) ?? '');
      if (candidateQuery.isNotEmpty && parsedYear != null) {
        query = candidateQuery;
        yearHint = parsedYear;
      }
    }

    // Smart language detection uk/ru/en
    var lang = state.activeProfile.preferences.contentLanguage;
    if (RegExp(r'^[A-Za-z0-9\s:,\-!&]+$').hasMatch(query)) {
      lang = 'en';
    } else if (RegExp(r'[іїєґ]', caseSensitive: false).hasMatch(query)) {
      lang = 'uk';
    } else if (RegExp(r'[ыэёъ]', caseSensitive: false).hasMatch(query)) {
      lang = 'ru';
    }

    setState(() {
      _searching = true;
      _searched = true;
      _errorMessage = null;
    });
    try {
      final items = await ref.read(appServicesProvider).tmdb.searchMulti(
            apiKey: state.tmdbKey,
            query: query,
            contentLanguage: lang,
            yearHint: yearHint,
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final s = state.strings;

    final filtered = _results.where((item) {
      if (_typeFilter != null && item.mediaType != _typeFilter) return false;
      if (_selectedGenre != null && !item.genreIds.contains(_selectedGenre)) return false;
      if (_minRating > 0 && item.voteAverage < _minRating) return false;
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: _queryController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: s.t('search_hint'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward, color: StarFilmColors.limeFocus),
                    onPressed: _search,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(s.t('type_all')),
                      selected: _typeFilter == null,
                      onSelected: (_) => setState(() => _typeFilter = null),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(s.t('type_movie')),
                      selected: _typeFilter == MediaType.movie,
                      onSelected: (_) => setState(() => _typeFilter = MediaType.movie),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(s.t('type_tv')),
                      selected: _typeFilter == MediaType.tv,
                      onSelected: (_) => setState(() => _typeFilter = MediaType.tv),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('7.0+'),
                      selected: _minRating >= 7.0,
                      onSelected: (on) => setState(() => _minRating = on ? 7.0 : 0),
                    ),
                    const SizedBox(width: 6),
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
                    child: Text(
                      _errorMessage ??
                          (state.tmdbKey.isEmpty
                              ? s.t('pick_need_tmdb')
                              : (_searched ? s.t('search_no_results') : s.t('search_empty'))),
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
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(10),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: item.posterPath.isNotEmpty
                              ? Image.network(
                                  TmdbClient.posterUrl(item.posterPath, size: 'w185'),
                                  width: 52,
                                  height: 78,
                                  fit: BoxFit.cover,
                                )
                              : const SizedBox(width: 52, height: 78, child: Icon(Icons.movie)),
                        ),
                        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            if (item.year != null) '${item.year}',
                            if (item.voteAverage > 0) 'TMDB ${item.voteAverage.toStringAsFixed(1)}',
                          ].join(' • '),
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: s.t('quick_want'),
                              icon: const Icon(Icons.bookmark_add_outlined),
                              onPressed: () => ref
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
                                    status: WatchStatus.watchlist,
                                  ),
                            ),
                            IconButton(
                              tooltip: s.t('quick_seen'),
                              icon: const Icon(Icons.check_circle_outline),
                              onPressed: () => ref
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
                                    status: WatchStatus.watched,
                                  ),
                            ),
                          ],
                        ),
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
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
