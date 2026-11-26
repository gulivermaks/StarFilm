# StarFilm — журнал прогресса, решений и данных для отладки

Последнее обновление: 2026-11-26  
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

- **Исправления под Android 15/16 / Samsung S26 Ultra и OTA (`v0.07`, `versionCode=7`)**:
  - Устранено перекрытие нижней кнопки «Проверить обновления» (и нижней части карточки фильма) 3-кнопочной системной панелью навигации Android: добавлен `SafeArea(top: false)` в `lib/features/settings/settings_screen.dart` и `lib/features/details/details_sheet.dart`, настроен `SystemUiMode.edgeToEdge` + прозрачные/светлые иконки системных баров (`lib/main.dart`, `lib/app/theme.dart`).
  - Настроена тёмная плавающая тема `SnackBarThemeData` в `lib/app/theme.dart` (без белой полосы на тёмном фоне).
  - В `android/app/src/main/kotlin/app/starfilm/android/MainActivity.kt` добавлена проверка `canRequestPackageInstalls()`: при отсутствии разрешения открываются настройки Android «Установка неизвестных приложений» для StarFilm, возвращается `permission_required`, а скачанный и проверенный APK сохраняется для повторного нажатия (`update_install_permission` в `lib/app/l10n.dart`, `lib/features/settings/settings_screen.dart`).
  - Проверки `v0.07`: `flutter analyze` — `No issues found!`, `flutter test` — `32/32`, собран `StarFilm.apk v0.07 (7)` (`60.56 MB`), установлено и проверено на Pixel XL (`HT6AD0200687`).

- **Крупное функциональное обновление `v0.08` (`versionCode=8`)**:
  - **Рейтинги Кинопоиска + IMDb по личному ключу КП** ([kinopoisk_client.dart](lib/features/ratings/kinopoisk_client.dart), [secret_store.dart](lib/core/security/secret_store.dart), [log_sanitizer.dart](lib/core/security/log_sanitizer.dart), [details_sheet.dart](lib/features/details/details_sheet.dart), [settings_screen.dart](lib/features/settings/settings_screen.dart), [onboarding_screen.dart](lib/features/onboarding/onboarding_screen.dart), [startv_client.dart](lib/features/startv/startv_client.dart)): проверка ключа на `kinopoiskapiunofficial.tech`, lookup по `imdbId` (`ratingKinopoisk` + `ratingImdb`) и фолбэк по названию/году, бейджи `КП {r}` / `IMDb {r}` в карточке тайтла, маскирование UUID-ключа в логах, перенос ключа Кинопоиска на `StarTV` (`/api/keys`).
  - **Пакетный импорт оценок `CSV/TSV`** ([rating_csv_import.dart](lib/features/library/rating_csv_import.dart), [settings_screen.dart](lib/features/settings/settings_screen.dart), [app_state.dart](lib/app/app_state.dart)): парсинг CSV/TSV (`;`, `\t`, `,`) и формата `"Название — 8/10"` (до 100 строк) через диалог в Настройках (выбор файла или вставка текста) с автопоиском в TMDB.
  - **Дополнительные мобильные плееры** ([mobile_players.dart](lib/features/players/mobile_players.dart), [MainActivity.kt](android/app/src/main/kotlin/app/starfilm/android/MainActivity.kt), [AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)): добавлены `VLC`, `MX Player` (с фолбэком `.pro`), `Kodi`, `TorrServe`.
  - **Голосовой ввод** ([device_bridge.dart](lib/core/platform/device_bridge.dart), [MainActivity.kt](android/app/src/main/kotlin/app/starfilm/android/MainActivity.kt), [discovery_tab.dart](lib/features/discovery/discovery_tab.dart), [search_tab.dart](lib/features/search/search_tab.dart)): системное распознавание речи Android `RecognizerIntent.ACTION_RECOGNIZE_SPEECH` по кнопке микрофона на вкладках «Підбір» и «Пошук».
  - **Парный Match-свайп на одном экране** ([match_swipe_sheet.dart](lib/features/discovery/match_swipe_sheet.dart), [discovery_tab.dart](lib/features/discovery/discovery_tab.dart)): пошаговый свайп двоих игроков с анимацией угла/глубины карточек, отменой шага, экраном передачи устройства и списком взаимных совпадений. (Расширенный «Спільний вечір» между локальными профилями окончательно исключён по решению владельца в [StarFilm_SPECIFICATION_v2.1_FREE.md](StarFilm_SPECIFICATION_v2.1_FREE.md).)
  - **Уведомления о цифровых релизах фильмов** ([digital_release_service.dart](lib/features/releases/digital_release_service.dart), [tmdb_client.dart](lib/features/search/tmdb_client.dart), [MainActivity.kt](android/app/src/main/kotlin/app/starfilm/android/MainActivity.kt), [main.dart](lib/main.dart), [details_sheet.dart](lib/features/details/details_sheet.dart)): строго для **фильмов** из списка «Хочу посмотреть» (`type == 4`, не сериалы/эпизоды), системный канал уведомлений `starfilm_releases`, `SnackBar`-баннер при старте и бейдж `Цифра: DD.MM.YYYY` в карточке.
  - **Проверки `v0.08`**:
    - `flutter analyze` — `No issues found!`;
    - `flutter test` — `40/40` (`All tests passed!`, включая [v08_enhancements_test.dart](test/v08_enhancements_test.dart));
    - `tools/build_apk.ps1` — собран подписанный `StarFilm.apk` `v0.08` (`versionCode=8`, `61.13 MB`);
    - Живая проверка на физическом **Pixel XL (`HT6AD0200687`)**: подтверждены кнопка голосового ввода и `Match вдвоём` на «Підбір», открыта карточная колода `Парный Match-свайп (1/12)`, в «Настройки» видны поле `Kinopoisk API key`, плееры (`VLC`, `MX Player`, `Kodi`, `TorrServe`), переключатель и ручная проверка цифровых релизов фильмов, `Пакетный импорт оценок (CSV/TSV)`, строка статуса `Диагностика` (`КП: нет` + `Журнал пуст`) и кнопка `Проверить обновления v0.08 (8)`.

