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

- [x] **Обновление `v0.04` (`versionCode=4`, `60.2 MB`) — закрытие всех 5 замечаний бэклога**:
  - **Локализованное название в буфер обмена** ([mobile_players.dart](lib/features/players/mobile_players.dart)): в `PlayerLaunchPlanner.plan()` приоритет переключён на локализованный `title` с fallback на `originalTitle` (единообразно для буфера обмена и поискового fallback URI).
  - **Инлайн-проверка ключей на онбординге** ([onboarding_screen.dart](lib/features/onboarding/onboarding_screen.dart)): для TMDB и Gemini вынесены отдельные кнопки `Перевірити` и текстовый статус результата прямо под каждым полем, чтобы экранная клавиатура не перекрывала проверку.
  - **Прямой перевод `Переглянуто` → `Хочу подивитися`** ([app_state.dart](lib/app/app_state.dart), [library_entry.dart](lib/core/models/library_entry.dart)): в `saveEntryAction` явный перевод в `watchlist`/`none`/`dismissed` очищает прежнюю оценку (а `merge()` разрешает конфликт `watchlist` vs `userRating` по более свежему `statusChangedAt > ratingChangedAt`), сохраняя автопереход в `watched` только при выставлении новой оценки. Причина: `normalized()` ранее возвращал старую оценку и откатывал статус обратно в `watched`.
  - **Импорт JSON-бэкапа с выбором режима** ([library_repository.dart](lib/features/library/library_repository.dart), [settings_screen.dart](lib/features/settings/settings_screen.dart)): добавлен диалог выбора **«Об'єднати (додати новіші)»** vs **«Відновити стан з копії (замінити бібліотеку)»** и метод `replaceFromBackupBundle()`, который атомарно восстанавливает снимок и ставит tombstones (`deletedAt`) на добавленные позже записи/коллекции/неактуальные профили, чтобы облачная синхронизация не воскрешала их.
  - **HDRezka MOD и иконка StarFilm** ([mobile_players.dart](lib/features/players/mobile_players.dart), [AndroidManifest.xml](android/app/src/main/AndroidManifest.xml), [MainActivity.kt](android/app/src/main/kotlin/app/starfilm/android/MainActivity.kt), `android/app/src/main/res/mipmap-*/ic_launcher.png`): обновлён пакет `to.pda.falcofemoralis.hdrezkaapp`, добавлен запуск установленного Android-приложения через `MethodChannel('app.starfilm.android/launcher')` (`getLaunchIntentForPackage`) с fallback в браузер, а также сгенерированы непрозрачные иконки `mipmap-mdpi..xxxhdpi` из [docs/logo.png](docs/logo.png) на фоне `#0B0D11`.
  - **Проверки `v0.04`**:
    - `flutter analyze` → `No issues found!`
    - `flutter test` → `23/23` пройдено (добавлены [mobile_players_test.dart](test/mobile_players_test.dart), [onboarding_and_backup_widget_test.dart](test/onboarding_and_backup_widget_test.dart), расширен [library_and_merge_test.dart](test/library_and_merge_test.dart)).
    - `tools/build_apk.ps1` → собран релизный [StarFilm.apk](StarFilm.apk) `v0.04` (`versionCode=4`, `60.2 MB`), `apksigner verify` подтвердил подпись (`CN=StarFilm`, SHA-1 `1e98ae2e8e8515d5c8ef00b9f705ea7305951da9`), SHA-256 APK: `8285211ab4f9dd9207eef9bbf65b47bdd8d0e2432e89df04456c0791cb879e19`.
  - **Живая проверка `v0.04` на Pixel XL (`192.168.47.247:5555`)**:
    - `adb install -r StarFilm.apk` поверх `v0.03` — успешно (`versionCode=4`, `versionName=0.04`), профиль и ключи сохранились; в Настройках отображается `v0.04 (4)` и выбран плеер `HDRezka`.
    - Через «Поиск» открыта карточка `Начало` (`Inception`, 2010): кнопка «Смотреть на телефоне» успешно запустила `to.pda.falcofemoralis.hdrezkaapp/.views.MainActivity`.
    - Проверен прямой перевод: после выставления оценки `7` (статус `Просмотрено`) нажатие «Хочу посмотреть» сразу перевело карточку в `Хочу посмотреть` (`selected="true"`) со сбросом оценки; тестовая запись удалена.
    - «Діагностика» после проверки: `Журнал порожній` (0 ошибок и 0 предупреждений).

