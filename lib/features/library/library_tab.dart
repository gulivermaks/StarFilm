import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../core/models/media_key.dart';
import '../details/details_sheet.dart';
import '../search/tmdb_client.dart';
import 'backup_codec.dart';

enum _LibrarySection { watchlist, watching, watched, collections }

enum _LibrarySort { recent, rating, year, title }

class LibraryTab extends ConsumerStatefulWidget {
  const LibraryTab({super.key});

  @override
  ConsumerState<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<LibraryTab> {
  _LibrarySection _section = _LibrarySection.watchlist;
  _LibrarySort _sort = _LibrarySort.recent;
  String _searchQuery = '';
  MediaType? _typeFilter;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final s = state.strings;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _tabChip(_LibrarySection.watchlist, s.t('status_watchlist')),
                    const SizedBox(width: 8),
                    _tabChip(_LibrarySection.watching, s.t('status_watching')),
                    const SizedBox(width: 8),
                    _tabChip(_LibrarySection.watched, s.t('status_watched')),
                    const SizedBox(width: 8),
                    _tabChip(_LibrarySection.collections, s.t('collections')),
                  ],
                ),
              ),
              if (_section != _LibrarySection.collections) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                        decoration: InputDecoration(
                          hintText: s.t('library_search_hint'),
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<_LibrarySort>(
                      icon: const Icon(Icons.sort),
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: _LibrarySort.recent, child: Text('За датою')),
                        PopupMenuItem(value: _LibrarySort.rating, child: Text('За оцінкою')),
                        PopupMenuItem(value: _LibrarySort.year, child: Text('За роком')),
                        PopupMenuItem(value: _LibrarySort.title, child: Text('За назвою')),
                      ],
                    ),
                    PopupMenuButton<MediaType?>(
                      icon: const Icon(Icons.filter_list),
                      onSelected: (v) => setState(() => _typeFilter = v),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: null, child: Text(s.t('type_all'))),
                        PopupMenuItem(value: MediaType.movie, child: Text(s.t('type_movie'))),
                        PopupMenuItem(value: MediaType.tv, child: Text(s.t('type_tv'))),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _section == _LibrarySection.collections
              ? _buildCollectionsView(context, state)
              : _buildEntriesList(context, state),
        ),
      ],
    );
  }

  Widget _tabChip(_LibrarySection section, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _section == section,
      onSelected: (_) => setState(() => _section = section),
    );
  }

  Widget _buildEntriesList(BuildContext context, AppControllerState state) {
    final s = state.strings;
    final targetStatus = switch (_section) {
      _LibrarySection.watchlist => WatchStatus.watchlist,
      _LibrarySection.watching => WatchStatus.watching,
      _LibrarySection.watched => WatchStatus.watched,
      _LibrarySection.collections => WatchStatus.none,
    };

    final items = state.entries.where((e) {
      if (e.status != targetStatus) return false;
      if (_typeFilter != null && e.mediaType != _typeFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final haystack =
            '${e.title} ${e.originalTitle} ${e.year ?? ''}'.toLowerCase();
        if (!haystack.contains(_searchQuery)) return false;
      }
      return true;
    }).toList();

    items.sort((a, b) {
      switch (_sort) {
        case _LibrarySort.recent:
          return b.clientUpdatedAt.compareTo(a.clientUpdatedAt);
        case _LibrarySort.rating:
          return (b.userRating ?? 0).compareTo(a.userRating ?? 0);
        case _LibrarySort.year:
          return (b.year ?? 0).compareTo(a.year ?? 0);
        case _LibrarySort.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
    });

    if (items.isEmpty) {
      return Center(
        child: Text(
          s.t('library_empty'),
          style: const TextStyle(color: StarFilmColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, idx) {
        final entry = items[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            contentPadding: const EdgeInsets.all(10),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: entry.posterPath.isNotEmpty
                  ? Image.network(
                      TmdbClient.posterUrl(entry.posterPath, size: 'w185'),
                      width: 50,
                      height: 75,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(width: 50, height: 75, child: Icon(Icons.movie)),
                    )
                  : const SizedBox(width: 50, height: 75, child: Icon(Icons.movie)),
            ),
            title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              [
                if (entry.year != null) '${entry.year}',
                if (entry.userRating != null) '★ ${entry.userRating}/10',
                entry.mediaType == MediaType.tv ? s.t('type_tv') : s.t('type_movie'),
              ].join(' • '),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: StarFilmColors.textSecondary),
              onPressed: () =>
                  ref.read(appControllerProvider.notifier).removeEntry(entry.mediaKey),
            ),
            onTap: () => MediaDetailsSheet.show(
              context,
              mediaType: entry.mediaType,
              tmdbId: entry.tmdbId,
              title: entry.title,
              originalTitle: entry.originalTitle,
              year: entry.year,
              posterPath: entry.posterPath,
              genreIds: entry.genreIds,
              tmdbRating: entry.tmdbRating,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollectionsView(BuildContext context, AppControllerState state) {
    final s = state.strings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: () => _promptNewCollection(context, s.t('new_collection')),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: Text(s.t('new_collection')),
        ),
        const SizedBox(height: 16),
        if (state.collections.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text(
                s.t('library_empty'),
                style: const TextStyle(color: StarFilmColors.textSecondary),
              ),
            ),
          )
        else
          for (final UserCollection col in state.collections)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const Icon(Icons.folder_special_outlined, color: StarFilmColors.lime),
                title: Text(col.title),
                subtitle: Text('${col.mediaKeys.length}'),
              ),
            ),
      ],
    );
  }

  Future<void> _promptNewCollection(BuildContext context, String title) async {
    final ctrl = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarFilmColors.surface,
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
    if (created != null && created.trim().isNotEmpty) {
      await ref.read(appControllerProvider.notifier).createCollection(created);
    }
  }
}