## 5. Итог выполнения доработок к v0.09 (2026-11-16)

Все согласованные изменения по удалению «Match вдвоём» и выполнению **Этапов 1, 2 и 3** реализованы, проверены, повышены до версии `v0.09 (9)` (`version.txt`) и подготовлены к публикации релиза на GitHub.

### Что сделано

- **Удалён режим «Match вдвоём»**: убрана кнопка и экран свайп-матчинга (`match_swipe_sheet.dart`), очищены локализации и тесты.
- **Этап 1 (безопасность, синхронизация, главный экран, стабильность входа)**:
  - Изоляция локальных данных при выходе из Google и диалог предпросмотра слияния/замены при повторном входе (`app_state.dart`, `library_repository.dart`).
  - Инкрементальный обмен с Firestore только по очереди локальных изменений, пропуск эха собственных записей, автоотправка с задержкой 2.5 с и при возврате в приложение, очистка устаревших пометок удаления (>90 дней) и сброс активного профиля на «Основной», если дополнительный профиль удалён на другом устройстве.
  - Усилены правила безопасности Firestore (`firestore.rules`) и расширены тесты правил.
  - Отключён Google Auto Backup для защиты локального хранилища (`AndroidManifest.xml`, `data_extraction_rules.xml`), добавлено восстановление при сбое шифрованного хранилища (`secret_store.dart`).
  - Кнопка «Подобрать» перенесена на полную ширину, имя профиля в шапке аккуратно сокращается без сжатия, ключи при переходе по шагам первого запуска сохраняются без затирания.
