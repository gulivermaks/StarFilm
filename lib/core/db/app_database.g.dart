// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ProfilesTableTable extends ProfilesTable
    with TableInfo<$ProfilesTableTable, ProfilesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 24,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _excludedGenresJsonMeta =
      const VerificationMeta('excludedGenresJson');
  @override
  late final GeneratedColumn<String> excludedGenresJson =
      GeneratedColumn<String>(
        'excluded_genres_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _favoriteGenresJsonMeta =
      const VerificationMeta('favoriteGenresJson');
  @override
  late final GeneratedColumn<String> favoriteGenresJson =
      GeneratedColumn<String>(
        'favorite_genres_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _contentLanguageMeta = const VerificationMeta(
    'contentLanguage',
  );
  @override
  late final GeneratedColumn<String> contentLanguage = GeneratedColumn<String>(
    'content_language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('uk'),
  );
  static const VerificationMeta _personalizedMeta = const VerificationMeta(
    'personalized',
  );
  @override
  late final GeneratedColumn<bool> personalized = GeneratedColumn<bool>(
    'personalized',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("personalized" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<int> clientUpdatedAt = GeneratedColumn<int>(
    'client_updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _serverSyncedAtMeta = const VerificationMeta(
    'serverSyncedAt',
  );
  @override
  late final GeneratedColumn<int> serverSyncedAt = GeneratedColumn<int>(
    'server_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    excludedGenresJson,
    favoriteGenresJson,
    contentLanguage,
    personalized,
    clientUpdatedAt,
    serverSyncedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfilesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('excluded_genres_json')) {
      context.handle(
        _excludedGenresJsonMeta,
        excludedGenresJson.isAcceptableOrUnknown(
          data['excluded_genres_json']!,
          _excludedGenresJsonMeta,
        ),
      );
    }
    if (data.containsKey('favorite_genres_json')) {
      context.handle(
        _favoriteGenresJsonMeta,
        favoriteGenresJson.isAcceptableOrUnknown(
          data['favorite_genres_json']!,
          _favoriteGenresJsonMeta,
        ),
      );
    }
    if (data.containsKey('content_language')) {
      context.handle(
        _contentLanguageMeta,
        contentLanguage.isAcceptableOrUnknown(
          data['content_language']!,
          _contentLanguageMeta,
        ),
      );
    }
    if (data.containsKey('personalized')) {
      context.handle(
        _personalizedMeta,
        personalized.isAcceptableOrUnknown(
          data['personalized']!,
          _personalizedMeta,
        ),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_synced_at')) {
      context.handle(
        _serverSyncedAtMeta,
        serverSyncedAt.isAcceptableOrUnknown(
          data['server_synced_at']!,
          _serverSyncedAtMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfilesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfilesTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      excludedGenresJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}excluded_genres_json'],
      )!,
      favoriteGenresJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}favorite_genres_json'],
      )!,
      contentLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_language'],
      )!,
      personalized: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}personalized'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}client_updated_at'],
      )!,
      serverSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_synced_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ProfilesTableTable createAlias(String alias) {
    return $ProfilesTableTable(attachedDatabase, alias);
  }
}

