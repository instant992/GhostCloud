# GhostCloud

Прокси-клиент на основе ClashMeta, простой и удобный в использовании, с открытым исходным кодом.

## Сборка

### Требования

- Flutter SDK >= 3.5.0
- Go (для сборки ядра)
- Rust (для Helper Service на Windows)

### Конфигурация

Перед сборкой:
1. Скопируйте `android/app/google-services.json.example` → `android/app/google-services.json` и заполните данными вашего Firebase проекта
2. Отредактируйте `lib/config/fox_config.dart`:
```dart
static const String telegramBotUsername = 'ваш_бот';
static const String authServerUrl = 'https://ваш-домен/api/auth';
```

### Android

```bash
flutter build apk --split-per-abi
```

### Windows

```bash
dart setup.dart windows --arch amd64 --out app
```

## Технологии

- Flutter + Riverpod
- ClashMeta core (Mihomo)
- Firebase Cloud Messaging (push-уведомления)

## Основан на

- [FlClash](https://github.com/chen08209/FlClash) — Clash Meta клиент
- [Mihomo](https://github.com/MetaCubeX/mihomo) — Clash.Meta ядро

## Автор

- [instant992](https://github.com/instant992)

## Особая благодарность

- [pluralplay](https://github.com/pluralplay)

## Лицензия

GPL-3.0

GPL-3.0
