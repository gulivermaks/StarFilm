import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../core/models/media_key.dart';
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

    return Padding(
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
          // Personal rating 1..10
          Text(s.t('your_rating'), style: const TextStyle(fontWeight: FontWeight.w600)),
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
                      onSelected: (_) {
                        ref.read(appControllerProvider.notifier).saveEntryAction(
                              mediaType: widget.mediaType,
                              tmdbId: widget.tmdbId,
                              title: title,
                              originalTitle: originalTitle,
                              year: year,
                              posterPath: posterPath,
                              genreIds: genreIds,
                              tmdbRating: rating,
                              runtimeMinutes: _details?.runtimeMinutes,
                              userRating: i,
                            );
                      },
                    ),
                  ),
              ],
            ),
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

  void _saveStatus(
    WatchStatus status,
    String title,
    String originalTitle,
    int? year,
    String posterPath,
    List<int> genreIds,
    double? tmdbRating,
  ) {
    ref.read(appControllerProvider.notifier).saveEntryAction(
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
        );
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
          const SnackBar(content: Text('Відправлено на StarTV')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка StarTV: $e')),
        );
      }
    }
  }
}
