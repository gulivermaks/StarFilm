import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/db/app_database.dart';
import '../core/models/library_entry.dart';
import '../core/models/media_key.dart';
import '../core/models/profile.dart';
import '../core/network/starfilm_http_client.dart';
import '../core/security/log_sanitizer.dart';
import '../core/security/secret_store.dart';
import '../features/cloud_sync/cloud_sync_models.dart';
import '../features/cloud_sync/firebase_sync_adapter.dart';
import '../features/discovery/discovery_models.dart';
import '../features/discovery/discovery_service.dart';
import '../features/discovery/gemini_client.dart';
import '../features/library/backup_codec.dart';
import '../features/library/library_repository.dart';
import '../features/players/mobile_players.dart';
import '../features/search/tmdb_client.dart';
import '../features/settings/ota_updater.dart';
import '../features/startv/startv_client.dart';
import '../features/startv/startv_models.dart';
import 'l10n.dart';

class AppControllerState {
  const AppControllerState({
    this.initialized = false,
    this.onboardingCompleted = false,
    this.uiLanguage = 'uk',
    this.activeProfileId = 'main',
    this.guestEvening = false,
    this.profiles = const [],
    this.entries = const [],
    this.collections = const [],
    this.tmdbKey = '',
    this.geminiKey = '',
    this.geminiModel = 'gemini-3.5-flash-lite',
    this.preferredPlayer = MobilePlayerId.stremio,
    this.pairedDevices = const [],
    this.selectedTvId = '',
    this.deviceId = '',
    this.cloudUid = '',
    this.cloudEmail = '',
    this.firebaseConfigured = false,
    this.syncState = SyncStatusState.offlineLocal,
    this.pendingSyncCount = 0,
    this.recommendations = const [],
    this.isPicking = false,
    this.usedFallback = false,
    this.recentShownIds = const {},
    this.recentShownLabels = const [],
  });

  final bool initialized;
  final bool onboardingCompleted;
  final String uiLanguage;
  final String activeProfileId;
  final bool guestEvening;
  final List<UserProfile> profiles;
  final List<LibraryEntry> entries;
  final List<UserCollection> collections;
  final String tmdbKey;
  final String geminiKey;
  final String geminiModel;
  final MobilePlayerId preferredPlayer;
  final List<StarTvDevice> pairedDevices;
  final String selectedTvId;
  final String deviceId;
  final String cloudUid;
  final String cloudEmail;
  final bool firebaseConfigured;
  final SyncStatusState syncState;
  final int pendingSyncCount;
  final List<RecommendationCard> recommendations;
  final bool isPicking;
  final bool usedFallback;
  final Set<String> recentShownIds;
  final List<String> recentShownLabels;

  UserProfile get activeProfile {
    for (final p in profiles) {
      if (p.id == activeProfileId) return p;
    }
    return profiles.isNotEmpty
        ? profiles.first
        : UserProfile(id: 'main', name: 'Головний');
  }

  StarTvDevice? get activeTv {
    if (pairedDevices.isEmpty) return null;
    for (final d in pairedDevices) {
      if (d.tvId == selectedTvId || d.ip == selectedTvId) return d;
    }
    return pairedDevices.first;
  }

  AppStrings get strings => AppStrings(uiLanguage);

  AppControllerState copyWith({
    bool? initialized,
    bool? onboardingCompleted,
    String? uiLanguage,
    String? activeProfileId,
    bool? guestEvening,
    List<UserProfile>? profiles,
    List<LibraryEntry>? entries,
    List<UserCollection>? collections,
    String? tmdbKey,
    String? geminiKey,
    String? geminiModel,
    MobilePlayerId? preferredPlayer,
    List<StarTvDevice>? pairedDevices,
    String? selectedTvId,
    String? deviceId,
    String? cloudUid,
    String? cloudEmail,
    bool? firebaseConfigured,
    SyncStatusState? syncState,
    int? pendingSyncCount,
    List<RecommendationCard>? recommendations,
    bool? isPicking,
    bool? usedFallback,
    Set<String>? recentShownIds,
    List<String>? recentShownLabels,
  }) {
    return AppControllerState(
      initialized: initialized ?? this.initialized,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      uiLanguage: uiLanguage ?? this.uiLanguage,
      activeProfileId: activeProfileId ?? this.activeProfileId,
      guestEvening: guestEvening ?? this.guestEvening,
      profiles: profiles ?? this.profiles,
      entries: entries ?? this.entries,
      collections: collections ?? this.collections,
      tmdbKey: tmdbKey ?? this.tmdbKey,
      geminiKey: geminiKey ?? this.geminiKey,
      geminiModel: geminiModel ?? this.geminiModel,
      preferredPlayer: preferredPlayer ?? this.preferredPlayer,
      pairedDevices: pairedDevices ?? this.pairedDevices,
      selectedTvId: selectedTvId ?? this.selectedTvId,
      deviceId: deviceId ?? this.deviceId,
      cloudUid: cloudUid ?? this.cloudUid,
      cloudEmail: cloudEmail ?? this.cloudEmail,
      firebaseConfigured: firebaseConfigured ?? this.firebaseConfigured,
      syncState: syncState ?? this.syncState,
      pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
      recommendations: recommendations ?? this.recommendations,
      isPicking: isPicking ?? this.isPicking,
      usedFallback: usedFallback ?? this.usedFallback,
      recentShownIds: recentShownIds ?? this.recentShownIds,
      recentShownLabels: recentShownLabels ?? this.recentShownLabels,
    );
  }
}

