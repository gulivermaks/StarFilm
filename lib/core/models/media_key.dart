enum MediaType {
  movie('movie'),
  tv('tv');

  const MediaType(this.wireValue);
  final String wireValue;

  static MediaType fromWire(String value) {
    return value == 'tv' ? MediaType.tv : MediaType.movie;
  }
}

enum WatchStatus {
  none('none'),
  watchlist('watchlist'),
  watching('watching'),
  watched('watched'),
  dismissed('dismissed');

  const WatchStatus(this.wireValue);
  final String wireValue;

  static WatchStatus fromWire(String? value) {
    for (final item in WatchStatus.values) {
      if (item.wireValue == value) return item;
    }
    return WatchStatus.none;
  }
}

enum Sentiment {
  neutral('neutral'),
  liked('liked'),
  disliked('disliked');

  const Sentiment(this.wireValue);
  final String wireValue;

  static Sentiment fromWire(String? value) {
    for (final item in Sentiment.values) {
      if (item.wireValue == value) return item;
    }
    return Sentiment.neutral;
  }
}

class MediaKey {
  MediaKey(this.mediaType, this.tmdbId) {
    if (tmdbId <= 0) {
      throw ArgumentError.value(tmdbId, 'tmdbId', 'Must be positive');
    }
  }

  final MediaType mediaType;
  final int tmdbId;

  String get value => '${mediaType.wireValue}:$tmdbId';
  String get firestoreId => '${mediaType.wireValue}_$tmdbId';

  static MediaKey? tryParse(String raw) {
    final sep = raw.contains(':') ? ':' : (raw.contains('_') ? '_' : null);
    if (sep == null) return null;
    final parts = raw.split(sep);
    if (parts.length != 2) return null;
    if (parts[0] != 'movie' && parts[0] != 'tv') return null;
    final id = int.tryParse(parts[1]);
    if (id == null || id <= 0) return null;
    return MediaKey(MediaType.fromWire(parts[0]), id);
  }

  @override
  bool operator ==(Object other) =>
      other is MediaKey && other.mediaType == mediaType && other.tmdbId == tmdbId;

  @override
  int get hashCode => Object.hash(mediaType, tmdbId);

  @override
  String toString() => value;
}

class TmdbGenre {
  const TmdbGenre(this.id, this.uk, this.ru, this.en);

  final int id;
  final String uk;
  final String ru;
  final String en;

  String labelFor(String lang) {
    switch (lang) {
      case 'ru':
        return ru;
      case 'en':
        return en;
      default:
        return uk;
    }
  }
}

/// Standard 19 TMDB genre IDs supported by StarFilm/StarTV (`excludedGenres`).
const List<TmdbGenre> kStandardGenres = [
  TmdbGenre(28, 'Бойовик', 'Боевик', 'Action'),
  TmdbGenre(12, 'Пригоди', 'Приключения', 'Adventure'),
  TmdbGenre(16, 'Анімація', 'Мультфильм', 'Animation'),
  TmdbGenre(35, 'Комедія', 'Комедия', 'Comedy'),
  TmdbGenre(80, 'Кримінал', 'Криминал', 'Crime'),
  TmdbGenre(99, 'Документальний', 'Документальный', 'Documentary'),
  TmdbGenre(18, 'Драма', 'Драма', 'Drama'),
  TmdbGenre(10751, 'Сімейний', 'Семейный', 'Family'),
  TmdbGenre(14, 'Фентезі', 'Фэнтези', 'Fantasy'),
  TmdbGenre(36, 'Історія', 'История', 'History'),
  TmdbGenre(27, 'Жахи', 'Ужасы', 'Horror'),
  TmdbGenre(10402, 'Музика', 'Музыка', 'Music'),
  TmdbGenre(9648, 'Детектив', 'Детектив', 'Mystery'),
  TmdbGenre(10749, 'Мелодрама', 'Мелодрама', 'Romance'),
  TmdbGenre(878, 'Фантастика', 'Фантастика', 'Science Fiction'),
  TmdbGenre(10770, 'ТБ-фільм', 'ТВ-фильм', 'TV Movie'),
  TmdbGenre(53, 'Трилер', 'Триллер', 'Thriller'),
  TmdbGenre(10752, 'Військовий', 'Военный', 'War'),
  TmdbGenre(37, 'Вестерн', 'Вестерн', 'Western'),
];
