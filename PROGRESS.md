# StarFilm — журнал прогресса, решений и данных для отладки

Последнее обновление: 2026-11-15  
Рабочий каталог: `D:\Обучение\StarFilm-AI` (ASCII-junction: `D:\Dev\starfilm`)

---

## 1. Жёсткие ограничения и правила проекта

- **Только StarFilm**: каталог StarTV (`d:\Обучение\AndroidTV-AI\free-my-tv`) не изменять и не использовать `FreeMyTV` / `io.freemytv`.
- **Название и ID**: `StarFilm`, Android `applicationId = "app.starfilm.android"`, репозиторий релизов `gulivermaks/StarFilm`.
- **Исключённые функции** (не добавлять):
  - трекинг серий/сезонов (`seasonNumber`, `episodeNumber`, `progressNote`, `S02E05`, `+1 серія`);
  - «порекомендовать другу» / шаринг подборок;
  - отдельные переключатели «без мистики / без сверхъестественного» (`noMysticism`, `noSupernatural`) — только стандартные 19 жанров TMDB (`excludedGenres`);
  - платные функции Firebase (Cloud Functions, Storage, AI Logic, тариф Blaze).
- **Язык**: общение с пользователем по-русски; UI приложения по умолчанию украинский (`uk`), также есть `ru` и `en`.
- **Только диск `D:`**: диск `C:` почти заполнен (~2 ГБ свободно), поэтому все SDK, кэши и временные файлы держим исключительно на `D:\Dev`.
- **Безопасность Git**: не коммитить `*.apk`, `*.jks`, `android/key.properties`, `android/app/google-services.json`, пользовательские API-ключи.

---

## 2. Итоговые технические решения

1. **Бесплатный Firebase Spark**:
   - Один общий Firebase-проект `starfilm-c25f7` (план Spark). Пользователи ничего в Firebase не регистрируют — только нажимают «Увійти через Google».
   - В Firestore хранятся только профили (`main` + до 3 `p_*`), статусы, оценки, коллекции, вкусовые фильтры и компактный срез карточки (`title`, `originalTitle`, `year`, `posterPath`, `genreIds`), без длинных описаний и постеров.
   - Пакеты `WriteBatch` режутся чанками по `<= 450` операций; курсор синхронизации по серверному `serverSyncedAt`; при недоступности облака — локальная работа на Drift/SQLite + очередь `pendingChanges`.
2. **Локальные BYOK-ключи (Android Keystore)**:
   - TMDB: поддерживаются **API Key (v3 `?api_key=...`)** и **Read Access Token (v4 `Authorization: Bearer ...`)** с автоопределением и явным выводом HTTP-ошибок (`TmdbHttpException`) в UI/диагностику.
   - Gemini: личный ключ (`AIza...`), по умолчанию модель `gemini-3.5-flash-lite` (с `thinkingLevel: 'MINIMAL'` для моделей 3.x и автоматическим fallback при HTTP 404 со старых `gemini-2.5-*`).
   - Ключи хранятся только локально через `flutter_secure_storage` (`encryptedSharedPreferences: true`), маскируются в диагностике (`LogSanitizer`) и проверяются кнопкой **«Перевірити»** прямо в диалоге ввода в Настройках.
3. **ИИ-подбор + поиск**:
   - Один запрос в Gemini → параллельная верификация через `TMDB /search/multi` (совпадение нормализованных названий в пределах ±1 года) → строгий локальный фильтр (исключённые жанры и уже просмотренное/отклонённое).
   - Fallback на `TMDB /discover` при отсутствии ключа Gemini или ошибках/429.
4. **Локальная база и профили**:
   - Drift/SQLite (`app_database.dart`, `app_database.g.dart`), до 4 профилей, до 2000 записей на профиль, независимый merge полей (`status`, `userRating`, `liked`, `notes` и т.д.).
   - Поддержка экспорта/импорта JSON (`starfilm_backup.json`) и импорта бэкапа StarTV (с игнорированием `progressNote`).
5. **Интеграция со StarTV (LAN)**:
   - `LanGuard`: HTTP разрешён только для RFC1918 IPv4, наружу только HTTPS.
   - Два режима сопряжения: `Мій домашній ТВ` (запуск, синхронизация библиотеки, передача ключей) и `Гостьовий ТВ` (только запуск видео/трейлера, синхронизация и передача ключей заблокированы).
