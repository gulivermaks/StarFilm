import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../library/backup_codec.dart';
import '../players/mobile_players.dart';
import '../search/tmdb_client.dart';

class MediaDetailsSheet extends ConsumerStatefulWidget {
  const MediaDetailsSheet({
    super.key,
    required this.mediaType,
    required this.tmdbId,
    required this.initialTitle,
    this.initialOriginalTitle = '',
    this.initialYear,
    this.initialPosterPath = '',
    this.initialGenreIds = const [],
    this.initialRating,
    this.reason = '',
  });

  final MediaType mediaType;
  final int tmdbId;
  final String initialTitle;
  final String initialOriginalTitle;
  final int? initialYear;
  final String initialPosterPath;
  final List<int> initialGenreIds;
  final double? initialRating;
  final String reason;

  static Future<void> show(
    BuildContext context, {
    required MediaType mediaType,
    required int tmdbId,
    required String title,
    String originalTitle = '',
    int? year,
    String posterPath = '',
    List<int> genreIds = const [],
    double? tmdbRating,
    String reason = '',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: StarFilmColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        builder: (_, controller) => MediaDetailsSheet(
          mediaType: mediaType,
          tmdbId: tmdbId,
          initialTitle: title,
          initialOriginalTitle: originalTitle,
          initialYear: year,
          initialPosterPath: posterPath,
          initialGenreIds: genreIds,
          initialRating: tmdbRating,
          reason: reason,
        ),
      ),
    );
  }

  @override
  ConsumerState<MediaDetailsSheet> createState() => _MediaDetailsSheetState();
}