final appServicesProvider = Provider<AppServices>((ref) {
  final log = DiagnosticsLog();
  final http = StarFilmHttpClient(log: log);
  final db = AppDatabase();
  final repo = LibraryRepository(db);
  final secrets = SecretStore();
  final tmdb = TmdbClient(http, log: log);
  final gemini = GeminiClient(http);
  final discovery = DiscoveryService(gemini: gemini, tmdb: tmdb, log: log);
  final starTv = StarTvClient(http);
  final updater = OtaUpdater(http);
  final firebaseSync = FirebaseSyncAdapter(log: log);
  return AppServices(
    log: log,
    http: http,
    db: db,
    repo: repo,
    secrets: secrets,
    tmdb: tmdb,
    gemini: gemini,
    discovery: discovery,
    starTv: starTv,
    updater: updater,
    firebaseSync: firebaseSync,
  );
});

class AppServices {
  const AppServices({
    required this.log,
    required this.http,
    required this.db,
    required this.repo,
    required this.secrets,
    required this.tmdb,
    required this.gemini,
    required this.discovery,
    required this.starTv,
    required this.updater,
    required this.firebaseSync,
  });

  final DiagnosticsLog log;
  final StarFilmHttpClient http;
  final AppDatabase db;
  final LibraryRepository repo;
  final SecretStore secrets;
  final TmdbClient tmdb;
  final GeminiClient gemini;
  final DiscoveryService discovery;
  final StarTvClient starTv;
  final OtaUpdater updater;
  final FirebaseSyncAdapter firebaseSync;
}

final appControllerProvider =
    NotifierProvider<AppController, AppControllerState>(AppController.new);

class AppController extends Notifier<AppControllerState> {
  static const _prefOnboarding = 'starfilm.onboarding_done';
  static const _prefUiLang = 'starfilm.ui_lang';
  static const _prefActiveProfile = 'starfilm.active_profile';
  static const _prefGeminiModel = 'starfilm.gemini_model';
  static const _prefPlayer = 'starfilm.preferred_player';
  static const _prefSelectedTv = 'starfilm.selected_tv';
  static const _prefSyncCursor = 'starfilm.sync_cursor_ms';

  @override
  AppControllerState build() {
    Future.microtask(bootstrap);
    return const AppControllerState();
  }

  AppServices get _s => ref.read(appServicesProvider);

  Future<void> bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _s.repo.ensureMainProfile();
      final firebaseOk = await _s.firebaseSync.tryInitialize();
      final cloudUser = firebaseOk ? _s.firebaseSync.currentUser() : null;
      final profiles = await _s.repo.listProfiles();
      final savedProfile = prefs.getString(_prefActiveProfile) ?? 'main';
      final activeId =
          profiles.any((p) => p.id == savedProfile) ? savedProfile : 'main';

      final entries = await _s.repo.listEntries(activeId);
      final collections = await _s.repo.listCollections(activeId);
      final tmdbKey = await _s.secrets.getTmdbKey();
      final geminiKey = await _s.secrets.getGeminiKey();
      final deviceId = await _s.secrets.getOrCreateDeviceId();
      final tvs = await _s.secrets.loadStarTvDevices();
      final pendingCount = await _s.repo.pendingChangesCount();