- **Этап 2 (качество подбора, поиск, карточка, библиотека, настройки)**:
  - Режим «До 90 мин» честно проверяет длительность фильмов через TMDB и исключает слишком длинные фильмы; для проверки названий ИИ допускается расхождение года `±1` и постраничное обновление выдачи.
  - Отдельный кэш рекомендаций и истории показов для каждого профиля, фикс привязки профиля на время длительных операций и импорта.
  - Поиск сохраняет выбранный язык контента даже для латиницы (`Inception` → «Начало»), фильтры `Год` и `Жанр` аккуратно переносятся, подсвечиваются уже сохранённые статусы, есть быстрая кнопка «Смотреть» и заглушка при ошибке загрузки постера.
  - В карточке оценки `1–10` выведены в два удобных ряда (`1–5` и `6–10`), прокрутка шторки едет плавно, переведены названия стран и подписи ролей, а при потере авторизации на StarTV предлагается заново подключить приставку.
  - В «Моё» все 4 вкладки (включая «Коллекции») видны сразу, удаление коллекции требует подтверждения, а удаление фильма/сериала можно отменить через всплывающую кнопку.
  - Импорт CSV/TSV поддерживает кодировку Windows-1251, не подставляет ложный фильм без года, выдерживает паузу при лимите запросов и корректно показывает ошибку при пустом списке.
  - Проверка цифровых релизов сперва отсекает уже отправленные фильмы, а затем берёт до 20 новых.
  - В настройках переведены «Поиск в браузере» и «Основной», добавлены переименование и удаление профилей (без технических идентификаторов в UI), ручной ввод модели Gemini, перенос выпадающего списка модели под заголовок без сжатия текста, кнопка копирования отчёта в «Диагностике» и плашка атрибуции TMDB.
- **Этап 3 (StarTV QR и оформление Android)**:
  - Добавлен живой сканер QR-кода камерой для подключения приставки StarTV (`qr_scanner_screen.dart`), предварительная проверка статуса перед авторизацией, синхронизация удалённых профилей и понятные русские/украинские/английские сообщения об ошибках.
  - Обновлены адаптивная иконка из `docs/logo.png`, монохромная иконка уведомлений с лаймовым акцентом, тёмный экран запуска (`#0B0D11`), сетевая конфигурация для локального IP приставки и `flutter_localizations` (`uk`, `ru`, `en`).

### Проверки

- `flutter analyze` — `No issues found!`.
- `flutter test` — `57/57 All tests passed!` (включая `stage1_sync_isolation_test.dart` и `stage2_3_improvements_test.dart`).
- `firebase emulators:exec --only firestore "npm --prefix tools/firestore_rules_test test"` — `4/4 pass`.
- `tools/build_apk.ps1` — версия повышена до `v0.09` (`versionCode=9` в `version.txt`), собран подписанный `StarFilm.apk` (`78.09 MB`), до повышения проверена живая установка сборки на тестовый Pixel XL (`HT6AD0200687`).
- Живая проверка на Pixel XL подтвердила: отсутствие `Match вдвоём`, широкую кнопку «Подобрать» и честный подбор «До 90 мин», поиск `Inception` на русском («Начало»), 4 видимые вкладки в «Моё», двухрядные оценки `1–5` / `6–10` и перевод стран, удаление с кнопкой «Отменить», диалог подключения StarTV с кнопкой камеры и понятной ошибкой вне домашней сети, переименование/удаление профилей без сырых ID, ровный выбор модели Gemini, копирование отчёта диагностики, плашку TMDB, чистую синхронизацию (`Ожидает синхронизации: 0`) и возврат базы к исходным 5 тестовым записям (`Профилей: 2 • Записей: 5 • Журнал пуст`).

### Что не удалось проверить без внешнего оборудования / ключей / устройств

- Подключение и обмен с реальной приставкой `StarTV` в домашней Wi-Fi сети (включая реальный скан QR-кода приставки).
- Запрос рейтингов Кинопоиска / IMDb при введённом ключе `Kinopoisk API key`.
- Системный запрос разрешения на уведомления на Android 13+ и установку обновления поверх прошлой версии на Samsung S26 Ultra (тестовый Pixel XL работает на Android 10).

