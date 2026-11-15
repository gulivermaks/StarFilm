import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class ProfilesTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 24)();
  TextColumn get excludedGenresJson => text().withDefault(const Constant('[]'))();
  TextColumn get favoriteGenresJson => text().withDefault(const Constant('[]'))();
  TextColumn get contentLanguage => text().withDefault(const Constant('uk'))();
  BoolColumn get personalized => boolean().withDefault(const Constant(true))();
  IntColumn get clientUpdatedAt => integer().withDefault(const Constant(0))();
  IntColumn get serverSyncedAt => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LibraryEntriesTable extends Table {
  TextColumn get profileId => text()();
  TextColumn get mediaType => text()();
  IntColumn get tmdbId => integer()();
  TextColumn get title => text()();
  TextColumn get originalTitle => text().withDefault(const Constant(''))();
  IntColumn get year => integer().nullable()();
  TextColumn get posterPath => text().withDefault(const Constant(''))();
  TextColumn get genreIdsJson => text().withDefault(const Constant('[]'))();
  RealColumn get tmdbRating => real().nullable()();
  IntColumn get runtimeMinutes => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('none'))();
  IntColumn get userRating => integer().nullable()();
  TextColumn get sentiment => text().withDefault(const Constant('neutral'))();
  IntColumn get statusChangedAt => integer().withDefault(const Constant(0))();
  IntColumn get ratingChangedAt => integer().withDefault(const Constant(0))();
  IntColumn get sentimentChangedAt => integer().withDefault(const Constant(0))();
  IntColumn get clientUpdatedAt => integer().withDefault(const Constant(0))();
  IntColumn get serverSyncedAt => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get updatedByDevice => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {profileId, mediaType, tmdbId};
}

class CollectionsTable extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get title => text()();
  TextColumn get mediaKeysJson => text().withDefault(const Constant('[]'))();
  IntColumn get clientUpdatedAt => integer().withDefault(const Constant(0))();
  IntColumn get serverSyncedAt => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {profileId, id};
}

class PendingChangesTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountUid => text().withDefault(const Constant(''))();
  TextColumn get entityType => text()(); // 'profile' | 'library' | 'collection'
  TextColumn get profileId => text()();
  TextColumn get entityKey => text()();
  IntColumn get createdAt => integer()();
}

class CachedDetailsTable extends Table {
  TextColumn get mediaKey => text()();
  TextColumn get payloadJson => text()();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column> get primaryKey => {mediaKey};
}

@DriftDatabase(tables: [
  ProfilesTable,
  LibraryEntriesTable,
  CollectionsTable,
  PendingChangesTable,
  CachedDetailsTable,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static List<int> decodeIntList(String raw) {
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<num>().map((e) => e.toInt()).toList();
    } catch (_) {
      return const [];
    }
  }

  static List<String> decodeStringList(String raw) {
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'starfilm.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
