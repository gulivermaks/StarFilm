# StarFilm — настройка бесплатной синхронизации Firebase Spark

> Один Firebase-проект на всех друзей. Пользователи **не регистрируют свои Firebase-проекты**; они только входят в приложение через Google.

## Настройка владельцем (один раз)

1. Сгенерировать постоянный релизный ключ подписи APK `starfilm-release.jks` (хранить локально вне Git) и снять отпечатки **SHA-1 и SHA-256** (а также SHA-1/SHA-256 локального `debug.keystore` для разработки).
2. Открыть https://console.firebase.google.com/ и создать проект `StarFilm`.
3. Оставить тариф **Spark / No-cost**. **Не добавлять платёжный аккаунт и не переходить на Blaze.**
4. Зарегистрировать Android-приложение с выбранным постоянным `applicationId` (например, `io.freemytv.starfilm` или `app.starfilm.android` — зафиксировать до первой сборки).
5. Добавить в настройки Android-приложения в Firebase отпечатки **SHA-1 и SHA-256** релизного и отладочного ключей; включить **Authentication → Sign-in method → Google** и скачать `google-services.json` (убедиться, что в нём присутствует `oauth_client` типа `3` — Web Client ID, нужный для Android Credential Manager).
6. Создать **Cloud Firestore (Standard, одну базу)**. Выбрать ближайший европейский регион (например, `eur3`), развернуть строгие правила доступа (см. ниже).
7. Подключить во Flutter пакеты `firebase_core`, `firebase_auth`, `cloud_firestore`, `google_sign_in`. Сгенерировать FlutterFire-конфигурацию и проверить Google-вход **в подписанном релизном APK** (`v0.01+`).
8. Синхронизировать **только** профили (`main` + `p_*`), статусы, оценки, пользовательские коллекции, вкусовые фильтры и компактный срез карточки (`title`, `originalTitle`, `year`, `posterPath`, `genreIds`). Длинные описания (`overview`), актёров и файлы картинок не писать в Firestore — кешировать локально из TMDB.
9. Инкрементальный курсор синхронизации строить по серверному времени `serverSyncedAt` (`FieldValue.serverTimestamp()`), а пакетные записи `WriteBatch` дробить чанками до **450 операций**.
10. В консоли периодически проверять расход чтений, записей и объём хранилища (лимиты Spark: 1 ГиБ, 50k reads/day, 20k writes/day, 20k deletes/day на весь проект). При исчерпании квоты приложение остаётся в локальном режиме без включения биллинга.

## Настройка другом (в приложении)

1. Установить подписанный `StarFilm.apk` (из `gulivermaks/StarFilm` Releases).
2. Получить личный Gemini API key в https://aistudio.google.com/apikey и личный TMDB API key в https://www.themoviedb.org/settings/api.
3. Ввести ключи в настройки StarFilm и нажать «Перевірити» (ключи хранятся в Android Keystore и **никогда не отправляются в Firebase**).
4. По желанию нажать **«Увійти через Google»** для облачной синхронизации между своими телефонами. Это обычный вход через Google-аккаунт без консолей и Firebase-ключей.
5. На втором смартфоне войти под тем же Google-аккаунтом — профили, названия, постеры и оценки подтянутся сразу. Личные ключи Gemini/TMDB вводятся на втором телефоне отдельно.

## Базовые правила Firestore Security Rules (проверить в Firebase Emulator)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function isOwner(userId) {
      return request.auth != null && request.auth.uid == userId;
    }

    match /users/{userId} {
      allow read: if isOwner(userId);
      allow create, update: if isOwner(userId)
        && request.resource.data.keys().size() <= 10;

      match /profiles/{profileId} {
        allow read: if isOwner(userId);
        allow write: if isOwner(userId)
          && profileId.matches('^(main|p_[a-z0-9]{4,16})$')
          && (!('name' in request.resource.data) || request.resource.data.name.size() <= 24);

        match /library/{itemKey} {
          allow read: if isOwner(userId);
          allow write: if isOwner(userId)
            && itemKey.matches('^(movie|tv)_[0-9]{1,10}$')
            && request.resource.data.keys().size() <= 20
            && (!('title' in request.resource.data) || request.resource.data.title.size() <= 200)
            && (!('originalTitle' in request.resource.data) || request.resource.data.originalTitle.size() <= 200)
            && (!('posterPath' in request.resource.data) || request.resource.data.posterPath.size() <= 160);
        }

        match /collections/{collectionId} {
          allow read: if isOwner(userId);
          allow write: if isOwner(userId)
            && collectionId.size() <= 48
            && (!('title' in request.resource.data) || request.resource.data.title.size() <= 60)
            && (!('mediaKeys' in request.resource.data) || request.resource.data.mediaKeys.size() <= 500);
        }
      }
    }
  }
}
```

**Никогда** не использовать `allow read, write: if true` в рабочем проекте. Перед раздачей APK прогнать тесты изоляции двух разных `uid` в Firebase Local Emulator.

## При недоступности облака

- Пользователь продолжает работать с локальной базой Drift/SQLite и видит статус «Не синхронізовано».
- Изменения накапливаются в локальной очереди `pendingChanges` и отправляются после восстановления квот/сети.
- Всегда доступен автономный экспорт/импорт резервной копии JSON (`starfilm_backup.json` и импорт бэкапа StarTV).

Официальные условия: https://firebase.google.com/docs/projects/billing/firebase-pricing-plans и https://firebase.google.com/docs/firestore/quotas.