class _MediaDetailsSheetState extends ConsumerState<MediaDetailsSheet> {
  MediaDetails? _details;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final appState = ref.read(appControllerProvider);
    final key = appState.tmdbKey;
    if (key.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final d = await ref.read(appServicesProvider).tmdb.fetchDetails(
            apiKey: key,
            mediaType: widget.mediaType,
            tmdbId: widget.tmdbId,
            contentLanguage: appState.activeProfile.preferences.contentLanguage,
          );
      if (mounted) {
        setState(() {
          _details = d;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final s = state.strings;
    final key = MediaKey(widget.mediaType, widget.tmdbId);
    final existing = state.entries.where((e) => e.mediaKey == key).firstOrNull;

    final title = _details?.title.isNotEmpty == true ? _details!.title : widget.initialTitle;
    final originalTitle = _details?.originalTitle.isNotEmpty == true
        ? _details!.originalTitle
        : widget.initialOriginalTitle;
    final year = _details?.year ?? widget.initialYear;
    final posterPath = _details?.posterPath.isNotEmpty == true
        ? _details!.posterPath
        : widget.initialPosterPath;
    final rating = _details?.tmdbRating ?? widget.initialRating;
    final genreIds =
        _details?.genreIds.isNotEmpty == true ? _details!.genreIds : widget.initialGenreIds;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: ListView(
          children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: StarFilmColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: posterPath.isNotEmpty
                    ? Image.network(
                        TmdbClient.posterUrl(posterPath, size: 'w342'),
                        width: 110,
                        height: 165,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _posterFallback(),
                      )
                    : _posterFallback(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (originalTitle.isNotEmpty && originalTitle != title) ...[
                      const SizedBox(height: 4),
                      Text(
                        originalTitle,
                        style: const TextStyle(color: StarFilmColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (year != null) _chip('$year'),
                        if (rating != null && rating > 0)
                          _chip('TMDB ${rating.toStringAsFixed(1)}'),
                        if (_details?.runtimeMinutes != null)
                          _chip(s.t('runtime_min', {'n': _details!.runtimeMinutes})),
                        if (widget.mediaType == MediaType.tv &&
                            _details?.numberOfSeasons != null)
                          _chip(s.t('seasons_count', {'n': _details!.numberOfSeasons})),
                      ],
                    ),
                    if (_details?.countries.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(
                        _details!.countries.join(', '),
                        style: const TextStyle(
                          color: StarFilmColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (widget.reason.isNotEmpty && widget.reason != 'TMDB') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: StarFilmColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StarFilmColors.lime.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.t('why_recommend'),
                    style: const TextStyle(
                      color: StarFilmColors.limeFocus,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(widget.reason),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Status actions (no episode tracking!)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusChip(
                label: s.t('status_watchlist'),
                selected: existing?.status == WatchStatus.watchlist,
                onTap: () => _saveStatus(
                  WatchStatus.watchlist,
                  title,
                  originalTitle,
                  year,
                  posterPath,
                  genreIds,
                  rating,
                ),
              ),
              _statusChip(
                label: s.t('status_watching'),
                selected: existing?.status == WatchStatus.watching,
                onTap: () => _saveStatus(
                  WatchStatus.watching,
                  title,
                  originalTitle,
                  year,
                  posterPath,
                  genreIds,
                  rating,
                ),
              ),
              _statusChip(
                label: s.t('status_watched'),
                selected: existing?.status == WatchStatus.watched,
                onTap: () => _saveStatus(
                  WatchStatus.watched,
                  title,
                  originalTitle,
                  year,
                  posterPath,
                  genreIds,
                  rating,
                ),
              ),
              _statusChip(
                label: s.t('status_dismissed'),
                selected: existing?.status == WatchStatus.dismissed,
                onTap: () => _saveStatus(
                  WatchStatus.dismissed,
                  title,
                  originalTitle,
                  year,
                  posterPath,
                  genreIds,
                  rating,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Personal rating 1..10 & clear toggle
          Row(
            children: [
              Text(s.t('your_rating'), style: const TextStyle(fontWeight: FontWeight.w600)),
              if (existing?.userRating != null) ...[
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _saveAction(
                    title: title,
                    originalTitle: originalTitle,
                    year: year,
                    posterPath: posterPath,
                    genreIds: genreIds,
                    tmdbRating: rating,
                    clearRating: true,
                  ),
                  child: Text(s.t('clear_rating'), style: const TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 1; i <= 10; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('$i'),
                      selected: existing?.userRating == i,
                      onSelected: (_) => _saveAction(
                        title: title,
                        originalTitle: originalTitle,
                        year: year,
                        posterPath: posterPath,
                        genreIds: genreIds,
                        tmdbRating: rating,
                        userRating: existing?.userRating == i ? null : i,
                        clearRating: existing?.userRating == i,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                avatar: Icon(
                  existing?.sentiment == Sentiment.liked
                      ? Icons.thumb_up
                      : Icons.thumb_up_outlined,
                  size: 16,
                ),
                label: Text(s.t('like')),
                selected: existing?.sentiment == Sentiment.liked,
                onSelected: (_) {
                  final next = existing?.sentiment == Sentiment.liked
                      ? Sentiment.neutral
                      : Sentiment.liked;
                  _saveAction(
                    title: title,
                    originalTitle: originalTitle,
                    year: year,
                    posterPath: posterPath,
                    genreIds: genreIds,
                    tmdbRating: rating,
                    status: (next == Sentiment.liked &&
                            existing?.status == WatchStatus.dismissed)
                        ? WatchStatus.none
                        : null,
                    sentiment: next,
                  );
                },
              ),
              ChoiceChip(
                avatar: Icon(
                  existing?.sentiment == Sentiment.disliked
                      ? Icons.thumb_down
                      : Icons.thumb_down_outlined,
                  size: 16,
                ),
                label: Text(s.t('dislike')),
                selected: existing?.sentiment == Sentiment.disliked,
                onSelected: (_) {
                  final next = existing?.sentiment == Sentiment.disliked
                      ? Sentiment.neutral
                      : Sentiment.disliked;
                  _saveAction(
                    title: title,
                    originalTitle: originalTitle,
                    year: year,
                    posterPath: posterPath,
                    genreIds: genreIds,
                    tmdbRating: rating,
                    sentiment: next,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Watch buttons
          Row(
            children: [
              if (state.activeTv != null) ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _watchOnTv(title, originalTitle, year),
                    icon: const Icon(Icons.tv),
                    label: Text(s.t('watch_on_tv')),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: state.activeTv == null
                    ? FilledButton.icon(
                        onPressed: () => _watchOnPhone(title, originalTitle, year),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(s.t('watch_on_phone')),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _watchOnPhone(title, originalTitle, year),
                        icon: const Icon(Icons.smartphone),
                        label: Text(s.t('watch_on_phone')),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              final uri = PlayerLaunchPlanner.youtubeTrailerUri(
                _details?.youtubeTrailerKey,
                title: title,
                year: year,
              );
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.ondemand_video),
            label: Text(s.t('trailer')),
          ),
          const SizedBox(height: 14),
          // Collections selector
          Text(s.t('collections'), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final col in state.collections)
                FilterChip(
                  label: Text(col.title),
                  selected: col.mediaKeys.contains(key.value),
                  onSelected: (_) => _toggleCollectionMembership(
                    col,
                    existing: existing,
                    mediaKey: key,
                    title: title,
                    originalTitle: originalTitle,
                    year: year,
                    posterPath: posterPath,
                    genreIds: genreIds,
                    tmdbRating: rating,
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: Text(s.t('new_collection')),
                onPressed: () => _createCollectionAndAdd(
                  context,
                  s.t('new_collection'),
                  s.t('cancel'),
                  s.t('ok'),
                  s.t('collection_name'),
                  existing: existing,
                  mediaKey: key,
                  title: title,
                  originalTitle: originalTitle,
                  year: year,
                  posterPath: posterPath,
                  genreIds: genreIds,
                  tmdbRating: rating,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            if (_details?.genres.isNotEmpty == true) ...[
              Text(
                _details!.genres.join(' • '),
                style: const TextStyle(color: StarFilmColors.lime),
              ),
              const SizedBox(height: 8),
            ],
            if (_details?.overview.isNotEmpty == true)
              Text(_details!.overview, style: const TextStyle(height: 1.45)),
            if (_details?.directorsOrCreators.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(
                _details!.directorsOrCreators.join(', '),
                style: const TextStyle(color: StarFilmColors.textSecondary),
              ),
            ],
            if (_details?.cast.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                _details!.cast.join(', '),
                style: const TextStyle(color: StarFilmColors.textSecondary, fontSize: 13),
              ),
            ],
          ],
        ],
      ),
    ),
    );
  }

  Widget _posterFallback() {
    return Container(
      width: 110,
      height: 165,
      color: StarFilmColors.surfaceElevated,
      child: const Icon(Icons.movie_outlined, size: 40, color: StarFilmColors.textSecondary),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: StarFilmColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StarFilmColors.border),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _statusChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  Future<void> _saveAction({
    required String title,
    required String originalTitle,
    required int? year,
    required String posterPath,
    required List<int> genreIds,
    required double? tmdbRating,
    WatchStatus? status,
    int? userRating,
    bool clearRating = false,
    Sentiment? sentiment,
  }) {
    return ref.read(appControllerProvider.notifier).saveEntryAction(
          mediaType: widget.mediaType,
          tmdbId: widget.tmdbId,
          title: title,
          originalTitle: originalTitle,
          year: year,
          posterPath: posterPath,
          genreIds: genreIds,
          tmdbRating: tmdbRating,
          runtimeMinutes: _details?.runtimeMinutes,
          status: status,
          userRating: userRating,
          clearRating: clearRating,
          sentiment: sentiment,
        );
  }

  void _saveStatus(
    WatchStatus status,
    String title,
    String originalTitle,
    int? year,
    String posterPath,
    List<int> genreIds,
    double? tmdbRating,
  ) {
    _saveAction(
      title: title,
      originalTitle: originalTitle,
      year: year,
      posterPath: posterPath,
      genreIds: genreIds,
      tmdbRating: tmdbRating,
      status: status,
    );
  }

  Future<void> _toggleCollectionMembership(
    UserCollection col, {
    required LibraryEntry? existing,
    required MediaKey mediaKey,
    required String title,
    required String originalTitle,
    required int? year,
    required String posterPath,
    required List<int> genreIds,
    required double? tmdbRating,
  }) async {
    if (existing == null && !col.mediaKeys.contains(mediaKey.value)) {
      await _saveAction(
        title: title,
        originalTitle: originalTitle,
        year: year,
        posterPath: posterPath,
        genreIds: genreIds,
        tmdbRating: tmdbRating,
        status: WatchStatus.none,
      );
    }
    await ref.read(appControllerProvider.notifier).toggleItemInCollection(col, mediaKey);
  }

  Future<void> _createCollectionAndAdd(
    BuildContext context,
    String dialogTitle,
    String cancelLabel,
    String okLabel,
    String hintLabel, {
    required LibraryEntry? existing,
    required MediaKey mediaKey,
    required String title,
    required String originalTitle,
    required int? year,
    required String posterPath,
    required List<int> genreIds,
    required double? tmdbRating,
  }) async {
    final ctrl = TextEditingController();
    final createdName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarFilmColors.surface,
        title: Text(dialogTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hintLabel),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(cancelLabel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    if (createdName == null || createdName.trim().isEmpty) return;
    final col =
        await ref.read(appControllerProvider.notifier).createCollection(createdName);
    if (col != null) {
      await _toggleCollectionMembership(
        col,
        existing: existing,
        mediaKey: mediaKey,
        title: title,
        originalTitle: originalTitle,
        year: year,
        posterPath: posterPath,
        genreIds: genreIds,
        tmdbRating: tmdbRating,
      );
    }
  }

  Future<void> _watchOnPhone(String title, String originalTitle, int? year) async {
    final state = ref.read(appControllerProvider);
    final player = state.preferredPlayer;
    final target = PlayerLaunchPlanner.plan(
      player: player,
      mediaType: widget.mediaType,
      title: title,
      originalTitle: originalTitle,
      year: year,
      imdbId: _details?.imdbId,
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

  Future<void> _watchOnTv(String title, String originalTitle, int? year) async {
    final s = ref.read(appControllerProvider).strings;
    try {
      await ref.read(appControllerProvider.notifier).launchOnTv(
            tmdbId: widget.tmdbId,
            mediaType: widget.mediaType,
            title: title,
            originalTitle: originalTitle,
            year: year,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('startv_sent'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('startv_error', {'e': '$e'}))),
        );
      }
    }
  }
}