---

## 6. Выполненный план к `v0.09`

### P0 — Критические дефекты (безопасность, сохранность данных, квота Spark, главный UI)
- [x] **P0.1.** Изоляция данных при выходе из Google и диалог предпросмотра слияния/замены при входе.
- [x] **P0.2.** Инкрементальная синхронизация Firestore по `pendingChangesTable`, фильтр эха, debounce, lifecycle-синк, очистка старых пометок удаления и сброс удалённого активного профиля.
- [x] **P0.3.** Полноширинная кнопка «Подобрать», удаление `Match вдвоём` и `Flexible`/`ellipsis` для имени профиля в шапке.
- [x] **P0.4.** Отключение Google Auto Backup (`allowBackup="false"`, `data_extraction_rules.xml`) и безопасное восстановление `SecretStore`.

### P1 — Важные баги, соответствие ТЗ и UX
- [x] **P1.1.** Обработка ошибок CSV-импорта, `StatefulWidget` для диалогов с контроллерами, сохранение ключей на первом шаге онбординга.
- [x] **P1.2.** Сохранение выбранного языка контента при поиске и CSV-импорте на латинице, поддержка Windows-1251 и защита от ложных совпадений без года.
- [x] **P1.3.** Усиление `firestore.rules` и расширение тестов эмулятора (`4/4`).
- [x] **P1.4.** Раздельный кэш и история на профиль, проверка `±1 год` и реальной длительности `<= 90 мин`, пагинация выдачи, ручная модель Gemini и атрибуция TMDB.
- [x] **P1.5.** Сканер QR камерой для StarTV, предварительный `GET /api/status`, повторное подключение при `401` и отправка удалённых профилей.
- [x] **P1.6.** `ScrollController` в карточке, двухрядные оценки `1–5`/`6–10`, перевод стран и ролей, 4 видимые вкладки в «Моё», Undo при удалении, подтверждение удаления коллекции, фикс очереди цифровых релизов.

### P2 — Платформенная полировка, локализация и тесты
- [x] **P2.1.** Адаптивная иконка Android, монохромная иконка уведомлений, тёмный сплеш `#0B0D11`, `network_security_config.xml`, `flutter_localizations`, переводы и переименование/удаление профилей, копирование диагностики.
- [x] **P2.2.** Написаны и пройдены unit/widget-тесты Этапов 1–3 (`57/57`, `stage1_sync_isolation_test.dart`, `stage2_3_improvements_test.dart`).

### v0.11 — Синхронизация со StarTV v0.8, новый брендинг и безопасность (2026-11-16)
- [x] **Логотипы и брендинг**: доработаны пользовательские логотипы (`Logo/`), обновлены иконки запуска Android (`mipmap-*`, `ic_launcher_background.xml` `#0B0D11`), монохромная иконка уведомлений (`ic_stat_starfilm.xml`), ассеты для GitHub (`docs/logo.png`, `docs/banner.png`) и UI-логотипы внутри приложения (`assets/images/starfilm_icon.png`, `starfilm_logo.png` на экране онбординга, в AppBar и настройках).
- [x] **Синхронизация и сопряжение со StarTV**: `StarTvClient.syncLibrary` и `AppController.syncWithHomeTv()` обновляют список установленных на ТВ плееров (`installedPlayers`) из ответа `/api/library-sync` (с fallback на `fetchStatus`) и сохраняют обновлённый `StarTvDevice`. В `StarTvPairingDialog` и `StarTvQrPayload.tryParseHostPort` добавлен разбор ручного ввода `IP:port` / `http://ip:port` и разделены ошибки неверного IP (`startv_error_lan`) и неверного QR (`startv_invalid_qr`).
- [x] **Firestore Rules & README**: в `firestore.rules` добавлена валидация `collectionId` по регулярному выражению `^[A-Za-z0-9_-]{1,48}$` (добавлен тест в `tools/firestore_rules_test/rules.test.mjs`). `README.md` переписан на украинском языке с актуальным описанием и логотипами.
- [x] **Проверки**: `flutter analyze` (0 замечаний), `flutter test` (63/63, включая `dual_sync_and_tv_fixes_test.dart`), эмулятор Firestore (`4/4`).