      state = state.copyWith(
        initialized: true,
        onboardingCompleted: prefs.getBool(_prefOnboarding) ?? false,
        uiLanguage: prefs.getString(_prefUiLang) ?? 'uk',
        activeProfileId: activeId,
        profiles: profiles,
        entries: entries,
        collections: collections,
        tmdbKey: tmdbKey,
        geminiKey: geminiKey,
        geminiModel: prefs.getString(_prefGeminiModel) ?? 'gemini-3.5-flash-lite',
        preferredPlayer: MobilePlayerId.fromId(prefs.getString(_prefPlayer)),
        pairedDevices: tvs,
        selectedTvId: prefs.getString(_prefSelectedTv) ?? '',
        deviceId: deviceId,
        firebaseConfigured: firebaseOk,
        cloudUid: cloudUser?.uid ?? '',
        cloudEmail: cloudUser?.email ?? '',
        syncState: firebaseOk
            ? (cloudUser != null
                ? SyncStatusState.synced
                : SyncStatusState.offlineLocal)
            : SyncStatusState.notConfigured,
        pendingSyncCount: pendingCount,
      );
      if (cloudUser != null) {
        Future.microtask(syncCloudNow);
      }
    } catch (e) {
      _s.log.error('Bootstrap failed: $e');
      state = state.copyWith(initialized: true);
    }
  }

  Future<bool> signInWithGoogle() async {
    final user = await _s.firebaseSync.signInWithGoogle();
    if (user == null) return false;
    state = state.copyWith(cloudUid: user.uid, cloudEmail: user.email);
    await syncCloudNow();
    return true;
  }

  Future<void> signOutFromGoogle() async {
    await _s.firebaseSync.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefSyncCursor);
    await _s.repo.clearAllLocalUserCloudState();
    state = state.copyWith(
      cloudUid: '',
      cloudEmail: '',
      syncState: SyncStatusState.offlineLocal,
      pendingSyncCount: 0,
    );
  }

  Future<SyncResultSummary> syncCloudNow() async {
    if (!state.firebaseConfigured || state.cloudUid.isEmpty) {
      return const SyncResultSummary(state: SyncStatusState.notConfigured);
    }
    state = state.copyWith(syncState: SyncStatusState.syncing);
    final prefs = await SharedPreferences.getInstance();
    final cursorMs = prefs.getInt(_prefSyncCursor) ?? 0;
    final res = await _s.firebaseSync.sync(
      repo: _s.repo,
      uid: state.cloudUid,
      deviceId: state.deviceId,
      lastServerCursorMs: cursorMs,
      onSaveCursor: (next) => prefs.setInt(_prefSyncCursor, next),
    );
    await _refreshActiveProfileState();
    state = state.copyWith(syncState: res.state);
    return res;
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefOnboarding, true);
    state = state.copyWith(onboardingCompleted: true);
  }

  Future<void> setUiLanguage(String lang) async {
    final normalized = (lang == 'ru' || lang == 'en') ? lang : 'uk';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUiLang, normalized);
    state = state.copyWith(uiLanguage: normalized);
  }

  Future<void> setApiKeys({String? tmdbKey, String? geminiKey}) async {
    if (tmdbKey != null) {
      await _s.secrets.setTmdbKey(tmdbKey);
    }
    if (geminiKey != null) {
      await _s.secrets.setGeminiKey(geminiKey);
    }
    state = state.copyWith(
      tmdbKey: tmdbKey?.trim() ?? state.tmdbKey,
      geminiKey: geminiKey?.trim() ?? state.geminiKey,
    );
  }

  Future<void> setGeminiModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefGeminiModel, model);
    state = state.copyWith(geminiModel: model);
  }

  Future<void> setPreferredPlayer(MobilePlayerId player) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPlayer, player.id);
    state = state.copyWith(preferredPlayer: player);
  }

  void toggleGuestEvening(bool enabled) {
    state = state.copyWith(guestEvening: enabled);
  }

  Future<void> switchProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefActiveProfile, profileId);
    final entries = await _s.repo.listEntries(profileId);
    final collections = await _s.repo.listCollections(profileId);
    state = state.copyWith(
      activeProfileId: profileId,
      entries: entries,
      collections: collections,
      recommendations: const [],
    );
  }

  Future<void> createProfile(String name) async {
    final created = await _s.repo.createProfile(name, accountUid: state.cloudUid);
    final profiles = await _s.repo.listProfiles();
    state = state.copyWith(profiles: profiles);
    await switchProfile(created.id);
  }

  Future<void> renameProfile(UserProfile profile, String newName) async {
    final updated = profile.copyWith(
      name: newName,
      clientUpdatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _s.repo.saveProfile(updated, accountUid: state.cloudUid);
    final profiles = await _s.repo.listProfiles();
    state = state.copyWith(profiles: profiles);
  }

  Future<void> deleteProfile(String profileId) async {
    await _s.repo.deleteProfile(profileId, accountUid: state.cloudUid);
    final profiles = await _s.repo.listProfiles();
    final nextActive =
        profileId == state.activeProfileId ? 'main' : state.activeProfileId;
    state = state.copyWith(profiles: profiles);
    await switchProfile(nextActive);
  }

  Future<void> updateProfilePreferences(ProfilePreferences nextPrefs) async {
    final updated = state.activeProfile.copyWith(
      preferences: nextPrefs,
      clientUpdatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _s.repo.saveProfile(updated, accountUid: state.cloudUid);
    final profiles = await _s.repo.listProfiles();
    state = state.copyWith(profiles: profiles);
  }

  Future<void> resetTasteFilters() async {
    final next = state.activeProfile.preferences.copyWith(
      excludedGenres: const [],
      favoriteGenres: const [],
      personalized: true,
    );
    await updateProfilePreferences(next);
  }

  Future<void> saveEntryAction({
    required MediaType mediaType,
    required int tmdbId,
    required String title,
    String originalTitle = '',
    int? year,
    String posterPath = '',
    List<int> genreIds = const [],
    double? tmdbRating,
    int? runtimeMinutes,
    WatchStatus? status,
    int? userRating,
    bool clearRating = false,
    Sentiment? sentiment,
  }) async {
    final existing =
        await _s.repo.findEntry(state.activeProfileId, MediaKey(mediaType, tmdbId));
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextStatus = status ?? existing?.status ?? WatchStatus.none;
    final clearsRatingForStatus = userRating == null &&
        status != null &&
        (status == WatchStatus.watchlist ||
            status == WatchStatus.none ||
            status == WatchStatus.dismissed);
    final nextRating = (clearRating || clearsRatingForStatus)
        ? null
        : (userRating ?? existing?.userRating);
    final entry = LibraryEntry(
      profileId: state.activeProfileId,
      mediaType: mediaType,
      tmdbId: tmdbId,
      title: title,
      originalTitle: originalTitle,
      year: year,
      posterPath: posterPath,
      genreIds: genreIds,
      tmdbRating: tmdbRating ?? existing?.tmdbRating,
      runtimeMinutes: runtimeMinutes ?? existing?.runtimeMinutes,
      status: nextStatus,
      userRating: nextRating,
      sentiment: sentiment ?? existing?.sentiment ?? Sentiment.neutral,
      statusChangedAt: existing?.statusChangedAt ?? now,
      ratingChangedAt: existing?.ratingChangedAt ?? now,
      sentimentChangedAt: existing?.sentimentChangedAt ?? now,
      clientUpdatedAt: now,
    );
    await _s.repo.upsertEntry(
      entry,
      deviceId: state.deviceId,
      accountUid: state.cloudUid,
      nowMs: now,
    );

    final entries = await _s.repo.listEntries(state.activeProfileId);
    final pendingCount = await _s.repo.pendingChangesCount();
    final remainingRecs = state.recommendations.where((card) {
      if (card.mediaKey == entry.mediaKey && entry.isExcludedFromRecommendations) {
        return false;
      }
      return true;
    }).toList();

    state = state.copyWith(
      entries: entries,
      pendingSyncCount: pendingCount,
      recommendations: remainingRecs,
    );
  }

  Future<void> removeEntry(MediaKey key) async {
    await _s.repo.softDeleteEntry(
      state.activeProfileId,
      key,
      deviceId: state.deviceId,
      accountUid: state.cloudUid,
    );
    final entries = await _s.repo.listEntries(state.activeProfileId);
    final pendingCount = await _s.repo.pendingChangesCount();
    state = state.copyWith(entries: entries, pendingSyncCount: pendingCount);
  }

  Future<void> createCollection(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final col = UserCollection(
      id: 'col_$now',
      profileId: state.activeProfileId,
      title: trimmed,
      mediaKeys: const [],
      clientUpdatedAt: now,
    );
    await _s.repo.saveCollection(col, accountUid: state.cloudUid);
    final collections = await _s.repo.listCollections(state.activeProfileId);
    state = state.copyWith(collections: collections);
  }

  Future<void> toggleItemInCollection(UserCollection col, MediaKey key) async {
    final keys = col.mediaKeys.toList();
    if (keys.contains(key.value)) {
      keys.remove(key.value);
    } else {
      keys.add(key.value);
    }
    final updated = UserCollection(
      id: col.id,
      profileId: col.profileId,
      title: col.title,
      mediaKeys: keys,
      clientUpdatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _s.repo.saveCollection(updated, accountUid: state.cloudUid);
    final collections = await _s.repo.listCollections(state.activeProfileId);
    state = state.copyWith(collections: collections);
  }

  Future<void> runDiscovery(DiscoveryRequest request) async {
    if (state.tmdbKey.trim().isEmpty) return;
    state = state.copyWith(isPicking: true);
    try {
      final result = await _s.discovery.recommend(
        tmdbApiKey: state.tmdbKey,
        geminiApiKey: state.geminiKey,
        geminiModel: state.geminiModel,
        request: DiscoveryRequest(
          prompt: request.prompt,
          preset: request.preset,
          mediaTypeFilter: request.mediaTypeFilter,
          maxMinutes: request.maxMinutes,
          guestMode: request.guestMode || state.guestEvening,
          different: request.different,
        ),
        profile: state.activeProfile,
        library: state.entries,
        recentShownIds: state.recentShownIds,
        recentShownLabels: state.recentShownLabels,
      );

      final nextShownIds = {...state.recentShownIds};
      final nextShownLabels = [...state.recentShownLabels];
      for (final card in result.cards) {
        nextShownIds.add(card.mediaKey.value);
        final label = card.year != null ? '${card.title} (${card.year})' : card.title;
        if (!nextShownLabels.contains(label)) {
          nextShownLabels.insert(0, label);
        }
      }

      state = state.copyWith(
        isPicking: false,
        recommendations: result.cards,
        usedFallback: result.usedFallback,
        recentShownIds: nextShownIds,
        recentShownLabels: nextShownLabels.take(36).toList(),
      );
    } catch (e) {
      _s.log.error('Discovery failed: $e');
      state = state.copyWith(isPicking: false);
    }
  }

  Future<void> saveStarTvDevice(StarTvDevice device, String bearerToken) async {
    await _s.secrets.saveStarTvDevice(device, bearerToken);
    final list = await _s.secrets.loadStarTvDevices();
    final prefs = await SharedPreferences.getInstance();
    final key = device.tvId.isNotEmpty ? device.tvId : device.ip;
    await prefs.setString(_prefSelectedTv, key);
    state = state.copyWith(pairedDevices: list, selectedTvId: key);
  }

  Future<void> selectStarTv(StarTvDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    final key = device.tvId.isNotEmpty ? device.tvId : device.ip;
    await prefs.setString(_prefSelectedTv, key);
    state = state.copyWith(selectedTvId: key);
  }

  Future<void> removeStarTv(StarTvDevice device) async {
    await _s.secrets.removeStarTvDevice(device);
    final list = await _s.secrets.loadStarTvDevices();
    state = state.copyWith(
      pairedDevices: list,
      selectedTvId: list.isNotEmpty ? list.first.tvId : '',
    );
  }

  Future<void> launchOnTv({
    required int tmdbId,
    required MediaType mediaType,
    required String title,
    String originalTitle = '',
    int? year,
    String player = 'auto',
  }) async {
    final tv = state.activeTv;
    if (tv == null) throw StateError('No StarTV device paired');
    final token = await _s.secrets.getStarTvToken(tv);
    if (token == null || token.isEmpty) throw StateError('Missing StarTV token');
    await _s.starTv.launchMedia(
      device: tv,
      bearerToken: token,
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      originalTitle: originalTitle,
      year: year,
      player: player,
    );
  }

  Future<int> syncWithHomeTv() async {
    final tv = state.activeTv;
    if (tv == null) throw StateError('No StarTV device paired');
    if (!tv.canSyncLibrary) {
      throw StateError('Library sync is blocked in Guest TV mode');
    }
    final token = await _s.secrets.getStarTvToken(tv);
    if (token == null || token.isEmpty) throw StateError('Missing StarTV token');

    final allProfiles = await _s.repo.listProfiles();
    final entriesMap = <String, List<LibraryEntry>>{};
    final deletedMap = <String, Map<String, int>>{};
    for (final p in allProfiles) {
      final all = await _s.repo.listEntries(p.id, includeDeleted: true);
      entriesMap[p.id] = all.where((e) => !e.isDeleted).toList();
      deletedMap[p.id] = {
        for (final e in all)
          if (e.isDeleted) e.keyString: e.deletedAt!,
      };
    }

    final mergedFromTv = await _s.starTv.syncLibrary(
      device: tv,
      bearerToken: token,
      activeProfileId: state.activeProfileId,
      profiles: allProfiles,
      entriesByProfile: entriesMap,
      deletedByProfile: deletedMap,
    );

    final count = await _s.repo.mergeImportedBundle(
      mergedFromTv,
      deviceId: state.deviceId,
      accountUid: state.cloudUid,
    );
    await _refreshActiveProfileState();
    return count;
  }

  Future<void> transferKeysToHomeTv() async {
    final tv = state.activeTv;
    if (tv == null) throw StateError('No StarTV device paired');
    if (!tv.canTransferKeys) {
      throw StateError('Key transfer is blocked in Guest TV mode');
    }
    final token = await _s.secrets.getStarTvToken(tv);
    if (token == null || token.isEmpty) throw StateError('Missing StarTV token');
    if (state.tmdbKey.isNotEmpty) {
      await _s.starTv.transferApiKey(
        device: tv,
        bearerToken: token,
        provider: 'tmdb',
        apiKey: state.tmdbKey,
      );
    }
    if (state.geminiKey.isNotEmpty) {
      await _s.starTv.transferApiKey(
        device: tv,
        bearerToken: token,
        provider: 'gemini',
        apiKey: state.geminiKey,
      );
    }
  }

  Future<String> exportBackupJson() async {
    final allProfiles = await _s.repo.listProfiles();
    final entriesMap = <String, List<LibraryEntry>>{};
    final collectionsMap = <String, List<UserCollection>>{};
    final deletedMap = <String, Map<String, int>>{};

    for (final p in allProfiles) {
      final allEntries = await _s.repo.listEntries(p.id, includeDeleted: true);
      entriesMap[p.id] = allEntries.where((e) => !e.isDeleted).toList();
      deletedMap[p.id] = {
        for (final e in allEntries)
          if (e.isDeleted) e.keyString: e.deletedAt!,
      };
      collectionsMap[p.id] = await _s.repo.listCollections(p.id);
    }

    return BackupCodec.encodeStarFilmBackup(
      activeProfileId: state.activeProfileId,
      profiles: allProfiles,
      entriesByProfile: entriesMap,
      collectionsByProfile: collectionsMap,
      deletedByProfile: deletedMap,
    );
  }

  Future<int> importBackupJson(
    String rawJson, {
    BackupImportMode mode = BackupImportMode.merge,
  }) async {
    final bundle = BackupCodec.decodeBackup(rawJson);
    return importBackupBundle(bundle, mode: mode);
  }

  Future<int> importBackupBundle(
    BackupBundle bundle, {
    BackupImportMode mode = BackupImportMode.merge,
  }) async {
    final count = mode == BackupImportMode.replace
        ? await _s.repo.replaceFromBackupBundle(
            bundle,
            deviceId: state.deviceId,
            accountUid: state.cloudUid,
          )
        : await _s.repo.mergeImportedBundle(
            bundle,
            deviceId: state.deviceId,
            accountUid: state.cloudUid,
          );
    if (mode == BackupImportMode.replace) {
      final profiles = await _s.repo.listProfiles();
      final hasActive = profiles.any((p) => p.id == state.activeProfileId);
      final targetProfileId = profiles.any((p) => p.id == bundle.activeProfileId)
          ? bundle.activeProfileId
          : (hasActive ? state.activeProfileId : 'main');
      if (targetProfileId != state.activeProfileId) {
        await switchProfile(targetProfileId);
      }
    }
    await _refreshActiveProfileState();
    return count;
  }

  Future<void> _refreshActiveProfileState() async {
    final profiles = await _s.repo.listProfiles();
    final entries = await _s.repo.listEntries(state.activeProfileId);
    final collections = await _s.repo.listCollections(state.activeProfileId);
    final pendingCount = await _s.repo.pendingChangesCount();
    state = state.copyWith(
      profiles: profiles,
      entries: entries,
      collections: collections,
      pendingSyncCount: pendingCount,
    );
  }

  @visibleForTesting
  Future<void> importFile(File file) async {
    final content = await file.readAsString(encoding: utf8);
    await importBackupJson(content);
  }
}