class ProfilesTableData extends DataClass
    implements Insertable<ProfilesTableData> {
  final String id;
  final String name;
  final String excludedGenresJson;
  final String favoriteGenresJson;
  final String contentLanguage;
  final bool personalized;
  final int clientUpdatedAt;
  final int serverSyncedAt;
  final int? deletedAt;
  const ProfilesTableData({
    required this.id,
    required this.name,
    required this.excludedGenresJson,
    required this.favoriteGenresJson,
    required this.contentLanguage,
    required this.personalized,
    required this.clientUpdatedAt,
    required this.serverSyncedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['excluded_genres_json'] = Variable<String>(excludedGenresJson);
    map['favorite_genres_json'] = Variable<String>(favoriteGenresJson);
    map['content_language'] = Variable<String>(contentLanguage);
    map['personalized'] = Variable<bool>(personalized);
    map['client_updated_at'] = Variable<int>(clientUpdatedAt);
    map['server_synced_at'] = Variable<int>(serverSyncedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  ProfilesTableCompanion toCompanion(bool nullToAbsent) {
    return ProfilesTableCompanion(
      id: Value(id),
      name: Value(name),
      excludedGenresJson: Value(excludedGenresJson),
      favoriteGenresJson: Value(favoriteGenresJson),
      contentLanguage: Value(contentLanguage),
      personalized: Value(personalized),
      clientUpdatedAt: Value(clientUpdatedAt),
      serverSyncedAt: Value(serverSyncedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ProfilesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfilesTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      excludedGenresJson: serializer.fromJson<String>(
        json['excludedGenresJson'],
      ),
      favoriteGenresJson: serializer.fromJson<String>(
        json['favoriteGenresJson'],
      ),
      contentLanguage: serializer.fromJson<String>(json['contentLanguage']),
      personalized: serializer.fromJson<bool>(json['personalized']),
      clientUpdatedAt: serializer.fromJson<int>(json['clientUpdatedAt']),
      serverSyncedAt: serializer.fromJson<int>(json['serverSyncedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'excludedGenresJson': serializer.toJson<String>(excludedGenresJson),
      'favoriteGenresJson': serializer.toJson<String>(favoriteGenresJson),
      'contentLanguage': serializer.toJson<String>(contentLanguage),
      'personalized': serializer.toJson<bool>(personalized),
      'clientUpdatedAt': serializer.toJson<int>(clientUpdatedAt),
      'serverSyncedAt': serializer.toJson<int>(serverSyncedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  ProfilesTableData copyWith({
    String? id,
    String? name,
    String? excludedGenresJson,
    String? favoriteGenresJson,
    String? contentLanguage,
    bool? personalized,
    int? clientUpdatedAt,
    int? serverSyncedAt,
    Value<int?> deletedAt = const Value.absent(),
  }) => ProfilesTableData(
    id: id ?? this.id,
    name: name ?? this.name,
    excludedGenresJson: excludedGenresJson ?? this.excludedGenresJson,
    favoriteGenresJson: favoriteGenresJson ?? this.favoriteGenresJson,
    contentLanguage: contentLanguage ?? this.contentLanguage,
    personalized: personalized ?? this.personalized,
    clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
    serverSyncedAt: serverSyncedAt ?? this.serverSyncedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ProfilesTableData copyWithCompanion(ProfilesTableCompanion data) {
    return ProfilesTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      excludedGenresJson: data.excludedGenresJson.present
          ? data.excludedGenresJson.value
          : this.excludedGenresJson,
      favoriteGenresJson: data.favoriteGenresJson.present
          ? data.favoriteGenresJson.value
          : this.favoriteGenresJson,
      contentLanguage: data.contentLanguage.present
          ? data.contentLanguage.value
          : this.contentLanguage,
      personalized: data.personalized.present
          ? data.personalized.value
          : this.personalized,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverSyncedAt: data.serverSyncedAt.present
          ? data.serverSyncedAt.value
          : this.serverSyncedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('excludedGenresJson: $excludedGenresJson, ')
          ..write('favoriteGenresJson: $favoriteGenresJson, ')
          ..write('contentLanguage: $contentLanguage, ')
          ..write('personalized: $personalized, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverSyncedAt: $serverSyncedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    excludedGenresJson,
    favoriteGenresJson,
    contentLanguage,
    personalized,
    clientUpdatedAt,
    serverSyncedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfilesTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.excludedGenresJson == this.excludedGenresJson &&
          other.favoriteGenresJson == this.favoriteGenresJson &&
          other.contentLanguage == this.contentLanguage &&
          other.personalized == this.personalized &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverSyncedAt == this.serverSyncedAt &&
          other.deletedAt == this.deletedAt);
}

class ProfilesTableCompanion extends UpdateCompanion<ProfilesTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> excludedGenresJson;
  final Value<String> favoriteGenresJson;
  final Value<String> contentLanguage;
  final Value<bool> personalized;
  final Value<int> clientUpdatedAt;
  final Value<int> serverSyncedAt;
  final Value<int?> deletedAt;
  final Value<int> rowid;
  const ProfilesTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.excludedGenresJson = const Value.absent(),
    this.favoriteGenresJson = const Value.absent(),
    this.contentLanguage = const Value.absent(),
    this.personalized = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverSyncedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesTableCompanion.insert({
    required String id,
    required String name,
    this.excludedGenresJson = const Value.absent(),
    this.favoriteGenresJson = const Value.absent(),
    this.contentLanguage = const Value.absent(),
    this.personalized = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverSyncedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<ProfilesTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? excludedGenresJson,
    Expression<String>? favoriteGenresJson,
    Expression<String>? contentLanguage,
    Expression<bool>? personalized,
    Expression<int>? clientUpdatedAt,
    Expression<int>? serverSyncedAt,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (excludedGenresJson != null)
        'excluded_genres_json': excludedGenresJson,
      if (favoriteGenresJson != null)
        'favorite_genres_json': favoriteGenresJson,
      if (contentLanguage != null) 'content_language': contentLanguage,
      if (personalized != null) 'personalized': personalized,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverSyncedAt != null) 'server_synced_at': serverSyncedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? excludedGenresJson,
    Value<String>? favoriteGenresJson,
    Value<String>? contentLanguage,
    Value<bool>? personalized,
    Value<int>? clientUpdatedAt,
    Value<int>? serverSyncedAt,
    Value<int?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ProfilesTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      excludedGenresJson: excludedGenresJson ?? this.excludedGenresJson,
      favoriteGenresJson: favoriteGenresJson ?? this.favoriteGenresJson,
      contentLanguage: contentLanguage ?? this.contentLanguage,
      personalized: personalized ?? this.personalized,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverSyncedAt: serverSyncedAt ?? this.serverSyncedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (excludedGenresJson.present) {
      map['excluded_genres_json'] = Variable<String>(excludedGenresJson.value);
    }
    if (favoriteGenresJson.present) {
      map['favorite_genres_json'] = Variable<String>(favoriteGenresJson.value);
    }
    if (contentLanguage.present) {
      map['content_language'] = Variable<String>(contentLanguage.value);
    }
    if (personalized.present) {
      map['personalized'] = Variable<bool>(personalized.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<int>(clientUpdatedAt.value);
    }
    if (serverSyncedAt.present) {
      map['server_synced_at'] = Variable<int>(serverSyncedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('excludedGenresJson: $excludedGenresJson, ')
          ..write('favoriteGenresJson: $favoriteGenresJson, ')
          ..write('contentLanguage: $contentLanguage, ')
          ..write('personalized: $personalized, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverSyncedAt: $serverSyncedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LibraryEntriesTableTable extends LibraryEntriesTable
    with TableInfo<$LibraryEntriesTableTable, LibraryEntriesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryEntriesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tmdbIdMeta = const VerificationMeta('tmdbId');
  @override
  late final GeneratedColumn<int> tmdbId = GeneratedColumn<int>(
    'tmdb_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalTitleMeta = const VerificationMeta(
    'originalTitle',
  );
  @override
  late final GeneratedColumn<String> originalTitle = GeneratedColumn<String>(
    'original_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _posterPathMeta = const VerificationMeta(
    'posterPath',
  );
  @override
  late final GeneratedColumn<String> posterPath = GeneratedColumn<String>(
    'poster_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _genreIdsJsonMeta = const VerificationMeta(
    'genreIdsJson',
  );
  @override
  late final GeneratedColumn<String> genreIdsJson = GeneratedColumn<String>(
    'genre_ids_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _tmdbRatingMeta = const VerificationMeta(
    'tmdbRating',
  );
  @override
  late final GeneratedColumn<double> tmdbRating = GeneratedColumn<double>(
    'tmdb_rating',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _runtimeMinutesMeta = const VerificationMeta(
    'runtimeMinutes',
  );
  @override
  late final GeneratedColumn<int> runtimeMinutes = GeneratedColumn<int>(
    'runtime_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _userRatingMeta = const VerificationMeta(
    'userRating',
  );
  @override
  late final GeneratedColumn<int> userRating = GeneratedColumn<int>(
    'user_rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sentimentMeta = const VerificationMeta(
    'sentiment',
  );
  @override
  late final GeneratedColumn<String> sentiment = GeneratedColumn<String>(
    'sentiment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('neutral'),
  );
  static const VerificationMeta _statusChangedAtMeta = const VerificationMeta(
    'statusChangedAt',
  );
  @override
  late final GeneratedColumn<int> statusChangedAt = GeneratedColumn<int>(
    'status_changed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ratingChangedAtMeta = const VerificationMeta(
    'ratingChangedAt',
  );
  @override
  late final GeneratedColumn<int> ratingChangedAt = GeneratedColumn<int>(
    'rating_changed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sentimentChangedAtMeta =
      const VerificationMeta('sentimentChangedAt');
  @override
  late final GeneratedColumn<int> sentimentChangedAt = GeneratedColumn<int>(
    'sentiment_changed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<int> clientUpdatedAt = GeneratedColumn<int>(
    'client_updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _serverSyncedAtMeta = const VerificationMeta(
    'serverSyncedAt',
  );
  @override
  late final GeneratedColumn<int> serverSyncedAt = GeneratedColumn<int>(
    'server_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    profileId,
    mediaType,
    tmdbId,
    title,
    originalTitle,
    year,
    posterPath,
    genreIdsJson,
    tmdbRating,
    runtimeMinutes,
    status,
    userRating,
    sentiment,
    statusChangedAt,
    ratingChangedAt,
    sentimentChangedAt,
    clientUpdatedAt,
    serverSyncedAt,
    deletedAt,
    updatedByDevice,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_entries_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryEntriesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('tmdb_id')) {
      context.handle(
        _tmdbIdMeta,
        tmdbId.isAcceptableOrUnknown(data['tmdb_id']!, _tmdbIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tmdbIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('original_title')) {
      context.handle(
        _originalTitleMeta,
        originalTitle.isAcceptableOrUnknown(
          data['original_title']!,
          _originalTitleMeta,
        ),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('poster_path')) {
      context.handle(
        _posterPathMeta,
        posterPath.isAcceptableOrUnknown(data['poster_path']!, _posterPathMeta),
      );
    }
    if (data.containsKey('genre_ids_json')) {
      context.handle(
        _genreIdsJsonMeta,
        genreIdsJson.isAcceptableOrUnknown(
          data['genre_ids_json']!,
          _genreIdsJsonMeta,
        ),
      );
    }
    if (data.containsKey('tmdb_rating')) {
      context.handle(
        _tmdbRatingMeta,
        tmdbRating.isAcceptableOrUnknown(data['tmdb_rating']!, _tmdbRatingMeta),
      );
    }
    if (data.containsKey('runtime_minutes')) {
      context.handle(
        _runtimeMinutesMeta,
        runtimeMinutes.isAcceptableOrUnknown(
          data['runtime_minutes']!,
          _runtimeMinutesMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('user_rating')) {
      context.handle(
        _userRatingMeta,
        userRating.isAcceptableOrUnknown(data['user_rating']!, _userRatingMeta),
      );
    }
    if (data.containsKey('sentiment')) {
      context.handle(
        _sentimentMeta,
        sentiment.isAcceptableOrUnknown(data['sentiment']!, _sentimentMeta),
      );
    }
    if (data.containsKey('status_changed_at')) {
      context.handle(
        _statusChangedAtMeta,
        statusChangedAt.isAcceptableOrUnknown(
          data['status_changed_at']!,
          _statusChangedAtMeta,
        ),
      );
    }
    if (data.containsKey('rating_changed_at')) {
      context.handle(
        _ratingChangedAtMeta,
        ratingChangedAt.isAcceptableOrUnknown(
          data['rating_changed_at']!,
          _ratingChangedAtMeta,
        ),
      );
    }
    if (data.containsKey('sentiment_changed_at')) {
      context.handle(
        _sentimentChangedAtMeta,
        sentimentChangedAt.isAcceptableOrUnknown(
          data['sentiment_changed_at']!,
          _sentimentChangedAtMeta,
        ),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_synced_at')) {
      context.handle(
        _serverSyncedAtMeta,
        serverSyncedAt.isAcceptableOrUnknown(
          data['server_synced_at']!,
          _serverSyncedAtMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, mediaType, tmdbId};
  @override
  LibraryEntriesTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryEntriesTableData(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      )!,
      tmdbId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tmdb_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      originalTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_title'],
      )!,
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      posterPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster_path'],
      )!,
      genreIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre_ids_json'],
      )!,
      tmdbRating: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}tmdb_rating'],
      ),
      runtimeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}runtime_minutes'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      userRating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_rating'],
      ),
      sentiment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sentiment'],
      )!,
      statusChangedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status_changed_at'],
      )!,
      ratingChangedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating_changed_at'],
      )!,
      sentimentChangedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sentiment_changed_at'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}client_updated_at'],
      )!,
      serverSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_synced_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
    );
  }

  @override
  $LibraryEntriesTableTable createAlias(String alias) {
    return $LibraryEntriesTableTable(attachedDatabase, alias);
  }
}

class LibraryEntriesTableData extends DataClass
    implements Insertable<LibraryEntriesTableData> {
  final String profileId;
  final String mediaType;
  final int tmdbId;
  final String title;
  final String originalTitle;
  final int? year;
  final String posterPath;
  final String genreIdsJson;
  final double? tmdbRating;
  final int? runtimeMinutes;
  final String status;
  final int? userRating;
  final String sentiment;
  final int statusChangedAt;
  final int ratingChangedAt;
  final int sentimentChangedAt;
  final int clientUpdatedAt;
  final int serverSyncedAt;
  final int? deletedAt;
  final String updatedByDevice;
  const LibraryEntriesTableData({
    required this.profileId,
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    required this.originalTitle,
    this.year,
    required this.posterPath,
    required this.genreIdsJson,
    this.tmdbRating,
    this.runtimeMinutes,
    required this.status,
    this.userRating,
    required this.sentiment,
    required this.statusChangedAt,
    required this.ratingChangedAt,
    required this.sentimentChangedAt,
    required this.clientUpdatedAt,
    required this.serverSyncedAt,
    this.deletedAt,
    required this.updatedByDevice,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['media_type'] = Variable<String>(mediaType);
    map['tmdb_id'] = Variable<int>(tmdbId);
    map['title'] = Variable<String>(title);
    map['original_title'] = Variable<String>(originalTitle);
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    map['poster_path'] = Variable<String>(posterPath);
    map['genre_ids_json'] = Variable<String>(genreIdsJson);
    if (!nullToAbsent || tmdbRating != null) {
      map['tmdb_rating'] = Variable<double>(tmdbRating);
    }
    if (!nullToAbsent || runtimeMinutes != null) {
      map['runtime_minutes'] = Variable<int>(runtimeMinutes);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || userRating != null) {
      map['user_rating'] = Variable<int>(userRating);
    }
    map['sentiment'] = Variable<String>(sentiment);
    map['status_changed_at'] = Variable<int>(statusChangedAt);
    map['rating_changed_at'] = Variable<int>(ratingChangedAt);
    map['sentiment_changed_at'] = Variable<int>(sentimentChangedAt);
    map['client_updated_at'] = Variable<int>(clientUpdatedAt);
    map['server_synced_at'] = Variable<int>(serverSyncedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    return map;
  }

  LibraryEntriesTableCompanion toCompanion(bool nullToAbsent) {
    return LibraryEntriesTableCompanion(
      profileId: Value(profileId),
      mediaType: Value(mediaType),
      tmdbId: Value(tmdbId),
      title: Value(title),
      originalTitle: Value(originalTitle),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      posterPath: Value(posterPath),
      genreIdsJson: Value(genreIdsJson),
      tmdbRating: tmdbRating == null && nullToAbsent
          ? const Value.absent()
          : Value(tmdbRating),
      runtimeMinutes: runtimeMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(runtimeMinutes),
      status: Value(status),
      userRating: userRating == null && nullToAbsent
          ? const Value.absent()
          : Value(userRating),
      sentiment: Value(sentiment),
      statusChangedAt: Value(statusChangedAt),
      ratingChangedAt: Value(ratingChangedAt),
      sentimentChangedAt: Value(sentimentChangedAt),
      clientUpdatedAt: Value(clientUpdatedAt),
      serverSyncedAt: Value(serverSyncedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      updatedByDevice: Value(updatedByDevice),
    );
  }

  factory LibraryEntriesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryEntriesTableData(
      profileId: serializer.fromJson<String>(json['profileId']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      tmdbId: serializer.fromJson<int>(json['tmdbId']),
      title: serializer.fromJson<String>(json['title']),
      originalTitle: serializer.fromJson<String>(json['originalTitle']),
      year: serializer.fromJson<int?>(json['year']),
      posterPath: serializer.fromJson<String>(json['posterPath']),
      genreIdsJson: serializer.fromJson<String>(json['genreIdsJson']),
      tmdbRating: serializer.fromJson<double?>(json['tmdbRating']),
      runtimeMinutes: serializer.fromJson<int?>(json['runtimeMinutes']),
      status: serializer.fromJson<String>(json['status']),
      userRating: serializer.fromJson<int?>(json['userRating']),
      sentiment: serializer.fromJson<String>(json['sentiment']),
      statusChangedAt: serializer.fromJson<int>(json['statusChangedAt']),
      ratingChangedAt: serializer.fromJson<int>(json['ratingChangedAt']),
      sentimentChangedAt: serializer.fromJson<int>(json['sentimentChangedAt']),
      clientUpdatedAt: serializer.fromJson<int>(json['clientUpdatedAt']),
      serverSyncedAt: serializer.fromJson<int>(json['serverSyncedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'mediaType': serializer.toJson<String>(mediaType),
      'tmdbId': serializer.toJson<int>(tmdbId),
      'title': serializer.toJson<String>(title),
      'originalTitle': serializer.toJson<String>(originalTitle),
      'year': serializer.toJson<int?>(year),
      'posterPath': serializer.toJson<String>(posterPath),
      'genreIdsJson': serializer.toJson<String>(genreIdsJson),
      'tmdbRating': serializer.toJson<double?>(tmdbRating),
      'runtimeMinutes': serializer.toJson<int?>(runtimeMinutes),
      'status': serializer.toJson<String>(status),
      'userRating': serializer.toJson<int?>(userRating),
      'sentiment': serializer.toJson<String>(sentiment),
      'statusChangedAt': serializer.toJson<int>(statusChangedAt),
      'ratingChangedAt': serializer.toJson<int>(ratingChangedAt),
      'sentimentChangedAt': serializer.toJson<int>(sentimentChangedAt),
      'clientUpdatedAt': serializer.toJson<int>(clientUpdatedAt),
      'serverSyncedAt': serializer.toJson<int>(serverSyncedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
    };
  }

  LibraryEntriesTableData copyWith({
    String? profileId,
    String? mediaType,
    int? tmdbId,
    String? title,
    String? originalTitle,
    Value<int?> year = const Value.absent(),
    String? posterPath,
    String? genreIdsJson,
    Value<double?> tmdbRating = const Value.absent(),
    Value<int?> runtimeMinutes = const Value.absent(),
    String? status,
    Value<int?> userRating = const Value.absent(),
    String? sentiment,
    int? statusChangedAt,
    int? ratingChangedAt,
    int? sentimentChangedAt,
    int? clientUpdatedAt,
    int? serverSyncedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? updatedByDevice,
  }) => LibraryEntriesTableData(
    profileId: profileId ?? this.profileId,
    mediaType: mediaType ?? this.mediaType,
    tmdbId: tmdbId ?? this.tmdbId,
    title: title ?? this.title,
    originalTitle: originalTitle ?? this.originalTitle,
    year: year.present ? year.value : this.year,
    posterPath: posterPath ?? this.posterPath,
    genreIdsJson: genreIdsJson ?? this.genreIdsJson,
    tmdbRating: tmdbRating.present ? tmdbRating.value : this.tmdbRating,
    runtimeMinutes: runtimeMinutes.present
        ? runtimeMinutes.value
        : this.runtimeMinutes,
    status: status ?? this.status,
    userRating: userRating.present ? userRating.value : this.userRating,
    sentiment: sentiment ?? this.sentiment,
    statusChangedAt: statusChangedAt ?? this.statusChangedAt,
    ratingChangedAt: ratingChangedAt ?? this.ratingChangedAt,
    sentimentChangedAt: sentimentChangedAt ?? this.sentimentChangedAt,
    clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
    serverSyncedAt: serverSyncedAt ?? this.serverSyncedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
  );
  LibraryEntriesTableData copyWithCompanion(LibraryEntriesTableCompanion data) {
    return LibraryEntriesTableData(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      tmdbId: data.tmdbId.present ? data.tmdbId.value : this.tmdbId,
      title: data.title.present ? data.title.value : this.title,
      originalTitle: data.originalTitle.present
          ? data.originalTitle.value
          : this.originalTitle,
      year: data.year.present ? data.year.value : this.year,
      posterPath: data.posterPath.present
          ? data.posterPath.value
          : this.posterPath,
      genreIdsJson: data.genreIdsJson.present
          ? data.genreIdsJson.value
          : this.genreIdsJson,
      tmdbRating: data.tmdbRating.present
          ? data.tmdbRating.value
          : this.tmdbRating,
      runtimeMinutes: data.runtimeMinutes.present
          ? data.runtimeMinutes.value
          : this.runtimeMinutes,
      status: data.status.present ? data.status.value : this.status,
      userRating: data.userRating.present
          ? data.userRating.value
          : this.userRating,
      sentiment: data.sentiment.present ? data.sentiment.value : this.sentiment,
      statusChangedAt: data.statusChangedAt.present
          ? data.statusChangedAt.value
          : this.statusChangedAt,
      ratingChangedAt: data.ratingChangedAt.present
          ? data.ratingChangedAt.value
          : this.ratingChangedAt,
      sentimentChangedAt: data.sentimentChangedAt.present
          ? data.sentimentChangedAt.value
          : this.sentimentChangedAt,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverSyncedAt: data.serverSyncedAt.present
          ? data.serverSyncedAt.value
          : this.serverSyncedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryEntriesTableData(')
          ..write('profileId: $profileId, ')
          ..write('mediaType: $mediaType, ')
          ..write('tmdbId: $tmdbId, ')
          ..write('title: $title, ')
          ..write('originalTitle: $originalTitle, ')
          ..write('year: $year, ')
          ..write('posterPath: $posterPath, ')
          ..write('genreIdsJson: $genreIdsJson, ')
          ..write('tmdbRating: $tmdbRating, ')
          ..write('runtimeMinutes: $runtimeMinutes, ')
          ..write('status: $status, ')
          ..write('userRating: $userRating, ')
          ..write('sentiment: $sentiment, ')
          ..write('statusChangedAt: $statusChangedAt, ')
          ..write('ratingChangedAt: $ratingChangedAt, ')
          ..write('sentimentChangedAt: $sentimentChangedAt, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverSyncedAt: $serverSyncedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('updatedByDevice: $updatedByDevice')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    profileId,
    mediaType,
    tmdbId,
    title,
    originalTitle,
    year,
    posterPath,
    genreIdsJson,
    tmdbRating,
    runtimeMinutes,
    status,
    userRating,
    sentiment,
    statusChangedAt,
    ratingChangedAt,
    sentimentChangedAt,
    clientUpdatedAt,
    serverSyncedAt,
    deletedAt,
    updatedByDevice,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryEntriesTableData &&
          other.profileId == this.profileId &&
          other.mediaType == this.mediaType &&
          other.tmdbId == this.tmdbId &&
          other.title == this.title &&
          other.originalTitle == this.originalTitle &&
          other.year == this.year &&
          other.posterPath == this.posterPath &&
          other.genreIdsJson == this.genreIdsJson &&
          other.tmdbRating == this.tmdbRating &&
          other.runtimeMinutes == this.runtimeMinutes &&
          other.status == this.status &&
          other.userRating == this.userRating &&
          other.sentiment == this.sentiment &&
          other.statusChangedAt == this.statusChangedAt &&
          other.ratingChangedAt == this.ratingChangedAt &&
          other.sentimentChangedAt == this.sentimentChangedAt &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverSyncedAt == this.serverSyncedAt &&
          other.deletedAt == this.deletedAt &&
          other.updatedByDevice == this.updatedByDevice);
}

class LibraryEntriesTableCompanion
    extends UpdateCompanion<LibraryEntriesTableData> {
  final Value<String> profileId;
  final Value<String> mediaType;
  final Value<int> tmdbId;
  final Value<String> title;
  final Value<String> originalTitle;
  final Value<int?> year;
  final Value<String> posterPath;
  final Value<String> genreIdsJson;
  final Value<double?> tmdbRating;
  final Value<int?> runtimeMinutes;
  final Value<String> status;
  final Value<int?> userRating;
  final Value<String> sentiment;
  final Value<int> statusChangedAt;
  final Value<int> ratingChangedAt;
  final Value<int> sentimentChangedAt;
  final Value<int> clientUpdatedAt;
  final Value<int> serverSyncedAt;
  final Value<int?> deletedAt;
  final Value<String> updatedByDevice;
  final Value<int> rowid;
  const LibraryEntriesTableCompanion({
    this.profileId = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.tmdbId = const Value.absent(),
    this.title = const Value.absent(),
    this.originalTitle = const Value.absent(),
    this.year = const Value.absent(),
    this.posterPath = const Value.absent(),
    this.genreIdsJson = const Value.absent(),
    this.tmdbRating = const Value.absent(),
    this.runtimeMinutes = const Value.absent(),
    this.status = const Value.absent(),
    this.userRating = const Value.absent(),
    this.sentiment = const Value.absent(),
    this.statusChangedAt = const Value.absent(),
    this.ratingChangedAt = const Value.absent(),
    this.sentimentChangedAt = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverSyncedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryEntriesTableCompanion.insert({
    required String profileId,
    required String mediaType,
    required int tmdbId,
    required String title,
    this.originalTitle = const Value.absent(),
    this.year = const Value.absent(),
    this.posterPath = const Value.absent(),
    this.genreIdsJson = const Value.absent(),
    this.tmdbRating = const Value.absent(),
    this.runtimeMinutes = const Value.absent(),
    this.status = const Value.absent(),
    this.userRating = const Value.absent(),
    this.sentiment = const Value.absent(),
    this.statusChangedAt = const Value.absent(),
    this.ratingChangedAt = const Value.absent(),
    this.sentimentChangedAt = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverSyncedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       mediaType = Value(mediaType),
       tmdbId = Value(tmdbId),
       title = Value(title);
  static Insertable<LibraryEntriesTableData> custom({
    Expression<String>? profileId,
    Expression<String>? mediaType,
    Expression<int>? tmdbId,
    Expression<String>? title,
    Expression<String>? originalTitle,
    Expression<int>? year,
    Expression<String>? posterPath,
    Expression<String>? genreIdsJson,
    Expression<double>? tmdbRating,
    Expression<int>? runtimeMinutes,
    Expression<String>? status,
    Expression<int>? userRating,
    Expression<String>? sentiment,
    Expression<int>? statusChangedAt,
    Expression<int>? ratingChangedAt,
    Expression<int>? sentimentChangedAt,
    Expression<int>? clientUpdatedAt,
    Expression<int>? serverSyncedAt,
    Expression<int>? deletedAt,
    Expression<String>? updatedByDevice,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (mediaType != null) 'media_type': mediaType,
      if (tmdbId != null) 'tmdb_id': tmdbId,
      if (title != null) 'title': title,
      if (originalTitle != null) 'original_title': originalTitle,
      if (year != null) 'year': year,
      if (posterPath != null) 'poster_path': posterPath,
      if (genreIdsJson != null) 'genre_ids_json': genreIdsJson,
      if (tmdbRating != null) 'tmdb_rating': tmdbRating,
      if (runtimeMinutes != null) 'runtime_minutes': runtimeMinutes,
      if (status != null) 'status': status,
      if (userRating != null) 'user_rating': userRating,
      if (sentiment != null) 'sentiment': sentiment,
      if (statusChangedAt != null) 'status_changed_at': statusChangedAt,
      if (ratingChangedAt != null) 'rating_changed_at': ratingChangedAt,
      if (sentimentChangedAt != null)
        'sentiment_changed_at': sentimentChangedAt,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverSyncedAt != null) 'server_synced_at': serverSyncedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryEntriesTableCompanion copyWith({
    Value<String>? profileId,
    Value<String>? mediaType,
    Value<int>? tmdbId,
    Value<String>? title,
    Value<String>? originalTitle,
    Value<int?>? year,
    Value<String>? posterPath,
    Value<String>? genreIdsJson,
    Value<double?>? tmdbRating,
    Value<int?>? runtimeMinutes,
    Value<String>? status,
    Value<int?>? userRating,
    Value<String>? sentiment,
    Value<int>? statusChangedAt,
    Value<int>? ratingChangedAt,
    Value<int>? sentimentChangedAt,
    Value<int>? clientUpdatedAt,
    Value<int>? serverSyncedAt,
    Value<int?>? deletedAt,
    Value<String>? updatedByDevice,
    Value<int>? rowid,
  }) {
    return LibraryEntriesTableCompanion(
      profileId: profileId ?? this.profileId,
      mediaType: mediaType ?? this.mediaType,
      tmdbId: tmdbId ?? this.tmdbId,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      year: year ?? this.year,
      posterPath: posterPath ?? this.posterPath,
      genreIdsJson: genreIdsJson ?? this.genreIdsJson,
      tmdbRating: tmdbRating ?? this.tmdbRating,
      runtimeMinutes: runtimeMinutes ?? this.runtimeMinutes,
      status: status ?? this.status,
      userRating: userRating ?? this.userRating,
      sentiment: sentiment ?? this.sentiment,
      statusChangedAt: statusChangedAt ?? this.statusChangedAt,
      ratingChangedAt: ratingChangedAt ?? this.ratingChangedAt,
      sentimentChangedAt: sentimentChangedAt ?? this.sentimentChangedAt,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverSyncedAt: serverSyncedAt ?? this.serverSyncedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (tmdbId.present) {
      map['tmdb_id'] = Variable<int>(tmdbId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (originalTitle.present) {
      map['original_title'] = Variable<String>(originalTitle.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (posterPath.present) {
      map['poster_path'] = Variable<String>(posterPath.value);
    }
    if (genreIdsJson.present) {
      map['genre_ids_json'] = Variable<String>(genreIdsJson.value);
    }
    if (tmdbRating.present) {
      map['tmdb_rating'] = Variable<double>(tmdbRating.value);
    }
    if (runtimeMinutes.present) {
      map['runtime_minutes'] = Variable<int>(runtimeMinutes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (userRating.present) {
      map['user_rating'] = Variable<int>(userRating.value);
    }
    if (sentiment.present) {
      map['sentiment'] = Variable<String>(sentiment.value);
    }
    if (statusChangedAt.present) {
      map['status_changed_at'] = Variable<int>(statusChangedAt.value);
    }
    if (ratingChangedAt.present) {
      map['rating_changed_at'] = Variable<int>(ratingChangedAt.value);
    }
    if (sentimentChangedAt.present) {
      map['sentiment_changed_at'] = Variable<int>(sentimentChangedAt.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<int>(clientUpdatedAt.value);
    }
    if (serverSyncedAt.present) {
      map['server_synced_at'] = Variable<int>(serverSyncedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryEntriesTableCompanion(')
          ..write('profileId: $profileId, ')
          ..write('mediaType: $mediaType, ')
          ..write('tmdbId: $tmdbId, ')
          ..write('title: $title, ')
          ..write('originalTitle: $originalTitle, ')
          ..write('year: $year, ')
          ..write('posterPath: $posterPath, ')
          ..write('genreIdsJson: $genreIdsJson, ')
          ..write('tmdbRating: $tmdbRating, ')
          ..write('runtimeMinutes: $runtimeMinutes, ')
          ..write('status: $status, ')
          ..write('userRating: $userRating, ')
          ..write('sentiment: $sentiment, ')
          ..write('statusChangedAt: $statusChangedAt, ')
          ..write('ratingChangedAt: $ratingChangedAt, ')
          ..write('sentimentChangedAt: $sentimentChangedAt, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverSyncedAt: $serverSyncedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CollectionsTableTable extends CollectionsTable
    with TableInfo<$CollectionsTableTable, CollectionsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaKeysJsonMeta = const VerificationMeta(
    'mediaKeysJson',
  );
  @override
  late final GeneratedColumn<String> mediaKeysJson = GeneratedColumn<String>(
    'media_keys_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<int> clientUpdatedAt = GeneratedColumn<int>(
    'client_updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _serverSyncedAtMeta = const VerificationMeta(
    'serverSyncedAt',
  );
  @override
  late final GeneratedColumn<int> serverSyncedAt = GeneratedColumn<int>(
    'server_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    title,
    mediaKeysJson,
    clientUpdatedAt,
    serverSyncedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collections_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('media_keys_json')) {
      context.handle(
        _mediaKeysJsonMeta,
        mediaKeysJson.isAcceptableOrUnknown(
          data['media_keys_json']!,
          _mediaKeysJsonMeta,
        ),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_synced_at')) {
      context.handle(
        _serverSyncedAtMeta,
        serverSyncedAt.isAcceptableOrUnknown(
          data['server_synced_at']!,
          _serverSyncedAtMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, id};
  @override
  CollectionsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      mediaKeysJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_keys_json'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}client_updated_at'],
      )!,
      serverSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_synced_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CollectionsTableTable createAlias(String alias) {
    return $CollectionsTableTable(attachedDatabase, alias);
  }
}

class CollectionsTableData extends DataClass
    implements Insertable<CollectionsTableData> {
  final String id;
  final String profileId;
  final String title;
  final String mediaKeysJson;
  final int clientUpdatedAt;
  final int serverSyncedAt;
  final int? deletedAt;
  const CollectionsTableData({
    required this.id,
    required this.profileId,
    required this.title,
    required this.mediaKeysJson,
    required this.clientUpdatedAt,
    required this.serverSyncedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['title'] = Variable<String>(title);
    map['media_keys_json'] = Variable<String>(mediaKeysJson);
    map['client_updated_at'] = Variable<int>(clientUpdatedAt);
    map['server_synced_at'] = Variable<int>(serverSyncedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  CollectionsTableCompanion toCompanion(bool nullToAbsent) {
    return CollectionsTableCompanion(
      id: Value(id),
      profileId: Value(profileId),
      title: Value(title),
      mediaKeysJson: Value(mediaKeysJson),
      clientUpdatedAt: Value(clientUpdatedAt),
      serverSyncedAt: Value(serverSyncedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory CollectionsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionsTableData(
      id: serializer.fromJson<String>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      title: serializer.fromJson<String>(json['title']),
      mediaKeysJson: serializer.fromJson<String>(json['mediaKeysJson']),
      clientUpdatedAt: serializer.fromJson<int>(json['clientUpdatedAt']),
      serverSyncedAt: serializer.fromJson<int>(json['serverSyncedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'profileId': serializer.toJson<String>(profileId),
      'title': serializer.toJson<String>(title),
      'mediaKeysJson': serializer.toJson<String>(mediaKeysJson),
      'clientUpdatedAt': serializer.toJson<int>(clientUpdatedAt),
      'serverSyncedAt': serializer.toJson<int>(serverSyncedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  CollectionsTableData copyWith({
    String? id,
    String? profileId,
    String? title,
    String? mediaKeysJson,
    int? clientUpdatedAt,
    int? serverSyncedAt,
    Value<int?> deletedAt = const Value.absent(),
  }) => CollectionsTableData(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    title: title ?? this.title,
    mediaKeysJson: mediaKeysJson ?? this.mediaKeysJson,
    clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
    serverSyncedAt: serverSyncedAt ?? this.serverSyncedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  CollectionsTableData copyWithCompanion(CollectionsTableCompanion data) {
    return CollectionsTableData(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      title: data.title.present ? data.title.value : this.title,
      mediaKeysJson: data.mediaKeysJson.present
          ? data.mediaKeysJson.value
          : this.mediaKeysJson,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverSyncedAt: data.serverSyncedAt.present
          ? data.serverSyncedAt.value
          : this.serverSyncedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionsTableData(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('title: $title, ')
          ..write('mediaKeysJson: $mediaKeysJson, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverSyncedAt: $serverSyncedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    profileId,
    title,
    mediaKeysJson,
    clientUpdatedAt,
    serverSyncedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionsTableData &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.title == this.title &&
          other.mediaKeysJson == this.mediaKeysJson &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverSyncedAt == this.serverSyncedAt &&
          other.deletedAt == this.deletedAt);
}

class CollectionsTableCompanion extends UpdateCompanion<CollectionsTableData> {
  final Value<String> id;
  final Value<String> profileId;
  final Value<String> title;
  final Value<String> mediaKeysJson;
  final Value<int> clientUpdatedAt;
  final Value<int> serverSyncedAt;
  final Value<int?> deletedAt;
  final Value<int> rowid;
  const CollectionsTableCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.title = const Value.absent(),
    this.mediaKeysJson = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverSyncedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionsTableCompanion.insert({
    required String id,
    required String profileId,
    required String title,
    this.mediaKeysJson = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverSyncedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       profileId = Value(profileId),
       title = Value(title);
  static Insertable<CollectionsTableData> custom({
    Expression<String>? id,
    Expression<String>? profileId,
    Expression<String>? title,
    Expression<String>? mediaKeysJson,
    Expression<int>? clientUpdatedAt,
    Expression<int>? serverSyncedAt,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (title != null) 'title': title,
      if (mediaKeysJson != null) 'media_keys_json': mediaKeysJson,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverSyncedAt != null) 'server_synced_at': serverSyncedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? profileId,
    Value<String>? title,
    Value<String>? mediaKeysJson,
    Value<int>? clientUpdatedAt,
    Value<int>? serverSyncedAt,
    Value<int?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CollectionsTableCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      title: title ?? this.title,
      mediaKeysJson: mediaKeysJson ?? this.mediaKeysJson,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverSyncedAt: serverSyncedAt ?? this.serverSyncedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (mediaKeysJson.present) {
      map['media_keys_json'] = Variable<String>(mediaKeysJson.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<int>(clientUpdatedAt.value);
    }
    if (serverSyncedAt.present) {
      map['server_synced_at'] = Variable<int>(serverSyncedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionsTableCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('title: $title, ')
          ..write('mediaKeysJson: $mediaKeysJson, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverSyncedAt: $serverSyncedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingChangesTableTable extends PendingChangesTable
    with TableInfo<$PendingChangesTableTable, PendingChangesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingChangesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _accountUidMeta = const VerificationMeta(
    'accountUid',
  );
  @override
  late final GeneratedColumn<String> accountUid = GeneratedColumn<String>(
    'account_uid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityKeyMeta = const VerificationMeta(
    'entityKey',
  );
  @override
  late final GeneratedColumn<String> entityKey = GeneratedColumn<String>(
    'entity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountUid,
    entityType,
    profileId,
    entityKey,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_changes_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingChangesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_uid')) {
      context.handle(
        _accountUidMeta,
        accountUid.isAcceptableOrUnknown(data['account_uid']!, _accountUidMeta),
      );
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('entity_key')) {
      context.handle(
        _entityKeyMeta,
        entityKey.isAcceptableOrUnknown(data['entity_key']!, _entityKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_entityKeyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingChangesTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingChangesTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      accountUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_uid'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      entityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_key'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PendingChangesTableTable createAlias(String alias) {
    return $PendingChangesTableTable(attachedDatabase, alias);
  }
}

class PendingChangesTableData extends DataClass
    implements Insertable<PendingChangesTableData> {
  final int id;
  final String accountUid;
  final String entityType;
  final String profileId;
  final String entityKey;
  final int createdAt;
  const PendingChangesTableData({
    required this.id,
    required this.accountUid,
    required this.entityType,
    required this.profileId,
    required this.entityKey,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_uid'] = Variable<String>(accountUid);
    map['entity_type'] = Variable<String>(entityType);
    map['profile_id'] = Variable<String>(profileId);
    map['entity_key'] = Variable<String>(entityKey);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  PendingChangesTableCompanion toCompanion(bool nullToAbsent) {
    return PendingChangesTableCompanion(
      id: Value(id),
      accountUid: Value(accountUid),
      entityType: Value(entityType),
      profileId: Value(profileId),
      entityKey: Value(entityKey),
      createdAt: Value(createdAt),
    );
  }

  factory PendingChangesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingChangesTableData(
      id: serializer.fromJson<int>(json['id']),
      accountUid: serializer.fromJson<String>(json['accountUid']),
      entityType: serializer.fromJson<String>(json['entityType']),
      profileId: serializer.fromJson<String>(json['profileId']),
      entityKey: serializer.fromJson<String>(json['entityKey']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'accountUid': serializer.toJson<String>(accountUid),
      'entityType': serializer.toJson<String>(entityType),
      'profileId': serializer.toJson<String>(profileId),
      'entityKey': serializer.toJson<String>(entityKey),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  PendingChangesTableData copyWith({
    int? id,
    String? accountUid,
    String? entityType,
    String? profileId,
    String? entityKey,
    int? createdAt,
  }) => PendingChangesTableData(
    id: id ?? this.id,
    accountUid: accountUid ?? this.accountUid,
    entityType: entityType ?? this.entityType,
    profileId: profileId ?? this.profileId,
    entityKey: entityKey ?? this.entityKey,
    createdAt: createdAt ?? this.createdAt,
  );
  PendingChangesTableData copyWithCompanion(PendingChangesTableCompanion data) {
    return PendingChangesTableData(
      id: data.id.present ? data.id.value : this.id,
      accountUid: data.accountUid.present
          ? data.accountUid.value
          : this.accountUid,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      entityKey: data.entityKey.present ? data.entityKey.value : this.entityKey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingChangesTableData(')
          ..write('id: $id, ')
          ..write('accountUid: $accountUid, ')
          ..write('entityType: $entityType, ')
          ..write('profileId: $profileId, ')
          ..write('entityKey: $entityKey, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, accountUid, entityType, profileId, entityKey, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingChangesTableData &&
          other.id == this.id &&
          other.accountUid == this.accountUid &&
          other.entityType == this.entityType &&
          other.profileId == this.profileId &&
          other.entityKey == this.entityKey &&
          other.createdAt == this.createdAt);
}

class PendingChangesTableCompanion
    extends UpdateCompanion<PendingChangesTableData> {
  final Value<int> id;
  final Value<String> accountUid;
  final Value<String> entityType;
  final Value<String> profileId;
  final Value<String> entityKey;
  final Value<int> createdAt;
  const PendingChangesTableCompanion({
    this.id = const Value.absent(),
    this.accountUid = const Value.absent(),
    this.entityType = const Value.absent(),
    this.profileId = const Value.absent(),
    this.entityKey = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PendingChangesTableCompanion.insert({
    this.id = const Value.absent(),
    this.accountUid = const Value.absent(),
    required String entityType,
    required String profileId,
    required String entityKey,
    required int createdAt,
  }) : entityType = Value(entityType),
       profileId = Value(profileId),
       entityKey = Value(entityKey),
       createdAt = Value(createdAt);
  static Insertable<PendingChangesTableData> custom({
    Expression<int>? id,
    Expression<String>? accountUid,
    Expression<String>? entityType,
    Expression<String>? profileId,
    Expression<String>? entityKey,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountUid != null) 'account_uid': accountUid,
      if (entityType != null) 'entity_type': entityType,
      if (profileId != null) 'profile_id': profileId,
      if (entityKey != null) 'entity_key': entityKey,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PendingChangesTableCompanion copyWith({
    Value<int>? id,
    Value<String>? accountUid,
    Value<String>? entityType,
    Value<String>? profileId,
    Value<String>? entityKey,
    Value<int>? createdAt,
  }) {
    return PendingChangesTableCompanion(
      id: id ?? this.id,
      accountUid: accountUid ?? this.accountUid,
      entityType: entityType ?? this.entityType,
      profileId: profileId ?? this.profileId,
      entityKey: entityKey ?? this.entityKey,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountUid.present) {
      map['account_uid'] = Variable<String>(accountUid.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (entityKey.present) {
      map['entity_key'] = Variable<String>(entityKey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingChangesTableCompanion(')
          ..write('id: $id, ')
          ..write('accountUid: $accountUid, ')
          ..write('entityType: $entityType, ')
          ..write('profileId: $profileId, ')
          ..write('entityKey: $entityKey, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CachedDetailsTableTable extends CachedDetailsTable
    with TableInfo<$CachedDetailsTableTable, CachedDetailsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedDetailsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaKeyMeta = const VerificationMeta(
    'mediaKey',
  );
  @override
  late final GeneratedColumn<String> mediaKey = GeneratedColumn<String>(
    'media_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [mediaKey, payloadJson, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_details_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedDetailsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_key')) {
      context.handle(
        _mediaKeyMeta,
        mediaKey.isAcceptableOrUnknown(data['media_key']!, _mediaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaKeyMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaKey};
  @override
  CachedDetailsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedDetailsTableData(
      mediaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_key'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedDetailsTableTable createAlias(String alias) {
    return $CachedDetailsTableTable(attachedDatabase, alias);
  }
}

class CachedDetailsTableData extends DataClass
    implements Insertable<CachedDetailsTableData> {
  final String mediaKey;
  final String payloadJson;
  final int cachedAt;
  const CachedDetailsTableData({
    required this.mediaKey,
    required this.payloadJson,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_key'] = Variable<String>(mediaKey);
    map['payload_json'] = Variable<String>(payloadJson);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  CachedDetailsTableCompanion toCompanion(bool nullToAbsent) {
    return CachedDetailsTableCompanion(
      mediaKey: Value(mediaKey),
      payloadJson: Value(payloadJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedDetailsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedDetailsTableData(
      mediaKey: serializer.fromJson<String>(json['mediaKey']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaKey': serializer.toJson<String>(mediaKey),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  CachedDetailsTableData copyWith({
    String? mediaKey,
    String? payloadJson,
    int? cachedAt,
  }) => CachedDetailsTableData(
    mediaKey: mediaKey ?? this.mediaKey,
    payloadJson: payloadJson ?? this.payloadJson,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedDetailsTableData copyWithCompanion(CachedDetailsTableCompanion data) {
    return CachedDetailsTableData(
      mediaKey: data.mediaKey.present ? data.mediaKey.value : this.mediaKey,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedDetailsTableData(')
          ..write('mediaKey: $mediaKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mediaKey, payloadJson, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedDetailsTableData &&
          other.mediaKey == this.mediaKey &&
          other.payloadJson == this.payloadJson &&
          other.cachedAt == this.cachedAt);
}

class CachedDetailsTableCompanion
    extends UpdateCompanion<CachedDetailsTableData> {
  final Value<String> mediaKey;
  final Value<String> payloadJson;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const CachedDetailsTableCompanion({
    this.mediaKey = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedDetailsTableCompanion.insert({
    required String mediaKey,
    required String payloadJson,
    required int cachedAt,
    this.rowid = const Value.absent(),
  }) : mediaKey = Value(mediaKey),
       payloadJson = Value(payloadJson),
       cachedAt = Value(cachedAt);
  static Insertable<CachedDetailsTableData> custom({
    Expression<String>? mediaKey,
    Expression<String>? payloadJson,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaKey != null) 'media_key': mediaKey,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedDetailsTableCompanion copyWith({
    Value<String>? mediaKey,
    Value<String>? payloadJson,
    Value<int>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedDetailsTableCompanion(
      mediaKey: mediaKey ?? this.mediaKey,
      payloadJson: payloadJson ?? this.payloadJson,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaKey.present) {
      map['media_key'] = Variable<String>(mediaKey.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedDetailsTableCompanion(')
          ..write('mediaKey: $mediaKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProfilesTableTable profilesTable = $ProfilesTableTable(this);
  late final $LibraryEntriesTableTable libraryEntriesTable =
      $LibraryEntriesTableTable(this);
  late final $CollectionsTableTable collectionsTable = $CollectionsTableTable(
    this,
  );
  late final $PendingChangesTableTable pendingChangesTable =
      $PendingChangesTableTable(this);
  late final $CachedDetailsTableTable cachedDetailsTable =
      $CachedDetailsTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    profilesTable,
    libraryEntriesTable,
    collectionsTable,
    pendingChangesTable,
    cachedDetailsTable,
  ];
}

typedef $$ProfilesTableTableCreateCompanionBuilder =
    ProfilesTableCompanion Function({
      required String id,
      required String name,
      Value<String> excludedGenresJson,
      Value<String> favoriteGenresJson,
      Value<String> contentLanguage,
      Value<bool> personalized,
      Value<int> clientUpdatedAt,
      Value<int> serverSyncedAt,
      Value<int?> deletedAt,
      Value<int> rowid,
    });
typedef $$ProfilesTableTableUpdateCompanionBuilder =
    ProfilesTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> excludedGenresJson,
      Value<String> favoriteGenresJson,
      Value<String> contentLanguage,
      Value<bool> personalized,
      Value<int> clientUpdatedAt,
      Value<int> serverSyncedAt,
      Value<int?> deletedAt,
      Value<int> rowid,
    });

class $$ProfilesTableTableFilterComposer
    extends Composer<_$AppDatabase, $ProfilesTableTable> {
  $$ProfilesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get excludedGenresJson => $composableBuilder(
    column: $table.excludedGenresJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get favoriteGenresJson => $composableBuilder(
    column: $table.favoriteGenresJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentLanguage => $composableBuilder(
    column: $table.contentLanguage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get personalized => $composableBuilder(
    column: $table.personalized,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSyncedAt => $composableBuilder(
    column: $table.serverSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfilesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfilesTableTable> {
  $$ProfilesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get excludedGenresJson => $composableBuilder(
    column: $table.excludedGenresJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get favoriteGenresJson => $composableBuilder(
    column: $table.favoriteGenresJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentLanguage => $composableBuilder(
    column: $table.contentLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get personalized => $composableBuilder(
    column: $table.personalized,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSyncedAt => $composableBuilder(
    column: $table.serverSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfilesTableTable> {
  $$ProfilesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get excludedGenresJson => $composableBuilder(
    column: $table.excludedGenresJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get favoriteGenresJson => $composableBuilder(
    column: $table.favoriteGenresJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentLanguage => $composableBuilder(
    column: $table.contentLanguage,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get personalized => $composableBuilder(
    column: $table.personalized,
    builder: (column) => column,
  );

  GeneratedColumn<int> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverSyncedAt => $composableBuilder(
    column: $table.serverSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ProfilesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfilesTableTable,
          ProfilesTableData,
          $$ProfilesTableTableFilterComposer,
          $$ProfilesTableTableOrderingComposer,
          $$ProfilesTableTableAnnotationComposer,
          $$ProfilesTableTableCreateCompanionBuilder,
          $$ProfilesTableTableUpdateCompanionBuilder,
          (
            ProfilesTableData,
            BaseReferences<
              _$AppDatabase,
              $ProfilesTableTable,
              ProfilesTableData
            >,
          ),
          ProfilesTableData,
          PrefetchHooks Function()
        > {
  $$ProfilesTableTableTableManager(_$AppDatabase db, $ProfilesTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> excludedGenresJson = const Value.absent(),
                Value<String> favoriteGenresJson = const Value.absent(),
                Value<String> contentLanguage = const Value.absent(),
                Value<bool> personalized = const Value.absent(),
                Value<int> clientUpdatedAt = const Value.absent(),
                Value<int> serverSyncedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesTableCompanion(
                id: id,
                name: name,
                excludedGenresJson: excludedGenresJson,
                favoriteGenresJson: favoriteGenresJson,
                contentLanguage: contentLanguage,
                personalized: personalized,
                clientUpdatedAt: clientUpdatedAt,
                serverSyncedAt: serverSyncedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> excludedGenresJson = const Value.absent(),
                Value<String> favoriteGenresJson = const Value.absent(),
                Value<String> contentLanguage = const Value.absent(),
                Value<bool> personalized = const Value.absent(),
                Value<int> clientUpdatedAt = const Value.absent(),
                Value<int> serverSyncedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesTableCompanion.insert(
                id: id,
                name: name,
                excludedGenresJson: excludedGenresJson,
                favoriteGenresJson: favoriteGenresJson,
                contentLanguage: contentLanguage,
                personalized: personalized,
                clientUpdatedAt: clientUpdatedAt,
                serverSyncedAt: serverSyncedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProfilesTableTable, ProfilesTableData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ProfilesTableTable,
                    ProfilesTableData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfilesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfilesTableTable,
      ProfilesTableData,
      $$ProfilesTableTableFilterComposer,
      $$ProfilesTableTableOrderingComposer,
      $$ProfilesTableTableAnnotationComposer,
      $$ProfilesTableTableCreateCompanionBuilder,
      $$ProfilesTableTableUpdateCompanionBuilder,
      (
        ProfilesTableData,
        BaseReferences<_$AppDatabase, $ProfilesTableTable, ProfilesTableData>,
      ),
      ProfilesTableData,
      PrefetchHooks Function()
    >;
typedef $$LibraryEntriesTableTableCreateCompanionBuilder =
    LibraryEntriesTableCompanion Function({
      required String profileId,
      required String mediaType,
      required int tmdbId,
      required String title,
      Value<String> originalTitle,
      Value<int?> year,
      Value<String> posterPath,
      Value<String> genreIdsJson,
      Value<double?> tmdbRating,
      Value<int?> runtimeMinutes,
      Value<String> status,
      Value<int?> userRating,
      Value<String> sentiment,
      Value<int> statusChangedAt,
      Value<int> ratingChangedAt,
      Value<int> sentimentChangedAt,
      Value<int> clientUpdatedAt,
      Value<int> serverSyncedAt,
      Value<int?> deletedAt,
      Value<String> updatedByDevice,
      Value<int> rowid,
    });
typedef $$LibraryEntriesTableTableUpdateCompanionBuilder =
    LibraryEntriesTableCompanion Function({
      Value<String> profileId,
      Value<String> mediaType,
      Value<int> tmdbId,
      Value<String> title,
      Value<String> originalTitle,
      Value<int?> year,
      Value<String> posterPath,
      Value<String> genreIdsJson,
      Value<double?> tmdbRating,
      Value<int?> runtimeMinutes,
      Value<String> status,
      Value<int?> userRating,
      Value<String> sentiment,
      Value<int> statusChangedAt,
      Value<int> ratingChangedAt,
      Value<int> sentimentChangedAt,
      Value<int> clientUpdatedAt,
      Value<int> serverSyncedAt,
      Value<int?> deletedAt,
      Value<String> updatedByDevice,
      Value<int> rowid,
    });

class $$LibraryEntriesTableTableFilterComposer
    extends Composer<_$AppDatabase, $LibraryEntriesTableTable> {
  $$LibraryEntriesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tmdbId => $composableBuilder(
    column: $table.tmdbId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalTitle => $composableBuilder(
    column: $table.originalTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get posterPath => $composableBuilder(
    column: $table.posterPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genreIdsJson => $composableBuilder(
    column: $table.genreIdsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get tmdbRating => $composableBuilder(
    column: $table.tmdbRating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get runtimeMinutes => $composableBuilder(
    column: $table.runtimeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get userRating => $composableBuilder(
    column: $table.userRating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sentiment => $composableBuilder(
    column: $table.sentiment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get statusChangedAt => $composableBuilder(
    column: $table.statusChangedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ratingChangedAt => $composableBuilder(
    column: $table.ratingChangedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sentimentChangedAt => $composableBuilder(
    column: $table.sentimentChangedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSyncedAt => $composableBuilder(
    column: $table.serverSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LibraryEntriesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $LibraryEntriesTableTable> {
  $$LibraryEntriesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tmdbId => $composableBuilder(
    column: $table.tmdbId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalTitle => $composableBuilder(
    column: $table.originalTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get posterPath => $composableBuilder(
    column: $table.posterPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genreIdsJson => $composableBuilder(
    column: $table.genreIdsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get tmdbRating => $composableBuilder(
    column: $table.tmdbRating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get runtimeMinutes => $composableBuilder(
    column: $table.runtimeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get userRating => $composableBuilder(
    column: $table.userRating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sentiment => $composableBuilder(
    column: $table.sentiment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get statusChangedAt => $composableBuilder(
    column: $table.statusChangedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ratingChangedAt => $composableBuilder(
    column: $table.ratingChangedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sentimentChangedAt => $composableBuilder(
    column: $table.sentimentChangedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSyncedAt => $composableBuilder(
    column: $table.serverSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LibraryEntriesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $LibraryEntriesTableTable> {
  $$LibraryEntriesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<int> get tmdbId =>
      $composableBuilder(column: $table.tmdbId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get originalTitle => $composableBuilder(
    column: $table.originalTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get posterPath => $composableBuilder(
    column: $table.posterPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get genreIdsJson => $composableBuilder(
    column: $table.genreIdsJson,
    builder: (column) => column,
  );

  GeneratedColumn<double> get tmdbRating => $composableBuilder(
    column: $table.tmdbRating,
    builder: (column) => column,
  );

  GeneratedColumn<int> get runtimeMinutes => $composableBuilder(
    column: $table.runtimeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get userRating => $composableBuilder(
    column: $table.userRating,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sentiment =>
      $composableBuilder(column: $table.sentiment, builder: (column) => column);

  GeneratedColumn<int> get statusChangedAt => $composableBuilder(
    column: $table.statusChangedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get ratingChangedAt => $composableBuilder(
    column: $table.ratingChangedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sentimentChangedAt => $composableBuilder(
    column: $table.sentimentChangedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverSyncedAt => $composableBuilder(
    column: $table.serverSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );
}

class $$LibraryEntriesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LibraryEntriesTableTable,
          LibraryEntriesTableData,
          $$LibraryEntriesTableTableFilterComposer,
          $$LibraryEntriesTableTableOrderingComposer,
          $$LibraryEntriesTableTableAnnotationComposer,
          $$LibraryEntriesTableTableCreateCompanionBuilder,
          $$LibraryEntriesTableTableUpdateCompanionBuilder,
          (
            LibraryEntriesTableData,
            BaseReferences<
              _$AppDatabase,
              $LibraryEntriesTableTable,
              LibraryEntriesTableData
            >,
          ),
          LibraryEntriesTableData,
          PrefetchHooks Function()
        > {
  $$LibraryEntriesTableTableTableManager(
    _$AppDatabase db,
    $LibraryEntriesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryEntriesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryEntriesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LibraryEntriesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> mediaType = const Value.absent(),
                Value<int> tmdbId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> originalTitle = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String> posterPath = const Value.absent(),
                Value<String> genreIdsJson = const Value.absent(),
                Value<double?> tmdbRating = const Value.absent(),
                Value<int?> runtimeMinutes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> userRating = const Value.absent(),
                Value<String> sentiment = const Value.absent(),
                Value<int> statusChangedAt = const Value.absent(),
                Value<int> ratingChangedAt = const Value.absent(),
                Value<int> sentimentChangedAt = const Value.absent(),
                Value<int> clientUpdatedAt = const Value.absent(),
                Value<int> serverSyncedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryEntriesTableCompanion(
                profileId: profileId,
                mediaType: mediaType,
                tmdbId: tmdbId,
                title: title,
                originalTitle: originalTitle,
                year: year,
                posterPath: posterPath,
                genreIdsJson: genreIdsJson,
                tmdbRating: tmdbRating,
                runtimeMinutes: runtimeMinutes,
                status: status,
                userRating: userRating,
                sentiment: sentiment,
                statusChangedAt: statusChangedAt,
                ratingChangedAt: ratingChangedAt,
                sentimentChangedAt: sentimentChangedAt,
                clientUpdatedAt: clientUpdatedAt,
                serverSyncedAt: serverSyncedAt,
                deletedAt: deletedAt,
                updatedByDevice: updatedByDevice,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required String mediaType,
                required int tmdbId,
                required String title,
                Value<String> originalTitle = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String> posterPath = const Value.absent(),
                Value<String> genreIdsJson = const Value.absent(),
                Value<double?> tmdbRating = const Value.absent(),
                Value<int?> runtimeMinutes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> userRating = const Value.absent(),
                Value<String> sentiment = const Value.absent(),
                Value<int> statusChangedAt = const Value.absent(),
                Value<int> ratingChangedAt = const Value.absent(),
                Value<int> sentimentChangedAt = const Value.absent(),
                Value<int> clientUpdatedAt = const Value.absent(),
                Value<int> serverSyncedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryEntriesTableCompanion.insert(
                profileId: profileId,
                mediaType: mediaType,
                tmdbId: tmdbId,
                title: title,
                originalTitle: originalTitle,
                year: year,
                posterPath: posterPath,
                genreIdsJson: genreIdsJson,
                tmdbRating: tmdbRating,
                runtimeMinutes: runtimeMinutes,
                status: status,
                userRating: userRating,
                sentiment: sentiment,
                statusChangedAt: statusChangedAt,
                ratingChangedAt: ratingChangedAt,
                sentimentChangedAt: sentimentChangedAt,
                clientUpdatedAt: clientUpdatedAt,
                serverSyncedAt: serverSyncedAt,
                deletedAt: deletedAt,
                updatedByDevice: updatedByDevice,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $LibraryEntriesTableTable,
                    LibraryEntriesTableData
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LibraryEntriesTableTable,
                    LibraryEntriesTableData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LibraryEntriesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LibraryEntriesTableTable,
      LibraryEntriesTableData,
      $$LibraryEntriesTableTableFilterComposer,
      $$LibraryEntriesTableTableOrderingComposer,
      $$LibraryEntriesTableTableAnnotationComposer,
      $$LibraryEntriesTableTableCreateCompanionBuilder,
      $$LibraryEntriesTableTableUpdateCompanionBuilder,
      (
        LibraryEntriesTableData,
        BaseReferences<
          _$AppDatabase,
          $LibraryEntriesTableTable,
          LibraryEntriesTableData
        >,
      ),
      LibraryEntriesTableData,
      PrefetchHooks Function()
    >;
typedef $$CollectionsTableTableCreateCompanionBuilder =
    CollectionsTableCompanion Function({
      required String id,
      required String profileId,
      required String title,
      Value<String> mediaKeysJson,
      Value<int> clientUpdatedAt,
      Value<int> serverSyncedAt,
      Value<int?> deletedAt,
      Value<int> rowid,
    });
typedef $$CollectionsTableTableUpdateCompanionBuilder =
    CollectionsTableCompanion Function({
      Value<String> id,
      Value<String> profileId,
      Value<String> title,
      Value<String> mediaKeysJson,
      Value<int> clientUpdatedAt,
      Value<int> serverSyncedAt,
      Value<int?> deletedAt,
      Value<int> rowid,
    });

class $$CollectionsTableTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionsTableTable> {
  $$CollectionsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaKeysJson => $composableBuilder(
    column: $table.mediaKeysJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSyncedAt => $composableBuilder(
    column: $table.serverSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CollectionsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionsTableTable> {
  $$CollectionsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaKeysJson => $composableBuilder(
    column: $table.mediaKeysJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSyncedAt => $composableBuilder(
    column: $table.serverSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionsTableTable> {
  $$CollectionsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get mediaKeysJson => $composableBuilder(
    column: $table.mediaKeysJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverSyncedAt => $composableBuilder(
    column: $table.serverSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$CollectionsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionsTableTable,
          CollectionsTableData,
          $$CollectionsTableTableFilterComposer,
          $$CollectionsTableTableOrderingComposer,
          $$CollectionsTableTableAnnotationComposer,
          $$CollectionsTableTableCreateCompanionBuilder,
          $$CollectionsTableTableUpdateCompanionBuilder,
          (
            CollectionsTableData,
            BaseReferences<
              _$AppDatabase,
              $CollectionsTableTable,
              CollectionsTableData
            >,
          ),
          CollectionsTableData,
          PrefetchHooks Function()
        > {
  $$CollectionsTableTableTableManager(
    _$AppDatabase db,
    $CollectionsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> mediaKeysJson = const Value.absent(),
                Value<int> clientUpdatedAt = const Value.absent(),
                Value<int> serverSyncedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsTableCompanion(
                id: id,
                profileId: profileId,
                title: title,
                mediaKeysJson: mediaKeysJson,
                clientUpdatedAt: clientUpdatedAt,
                serverSyncedAt: serverSyncedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String profileId,
                required String title,
                Value<String> mediaKeysJson = const Value.absent(),
                Value<int> clientUpdatedAt = const Value.absent(),
                Value<int> serverSyncedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsTableCompanion.insert(
                id: id,
                profileId: profileId,
                title: title,
                mediaKeysJson: mediaKeysJson,
                clientUpdatedAt: clientUpdatedAt,
                serverSyncedAt: serverSyncedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CollectionsTableTable, CollectionsTableData>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $CollectionsTableTable,
                    CollectionsTableData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CollectionsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionsTableTable,
      CollectionsTableData,
      $$CollectionsTableTableFilterComposer,
      $$CollectionsTableTableOrderingComposer,
      $$CollectionsTableTableAnnotationComposer,
      $$CollectionsTableTableCreateCompanionBuilder,
      $$CollectionsTableTableUpdateCompanionBuilder,
      (
        CollectionsTableData,
        BaseReferences<
          _$AppDatabase,
          $CollectionsTableTable,
          CollectionsTableData
        >,
      ),
      CollectionsTableData,
      PrefetchHooks Function()
    >;
typedef $$PendingChangesTableTableCreateCompanionBuilder =
    PendingChangesTableCompanion Function({
      Value<int> id,
      Value<String> accountUid,
      required String entityType,
      required String profileId,
      required String entityKey,
      required int createdAt,
    });
typedef $$PendingChangesTableTableUpdateCompanionBuilder =
    PendingChangesTableCompanion Function({
      Value<int> id,
      Value<String> accountUid,
      Value<String> entityType,
      Value<String> profileId,
      Value<String> entityKey,
      Value<int> createdAt,
    });

class $$PendingChangesTableTableFilterComposer
    extends Composer<_$AppDatabase, $PendingChangesTableTable> {
  $$PendingChangesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountUid => $composableBuilder(
    column: $table.accountUid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityKey => $composableBuilder(
    column: $table.entityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingChangesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingChangesTableTable> {
  $$PendingChangesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountUid => $composableBuilder(
    column: $table.accountUid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityKey => $composableBuilder(
    column: $table.entityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingChangesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingChangesTableTable> {
  $$PendingChangesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountUid => $composableBuilder(
    column: $table.accountUid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get entityKey =>
      $composableBuilder(column: $table.entityKey, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PendingChangesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingChangesTableTable,
          PendingChangesTableData,
          $$PendingChangesTableTableFilterComposer,
          $$PendingChangesTableTableOrderingComposer,
          $$PendingChangesTableTableAnnotationComposer,
          $$PendingChangesTableTableCreateCompanionBuilder,
          $$PendingChangesTableTableUpdateCompanionBuilder,
          (
            PendingChangesTableData,
            BaseReferences<
              _$AppDatabase,
              $PendingChangesTableTable,
              PendingChangesTableData
            >,
          ),
          PendingChangesTableData,
          PrefetchHooks Function()
        > {
  $$PendingChangesTableTableTableManager(
    _$AppDatabase db,
    $PendingChangesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingChangesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingChangesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PendingChangesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> accountUid = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> entityKey = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => PendingChangesTableCompanion(
                id: id,
                accountUid: accountUid,
                entityType: entityType,
                profileId: profileId,
                entityKey: entityKey,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> accountUid = const Value.absent(),
                required String entityType,
                required String profileId,
                required String entityKey,
                required int createdAt,
              }) => PendingChangesTableCompanion.insert(
                id: id,
                accountUid: accountUid,
                entityType: entityType,
                profileId: profileId,
                entityKey: entityKey,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $PendingChangesTableTable,
                    PendingChangesTableData
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PendingChangesTableTable,
                    PendingChangesTableData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingChangesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingChangesTableTable,
      PendingChangesTableData,
      $$PendingChangesTableTableFilterComposer,
      $$PendingChangesTableTableOrderingComposer,
      $$PendingChangesTableTableAnnotationComposer,
      $$PendingChangesTableTableCreateCompanionBuilder,
      $$PendingChangesTableTableUpdateCompanionBuilder,
      (
        PendingChangesTableData,
        BaseReferences<
          _$AppDatabase,
          $PendingChangesTableTable,
          PendingChangesTableData
        >,
      ),
      PendingChangesTableData,
      PrefetchHooks Function()
    >;
typedef $$CachedDetailsTableTableCreateCompanionBuilder =
    CachedDetailsTableCompanion Function({
      required String mediaKey,
      required String payloadJson,
      required int cachedAt,
      Value<int> rowid,
    });
typedef $$CachedDetailsTableTableUpdateCompanionBuilder =
    CachedDetailsTableCompanion Function({
      Value<String> mediaKey,
      Value<String> payloadJson,
      Value<int> cachedAt,
      Value<int> rowid,
    });

class $$CachedDetailsTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedDetailsTableTable> {
  $$CachedDetailsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedDetailsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedDetailsTableTable> {
  $$CachedDetailsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedDetailsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedDetailsTableTable> {
  $$CachedDetailsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaKey =>
      $composableBuilder(column: $table.mediaKey, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedDetailsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedDetailsTableTable,
          CachedDetailsTableData,
          $$CachedDetailsTableTableFilterComposer,
          $$CachedDetailsTableTableOrderingComposer,
          $$CachedDetailsTableTableAnnotationComposer,
          $$CachedDetailsTableTableCreateCompanionBuilder,
          $$CachedDetailsTableTableUpdateCompanionBuilder,
          (
            CachedDetailsTableData,
            BaseReferences<
              _$AppDatabase,
              $CachedDetailsTableTable,
              CachedDetailsTableData
            >,
          ),
          CachedDetailsTableData,
          PrefetchHooks Function()
        > {
  $$CachedDetailsTableTableTableManager(
    _$AppDatabase db,
    $CachedDetailsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedDetailsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedDetailsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedDetailsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> mediaKey = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedDetailsTableCompanion(
                mediaKey: mediaKey,
                payloadJson: payloadJson,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaKey,
                required String payloadJson,
                required int cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedDetailsTableCompanion.insert(
                mediaKey: mediaKey,
                payloadJson: payloadJson,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedDetailsTableTable, CachedDetailsTableData>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedDetailsTableTable,
                    CachedDetailsTableData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedDetailsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedDetailsTableTable,
      CachedDetailsTableData,
      $$CachedDetailsTableTableFilterComposer,
      $$CachedDetailsTableTableOrderingComposer,
      $$CachedDetailsTableTableAnnotationComposer,
      $$CachedDetailsTableTableCreateCompanionBuilder,
      $$CachedDetailsTableTableUpdateCompanionBuilder,
      (
        CachedDetailsTableData,
        BaseReferences<
          _$AppDatabase,
          $CachedDetailsTableTable,
          CachedDetailsTableData
        >,
      ),
      CachedDetailsTableData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProfilesTableTableTableManager get profilesTable =>
      $$ProfilesTableTableTableManager(_db, _db.profilesTable);
  $$LibraryEntriesTableTableTableManager get libraryEntriesTable =>
      $$LibraryEntriesTableTableTableManager(_db, _db.libraryEntriesTable);
  $$CollectionsTableTableTableManager get collectionsTable =>
      $$CollectionsTableTableTableManager(_db, _db.collectionsTable);
  $$PendingChangesTableTableTableManager get pendingChangesTable =>
      $$PendingChangesTableTableTableManager(_db, _db.pendingChangesTable);
  $$CachedDetailsTableTableTableManager get cachedDetailsTable =>
      $$CachedDetailsTableTableTableManager(_db, _db.cachedDetailsTable);
}