- [x] **Реализован и опубликован релиз `v0.05` (`versionCode=5`, `60.38 MB`):**
  - **Коллекции (полный цикл UI + controller)** ([app_state.dart](lib/app/app_state.dart), [details_sheet.dart](lib/features/details/details_sheet.dart), [library_tab.dart](lib/features/library/library_tab.dart)):
    - В `AppController` добавлены `renameCollection`, `deleteCollection` (soft-delete через `deletedAt` tombstone), общий `_saveAndRefreshCollection` с обновлением `pendingSyncCount`, а `createCollection` возвращает созданную коллекцию для мгновенного добавления тайтла.
    - В `MediaDetailsSheet` добавлен блок «Колекції» с `FilterChip` (автосохранением метаданных записи с `WatchStatus.none`, если её ещё нет в локальной базе) и кнопкой `+ Нова колекція`.
    - В `LibraryTab` («Моє → Колекції») карточки коллекций стали раскрывающимися (`ExpansionTile`) со списком входящих тайтлов, открытием `MediaDetailsSheet` по тапу, удалением тайтла из коллекции и меню «Перейменувати» / «Видалити».
  - **Сигналы вкуса (`Like` / `Dislike`) и снятие оценки** ([details_sheet.dart](lib/features/details/details_sheet.dart)):
    - В карточку деталей добавлены чипы `Подобається` / `Не подобається` (повторный тап сбрасывает в `neutral`; выбор `Like` на `dismissed` сбрасывает статус в `none`, чтобы `normalized()` не затёр лайк).
    - Добавлено снятие оценки (`Зняти оцінку` и повторный тап по активной цифре `1..10`) с сохранением статуса просмотра и `sentiment`.
  - **Видимая обратная связь для ИИ-подбора, облака и OTA-обновлений** ([tmdb_client.dart](lib/features/search/tmdb_client.dart), [discovery_service.dart](lib/features/discovery/discovery_service.dart), [app_state.dart](lib/app/app_state.dart), [discovery_tab.dart](lib/features/discovery/discovery_tab.dart), [settings_screen.dart](lib/features/settings/settings_screen.dart)):
    - `TmdbClient.discoverFallback` теперь выбрасывает `TmdbHttpException` при ошибке HTTP, а `DiscoveryService.recommend` пробрасывает ошибку, если ИИ-кандидаты не найдены (`lastDiscoveryError` отображается в красной карточке на вкладке «Підбір»).
    - Кнопка облачной синхронизации в `SettingsScreen` показывает `SnackBar` с итогом (`↑pushed / ↓pulled`, квота `sync_quota` или ошибка).
    - `SettingsScreen._checkUpdates` при наличии новой версии открывает `showUpdateAvailableDialog` с `releaseNotes` и кнопкой «Завантажити APK» (`url_launcher` внешним приложением).
  - **Локализация `uk / ru / en`** ([l10n.dart](lib/app/l10n.dart), [discovery_tab.dart](lib/features/discovery/discovery_tab.dart), [search_tab.dart](lib/features/search/search_tab.dart), [library_tab.dart](lib/features/library/library_tab.dart), [settings_screen.dart](lib/features/settings/settings_screen.dart)): заменены оставшиеся захардкоженные украинские строки на всех основных экранах (сортировка, жанры, быстрые кнопки, ошибки TMDB, диалоги настроек и диагностики).
  - **Проверки `v0.05`**:
    - `flutter analyze` → `No issues found!`
    - `flutter test` → `29/29` пройдены (добавлены [collections_and_controller_test.dart](test/collections_and_controller_test.dart) и [collections_and_ui_widget_test.dart](test/collections_and_ui_widget_test.dart)).
    - `powershell -NoProfile -File tools/build_apk.ps1` → собран релизный `StarFilm.apk v0.05 (code 5, 60.38 MB)` без ошибок.
  - **Живая проверка `v0.05` на Pixel XL (USB `HT6AD0200687`)**:
    - `adb install -r StarFilm.apk` → `Success`; в Настройках отображается `Проверить обновления v0.05 (5)`, все разделы, диалоги и вкладки («Поиск», «Моё», «Настройки») полностью локализованы на `ru`.
    - Облачная синхронизация вывела `SnackBar`: `Синхронизировано (↑10, ↓8)`.
    - Через «Поиск» (`Inception`) открыта карточка `Начало`: поставлена оценка `7`, нажато `Нравится`, создана коллекция `TestCol` с автодобавлением фильма, затем повторным тапом по `7` оценка успешно сброшена.
    - В «Моё → Коллекции» раскрыта `TestCol (Тайтлов: 1)`, тайтл убран, коллекция `TestCol` удалена, тестовая запись `Начало` удалена из «Просмотрено» и синхронизирована в облако.
    - «Диагностика» после E2E-проверки: `Журнал пуст`.

