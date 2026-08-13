# Pterodactyl Mobile

Natywna (bez WebView) aplikacja mobilna do zarządzania wieloma instancjami
Pterodactyl Panel z jednego urządzenia: lista serwerów, status i metryki
runtime w czasie rzeczywistym, live konsola przez WebSocket, akcje
zasilania (start/stop/restart/kill).

Szczegółowa architektura, decyzje projektowe i design system:
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Stack technologiczny

- **Flutter** 3.38+ (kanał stable) / **Dart** SDK `^3.10.7`
- **Riverpod** — state management (`flutter_riverpod`)
- **go_router** — nawigacja (`StatefulShellRoute`)
- **dio** — HTTP client
- **web_socket_channel** — realtime konsoli/Wings
- **flutter_secure_storage** — szyfrowane przechowywanie API key (Android
  Keystore / iOS Keychain)
- Docelowe platformy: **Android** (aktywnie rozwijane i testowane), iOS
  (szkielet obecny, niewalidowany na tym etapie)

## Wymagania developerskie

- Flutter 3.38+ / Dart `^3.10.7` — sprawdź: `flutter --version`
- Android SDK **37** z zaakceptowanymi licencjami:
  `flutter doctor --android-licenses`
  (`compileSdk 37` wymagane przez `flutter_secure_storage`, patrz
  `android/app/build.gradle.kts`)
- Xcode (tylko macOS) — wyłącznie jeśli budujesz na iOS

## Uruchomienie projektu

```bash
flutter pub get
flutter run                  # na podłączonym urządzeniu/emulatorze
```

## Testy i analiza statyczna

```bash
flutter analyze              # musi przechodzić bez ostrzeżeń
flutter test                 # cały pakiet testów (widget + unit)
```

## Build APK

```bash
flutter build apk --debug                        # debug, do testów na urządzeniu
flutter build apk --release                       # release, wszystkie ABI w jednym pliku
flutter build apk --release --split-per-abi        # release, mniejsze pliki per architektura
```

Aplikacja jest obecnie podpisywana kluczem debug również w buildzie
release (`android/app/build.gradle.kts`, `signingConfig =
signingConfigs.getByName("debug")`) — nie ma jeszcze skonfigurowanego
prawdziwego keystore'a release. To świadomy, tymczasowy stan; realny
keystore i `key.properties` (już wykluczone w `android/.gitignore`) mają
zostać dodane przy konfiguracji release-signingu, nigdy nie commitowane.

## Wersjonowanie

`pubspec.yaml` → `version: MAJOR.MINOR.PATCH+BUILD`, np. `1.0.0+1`.

- `MAJOR.MINOR.PATCH` — podnoszone ręcznie, przy realnych zmianach w
  aplikacji.
- `+BUILD` — numer builda; docelowo nadawany przez Jenkins
  (`--build-number` przy `flutter build`), nie utrzymywany ręcznie w
  repo.

Brak na razie automatycznego semantic-release — to celowe uproszczenie na
tym etapie.

## Struktura branchy

- **`main`** — branch produkcyjny. Zawiera tylko stabilny kod. Merge do
  `main` uruchamia pipeline Jenkins Production (pełna walidacja + release
  build).
- **`develop`** — główny branch developerski. Tu trafiają ukończone
  feature'y. Uruchamiany raz dziennie (nightly) pipeline Jenkins
  Develop-Nightly (pełny zestaw testów, build APK, testy na emulatorze).
- **`feature/*`** — gałęzie robocze pojedynczych zmian, odchodzą od
  `develop` i wracają do `develop` przez pull request.

### Workflow

```
feature/*  →  develop  →  (nightly Jenkins)  →  stabilizacja  →  main  →  (production Jenkins)
```

1. Nowa praca zaczyna się jako `feature/<nazwa>` odgałęziony od `develop`.
2. Ukończony feature trafia do `develop` przez pull request.
3. `develop` jest raz dziennie automatycznie budowany i testowany
   (nightly).
4. Gdy `develop` jest stabilny, robiony jest merge do `main`.
5. Merge do `main` uruchamia pełny pipeline produkcyjny.

Bez dodatkowych branchy `release/*`/`hotfix/*` na tym etapie — jeśli po
uruchomieniu CI/CD pojawi się konkretna potrzeba, zostaną dodane wtedy.