6. **Версионирование и сборка APK**:
   - В `pubspec.yaml` используется SemVer `0.0.1+1` (т.к. Dart запрещает ведущий ноль `0.01`).
   - В Android (`versionName`/`versionCode`) используется `version.txt` и [tools/build_apk.ps1](tools/build_apk.ps1): автоинкремент `+0.01` (`0.01`, `0.02`, ...), для проверок флаг `-NoBump` / `--no-bump`.
   - Сборка всегда запускается через junction `D:\Dev\starfilm`, т.к. `build_runner` AOT падает на кириллице в пути `Обучение`.
   - В [android/gradle.properties](android/gradle.properties) зафиксированы ограничения памяти (`-Xmx2G -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=256m -XX:CICompilerCount=2`, `org.gradle.workers.max=4`) — без них R8 на 16-ядерном CPU исчерпывал виртуальную память.
   - Для `:google_sign_in_android:lintVitalAnalyzeRelease` в AGP 9.3.1 / Gradle 9.5 требуется JDK 21 (`List.removeLast()`); скрипт [tools/build_apk.ps1](tools/build_apk.ps1) принудительно выставляет `JAVA_HOME=D:\Dev\jdk-21` и `TEMP`/`TMP=D:\Dev\tmp`.
7. **Анализатор Dart (`analysis_options.yaml`)**:
   - Игнорируется `deprecated_member_use` (в Flutter 3.50 помечен deprecated `package:flutter/material.dart` и `RadioListTile.groupValue`) и отключено `prefer_initializing_formals`, чтобы `flutter analyze` проходил с кодом 0 без ломки совместимости.

---

## 3. Данные для отладки, ключей и окружения

### Установленные инструменты (на `D:\Dev`)
- Flutter: `D:\Dev\flutter` (`3.50.0`, Dart `3.14.0`, аналитика отключена)
- Java для Gradle/Firebase: `D:\Dev\jdk-21` (Temurin `21.0.13_9`; системный `JAVA_HOME` для других проектов не менялся — `D:\Program Files\Java\jdk-17`)
- Android SDK: `D:\Program Files\Android\Sdk` (установлены `platforms;android-35`, `platforms;android-36`, `build-tools;34.0.0`, `build-tools;35.0.0`, `build-tools;36.0.0`, `NDK 28.2`, `CMake 3.22.1`, `Platform-Tools 37.0.1`)
- CLI: `firebase-tools 15.36.0` (`D:\Dev\npm-global\firebase.cmd`), `flutterfire_cli 1.5.0` (`D:\Dev\.pub-cache\bin`)
- Переменные пользователя (`HKCU\Environment`):
  - `TEMP=D:\Dev\tmp`, `TMP=D:\Dev\tmp`
  - `PUB_CACHE=D:\Dev\.pub-cache`
  - `GRADLE_USER_HOME=D:\Dev\.gradle`
  - `XDG_CACHE_HOME=D:\Dev\.cache`
  - `NPM_CONFIG_CACHE=D:\Dev\.npm-cache`
  - `FIREBASE_EMULATORS_PATH=D:\Dev\.firebase-emulators`

### Подпись APK и Firebase
- **Release keystore** (вне Git): `D:\Dev\StarFilmKeys\starfilm-release.jks`, alias `starfilm`, свойства в gitignored [android/key.properties](android/key.properties).
- **Release SHA-1**: `1E:98:AE:2E:8E:85:15:D5:C8:EF:00:B9:F7:05:EA:73:05:95:1D:A9`
- **Release SHA-256**: `8F:CA:33:0B:30:CF:EF:62:5D:A1:21:9E:1E:14:C1:5A:90:AF:78:2B:7A:EB:BA:A5:CE:AB:89:B0:24:06:BF:9F`
- **Debug keystore**: `D:\Program Files\Android\.android\debug.keystore`
- **Debug SHA-1**: `16:47:EC:9B:94:1F:88:19:6E:ED:1A:4A:07:6F:1F:A5:D9:EA:3F:70`
- **Debug SHA-256**: `F6:29:68:C0:D3:74:A1:A1:C8:24:31:D5:F4:5B:F8:FA:CA:47:4B:2C:D6:D7:19:9A:5C:53:D2:41:6C:92:2D:E0`
- **Firebase проект**: `starfilm-c25f7` (number `726138536104`, app id `1:726138536104:android:2ffc92f09e28a97be3429d`)
- **`google-services.json`**: лежит в `android/app/google-services.json` (gitignored), содержит оба `client_type: 1` (release + debug SHA-1) и Web Client ID (`client_type: 3`).

