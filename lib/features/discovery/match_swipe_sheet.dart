import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../details/details_sheet.dart';
import '../search/tmdb_client.dart';
import 'discovery_models.dart';

enum _SwipeStage { player1, handoff, player2, results }

class _SwipeDecision {
  const _SwipeDecision({required this.card, required this.liked});

  final RecommendationCard card;
  final bool liked;
}

/// Pass-and-play two-player match swipe deck on a single screen with animated
/// drag rotation, depth scaling, and mutual-like reveal.
class MatchSwipeSheet extends StatefulWidget {
  const MatchSwipeSheet({
    super.key,
    required this.cards,
    required this.strings,
  });

  final List<RecommendationCard> cards;
  final AppStrings strings;

  static Future<void> show(
    BuildContext context, {
    required List<RecommendationCard> cards,
    required AppStrings strings,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: StarFilmColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: MatchSwipeSheet(cards: cards, strings: strings),
      ),
    );
  }

  @override
  State<MatchSwipeSheet> createState() => _MatchSwipeSheetState();
}

class _MatchSwipeSheetState extends State<MatchSwipeSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  Animation<Offset>? _slideAnim;

  _SwipeStage _stage = _SwipeStage.player1;
  int _index = 0;
  Offset _dragOffset = Offset.zero;
  bool _animatingOut = false;

  final List<_SwipeDecision> _p1History = [];
  final List<_SwipeDecision> _p2History = [];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_slideAnim != null && mounted) {
          setState(() => _dragOffset = _slideAnim!.value);
        }
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  List<_SwipeDecision> get _currentHistory =>
      _stage == _SwipeStage.player1 ? _p1History : _p2History;

  List<RecommendationCard> get _mutualMatches {
    final p1Liked = {
      for (final d in _p1History)
        if (d.liked) d.card.mediaKey.value,
    };
    return [
      for (final d in _p2History)
        if (d.liked && p1Liked.contains(d.card.mediaKey.value)) d.card,
    ];
  }

  Future<void> _animateCardExit({required bool liked}) async {
    if (_animatingOut || _index >= widget.cards.length) return;
    _animatingOut = true;

    final targetX = liked ? 520.0 : -520.0;
    _slideAnim = Tween<Offset>(
      begin: _dragOffset,
      end: Offset(targetX, _dragOffset.dy + 28),
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    await _animController.forward(from: 0);
    if (!mounted) return;

    final currentCard = widget.cards[_index];
    setState(() {
      _currentHistory.add(_SwipeDecision(card: currentCard, liked: liked));
      _dragOffset = Offset.zero;
      _animatingOut = false;
      _index++;
      if (_index >= widget.cards.length) {
        _stage = _stage == _SwipeStage.player1
            ? _SwipeStage.handoff
            : _SwipeStage.results;
      }
    });
  }

  Future<void> _springBack() async {
    _slideAnim = Tween<Offset>(
      begin: _dragOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutBack));
    await _animController.forward(from: 0);
    if (mounted) {
      setState(() => _dragOffset = Offset.zero);
    }
  }

  void _undo() {
    if (_animatingOut || _currentHistory.isEmpty || _index <= 0) return;
    setState(() {
      _currentHistory.removeLast();
      _index--;
      _dragOffset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.t('match_swipe_title'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildStageBody(s)),
          ],
        ),
      ),
    );
  }

  Widget _buildStageBody(AppStrings s) {
    if (widget.cards.isEmpty) {
      return Center(child: Text(s.t('match_none_desc')));
    }

    switch (_stage) {
      case _SwipeStage.handoff:
        final likedCount = _p1History.where((d) => d.liked).length;
        return Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_horiz, size: 52, color: StarFilmColors.lime),
                  const SizedBox(height: 16),
                  Text(
                    s.t('match_hand_off'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.t('match_hand_off_desc', {
                      'liked': likedCount,
                      'total': widget.cards.length,
                    }),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: StarFilmColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => setState(() {
                      _stage = _SwipeStage.player2;
                      _index = 0;
                      _dragOffset = Offset.zero;
                    }),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(s.t('match_start_p2')),
                  ),
                ],
              ),
            ),
          ),
        );

      case _SwipeStage.results:
        final matches = _mutualMatches;
        if (matches.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sentiment_neutral, size: 52, color: StarFilmColors.textSecondary),
                const SizedBox(height: 12),
                Text(
                  s.t('match_none_title'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  s.t('match_none_desc'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: StarFilmColors.textSecondary),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.t('match_found_title', {'n': matches.length}),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: StarFilmColors.limeFocus,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (_, i) {
                  final card = matches[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: card.posterPath.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                TmdbClient.posterUrl(card.posterPath, size: 'w185'),
                                width: 44,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(Icons.movie),
                              ),
                            )
                          : const Icon(Icons.movie),
                      title: Text(card.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        [
                          if (card.year != null) '${card.year}',
                          if (card.tmdbRating != null && card.tmdbRating! > 0)
                            'TMDB ${card.tmdbRating!.toStringAsFixed(1)}',
                        ].join(' • '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
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
                    ),
                  );
                },
              ),
            ),
          ],
        );

      case _SwipeStage.player1:
      case _SwipeStage.player2:
        final playerNum = _stage == _SwipeStage.player1 ? 1 : 2;
        final current = widget.cards[_index];
        final next = _index + 1 < widget.cards.length ? widget.cards[_index + 1] : null;
        final dragFraction = (_dragOffset.dx.abs() / 140).clamp(0.0, 1.0);
        final likeAlpha = _dragOffset.dx > 12 ? dragFraction : 0.0;
        final skipAlpha = _dragOffset.dx < -12 ? dragFraction : 0.0;
        final nextScale = 0.94 + (0.06 * dragFraction);

        return Column(
          children: [
            Text(
              s.t('match_player_turn', {
                'n': playerNum,
                'cur': _index + 1,
                'total': widget.cards.length,
              }),
              style: const TextStyle(
                color: StarFilmColors.lime,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (next != null)
                    Transform.scale(
                      scale: nextScale,
                      child: Opacity(
                        opacity: 0.72 + (0.28 * dragFraction),
                        child: _SwipeCardFace(card: next, strings: s),
                      ),
                    ),
                  GestureDetector(
                    onPanUpdate: _animatingOut
                        ? null
                        : (details) => setState(() => _dragOffset += details.delta),
                    onPanEnd: _animatingOut
                        ? null
                        : (_) {
                            if (_dragOffset.dx > 105) {
                              _animateCardExit(liked: true);
                            } else if (_dragOffset.dx < -105) {
                              _animateCardExit(liked: false);
                            } else {
                              _springBack();
                            }
                          },
                    child: Transform.translate(
                      offset: _dragOffset,
                      child: Transform.rotate(
                        angle: (_dragOffset.dx / 1800).clamp(-0.28, 0.28),
                        child: Stack(
                          children: [
                            _SwipeCardFace(card: current, strings: s),
                            if (likeAlpha > 0)
                              Positioned(
                                top: 24,
                                left: 20,
                                child: Transform.rotate(
                                  angle: -0.22,
                                  child: Opacity(
                                    opacity: likeAlpha,
                                    child: _StampBadge(
                                      label: s.t('match_like'),
                                      color: StarFilmColors.limeFocus,
                                    ),
                                  ),
                                ),
                              ),
                            if (skipAlpha > 0)
                              Positioned(
                                top: 24,
                                right: 20,
                                child: Transform.rotate(
                                  angle: 0.22,
                                  child: Opacity(
                                    opacity: skipAlpha,
                                    child: _StampBadge(
                                      label: s.t('match_skip'),
                                      color: StarFilmColors.error,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: 'swipe_skip_$playerNum',
                  backgroundColor: StarFilmColors.surfaceElevated,
                  foregroundColor: StarFilmColors.error,
                  onPressed: () => _animateCardExit(liked: false),
                  child: const Icon(Icons.close, size: 28),
                ),
                IconButton.outlined(
                  onPressed: _currentHistory.isEmpty ? null : _undo,
                  icon: const Icon(Icons.replay),
                ),
                FloatingActionButton(
                  heroTag: 'swipe_like_$playerNum',
                  backgroundColor: StarFilmColors.lime,
                  foregroundColor: StarFilmColors.onLime,
                  onPressed: () => _animateCardExit(liked: true),
                  child: const Icon(Icons.favorite, size: 28),
                ),
              ],
            ),
          ],
        );
    }
  }
}

class _StampBadge extends StatelessWidget {
  const _StampBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: StarFilmColors.background.withValues(alpha: 0.72),
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 22,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _SwipeCardFace extends StatelessWidget {
  const _SwipeCardFace({required this.card, required this.strings});

  final RecommendationCard card;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: card.posterPath.isNotEmpty
                ? Image.network(
                    TmdbClient.posterUrl(card.posterPath, size: 'w500'),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(Icons.movie_outlined, size: 64),
                    ),
                  )
                : const Center(child: Icon(Icons.movie_outlined, size: 64)),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (card.year != null) '${card.year}',
                      if (card.tmdbRating != null && card.tmdbRating! > 0)
                        'TMDB ${card.tmdbRating!.toStringAsFixed(1)}',
                    ].join(' • '),
                    style: const TextStyle(color: StarFilmColors.lime, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        card.reason.isNotEmpty
                            ? card.reason
                            : card.originalTitle,
                        maxLines: math.max(3, 5),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: StarFilmColors.textSecondary, height: 1.35),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
