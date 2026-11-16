import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../core/models/media_key.dart';
import '../../core/platform/device_bridge.dart';
import '../details/details_sheet.dart';
import '../search/tmdb_client.dart';
import 'discovery_models.dart';

class DiscoveryTab extends ConsumerStatefulWidget {
  const DiscoveryTab({super.key});

  @override
  ConsumerState<DiscoveryTab> createState() => _DiscoveryTabState();
}

class _DiscoveryTabState extends ConsumerState<DiscoveryTab> {
  final _promptController = TextEditingController();
  EveningPreset? _selectedPreset;
  MediaType? _typeFilter;
  bool _autoLoadedOnce = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _runPick({bool different = false}) async {
    _autoLoadedOnce = false;
    await ref.read(appControllerProvider.notifier).runDiscovery(
          DiscoveryRequest(
            prompt: _promptController.text,
            preset: _selectedPreset,
            mediaTypeFilter: _typeFilter,
            different: different,
          ),
        );
  }

  Future<void> _voicePrompt() async {
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
      _promptController.text = spoken;
      await _runPick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final s = state.strings;

    // Single auto-fetch when the visible batch has been completely triaged.
    if (!_autoLoadedOnce &&
        !state.isPicking &&
        state.recommendations.isEmpty &&
        state.recentShownIds.isNotEmpty &&
        state.tmdbKey.isNotEmpty) {
      _autoLoadedOnce = true;
      Future.microtask(() {
        if (!mounted) return;
        ref.read(appControllerProvider.notifier).runDiscovery(
              DiscoveryRequest(
                prompt: _promptController.text,
                preset: _selectedPreset,
                mediaTypeFilter: _typeFilter,
                different: true,
              ),
            );
      });
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _promptController,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _runPick(),
          decoration: InputDecoration(
            hintText: s.t('pick_prompt_hint'),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: s.t('voice_input_tooltip'),
                  icon: const Icon(Icons.mic_none),
                  onPressed: state.isPicking ? null : _voicePrompt,
                ),
                IconButton(
                  icon: const Icon(Icons.auto_awesome, color: StarFilmColors.limeFocus),
                  onPressed: state.isPicking ? null : () => _runPick(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final preset in EveningPreset.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_presetLabel(s, preset)),
                    selected: _selectedPreset == preset,
                    onSelected: (on) =>
                        setState(() => _selectedPreset = on ? preset : null),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<MediaType?>(
                segments: [
                  ButtonSegment(value: null, label: Text(s.t('type_all'))),
                  ButtonSegment(value: MediaType.movie, label: Text(s.t('type_movie'))),
                  ButtonSegment(value: MediaType.tv, label: Text(s.t('type_tv'))),
                ],
                selected: {_typeFilter},
                onSelectionChanged: (val) => setState(() => _typeFilter = val.first),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: state.isPicking || state.tmdbKey.isEmpty ? null : () => _runPick(),
            icon: state.isPicking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: StarFilmColors.onLime,
                    ),
                  )
                : const Icon(Icons.movie_filter),
            label: Text(s.t('pick_button')),
          ),
        ),
        if (state.recommendations.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: state.isPicking ? null : () => _runPick(different: true),
              icon: const Icon(Icons.refresh),
              label: Text(s.t('pick_more')),
            ),
          ),
        ],
        if (state.tmdbKey.isEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                s.t('pick_need_tmdb'),
                style: const TextStyle(color: StarFilmColors.warning),
              ),
            ),
          ),
        ] else if (state.lastDiscoveryError.isNotEmpty && !state.isPicking) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                s.t('pick_error', {'e': state.lastDiscoveryError}),
                style: const TextStyle(color: StarFilmColors.error),
              ),
            ),
          ),
        ],
        if (state.usedFallback && state.recommendations.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            s.t('pick_ai_fallback'),
            style: const TextStyle(color: StarFilmColors.textSecondary, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        for (final card in state.recommendations) _buildCard(context, card, state),
      ],
    );
  }

  Widget _buildCard(
    BuildContext context,
    RecommendationCard card,
    AppControllerState state,
  ) {
    final s = state.strings;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => MediaDetailsSheet.show(
          context,
          mediaType: card.mediaType,
          tmdbId: card.tmdbId,
          title: card.title,
          originalTitle: card.originalTitle,
          year: card.year,
          posterPath: card.posterPath,
          genreIds: card.genreIds,
          tmdbRating: card.tmdbRating,
          reason: card.reason,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: card.posterPath.isNotEmpty
                    ? Image.network(
                        TmdbClient.posterUrl(card.posterPath, size: 'w185'),
                        width: 82,
                        height: 122,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _fallbackBox(),
                      )
                    : _fallbackBox(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (card.year != null) '${card.year}',
                        if (card.runtimeMinutes != null)
                          s.t('runtime_min', {'n': card.runtimeMinutes}),
                        if (card.tmdbRating != null) 'TMDB ${card.tmdbRating!.toStringAsFixed(1)}',
                        card.mediaType == MediaType.tv ? s.t('type_tv') : s.t('type_movie'),
                      ].join(' • '),
                      style: const TextStyle(
                        color: StarFilmColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (card.reason.isNotEmpty && card.reason != 'TMDB') ...[
                      const SizedBox(height: 6),
                      Text(
                        card.reason,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _quickBtn(
                          label: s.t('quick_want'),
                          onTap: () => _mark(card, WatchStatus.watchlist),
                        ),
                        _quickBtn(
                          label: s.t('quick_seen'),
                          onTap: () => _mark(card, WatchStatus.watched),
                        ),
                        _quickBtn(
                          label: s.t('quick_no'),
                          onTap: () => _mark(card, WatchStatus.dismissed),
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
  }

  Widget _quickBtn({required String label, required VoidCallback onTap}) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  void _mark(RecommendationCard card, WatchStatus status) {
    ref.read(appControllerProvider.notifier).saveEntryAction(
          mediaType: card.mediaType,
          tmdbId: card.tmdbId,
          title: card.title,
          originalTitle: card.originalTitle,
          year: card.year,
          posterPath: card.posterPath,
          genreIds: card.genreIds,
          tmdbRating: card.tmdbRating,
          status: status,
        );
  }

  Widget _fallbackBox() {
    return Container(
      width: 82,
      height: 122,
      color: StarFilmColors.surfaceElevated,
      child: const Icon(Icons.movie, color: StarFilmColors.textSecondary),
    );
  }

  String _presetLabel(dynamic s, EveningPreset preset) {
    switch (preset) {
      case EveningPreset.friends:
        return s.t('preset_friends');
      case EveningPreset.family:
        return s.t('preset_family');
      case EveningPreset.under90:
        return s.t('preset_short');
      case EveningPreset.tense:
        return s.t('preset_tense');
      case EveningPreset.trueStory:
        return s.t('preset_true');
    }
  }
}