### v0.12 — Исправление OTA-проверки подписи, Gemini моделей и поиска (2026-11-17)
- [x] **OTA-установка и проверка подписи**: в `android/app/build.gradle.kts` включены `enableV1Signing = true` и `enableV2Signing = true`; в `MainActivity.kt` (`getInstalledSigningSha256`, `getArchiveSigningSha256`, `extractCertSha256`) добавлена комбинированная проверка `GET_SIGNING_CERTIFICATES | GET_SIGNATURES` и резервное чтение сертификатов из `JarFile` (`META-INF/*.RSA|DSA|EC`).
- [x] **Диалог обновления**: в `SettingsScreen.formatReleaseNotes` добавлена очистка сырого Markdown (`##`, `**`, `` ` ``, `- ` -> `• `) для читаемого отображения заметок релиза.
- [x] **Gemini модели и язык контента**: в `GeminiClient` и `AppController` заменены устаревшие/несуществующие `3.x`-идентификаторы на `gemini-2.5-flash-lite` с автоматическим фолбэком `gemini-2.5-flash-lite` → `gemini-2.5-flash` → `gemini-flash-lite-latest`, нормализацией сохранённых настроек в `bootstrap()` и синхронизацией `contentLanguage` активного профиля в `setUiLanguage`.
- [x] **Умный поиск и фонетическая транслитерация**: в `TmdbMatcher.phoneticLatinQuery` и `TmdbClient` добавлена транслитерация запросов вроде `стрит файтер` → `street fighter`; в `DiscoveryService` добавлен прямой поиск по `prompt`, автоопределение жанров по запросу для backfill и исправлено условие `usedFallback`.
- [x] **Проверки**: `flutter analyze` (0 замечаний), `flutter test` (65/65).

### v0.13 — Каскад AI + резервный ключ, точный поиск фильмов и иконка без круга (2026-11-26)
- [x] **Каскад моделей Gemini и резервный бесплатный AI-ключ**:
  - В `GeminiClient` (`lib/features/discovery/gemini_client.dart`) обновлены актуальные бесплатные модели (`gemini-3.5-flash-lite`, `gemini-3.1-flash-lite`, `gemini-3.6-flash`, `gemini-3.8-flash`, `gemini-4-hydrogen`, `gemini-2.5-flash-lite`, `gemini-2.5-flash`, `gemini-flash-lite-latest`), настроены совместимые параметры `thinkingConfig` (`minimal` для `3.5`/`3.1`/`3.6`, `low` для `3.8`/`4-*`, `thinkingBudget: 0` для `2.5`), добавлен повтор при `HTTP 400` с упрощённым конфигом, кэш 404/cooldown 429 на 90 с и автопоиск доступных текстовых моделей через `GET /v1beta/models`.
  - Добавлена поддержка резервного AI-ключа (`SecretStore.getBackupAiKey`/`setBackupAiKey`, `SettingsScreen` + `DiagnosticsLog`/`LogSanitizer`): поддерживаются второй ключ **Gemini (`AIza...`)**, бесплатный **Groq (`gsk_...`)** и бесплатный **OpenRouter (`sk-or-...`)** (включая список ключей через запятую/перенос строки) с кнопкой проверки и автоматическим переключением при исчерпании/сбое основного ключа.
  - В `DiscoveryTab` добавлено отображение реальной причины fallback вместо общего сообщения об ошибке Gemini.
- [x] **Точный поиск по названию фильма (`RU / UK / EN`)**:
  - В `TmdbMatcher` и `TmdbClient.searchCatalog` (`lib/features/search/tmdb_matcher.dart`, `tmdb_client.dart`) реализован многоисточниковый поиск (`/3/search/movie` + `/3/search/tv`), кросс-локальные запросы (`ru-RU` / `uk-UA` / `en-US` с сохранением локализованного заголовка профиля), фонетический merge при непустых ответах, подгрузка 2-й страницы, опциональные подсказки через `KinopoiskClient.searchTitleHints` и ранжирование, гарантирующее вывод точного совпадения на 1-е место выше более популярных сиквелов/частичных совпадений.
  - В `DiscoveryService` точные совпадения по явному запросу закрепляются в начале списка (`isExactMatch`), а при отказе AI добор идёт через похожие фильмы TMDB `/recommendations` перед `/discover`.
  - В `SearchTab` и `DiscoveryTab` добавлены бейдж «Точное совпадение», вторая строка `originalTitle`, кнопка очистки запроса и кнопка сброса скрывающих фильтров.
- [x] **Прозрачная иконка Android без чёрного круга**: удалена адаптивная обёртка `mipmap-anydpi-v26/ic_launcher.xml`, `ic_launcher_background.xml` и `ic_launcher_foreground.png`; в `mipmap-mdpi..xxxhdpi/ic_launcher.png` сгенерированы прозрачные RGBA-иконки звезды из `Logo/star_transparent_master.png`.
- [x] **Проверки**:
  - `flutter analyze` → `No issues found!`;
  - `flutter test` → `67/67 All tests passed!` (обновлены и расширены `test/discovery_and_tmdb_test.dart`, `test/stage2_3_improvements_test.dart`);
  - `powershell -NoProfile -File tools/build_apk.ps1` → версия повышена до `v0.13` (`versionCode=13` в `version.txt`), собран подписанный release `StarFilm.apk` (`78.57 MB`).
  - **Живая проверка на Pixel XL (Android 10, USB `HT6AD0200687`)**:
    - Иконка лаунчера: зелёная звезда StarFilm на стандартном белом круге Pixel Launcher (без чёрного круга).
    - Настройки и диагностика: пункт `Резервный AI-ключ (Gemini / Groq / OpenRouter)`, строка `Backup AI: нет • Model: ...`.
    - Живой ИИ-подбор: по запросу `heist thriller` каскад перехватил реальный `HTTP 404` от устаревшей `gemini-2.5-flash-lite` и выдал живые рекомендации без перехода в режим ошибки; по запросу `Inception` первым закреплён «Начало» с бейджем «Точное совпадение».
    - Точный поиск: `Drive` → №1 «Драйв» (`Drive`, 2011) + кнопка очистки `✕`; `Squid Game` → №1 «Игра в кальмара» (`Точное совпадение`, `오징어 게임`); проверено появление и восстановление по кнопке «Сбросить фильтры» при скрытии результатов фильтрами.
    - Чистое завершение: удалена случайная тестовая запись, синхронизация прошла (`Ожидает синхронизации: 0`), итоговая база и диагностика чистые (`Профилей: 3 • Записей: 35`, без сбоев).
  - *Не проверялось вживую на устройстве*: реальные резервные ключи `Groq`/`OpenRouter`, отображение иконки в сторонних лаунчерах (`Nova`/`One UI`) и системный запрос разрешения уведомлений на Android 13+.

### Следующий шаг
- Собрать обратную связь по работе AI-каскада, резервного ключа и точного поиска в `v0.13` для планирования `v0.14`.

---

## 7. Архив закрытого бэклога (закрыто в v0.04)

- [x] 1. Локализованное название в буфер обмена (`mobile_players.dart`).
- [x] 2. Инлайн-проверка ключей на онбординге (`onboarding_screen.dart`).
- [x] 3. Прямой перевод из «Переглянуто» в «Хочу подивитися» (`app_state.dart`, `library_entry.dart`).
- [x] 4. Импорт JSON-бэкапа: режим восстановления снимка (`library_repository.dart`, `settings_screen.dart`).
- [x] 5. Интеграция HDRezka MOD (`to.pda.falcofemoralis.hdrezkaapp`) и иконка приложения в `mipmap-*`.
