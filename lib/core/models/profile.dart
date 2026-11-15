import 'media_key.dart';

class ProfilePreferences {
  const ProfilePreferences({
    this.excludedGenres = const [],
    this.favoriteGenres = const [],
    this.contentLanguage = 'uk',
    this.personalized = true,
  });

  final List<int> excludedGenres;
  final List<int> favoriteGenres;
  final String contentLanguage;
  final bool personalized;

  ProfilePreferences copyWith({
    List<int>? excludedGenres,
    List<int>? favoriteGenres,
    String? contentLanguage,
    bool? personalized,
  }) {
    return ProfilePreferences(
      excludedGenres: excludedGenres ?? this.excludedGenres,
      favoriteGenres: favoriteGenres ?? this.favoriteGenres,
      contentLanguage: normalizeContentLanguage(contentLanguage ?? this.contentLanguage),
      personalized: personalized ?? this.personalized,
    );
  }

  static String normalizeContentLanguage(String raw) {
    switch (raw.toLowerCase()) {
      case 'ru':
        return 'ru';
      case 'en':
        return 'en';
      default:
        return 'uk';
    }
  }

  Map<String, dynamic> toJson() => {
        'excludedGenres': excludedGenres,
        'favoriteGenres': favoriteGenres,
        'contentLanguage': contentLanguage,
        'personalized': personalized,
      };

  factory ProfilePreferences.fromJson(Map<String, dynamic> json) {
    final validGenreIds = kStandardGenres.map((g) => g.id).toSet();
    final excluded = (json['excludedGenres'] as List<dynamic>? ?? const [])
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
        .whereType<int>()
        .where(validGenreIds.contains)
        .toSet()
        .toList()
      ..sort();
    final favorites = (json['favoriteGenres'] as List<dynamic>? ?? const [])
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
        .whereType<int>()
        .where(validGenreIds.contains)
        .toSet()
        .toList()
      ..sort();
    return ProfilePreferences(
      excludedGenres: excluded,
      favoriteGenres: favorites,
      contentLanguage: normalizeContentLanguage(
        json['contentLanguage']?.toString() ?? 'uk',
      ),
      personalized: json['personalized'] is bool ? json['personalized'] as bool : true,
    );
  }
}

class UserProfile {
  UserProfile({
    required this.id,
    required String name,
    this.preferences = const ProfilePreferences(),
    this.clientUpdatedAt = 0,
    this.serverSyncedAt = 0,
    this.deletedAt,
  }) : name = sanitizeName(name) {
    if (!isValidId(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid profile id');
    }
  }

  static const int maxProfiles = 4;
  static const int maxNameLength = 24;
  static const int maxEntriesPerProfile = 2000;
  static final RegExp _idPattern = RegExp(r'^(main|p_[a-z0-9]{4,16})$');

  final String id;
  final String name;
  final ProfilePreferences preferences;
  final int clientUpdatedAt;
  final int serverSyncedAt;
  final int? deletedAt;

  bool get isMain => id == 'main';
  bool get isDeleted => deletedAt != null && deletedAt! > 0;

  static bool isValidId(String id) => _idPattern.hasMatch(id);

  static String sanitizeName(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return 'Профіль';
    if (trimmed.length <= maxNameLength) return trimmed;
    return trimmed.substring(0, maxNameLength);
  }

  UserProfile copyWith({
    String? name,
    ProfilePreferences? preferences,
    int? clientUpdatedAt,
    int? serverSyncedAt,
    int? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      preferences: preferences ?? this.preferences,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverSyncedAt: serverSyncedAt ?? this.serverSyncedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}