---

- **Финализация `StarFilm v1.0` (`v0.06`, `versionCode=6`)**:
  - Встроенный OTA-апдейт в приложении: потоковое скачивание в `cacheDir/updates` с прогресс-баром, проверкой размера и `SHA-256` (`lib/features/settings/ota_updater.dart`, `lib/core/network/starfilm_http_client.dart`), проверкой совпадения сертификата подписи APK и установкой через `OtaFileProvider` + `ACTION_INSTALL_PACKAGE`/`ACTION_VIEW` (`android/app/src/main/kotlin/app/starfilm/android/MainActivity.kt`, `OtaFileProvider.kt`, `starfilm_ota_paths.xml`, `AndroidManifest.xml`), плюс резервная кнопка «Открыть в браузере».
  - Полная локализация `uk/ru/en` для оставшихся экранов и диалогов: `lib/features/onboarding/onboarding_screen.dart` (шаги 0–4, «Назад»/«Далее»), `lib/features/startv/startv_pairing_dialog.dart`, StarTV-снекбары в `lib/features/details/details_sheet.dart` (`lib/app/l10n.dart`).
  - Сводная строка статусов в «Диагностика» над санитаризированным журналом (`TMDB • Gemini • Облако • Профилей • Записей • StarTV` в `lib/features/settings/settings_screen.dart`).
  - Проверки `v0.06`:
    - `flutter analyze` — `No issues found!`;
    - `flutter test` — `31/31` (`All tests passed!`, добавлены unit-тест `OtaUpdater.downloadAndVerifyApk` в `test/ota_updater_test.dart` и widget-тесты OTA-диалога и локализации Onboarding/StarTV в `test/collections_and_ui_widget_test.dart`);
    - `tools/build_apk.ps1` — собран подписанный `StarFilm.apk` `v0.06` (`versionCode=6`, `60.56 MB`);
    - Живая проверка на физическом **Pixel XL (`HT6AD0200687`)**: `adb install -r StarFilm.apk` (`Success`), подтверждены локализованный диалог «Подключить StarTV», строка статуса в «Диагностика» (`TMDB: OK • Gemini: OK • Облако: OK • Профилей: 2 • Записей: 5 • StarTV: нет` + `Журнал пуст`), `Проверить обновления v0.06 (6)` и ответ `У вас актуальная версия (0.06)`.

## 5. На каком этапе остановились и что дальше

- **Текущий этап**: Релиз **`v0.05` (`versionCode=5`)** опубликован на GitHub; итерация **`v0.06` (`versionCode=6`)** закрыла все оставшиеся задачи `StarFilm v1.0` на стороне телефона (`StarFilm_SPECIFICATION_v2.1_FREE.md`), собрана, проверена автотестами (`31/31`) и установлена/проверена на физическом Pixel XL.
- **Следующий шаг**:
  1. По явной команде владельца: публикация `v0.06` на GitHub (при необходимости), доработка серверной стороны `StarTV` на приставке, либо переход к бэклогу `v1.1+` (раздел 12 спецификации).

---

## 6. Бэклог на следующее обновление (закрыто в v0.04)

- [x] 1. Локализованное название в буфер обмена (`mobile_players.dart`).
- [x] 2. Инлайн-проверка ключей на онбординге (`onboarding_screen.dart`).
- [x] 3. Прямой перевод из «Переглянуто» в «Хочу подивитися» (`app_state.dart`, `library_entry.dart`).
- [x] 4. Импорт JSON-бэкапа: режим восстановления снимка (`library_repository.dart`, `settings_screen.dart`).
- [x] 5. Интеграция HDRezka MOD (`to.pda.falcofemoralis.hdrezkaapp`) и иконка приложения в `mipmap-*`.
