import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/models/library_entry.dart';
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _tabChip(_LibrarySection.watchlist, s.t('status_watchlist')),
                  _tabChip(_LibrarySection.watching, s.t('status_watching')),
                  _tabChip(_LibrarySection.watched, s.t('status_watched')),
                  _tabChip(_LibrarySection.collections, s.t('collections')),
                ],
              ),
              if (_section != _LibrarySection.collections) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) =>
                            setState(() => _searchQuery = v.trim().toLowerCase()),
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
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: _LibrarySort.recent,
                          child: Text(s.t('sort_recent')),
                        ),
                        PopupMenuItem(
                          value: _LibrarySort.rating,
                          child: Text(s.t('sort_rating')),
                        ),
                        PopupMenuItem(
                          value: _LibrarySort.year,
                          child: Text(s.t('sort_year')),
                        ),
                        PopupMenuItem(
                          value: _LibrarySort.title,
                          child: Text(s.t('sort_title')),
                        ),
                      ],
                    ),
                    PopupMenuButton<MediaType?>(
                      icon: const Icon(Icons.filter_list),
                      onSelected: (v) => setState(() => _typeFilter = v),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: null, child: Text(s.t('type_all'))),
                        PopupMenuItem(
                            value: MediaType.movie, child: Text(s.t('type_movie'))),
                        PopupMenuItem(
                            value: MediaType.tv, child: Text(s.t('type_tv'))),
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

  Future<void> _removeWithUndo(
    BuildContext context,
    AppStrings s,
    LibraryEntry entry,
  ) async {
    final notifier = ref.read(appControllerProvider.notifier);
    await notifier.removeEntry(entry.mediaKey);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.t('entry_removed_undo', {'title': entry.title})),
        action: SnackBarAction(
          label: s.t('undo'),
          onPressed: () {
            notifier.restoreDeletedEntry(entry);
          },
        ),
      ),
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
              onPressed: () => _removeWithUndo(context, s, entry),
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
    final entriesByKey = <String, LibraryEntry>{
      for (final e in state.entries) e.keyString: e,
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: () => _createCollectionDialog(context, s),
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
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: const Icon(
                  Icons.folder_special_outlined,
                  color: StarFilmColors.lime,
                ),
                title: Text(col.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  s.t('collection_items_count', {'n': col.mediaKeys.length}),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'rename') {
                      await _renameCollectionDialog(context, s, col);
                    } else if (action == 'delete') {
                      await _confirmDeleteCollection(context, s, col);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'rename', child: Text(s.t('rename'))),
                    PopupMenuItem(value: 'delete', child: Text(s.t('delete'))),
                  ],
                ),
                children: [
                  if (col.mediaKeys.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          s.t('collection_empty'),
                          style: const TextStyle(color: StarFilmColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    for (final keyStr in col.mediaKeys)
                      _buildCollectionMemberTile(
                        context,
                        s,
                        col,
                        keyStr,
                        entriesByKey[keyStr],
                      ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _buildCollectionMemberTile(
    BuildContext context,
    AppStrings s,
    UserCollection col,
    String keyStr,
    LibraryEntry? entry,
  ) {
    final parsed = MediaKey.tryParse(keyStr);
    if (entry != null) {
      return ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: entry.posterPath.isNotEmpty
              ? Image.network(
                  TmdbClient.posterUrl(entry.posterPath, size: 'w185'),
                  width: 36,
                  height: 54,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const SizedBox(width: 36, height: 54, child: Icon(Icons.movie)),
                )
              : const SizedBox(width: 36, height: 54, child: Icon(Icons.movie)),
        ),
        title: Text(entry.title),
        subtitle: Text(
          [
            if (entry.year != null) '${entry.year}',
            if (entry.userRating != null) '★ ${entry.userRating}/10',
            entry.mediaType == MediaType.tv ? s.t('type_tv') : s.t('type_movie'),
          ].join(' • '),
        ),
        trailing: IconButton(
          tooltip: s.t('remove_from_collection'),
          icon: const Icon(Icons.close),
          onPressed: () => ref
              .read(appControllerProvider.notifier)
              .toggleItemInCollection(col, entry.mediaKey),
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
      );
    }

    return ListTile(
      leading: const Icon(Icons.movie_outlined, color: StarFilmColors.textSecondary),
      title: Text(s.t('missing_in_library', {'key': keyStr})),
      trailing: parsed == null
          ? null
          : IconButton(
              tooltip: s.t('remove_from_collection'),
              icon: const Icon(Icons.close),
              onPressed: () => ref
                  .read(appControllerProvider.notifier)
                  .toggleItemInCollection(col, parsed),
            ),
    );
  }

  Future<void> _confirmDeleteCollection(
    BuildContext context,
    AppStrings s,
    UserCollection col,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarFilmColors.surface,
        title: Text(s.t('delete_collection_confirm_title')),
        content: Text(s.t('delete_collection_confirm_body', {'name': col.title})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(appControllerProvider.notifier).deleteCollection(col);
    }
  }

  Future<String?> _promptCollectionTitle(
    BuildContext context,
    AppStrings s, {
    required String dialogTitle,
    String initialValue = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _CollectionTitleDialog(
        dialogTitle: dialogTitle,
        hintText: s.t('collection_name'),
        cancelLabel: s.t('cancel'),
        okLabel: s.t('ok'),
        initialValue: initialValue,
      ),
    );
  }

  Future<void> _createCollectionDialog(BuildContext context, AppStrings s) async {
    final created = await _promptCollectionTitle(
      context,
      s,
      dialogTitle: s.t('new_collection'),
    );
    if (created != null && created.trim().isNotEmpty) {
      await ref.read(appControllerProvider.notifier).createCollection(created);
    }
  }

  Future<void> _renameCollectionDialog(
    BuildContext context,
    AppStrings s,
    UserCollection col,
  ) async {
    final next = await _promptCollectionTitle(
      context,
      s,
      dialogTitle: s.t('rename'),
      initialValue: col.title,
    );
    if (next != null && next.trim().isNotEmpty) {
      await ref.read(appControllerProvider.notifier).renameCollection(col, next);
    }
  }
}

class _CollectionTitleDialog extends StatefulWidget {
  const _CollectionTitleDialog({
    required this.dialogTitle,
    required this.hintText,
    required this.cancelLabel,
    required this.okLabel,
    this.initialValue = '',
  });

  final String dialogTitle;
  final String hintText;
  final String cancelLabel;
  final String okLabel;
  final String initialValue;

  @override
  State<_CollectionTitleDialog> createState() => _CollectionTitleDialogState();
}

class _CollectionTitleDialogState extends State<_CollectionTitleDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: StarFilmColors.surface,
      title: Text(widget.dialogTitle),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hintText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(widget.okLabel),
        ),
      ],
    );
  }
}