### Целевой тестовый телефон (от пользователя)
- **Pixel XL (Android 10)**, `product:marlin`, ADB по Wi-Fi: `192.168.47.247:5555` (ТВ-приставка `model:W2` — **не трогать**).

---

## 4. Что уже выполнено и проверено

- [x] Установлены все SDK, компиляторы и зависимости на `D:\Dev`.
- [x] Сгенерированы debug/release keystores и отпечатки.
- [x] Написаны [firestore.rules](firestore.rules), [firebase.json](firebase.json) и проверены в Firestore Emulator (3/3 теста).
- [x] Реализованы все модули `lib/` по [StarFilm_SPECIFICATION_v2.1_FREE.md](StarFilm_SPECIFICATION_v2.1_FREE.md) и сгенерирована схема Drift (`app_database.g.dart`).
- [x] Пройдены проверки:
  - `flutter analyze` → `No issues found!`
  - `flutter test` → `16/16` тестов (включая масштаб `4×2000`, `LanGuard`, `LogSanitizer`, `BackupCodec`, `OtaUpdater`, `DiscoveryService`, v4 Bearer / HTTP 401 / Gemini 404 fallback в `TmdbClient`/`GeminiClient`, `StarTvClient`, `widget_test`).
- [x] Пользователь создал Firebase Spark проект `starfilm-c25f7`, добавил все 4 SHA-отпечатка, включил Google Sign-In и скачал `google-services.json`.
- [x] Собран и проверен подписанный release [StarFilm.apk](StarFilm.apk) **`v0.03` (`versionCode=3`, `60.12 MB`)**:
  - Устранён сбой ИИ-подбора из-за устаревшей для новых аккаунтов `gemini-2.5-flash-lite` (`HTTP 404`): модель по умолчанию обновлена на `gemini-3.5-flash-lite`, добавлен fallback при 404.
  - Добавлена поддержка TMDB v4 Bearer Read Access Token (`eyJ...`) в дополнение к v3 API Key, отображение реальных HTTP-ошибок на вкладке «Пошук» и кнопка «Перевірити» при сохранении ключей.
- [x] **Живой тест на Pixel XL (Android 10, `192.168.47.247:5555`) пройден (`v0.03`):**
  - Обновление `adb install -r` поверх `v0.02` — успешно, ключи и вход Google сохранились.
  - Проверены экраны: Онбординг, «Підбір», «Пошук», «Моє», диалог «Підключити StarTV» и «Налаштування».
  - Проверен Google Sign-In (`guliverjw@gmail.com`) и синхронизация с Firestore («Синхронізувати» → без ошибок).
  - **Живой ИИ-подбор («Підбір»)** с реальными ключами пользователя (`gemini-3.5-flash-lite`) сработал и загрузил карточки и постеры TMDB («Втеча з Шоушенка», «Хрещений батько»).
  - **Живой поиск TMDB («Пошук»)** по запросу `Inception` вернул `Inception (2010 • TMDB 8.4)` с постером.
  - **Карточка деталей + «Моє» + Firestore sync**: открыта карточка «Початок» (`148 хв`, жанры, постер), выставлены статус и оценка `7/10`, запись появилась во вкладке «Моє», синхронизировалась с Firestore (`Очікує синхронізації: 0`), затем тестовая запись удалена и повторно синхронизирована.
  - **Экспорт JSON, OTA и StarTV UI**: «Експорт JSON» открыл системное окно отправки `starfilm_backup.json`; кнопка «Перевірити оновлення v0.03 (3)» корректно отработала без ошибок; диалог «Підключити StarTV» открылся без сбоев.
  - **«Діагностика»** после всего E2E-прогона: `Журнал порожній` (0 ошибок и 0 предупреждений).
- [x] **Аудит безопасности, правил и готовности к релизу**:
  - Проверен весь `lib/` на запрещённые функции (`FreeMyTV`, трекинг серий, `noMysticism`/`noSupernatural`) — отсутствуют.
  - Обновлён [.gitignore](.gitignore): добавлены `Key.txt` и `ADB Pixel/`.
  - Повторно прогнаны правила Firestore в эмуляторе (`firebase emulators:exec --only firestore` → `3/3` теста пройдены).
  - Проверен `release_github.ps1 -DryRun`: `apksigner verify` подтвердил подпись (`CN=StarFilm`, SHA-1 `1e98...`), `gh auth status` и репозиторий `https://github.com/gulivermaks/StarFilm` готовы, SHA-256 APK: `85894e74f6e3b1e546572ac2a0e98a2a4cc5790b089a39d5a9b38b9edc1367cb`.

---

## 5. На каком этапе остановились и что дальше

- **Текущий этап**: всё, что не требует участия пользователя, завершено. Релизный [StarFilm.apk](StarFilm.apk) **`v0.03` (`versionCode=3`)** установлен на **Pixel XL (`192.168.47.247:5555`)** и полностью проверен E2E.
- **Осталось (требует участия/решения пользователя)**:
  1. Пройти ручной чеклист (связка со StarTV в LAN, реальный плеер/YouTube на телефоне, при желании второй телефон/аккаунт для теста изоляции Firestore).
  2. Публикация релиза `v0.03` на GitHub через [tools/release_github.ps1](tools/release_github.ps1).

---

## 6. Бэклог на следующее обновление (v0.04, замечания от 2026-11-15 — код в v0.03 НЕ менялся)

1. **Локализованное название в буфер обмена** ([mobile_players.dart](lib/features/players/mobile_players.dart#L52)):
   - Сейчас в `PlayerLaunchPlanner.plan()` приоритет у `originalTitle` (английское название). Переключить приоритет на отображаемое локализованное `title` (украинский/русский), с fallback на `originalTitle`.
2. **Проверка ключей при первом запуске (Онбординг)** ([onboarding_screen.dart](lib/features/onboarding/onboarding_screen.dart#L163-L234)):
   - Сейчас общая кнопка `Перевірити` внизу часто перекрывается экранной клавиатурой внутри `ListView`, а результат показывается только мелкой иконкой. Добавить понятную инлайн-кнопку/статус проверки с текстом успеха или причины ошибки прямо у полей TMDB и Gemini (как в Настройках).
3. **Прямой перевод из «Переглянуто» в «Хочу подивитися»** ([library_entry.dart](lib/core/models/library_entry.dart#L81-L85)):
   - Сейчас `LibraryEntry.normalized()` при наличии `userRating != null` принудительно возвращает статус `watchlist` обратно в `watched` (поэтому перевод работал только через `Дивлюся` → `Не цікавить`, где оценка обнулялась). Исправить инвариант/действие сохранения так, чтобы явный выбор `Хочу подивитися` переводил запись напрямую (а автопереход в `watched` происходил только при выставлении новой оценки).
4. **Импорт JSON-бэкапа: режим восстановления снимка** ([library_repository.dart](lib/features/library/library_repository.dart#L266)):
   - Сейчас `mergeImportedBundle()` делает только слияние по более свежему `clientUpdatedAt` и не удаляет добавленные после экспорта записи, поэтому откат библиотеки к более раннему экспорту не происходит. Добавить в диалоге импорта выбор: **«Відновити стан з копії (замінити бібліотеку)»** vs **«Об'єднати (додати новіші)»**.
5. **Интеграция HDRezka MOD (`to.pda.falcofemoralis.hdrezkaapp`) и иконка приложения**:
   - На Pixel XL установлен [hdrezka_mod.apk](file:///D:/Обучение/AndroidTV-AI-Ivan/hdrezka_mod.apk); фактический `package` = `to.pda.falcofemoralis.hdrezkaapp` (в [mobile_players.dart](lib/features/players/mobile_players.dart#L7) и [AndroidManifest.xml](android/app/src/main/AndroidManifest.xml#L50) пока указан `com.hdrezka.client`, а `_watchOnPhone` открывает только URI без запуска пакета). Обновить package name и добавить запуск установленного приложения по package/intent, а также перенести сгенерированный логотип StarFilm в `mipmap-*`.
