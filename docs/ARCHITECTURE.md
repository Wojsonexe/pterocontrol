# Architektura — Pterodactyl Mobile

> Szczegółowy, chronologiczny zapis decyzji architektonicznych i stanu
> projektu krok po kroku. Po szybki start, listę komend i strukturę
> branchy zobacz [`README.md`](../README.md) w katalogu głównym repo.
> Niektóre fragmenty poniżej (np. nazwy zakładek w sekcji "Nawigacja i
> ekrany") mogą odbiegać od najnowszego stanu UI — ten dokument opisuje
> architekturę i decyzje, nie jest źródłem prawdy o bieżącym wyglądzie
> ekranów.

Natywny (bez WebView) klient mobilny do zarządzania wieloma instancjami
Pterodactyl Panel z jednego konta na urządzeniu.

Stan projektu: **fundament aplikacji** (Instance Manager, bezpieczne
przechowywanie poświadczeń) + **prawdziwa, live konsola przez WebSocket**
(realny protokół Wings — auth, reconnect, mapowanie zdarzeń) + **spójny,
produkcyjny Design System** + **pełna nawigacja mobilna** — bottom nav
(Panel/Serwery/Aktywność/Ustawienia) osadzona przez `go_router`'s
`StatefulShellRoute`, wieloetapowy onboarding dodawania panelu z realnym
testem połączenia, i ekrany dla każdej funkcji z mapy IA (Files/Backupy/
Ustawienia serwera pokazują uczciwy stan „Wkrótce” tam, gdzie nie ma
jeszcze integracji API — patrz [Nawigacja i ekrany](#nawigacja-i-ekrany)).
Patrz [Zakres tego kroku](#zakres-tego-kroku).

## Wymagania

- Flutter 3.38+ (kanał stable), Dart SDK ^3.10.7 — sprawdź: `flutter --version`
- Android SDK **37** z zaakceptowanymi licencjami:
  `flutter doctor --android-licenses` (patrz uwaga w `android/app/build.gradle.kts`
  — `flutter_secure_storage` wymaga `compileSdk 37`, wyżej niż domyślne 36
  tej wersji Fluttera; kompatybilne wstecznie z `minSdk`)
- Xcode (tylko na macOS) do budowania na iOS — nieużywane na tym etapie,
  ale architektura jest z nim kompatybilna (patrz [Architektura](#architektura))

## Uruchomienie projektu

```bash
cd mobile
flutter pub get
flutter analyze      # statyczna analiza — musi przechodzić bez ostrzeżeń
flutter test         # cały pakiet testów
flutter run          # uruchomienie na podłączonym urządzeniu/emulatorze
flutter build apk --debug   # build Androida (wymaga zaakceptowanych licencji SDK)
```

Domyślny target to Android. Projekt zawiera też szkielet `ios/` wygenerowany
przez `flutter create` — nieużywany jeszcze aktywnie, ale nic w kodzie `lib/`
nie zakłada platformy (brak platform-specific API poza standardowymi
pluginami Fluttera — `flutter_secure_storage` samo obsługuje Keychain na
iOS), więc `flutter run -d ios`/`flutter build ios` powinny działać bez
zmian w kodzie aplikacji, gdy będzie taka potrzeba.

## Zakres tego kroku

**Krok 1 (fundament):** Instance Manager — dodawanie/usuwanie/wybór
instancji Pterodactyl Panel, przechowywanie metadanych lokalnie, routing,
motyw Material 3.

**Krok 2:** pierwszy kompletny pionowy przekrój — `Instance →
PterodactylApiClient → GET /api/client → lista serwerów → ServersScreen →
wybór serwera → ServerDetailScreen`, z pełną izolacją między instancjami
(patrz [Instance scoping](#instance-scoping)).

**Krok 3 (ten commit):**
- Prawdziwe bezpieczne przechowywanie poświadczeń (`SecureCredentialStorage`,
  Android Keystore / iOS Keychain przez `flutter_secure_storage`), w miejsce
  placeholdera `InMemoryCredentialStorage` — patrz
  [Secure storage poświadczeń](#secure-storage-poświadczeń).
- Server power actions: `POST /api/client/servers/{server}/power`
  (start/restart/stop/kill) — pełny przepływ
  presentation → application → repository → API → `PterodactylApiClient`,
  z potwierdzeniem dla `kill`.

**Krok 4:** fundament architektoniczny pod przyszłą konsolę live i dalsze
funkcje realtime — modele domenowe (`ServerRuntimeState`,
`ConsoleConnectionState`, `ConsoleEvent`) bez żadnego kodu WebSocket.

**Krok 5:** prawdziwa integracja konsoli live przez WebSocket Wings —
`GET /api/client/servers/{server}/websocket` → połączenie WS bezpośrednio
do node'a → autentykacja (`auth`/`auth success`) → mapowanie zdarzeń Wings
na `ConsoleEvent`/`ServerRuntimeState` → reconnect z exponential backoff.
Patrz [Konsola live przez WebSocket](#konsola-live-przez-websocket).

**Krok 6:** Design System + migracja całego UI na produkcyjny wygląd —
jeden spójny system typografii/spacingu/radiusów/kolorów semantycznych
(`core/theme/`), wspólne komponenty statusu/sekcji/metryk
(`core/presentation/widgets/`) zastępujące wcześniejsze zduplikowane
implementacje, poprawka realnego błędu (surowe kody ANSI wyświetlane jako
tekst w konsoli zamiast kolorowanego outputu). Patrz
[Design System](#design-system).

**Krok 7 (ten commit):** pełna architektura nawigacji i information
architecture całej aplikacji — bottom-nav shell (`StatefulShellRoute
.indexedStack`) z czterema zakładkami, Dashboard, przebudowany Server List
(wyszukiwanie/sortowanie/skeleton loading), `ServerDetailScreen` jako hub
z zakładkami (Przegląd/Konsola/Pliki/Backupy/Ustawienia), wieloetapowy
onboarding dodawania panelu z **realnym** testem połączenia
(`InstanceListController.testConnection`), oraz kompletny hub Ustawień
(Konto/Połączenie/Wygląd z działającym przełącznikiem motywu/
Bezpieczeństwo/Informacje). Patrz [Nawigacja i ekrany](#nawigacja-i-ekrany).

Świadomie **nie** zaimplementowano jeszcze:

- logowania przez parowanie QR,
- ECC / szyfrowania end-to-end,
- komunikacji z centralnym backendem (push, sync),
- push notifications,
- własnego forka Pterodactyla,
- synchronizacji zero-knowledge,
- biometrii / blokady aplikacji przed dostępem do `SecureCredentialStorage`,
- jakiegokolwiek WebView,
- rzeczywistej integracji z REST API plików/backupów/ustawień
  startup+environment serwera — `ServerDetailScreen` ma już na nie zakładki
  (Pliki/Backupy/Ustawienia), ale każda pokazuje uczciwy stan „Wkrótce”
  (`ComingSoonView`), nie fałszywe dane — patrz
  [Nawigacja i ekrany](#nawigacja-i-ekrany),
- profilu konta (`GET /api/client/account`) i blokady biometrycznej —
  Ustawienia → Konto/Bezpieczeństwo mają swoje ekrany, też z `ComingSoonView`,
- historii aktywności/powiadomień push — zakładka „Aktywność” to również
  `ComingSoonView`,
- wysyłania komend do konsoli w ramach osobnego, rozbudowanego UI (historia
  komend, autouzupełnianie) — jest proste pole tekstowe + wysyłka
  (`ConsoleController.sendCommand`), bo protokół i architektura i tak już to
  wspierają (patrz niżej), ale nic ponad to minimum.

**Krok 10 (ten commit):** przeprojektowanie Dashboardu na poziom "produktu,
który można pokazać klientowi" — bez zmiany architektury danych/realtime z
Kroku 8. Nowości: jeden **unified status badge** per serwer
(`effectiveServerStatus` — łączy status administracyjny Panelu i żywy stan
zasilania Wings w jedną, jednoznaczną odpowiedź zamiast dwóch osobnych
plakietek obok siebie), realna, krótka historia próbek na serwer
(`ServerMetricsHistory`/`MetricSample`, akumulowana w
`ServerRuntimeSyncController` z każdego udanego polla — **nigdy**
generowana), `Sparkline` (lekki wykres CustomPainter) zasilany tą historią
na karcie "Wykorzystanie zasobów", realny throughput sieci (bajty/s
wyliczane z różnicy dwóch kolejnych realnych odczytów licznika
kumulatywnego, nie zmyślone), pierścień stanu infrastruktury
(`_InfrastructureHealthCard`) zamiast trzech równoważnych kart, oraz
minimalny wskaźnik `SyncStatusIndicator` (kropka + etykieta, bez plakietki
tła) pokazujący też stan `syncing`/reconnecting zamiast go ukrywać. Patrz
[Design System](#design-system) (sekcja o pierścieniu/sparkline) oraz
[Synchronizacja stanu serwerów w czasie rzeczywistym](#synchronizacja-stanu-serwerów-w-czasie-rzeczywistym)
(architektura danych, niezmieniona).

**Krok 9:** przebudowa całego systemu UI/UX od podstaw — nowy
design system (paleta marki zamiast `ColorScheme.fromSeed`, para krojów
Sora/Inter zbundlowana lokalnie, osobny system powierzchni light/dark,
scentralizowany system ruchu), nowe komponenty wielokrotnego użytku
(`AppCard`, `AppTopBar`, `AppBottomNav`, `AppSearchField`, `showFilterSheet`,
`MetricCard`, `UsageBar`, `StatusDot`, `FadeSlideIn`), oraz przebudowa
Dashboardu (hierarchiczna karta podsumowania zamiast trzech równorzędnych
kart, agregacja żywego CPU/RAM, szybkie akcje), listy serwerów
(`ServerCard` z paskiem akcentu/żywymi paskami użycia, filtrowanie statusu,
sortowanie przez arkusz), ekranu szczegółów serwera (karta "Na żywo" z
paskami CPU/RAM), ekranu paneli i dolnej nawigacji. Żadna z dotychczasowej
architektury real-time sync (Krok 8) nie została naruszona — to przebudowa
wyłącznie warstwy prezentacji na tych samych danych/providerach. Patrz
[Design System](#design-system).

**Krok 8:** prawdziwa synchronizacja stanu serwerów w czasie
rzeczywistym na Dashboardzie/liście/ekranie szczegółów — bez ręcznego
odświeżania. Polling `.../resources` w tle (`ServerRuntimeSyncController`),
scalanie z żywym strumieniem WebSocketu konsoli tam, gdzie jest już
połączony, obsługa tła/pierwszego planu aplikacji (`AppLifecycleController`,
współdzielony z konsolą), targetowane odświeżanie jednego serwera
(`ServerListController.refreshOne`) zamiast całej listy po zdarzeniu
`install completed`/`backup restore completed`, oraz subtelny wskaźnik
"Na żywo/Offline" w nagłówku ekranu (`SyncStatusIndicator`). Patrz
[Synchronizacja stanu serwerów w czasie rzeczywistym](#synchronizacja-stanu-serwerów-w-czasie-rzeczywistym).

Dodawanie instancji odbywa się przez prosty formularz (nazwa, URL, klucz API
wklejony ręcznie).

## Struktura katalogów

```
lib/
  app/                          # Kompozycja aplikacji: MaterialApp, routing
    app.dart                    # Root widget (theme + router)
    app_provider_policy.dart    # Wyłącza domyślny auto-retry Riverpoda — patrz niżej
    router/
      app_router.dart           # GoRouter — pre-shell routes + StatefulShellRoute.indexedStack
      app_routes.dart           # Stałe ze ścieżkami tras
    shell/
      root_screen.dart          # Splash / panel picker / redirect do Dashboardu — jedyna bramka do /app
      splash_screen.dart        # Branded ekran ładowania
      app_shell.dart            # Bottom nav (NavigationBar) wokół StatefulNavigationShell

  core/                         # Kod współdzielony między feature'ami,
                                 # bez wiedzy o konkretnym feature
    error/
      app_exception.dart        # Sealed hierarchy błędów domenowych
      result.dart                # Result<T> = Success | Failure
    network/
      pterodactyl_api_client.dart  # Generyczny klient HTTP (get/post/put/delete)
      api_client_factory.dart      # Buduje klienta per-instancja (baseUrl + auth + bezpieczny debug-logger)
      api_client_config.dart       # Timeouty
      api_exception_mapper.dart    # DioException -> AppException
      pterodactyl_envelope.dart    # Dekoduje kopertę Fractal {object,attributes}/{data,meta}
      interceptors/
        auth_interceptor.dart      # Nagłówek Authorization: Bearer
      network_providers.dart       # Provider<PterodactylApiClientFactory>
    storage/
      shared_preferences_provider.dart  # Provider<SharedPreferences> (override w main()) — TYLKO metadane, nigdy sekrety
    theme/                       # Design System — patrz niżej
      app_theme.dart             # ThemeData light()/dark() — jedyne źródło prawdy: typografia/kolory/buttony/karty/inputy
      app_theme_mode_controller.dart  # Persystowany wybór light/dark/system (SharedPreferences) — Ustawienia -> Wygląd
      app_typography.dart        # AppTypography — jawny TextTheme + styl terminala
      app_spacing.dart           # AppSpacing — tokeny odstępów (xxs..xxxl)
      app_radius.dart            # AppRadius — tokeny promieni (xs/sm/md/lg/full)
      app_semantic_colors.dart   # AppSemanticColors — ThemeExtension: success/pending/danger/neutral
      app_console_colors.dart    # AppConsoleColors — ThemeExtension: paleta terminala (zawsze ciemna)
      app_status_tokens.dart     # AppStatusTone, AppStatusVisual — dane pod AppStatusBadge
    presentation/widgets/
      empty_state_view.dart      # Generyczny "pusty stan"
      error_view.dart            # Generyczny widok błędu + retry
      app_status_badge.dart      # Jeden wspólny badge statusu (icon+label+kolor+kształt), zastępuje 3 duplikaty
      section_header.dart        # Nagłówek sekcji ekranu + opcjonalny trailing
      metric_grid.dart           # Kompaktowy grid metryk (2 kolumny), zamiast stosu ListTile
      skeleton_box.dart          # Pulsujący placeholder pod skeleton loading (karty serwerów, dashboard)
      coming_soon_view.dart      # Uczciwy stan "funkcja jeszcze niezaimplementowana" (Files/Backupy/Konto/...)

  features/
    authentication/              # Bezpieczne przechowywanie poświadczeń
      domain/
        instance_credentials.dart   # Value object (apiKey) — bez toString() z polami, patrz testy
        credential_storage.dart     # Interfejs: save/read/delete, per instanceId
      data/
        secure_credential_storage.dart  # Android Keystore / iOS Keychain (flutter_secure_storage)
      application/
        credential_storage_provider.dart  # jedyne miejsce, które trzeba zmienić przy kolejnej podmianie

    instances/                   # Instance Manager
      domain/
        pterodactyl_instance.dart    # Encja domenowa (bez HTTP/JSON)
        instance_repository.dart     # Interfejs repozytorium (tylko metadane, nigdy credentiale)
        instance_url_validator.dart  # Walidacja/normalizacja URL panelu
      data/
        instance_local_dto.dart      # DTO JSON do SharedPreferences
        local_instance_repository.dart
      application/
        instance_list_state.dart     # Stan: lista + aktywna instancja
        instance_list_controller.dart # Riverpod AsyncNotifier — Instance Manager (+ testConnection, patrz niżej)
        instance_providers.dart      # Provider<InstanceRepository>
        instance_api_client_provider.dart  # PterodactylApiClient per-instancja (patrz Instance scoping)
      presentation/
        screens/
          instances_screen.dart      # Lista paneli — root picker ORAZ Ustawienia -> Połączenia (patrz RootScreen)
          add_instance_screen.dart   # Wieloetapowy wizard: URL -> klucz API -> nazwa+test połączenia -> sukces
        widgets/
          instance_tile.dart
          connection_status_chip.dart
          empty_instances_view.dart

    dashboard/                   # Zakładka "Panel" — landing po aktywacji instancji
      presentation/screens/
        dashboard_screen.dart      # Podsumowanie (liczba/status serwerów, real dane) + podgląd listy

    activity/                    # Zakładka "Aktywność" — historia zdarzeń/powiadomienia
      presentation/screens/
        activity_screen.dart       # ComingSoonView — brak API dziennika aktywności/push

    settings/                    # Zakładka "Ustawienia"
      presentation/screens/
        settings_screen.dart               # Hub: Konto/Połączenie/Aplikacja/Bezpieczeństwo/Informacje
        application_settings_screen.dart   # Realny przełącznik motywu (AppThemeModeController)
        account_settings_screen.dart       # ComingSoonView
        security_settings_screen.dart      # ComingSoonView
        about_screen.dart                  # Wersja + showLicensePage (wbudowane we Flutter, zero zależności)

    servers/                     # Lista, szczegóły i akcje zasilania serwerów aktywnej instancji
      domain/
        server.dart                  # Encja Server, ServerLimits, ServerAdministrativeStatus
        server_page.dart             # Jedna strona wyników (paginacja)
        server_power_action.dart     # enum start/stop/restart/kill
        server_power_state.dart      # enum: rzeczywisty stan zasilania (unknown/offline/starting/running/stopping)
        server_runtime_state.dart    # ServerPowerState + kiedy zaobserwowany — bez producenta, patrz niżej
        server_repository.dart       # Interfejs repozytorium (scoped do 1 instancji)
      data/
        server_dto.dart              # Surowy kształt JSON serwera
        servers_api.dart             # Zna GET /api/client i POST .../power
        server_repository_impl.dart  # Mapowanie DTO -> domain, Result -> throw
      application/
        server_list_state.dart
        server_list_controller.dart  # AsyncNotifier.family<..., String instanceId>
        server_power_action_controller.dart  # AsyncNotifier.family<..., ServerActionTarget>
        servers_providers.dart       # Provider.family: ServersApi, ServerRepository
      presentation/
        screens/
          servers_screen.dart        # Zakładka "Serwery": szukaj/sortuj/skeleton, pełny top-level ekran
          server_detail_screen.dart  # Hub serwera: TabBar Przegląd/Konsola/Pliki/Backupy/Ustawienia
        widgets/
          server_tile.dart
          server_status_chip.dart
          empty_servers_view.dart
          server_power_actions.dart  # Start/Restart/Stop + osobna "danger zone" dla Kill

    console/                     # Konsola live jednego serwera przez WebSocket Wings
      domain/
        console_connection_state.dart  # enum: cykl życia połączenia WS
        console_event.dart             # ConsoleEvent + ConsoleEventType (output/daemonMessage/daemonError/unknown)
        console_target.dart            # typedef ConsoleTarget = ({instanceId, serverIdentifier})
        console_repository.dart        # Interfejs: 3 strumienie + connect/disconnect/sendCommand/dispose
      data/
        console_websocket_token_dto.dart  # {"data":{"token","socket"}} — NIE koperta Fractal
        console_api.dart                  # GET .../websocket (przez PterodactylApiClient)
        console_protocol_events.dart      # Stałe z dokładnymi nazwami zdarzeń Wings (źródło prawdy)
        console_protocol_message.dart     # Surowa ramka {"event","args"} + joinedArgs
        console_transport.dart            # Abstrakcja nad surowym WS (testowalność bez sieci)
        web_socket_channel_transport.dart # Prawdziwy transport (package:web_socket_channel), ping/pong
        console_websocket_client.dart     # Kodek: (de)koduje ramki, odrzuca zniekształcone bez crasha
        console_repository_impl.dart      # Auth, reconnect (backoff), mapowanie zdarzeń, bufor — patrz niżej
      application/
        console_state.dart           # Bundle: connectionState + runtimeState + events
        console_providers.dart       # ConsoleApi + ConsoleRepository, scoped po ConsoleTarget
        console_controller.dart      # AsyncNotifier.family<..., ConsoleTarget>
      presentation/widgets/
        console_view.dart            # Terminal: auto-scroll, jump-to-bottom, status, komendy; `fullscreen:` do osadzenia jako pełna zakładka
        ansi_text.dart                # parseAnsiToSpans — koduje kody ANSI SGR na kolorowany TextSpan (naprawia surowe "[33;1m" w outpucie)

  main.dart                      # Bootstrap: SharedPreferences -> ProviderScope(retry: noAutomaticProviderRetry) -> App

test/                            # Struktura testów odzwierciedla lib/
  support/
    fake_http_client_adapter.dart   # Fake HttpClientAdapter dla Dio, bez dodatkowej zależności
    fake_console_transport.dart     # Fake ConsoleTransport + connector — bez prawdziwego WS/sieci
    fake_console_repository.dart    # Fake ConsoleRepository (strumienie sterowane ręcznie) — dla kontrolera/UI
  app/
    app_test.dart
    servers_navigation_test.dart   # E2E: RootScreen -> Dashboard -> Servers tab -> ServerDetailScreen, fejkowany Console
  core/network/
    auth_interceptor_test.dart
    api_client_factory_test.dart   # Regresja: token nigdy nie trafia do debug-logów
  core/theme/                      # AppTheme, AppThemeModeController, AppTypography, AppSpacing, AppRadius, AppSemanticColors, AppConsoleColors, AppStatusTone/Visual
  core/presentation/widgets/       # AppStatusBadge, SectionHeader, MetricGrid
  features/instances/domain/...
  features/instances/data/...
  features/instances/application/...
  features/instances/presentation/screens/add_instance_screen_test.dart  # Nawigacja krok po kroku wizarda
  features/authentication/domain/...
  features/authentication/data/...
  features/servers/domain/...
  features/servers/data/...
  features/servers/application/...
  features/servers/presentation/...  # + wyszukiwanie w servers_screen_test.dart
  features/console/domain/...
  features/console/data/...        # protokół, WS client, API, repository (auth/reconnect/mapowanie/bufor)
  features/console/application/... # providery (izolacja instancji) + kontroler
  features/console/presentation/... # ConsoleView + ansi_text.dart (parser ANSI)
  features/dashboard/presentation/screens/dashboard_screen_test.dart
```

Katalogi `files`, `backups`, `databases`, `schedules`, `settings`
**nie istnieją jeszcze** — zostaną utworzone dopiero razem z pierwszą realną
funkcjonalnością, którą będą zawierać. Puste moduły "na zapas" celowo nie
zostały utworzone.

## Design System

Jedno spójne źródło prawdy dla wyglądu całej aplikacji, w `core/theme/` +
`core/presentation/widgets/`. Cel: żaden ekran nie wybiera koloru/paddingu/
promienia "na oko" — wszystko przechodzi przez tokeny albo `ThemeData`.

Ten system zastąpił poprzedni, oparty na `ColorScheme.fromSeed` (jeden seed
→ cała paleta wyliczona formułą) — świadomie, bo to właśnie ten mechanizm
sprawiał, że appka wyglądała jak dowolna inna wygenerowana aplikacja M3, nie
jak zaprojektowany produkt. Poniższe role są dobierane ręcznie, nie
wyliczane.

- **Typografia** — dwa kroje: **Sora** (geometryczny, nieco techniczny) dla
  wszystkiego, co czyta się jak nagłówek/liczba-na-którą-patrzysz (tytuły
  ekranów, nagłówki sekcji, wartości metryk), **Inter** (strojony pod
  czytelność w małych rozmiarach) dla treści (body, listy, etykiety) —
  zbundlowane lokalnie jako pliki variable-font (`assets/fonts/`,
  `pubspec.yaml`), **nie** przez pakiet `google_fonts` pobierający czcionkę
  w runtime — appka musi poprawnie renderować typografię offline, przy
  pierwszym uruchomieniu, i deterministycznie w testach widgetowych.
  `AppTypography.textTheme(colorScheme)` pozostaje jawnym, zablokowanym
  `TextTheme`. Tylko dwie wagi: w400 i w600. `AppTypography.metricNumber`
  — osobny styl dla wartości liczbowych (`FontFeature.tabularFigures()`,
  krój Sora), żeby cyfry w kolumnie kart metryk się wyrównywały. Terminal
  ma osobny styl (`AppTypography.terminal`, `fontFamily: 'monospace'`).
- **Spacing** — `AppSpacing` (`xxs`=4 … `xxxl`=64), skala 4dp.
- **Radius** — `AppRadius` (`xs`=8, `sm`=12, `md`=16, `lg`=24, `xl`=28,
  `full`). Karty i duże przyciski: `md`. Inputy: `sm`. Panel terminala i
  duże arkusze (bottom sheet): `lg`/`xl`. Buttony M3 domyślnie są
  pill-shaped — świadomie nadpisane na `md`.
- **System powierzchni** — `AppSurfaceColors` (`ThemeExtension`, osobne
  presety light/dark): `background`/`surface`/`surfaceElevated`/
  `surfaceActive`/`border`/`borderStrong`/`textPrimary`/`textSecondary`/
  `textTertiary` — dokładnie tyle poziomów, ile appka faktycznie
  potrzebuje do pokazania głębi bez pojedynczej ramki na każdej karcie
  (patrz `AppCard`: karta nie ma obramowania — czyta się przez kontrast
  tonalny względem `background`, co było głównym źródłem wrażenia
  "przypadkowych prostokątów" w poprzednim UI). Dark mode to osobno
  dobrana paleta (grafitowe tła, nie `#000000`), nie mechaniczna inwersja
  jasnego motywu.
- **Kolory semantyczne** — `AppSemanticColors` (`ThemeExtension`, osobne
  presety light/dark): role `success`/`pending`/`danger`/`info`/`neutral`,
  każda z parą `<rola>`/`on<Rola>`/`<rola>Container`/`on<rola>Container`.
  `info` to świadomie osobna rola od `success` — "dane synchronizują się
  na żywo" (proces, `SyncStatusIndicator`) i "ten serwer działa" (stan,
  `ServerStatusChip`/`PowerStateChip`) nigdy nie dzielą koloru, żeby jedno
  nie było mylone z drugim na pierwszy rzut oka.
- **Ruch** — `AppMotion`: scentralizowane czasy trwania (`fast`=140ms,
  `medium`=220ms, `slow`=320ms) i krzywe animacji — jedno miejsce, z
  którego korzysta każda animacja w appce (zmiana statusu, pojawienie się
  karty, rozwinięcie paska użycia), zamiast każdego ekranu wymyślającego
  własne wartości. Krótkie i funkcjonalne z założenia — to narzędzie do
  monitoringu, nie prezentacja efektów.
- **Paleta konsoli** — `AppConsoleColors` (osobny `ThemeExtension`,
  identyczny w `light()`/`dark()` — terminal jest świadomie zawsze ciemny,
  niezależnie od motywu appki).
- **Tokeny statusu** — `AppStatusTone` (5 ról, patrz wyżej) +
  `AppStatusVisual` (ikona/etykieta/tone/czy animowany) + `AppStatusBadge`
  (jedyny widget renderujący status jako pigułkę) + `StatusDot` (najbardziej
  kompaktowy sygnał — sama kropka, z opcjonalnym "oddychającym" pulsem dla
  stanów faktycznie trwających teraz, np. `running`). Status nigdy nie
  polega tylko na kolorze: zawsze ikona/kropka + tekst obok (nadany przez
  wywołującego) + `Semantics` z pełną etykietą w jednym węźle.
- **`AppTheme.light()`/`.dark()`** — jedyne miejsce budujące `ThemeData`:
  bazowy `ColorScheme.fromSeed` tylko jako fallback dla ról, których ten
  plik świadomie nie nadpisuje (`tertiary`, `shadow`, ...), z `primary`/
  `surface`/`onSurface`/`outline`/`error`/... nadpisanymi wprost wartościami
  marki/`AppSurfaceColors`/`AppSemanticColors`. `cardTheme` bez obramowania
  (patrz System powierzchni), `tabBarTheme`/`chipTheme`/
  `bottomSheetTheme`/`snackBarTheme` dotknięte tak samo jak
  `filledButtonTheme`/`outlinedButtonTheme`/`textButtonTheme`/
  `iconButtonTheme` (radius `md`, min. touch target 48dp),
  `inputDecorationTheme` (radius `sm`).
- **Komponenty wielokrotnego użytku** (`core/presentation/widgets/`) —
  `AppCard` (bazowa powierzchnia dla każdej karty w appce, z opcjonalnym
  paskiem akcentu), `AppTopBar` (nagłówek ekranów głównych zakładek —
  tytuł + podtytuł + slot na wskaźniki, nie `AppBar`; ekrany z przyciskiem
  "wstecz" — szczegóły serwera, panele — zostały przy zwykłym `AppBar`,
  które samo wykrywa `Navigator.canPop`), `AppBottomNav` (dolna nawigacja
  z wypełnioną "pigułką" aktywnej zakładki zamiast czterech identycznych
  ikon), `AppSearchField`, `showFilterSheet`/`FilterOption` (generyczny
  arkusz wyboru), `MetricCard` (pojedyncza duża statystyka — Dashboard),
  `UsageBar` (pasek wykorzystania CPU/RAM z wypełnieniem), `FadeSlideIn`
  (jednorazowe pojawienie się wiersza listy — patrz uwaga o
  `SlideTransition` niżej).

Brak osobnego `DestructiveButtonTheme` — Kill/Usuń nie są globalnym
"czerwonym przyciskiem": kolor `AppSemanticColors.of(context).danger` jest
nakładany per-instancję (`ServerPowerActions`' Kill i dialog potwierdzenia
usunięcia instancji), tak jak dziś robią to z `colorScheme.error`.

**Pułapka odnotowana podczas budowy** (`AppCard`): pasek akcentu użył
`Row(crossAxisAlignment: CrossAxisAlignment.stretch, ...)` bezpośrednio
wewnątrz karty w `ListView` — `stretch` wymaga *ograniczonej* wysokości od
rodzica, a element listy daje dziecku wysokość nieograniczoną (żeby mogło
się dopasować do własnej treści), co kończyło się realnym layoutowym
`BoxConstraints forces an infinite height` (nie kosmetycznym warningiem —
appka faktycznie się wywalała na ekranach z listą serwerów). Naprawione
przez `IntrinsicHeight` wokół tego `Row` — mierzy naturalną wysokość treści
i dopiero wtedy daje paskowi akcentu realną, skończoną wysokość do
rozciągnięcia. Osobno: `SlideTransition` (transform) owijający poddrzewo z
`Semantics` wewnątrz przewijanej listy okazał się wyzwalać błąd frameworka
Fluttera (`!semantics.parentDataDirty`) — `FadeSlideIn` używa więc tylko
`FadeTransition` (samo opacity), bez transformu.

## Nawigacja i ekrany

### Dwa regiony routingu

- **Pre-shell**: `/` (`RootScreen`) i `/instances/add` (wizard dodawania
  panelu). `RootScreen` to jedyna bramka do reszty appki: dopóki
  `instanceListControllerProvider` się ładuje, pokazuje `SplashScreen`;
  jeśli nie ma aktywnej instancji, pokazuje `InstancesScreen` (picker);
  jeśli aktywna instancja już istnieje (zwykły przypadek powracającego
  użytkownika), natychmiast przekierowuje do `/app/dashboard`.
- **`/app` — `StatefulShellRoute.indexedStack`**: cztery gałęzie —
  Dashboard / Serwery / Aktywność / Ustawienia — każda z własnym stosem
  nawigacji (`StatefulShellBranch.navigatorKey`), opakowane w `AppShell`
  (`NavigationBar` na dole). Tylko ta część appki zakłada, że instancja
  jest aktywna — żaden ekran pod `/app` nie przyjmuje `instanceId` jako
  parametru, tylko czyta `instanceListControllerProvider().activeInstanceId`
  bezpośrednio.

`ServerDetailScreen` jest zagnieżdżony *wewnątrz* gałęzi Serwery
(`/app/servers/:serverId`), nie jako osobna trasa na tym samym poziomie —
dzięki temu bottom nav znika dopiero po wejściu w konkretny serwer (tak
jak w prawdziwej appce), a serwer i tak liczy się jako część stosu
nawigacji zakładki "Serwery" (system back wraca do listy, nie do
Dashboardu).

### Mapa ekranów

```
RootScreen (Splash / picker)
└── /app (bottom nav: Panel / Serwery / Aktywność / Ustawienia)
    ├── Dashboard          — podsumowanie (liczby realne, bez fake CPU/RAM), podgląd serwerów
    ├── Serwery            — pełna lista: szukaj, sortuj, skeleton, pull-to-refresh, paginacja
    │   └── Serwer         — TabBar:
    │       ├── Przegląd   — status, MetricGrid (Node/RAM/Dysk/CPU), Power Actions
    │       ├── Konsola    — ConsoleView(fullscreen: true) — pełnoekranowy terminal
    │       ├── Pliki      — ComingSoonView (brak integracji z .../files/*)
    │       ├── Backupy    — ComingSoonView (brak integracji z .../backups)
    │       └── Ustawienia — realne dane tylko-do-odczytu (identyfikator/node/opis)
    │                        + ComingSoonView dla Startup/Zmienne środowiskowe
    ├── Aktywność          — ComingSoonView (brak API dziennika zdarzeń/push)
    └── Ustawienia
        ├── Konto          — ComingSoonView (brak GET /api/client/account)
        ├── Połączenie     — InstancesScreen (ten sam ekran co root picker)
        ├── Wygląd         — RadioGroup<ThemeMode>, realnie działający, persystowany
        ├── Bezpieczeństwo — ComingSoonView (brak blokady biometrycznej)
        └── Informacje     — wersja + showLicensePage (wbudowane we Flutter)
```

### Add Panel — wieloetapowy onboarding z realnym testem połączenia

`AddInstanceScreen` to teraz 4-krokowy `PageView` (URL → klucz API → nazwa
+ test → sukces), nie jeden formularz. Krok 3 wywołuje
`InstanceListController.testConnection(baseUrl, apiKey)` — **prawdziwe**
`GET /api/client` z podanymi danymi, bez zapisywania czegokolwiek — i
pokazuje dokładnie ten `AppException.message`, który ta odpowiedź
wygenerowała (więc "Sesja wygasła lub klucz API jest nieprawidłowy."/"Nie
udało się połączyć z serwerem." to prawdziwe komunikaty błędów, nie
wymyślony tekst). Zapis (`addInstance`) następuje dopiero po udanym
teście. `testConnection` dzieli dokładnie to samo ograniczenie
testowalności co istniejące `checkConnection` — `PterodactylApiClientFactory`
buduje własny `Dio` bez punktu wstrzyknięcia adaptera z zewnątrz, więc
jego zachowanie sieciowe nie ma testu jednostkowego (już udokumentowane
niżej, w sekcji Testy, jako świadome, zaakceptowane ograniczenie — nie
nowe w tym kroku).

## Zasady architektoniczne

Cztery warstwy w każdym feature (tam, gdzie feature ich potrzebuje —
`authentication` na tym etapie nie ma np. `presentation`, bo nie ma jeszcze
własnego ekranu):

- **domain** — czyste encje i interfejsy (`InstanceRepository`,
  `ServerRepository`, `Server`, `PterodactylInstance`, `CredentialStorage`).
  Zero importów z Fluttera, zero wiedzy o HTTP/JSON/SharedPreferences/
  Keystore.
- **data** — implementacje interfejsów z `domain` (repozytoria, DTO, API,
  `SecureCredentialStorage`). Zna format przechowywania/transportu, tłumaczy
  go na/z encji domenowych. Widoki nigdy nie widzą DTO.
- **application** — stan i logika UI-facing: kontrolery Riverpod
  (`InstanceListController`, `ServerListController`,
  `ServerPowerActionController`), providery spinające `domain`+`data`+`core`.
  To jedyna warstwa, która wie o Riverpodzie *i* o repozytoriach naraz.
- **presentation** — wyłącznie widgety. Czytają stan przez
  `ref.watch(xProvider)`, wywołują akcje przez
  `ref.read(xProvider.notifier).doSomething()`. **Nigdy** nie wołają
  `Dio`/`http`/`SharedPreferences`/`FlutterSecureStorage` bezpośrednio i
  nigdy nie importują niczego z `data/`.

### Kontrakt API (`core/network` → `features/*/data`)

```
PterodactylApiClient          — core/network, generyczny get/post/put/delete -> Result<T>
    ↓ budowany per instancja przez
PterodactylApiClientFactory + instanceApiClientProvider(instanceId)
    ↓ na nim
ServersApi                    — features/servers/data, zna GET /api/client i POST .../power
    ↓ konsumowany przez
ServerRepositoryImpl           — mapuje DTO -> domain, Result -> throw AppException
    ↓ czytany przez
ServerListController / ServerPowerActionController
    ↓ obserwowane przez
ServersScreen / ServerDetailScreen / ServerPowerActions
```

Ta sama sekwencja (`XApi` → `XRepositoryImpl` → `XController` → ekran) to
wzorzec do powielenia dla `console`, `files`, `backups`, `databases`,
`schedules` — patrz [Dodawanie kolejnych feature'ów](#dodawanie-kolejnych-featureów).

`PterodactylApiClient` nadal nie zna żadnego konkretnego endpointu — tylko
jak bezpiecznie wykonać request, zdekodować kopertę Fractal
(`core/network/pterodactyl_envelope.dart`, wspólna dla każdego endpointu
Client API) i zamienić błąd transportu na `AppException`.

### Akcje zasilania serwera (power actions)

`ServerPowerActionController` (`.family<ServerActionTarget>`, gdzie
`ServerActionTarget = ({String instanceId, String serverIdentifier})`) trzyma
stan **jednej** trwającej/ostatniej akcji dla **jednego** serwera —
świadomie osobno od `ServerListState` (które opisuje całą listę, nie stan
pojedynczej akcji). Reużywa dokładnie ten sam mechanizm `AsyncNotifier`/
`AsyncValue` co reszta aplikacji (loading/data/error) zamiast własnej maszyny
stanów. `POST /api/client/servers/{server}/power` jest fire-and-forget —
sukces oznacza "polecenie przyjęte", nie "serwer już zmienił stan" (patrz
doc-comment `ServerPowerAction`) — po sukcesie kontroler wywołuje
`ServerListController.refresh()` tej samej instancji, żeby odświeżyć to, co
Panel aktualnie zgłasza (status administracyjny, limity).

Oba te kontrolery są `autoDispose`, więc mogą zostać zutylizowane, jeśli
użytkownik zejdzie z ekranu w trakcie requestu — obie metody sprawdzają
`ref.mounted` po `await`, zamiast rzucać `UnmountedRefException` (patrz
doc-comment `ServerListController.refresh()`/`ServerPowerActionController.send()`).
Testy `autoDispose` przez surowy `ProviderContainer` (bez drzewa widgetów)
muszą jawnie utrzymać provider przy życiu przez `container.listen(...)` —
`container.read()` samo w sobie tego nie robi (patrz komentarz w
`server_power_action_controller_test.dart`).

### Konsola live przez WebSocket

Cztery odrębne pojęcia, celowo nierozmyte w jeden typ (wprowadzone jako
czyste modele w Kroku 4, z prawdziwym producentem od Kroku 5):

| Typ | Skąd | Plik |
|---|---|---|
| `ServerAdministrativeStatus` | `GET /api/client` (Panel) | `servers/domain/server.dart` |
| `ServerPowerState` | WS `status` | `servers/domain/server_power_state.dart` |
| `ServerRuntimeState` | agregat: `ServerPowerState` + `observedAt` | `servers/domain/server_runtime_state.dart` |
| `ConsoleConnectionState` | cykl życia WS (transport) | `console/domain/console_connection_state.dart` |
| `ConsoleEvent` | pojedyncza linia/zdarzenie konsoli | `console/domain/console_event.dart` |

`ConsoleConnectionState` jest świadomie odrębny od istniejącego
`InstanceConnectionStatus` (`instances/domain/pterodactyl_instance.dart`) —
tamten opisuje osiągalność REST API całej instancji, ten opisuje sesję WS
**jednego serwera**.

#### Protokół (źródło prawdy: rzeczywisty kod Wings/Panel)

Zweryfikowano wprost w kodzie `wings/router/websocket/*.go`,
`wings/router/router_server_ws.go` oraz referencyjnym kliencie TS Panelu
(`resources/scripts/{plugins/Websocket.ts,components/server/console/Console.tsx,
components/server/WebsocketHandler.tsx}`) — nic w tej sekcji nie jest
zgadywane.

1. **Token**: `GET /api/client/servers/{serverIdentifier}/websocket` (przez
   istniejący, instancja-scoped `PterodactylApiClient` — ten sam klucz API co
   reszta Client API). Odpowiedź to **bespoke** `{"data": {"token", "socket"}}`
   — **nie** koperta Fractal (`console_websocket_token_dto.dart`,
   `console_api.dart`). Token ważny ~10 minut.
2. **Połączenie**: bezpośrednio do `socket` (URL do node'a, z pominięciem
   Panelu), z nagłówkiem `Origin` ustawionym na `baseUrl` instancji — Wings'
   `CheckOrigin` (`websocket.go`) odrzuca upgrade bez pasującego originu; apka
   mobilna nie ma naturalnego originu przeglądarki, więc wysyła URL Panelu,
   który Wings i tak już zna jako zaufany.
3. **Ramka**: każda wiadomość w obie strony to `{"event": "...", "args": [...]}`
   (`console_protocol_message.dart`). Zniekształcone ramki są po cichu
   odrzucane (tak samo jak robi to sam Wings) — nigdy nie crashują konsoli
   (`console_websocket_client_test.dart`).
4. **Auth**: po otwarciu WS wysyłamy `{"event":"auth","args":[token]}`. Po
   `auth success` wysyłamy dodatkowo `{"event":"send logs"}` (Wings nie
   wysyła backlogu automatycznie) — ale **tylko** przy świeżym połączeniu
   (patrz reconnect niżej).
5. **Odświeżanie tokenu na tym samym sockecie**: `token expiring`/
   `token expired` → pobierz nowy token tym samym REST-em, wyślij nowy `auth`
   na **tym samym** WS (bez reconnectu, bez czyszczenia bufora — Wings też
   nie re-rejestruje tego jako nowe połączenie).
6. **`jwt error`**: naprawialne tylko dla dwóch konkretnych komunikatów
   (`jwt: exp claim is invalid`, `jwt: created too far in past (denylist)`,
   dopasowanie case-insensitive substring — dokładnie ta lista, co
   referencyjny klient) → odśwież token i re-autentykuj. Każdy inny `jwt error`
   (brak uprawnień, zły UUID serwera, brak tokenu) → `ConsoleConnectionState.error`,
   **bez** automatycznego reconnectu.
7. **Kody zamknięcia bez reconnectu**: `4409` (serwer zawieszony), `4400`
   (zarezerwowany) — tak samo jak referencyjny klient.
8. **Mapowanie na `ConsoleEvent`**: `console output`/`install output` →
   `output`; `daemon message` → `daemonMessage`; `daemon error` →
   `daemonError`; `status` → **osobno** aktualizuje `ServerRuntimeState`
   (nie trafia do bufora konsoli); wszystko inne (`stats`, `backup completed:<uuid>`,
   `transfer logs`/`transfer status`, `install started`/`install completed`,
   `deleted`, `throttled`, i cokolwiek Wings doda w przyszłości) → `unknown`
   — **nigdy** po cichu odrzucone, zawsze zachowane z surową nazwą zdarzenia
   w `message`.

#### Reconnect

Mechanizm reconnectu **należy do `ConsoleRepositoryImpl`**, nie do
automatycznego retry Riverpoda (świadomie wyłączonego globalnie, patrz
[Obsługa błędów](#obsługa-błędów)) — WebSocket wymaga stanu (kolejny numer
próby, anulowalny timer, flaga "połączenie zamierzone"), którego mechanizm
retry providera nie modeluje. Exponential backoff (`defaultConsoleReconnectBackoff`):
1s, 2s, 4s, 8s, 16s, potem zatrzaśnięty na 30s — ograniczony, nigdy tight
loop. Reconnect **nie** następuje: po jawnym `disconnect()`, po `dispose()`
(timer jest anulowany), ani po kodach 4409/4400 czy nienaprawialnym `jwt error`
(patrz wyżej). Przy prawdziwym reconnect (nowy transport, nie odświeżenie
tokenu na tym samym sockecie) bufor konsoli jest czyszczony i backlog
requestowany od nowa — inaczej stara treść dublowałaby się z nową.

#### Heartbeat

Prawdziwy protokół Wings **nie ma** heartbeatu na poziomie aplikacji —
zweryfikowane brakiem takiego zdarzenia w `wings/router/websocket/*.go` i
referencyjnym kliencie TS. Jedynym mechanizmem keep-alive jest standardowy
WebSocket ping/pong na poziomie transportu, obsługiwany automatycznie przez
`dart:io`'s `WebSocket` przez `pingInterval` w `IOWebSocketChannel.connect`
(`web_socket_channel_transport.dart`, `kConsoleWebSocketPingInterval = 20s`).
Nie ma więc formatu ramki do zaimplementowania ani (de)zakodowania — to
świadomie *cała* odpowiedź na ten wymóg, nie luka.

#### Bufor konsoli

`ConsoleRepositoryImpl` trzyma ograniczony bufor (`maxBufferSize`, domyślnie
500 linii) — najstarsze linie są usuwane, gdy bufor przekracza limit, żeby
długo działająca sesja nie rosła w pamięci bez ograniczeń.

#### UI (`ConsoleView`)

Ciemny, monospace panel terminala o stałej wysokości (osadzony w
przewijalnym `ServerDetailScreen`), wskaźnik stanu połączenia, przycisk
ręcznego reconnectu po błędzie/rozłączeniu, stan pustki/ładowania, oraz
proste pole komend (`ConsoleController.sendCommand` — no-op przed auth).
Auto-scroll do najnowszej linii **tylko** gdy użytkownik był już blisko dołu
przed nowymi danymi (`kConsoleAutoScrollThreshold`) — przewinięcie w górę,
żeby przeczytać wcześniejszą treść, nigdy nie jest cofane siłą. `ListView.builder`
zamiast renderowania całej listy na każdą nową linię.

#### Bezpieczeństwo

Token WebSocket **nigdy nie jest persystowany** — żyje tylko w pamięci na
czas jednej próby połączenia i jest pobierany od nowa przy każdym
(re)connect/odświeżeniu. Żaden log/wyjątek nie zawiera tokenu WS ani
nagłówka `Authorization` (ta sama zasada co reszta apki, patrz
[Secure storage poświadczeń](#secure-storage-poświadczeń)) — `ConsoleRepositoryImpl`
nigdy nie loguje treści ramek `auth`/`jwt error` poza tym, co trafia do
`ConsoleConnectionState`. Riverpod state (`ConsoleState`) niesie tylko
`ConsoleConnectionState`/`ServerRuntimeState`/`List<ConsoleEvent>` — nigdy
token ani surową ramkę.

### Synchronizacja stanu serwerów w czasie rzeczywistym

**Punkt wyjścia (zweryfikowany wprost w kodzie Panelu, nie zgadywany):**
prawdziwy web Panel Pterodactyla **nie ma** WebSocketu dla listy
serwerów/Dashboardu — `DashboardContainer.tsx` robi zwykły REST fetch
`GET /api/client`, a każdy `ServerRow.tsx` na liście osobno pollinguje
`GET /api/client/servers/{server}/resources` co **30s**
(`setInterval(() => getStats(), 30000)`), przy czym ten endpoint ma
20-sekundowy cache po stronie serwera (`ResourceUtilizationController.php`,
`Carbon::now()->addSeconds(20)`) — pollowanie częściej niż 20s i tak
zwróciłoby tę samą wartość z cache. Ta apka odtwarza dokładnie ten sam
mechanizm i cadence, zamiast wymyślać własny — patrz
`server_resource_usage_dto.dart`.

Instalacja/reinstalacja kończąca się (status administracyjny
`installing`/`restoring_backup` → `active`) to jedyna zmiana, której
`.../resources` **nie** widzi — ten endpoint zna tylko żywy stan zasilania
Wings, nie administracyjny status Panelu. Referencyjny klient łapie to przez
WebSocket (`InstallListener.tsx`: `INSTALL_COMPLETED` → `getServer(uuid)`);
ta apka odtwarza ten sam wzorzec dwiema ścieżkami — patrz "Przepływ zdarzeń"
niżej.

#### Modele

| Typ | Producent | Cadence |
|---|---|---|
| `ServerRuntimeState` (rozszerzony) | `ServerRuntimeSyncController` (REST) **lub** `ConsoleRepositoryImpl` (WS) | 30s / sekundy |
| `ServerSyncStatus` (`live`/`syncing`/`offline`) | `ServerRuntimeSyncController` | — |

`ServerRuntimeState` niesie teraz nie tylko `powerState`/`observedAt`, ale
też `cpuAbsolutePercent`/`memoryBytes`/`diskBytes`/`networkRxBytes`/
`networkTxBytes`/`uptimeMs` — dokładnie te same pola, które Wings marszaluje
zarówno do `GET .../resources` (`StatsTransformer.php`), jak i do WS
`stats` (`environment.Stats`/`ResourceUsage`, `wings/environment/stats.go`,
`wings/server/resources.go`) — dwaj producenci tego samego kształtu danych,
różne transporty, ten sam typ domenowy. `hasResourceReading` mówi UI, czy
pokazywać żywe metryki, czy spaść na skonfigurowane limity.

**Świadomie jeden typ z dwoma producentami, nie drugi, równoległy store** —
`ServerRuntimeSyncController` **czyta** listę serwerów z
`ServerListController` (przez `ref.listen`, żeby nie zgubić jej po drodze —
patrz niżej) i **pisze** do niej tylko przez `refreshOne` (nigdy przez
osobny stan) — `ServerListController` zostaje jedynym źródłem prawdy o tym,
jakie serwery istnieją i jaki mają status administracyjny.

#### Przepływ zdarzeń: Pterodactyl → UI

**Ścieżka A — Dashboard/lista serwerów (REST polling, zawsze aktywna):**

1. `ServerRuntimeSyncController` (`.autoDispose.family<String instanceId>`,
   `server_runtime_sync_controller.dart`) odpytuje
   `GET /api/client/servers/{server}/resources` dla każdego serwera aktualnie
   wczytanego w `ServerListController(instanceId)`, co 30s, natychmiast po
   zbudowaniu i natychmiast po powrocie z tła (patrz niżej).
2. Wynik trafia do `Map<String identifier, ServerRuntimeState>` w
   `ServerRuntimeSyncState` — **tylko** dotknięty wpis w mapie się zmienia,
   nigdy cała lista (wymóg "aktualizuj tylko konkretną instancję").
3. `DashboardScreen`/`ServersScreen` czytają tę mapę i przekazują
   `runtimeState` do każdego `ServerTile` — kafelek pokazuje żywe CPU/RAM
   zamiast skonfigurowanych limitów, gdy `hasResourceReading` jest `true`.
4. Dla serwerów, których administracyjny status to `installing` lub
   `restoringBackup`, ten sam tick **dodatkowo** wywołuje
   `ServerListController.refreshOne(identifier)` (pełny
   `GET /api/client/servers/{server}`) — to jedyny sposób złapania
   zakończenia instalacji na ekranie listy, bo `.../resources` go nie
   niesie. Ograniczone tylko do serwerów faktycznie w trakcie zmiany, żeby
   nie generować niepotrzebnych requestów dla reszty listy.

**Ścieżka B — ekran szczegółów serwera, gdy konsola jest połączona
(WebSocket, bogatszy i szybszy):** `ServerDetailScreen` zawsze ma `ConsoleView`
zbudowany jako jedną z zakładek `TabBarView` (niezależnie od tego, która
zakładka jest aktywnie widoczna), więc `ConsoleController`/
`ConsoleRepositoryImpl` łączy się od razu przy wejściu na ekran:

1. WS `status` **i** `stats` (`ConsoleRepositoryImpl._handleStatus`/
   `_handleStats`) trafiają na `runtimeState` — `stats` niesie pełny
   `ResourceUsage` (CPU/RAM/dysk/sieć/uptime), `status` tylko żywy stan
   zasilania. Zakładka "Przegląd" pokazuje kartę "Na żywo"
   (`_liveMetricsFor`) natychmiast, gdy przyjdzie pierwszy odczyt —
   sekundy, nie 30s REST-owego pollingu.
2. `install completed`/`backup restore completed` na WS (odbierane już
   dziś jako `ConsoleEventType.unknown` z surową nazwą zdarzenia w
   `.message`) są diffowane w `_ServerDetailContentState._handleConsoleEvents`
   (`server_detail_screen.dart`) — nowe zdarzenia od ostatniego builda, nie
   cały bufor od zera — i wywołują dokładnie ten sam
   `ServerListController.refreshOne(serverId)`, co Ścieżka A. To
   odtworzenie wzorca `InstallListener.tsx` z referencyjnego klienta, tylko
   że triggerowane przez event WS zamiast (dodatkowo) przez timer, bo tu WS
   już jest podłączony.

Efekt end-to-end na przykładzie z wymagań: `fivem` pokazuje "Instalacja…" →
Wings kończy instalację → (a) na ekranie szczegółów: WS `install completed` →
diff bufora → `refreshOne('fivem')` → `GET /api/client/servers/fivem` →
status `active` → `ServerListController` podmienia ten jeden wpis →
`ServerStatusChip` przechodzi na "Aktywny", **bez** zamykania ekranu, bez
pull-to-refresh, bez ponownego wejścia; (b) na Dashboardzie/liście: kolejny
tick `ServerRuntimeSyncController` (do 30s) robi to samo przez REST.
Zweryfikowane end-to-end w `server_detail_install_completed_test.dart`.

#### Tło/pierwszy plan aplikacji

Wspólny mechanizm dla obu ścieżek: `AppLifecycleController`
(`app/lifecycle/app_lifecycle_controller.dart`) — cienki wrapper Riverpod
nad `WidgetsBindingObserver`, jeden per aplikację (nie per-feature), żeby
`ServerRuntimeSyncController` i `ConsoleController` reagowały na dokładnie
ten sam sygnał zamiast dwóch niezależnych obserwatorów cyklu życia.

- **Tło** (`paused`/`detached`/`hidden` — **nie** `inactive`, patrz
  `AppLifecycleStateX.isAppVisible`): `ServerRuntimeSyncController`
  zatrzymuje `Timer.periodic`; `ConsoleController` woła
  `ConsoleRepository.disconnect()` (zamyka WS zamiast walczyć z systemem o
  utrzymanie gniazda w tle).
- **Powrót na pierwszy plan**: obie strony natychmiast wznawiają — polling
  robi tick od razu (nie czeka do 30s), konsola łączy się od nowa ze
  świeżym tokenem — więc użytkownik nigdy nie widzi bardziej nieaktualnego
  stanu niż "sprzed chwili".
- **Edge-triggered, nie level-triggered**: reakcja następuje tylko na
  faktyczne przejście widoczny↔niewidoczny, nigdy na
  `resumed → inactive → resumed` (np. krótkotrwały systemowy dialog) — to
  wciąż "widoczne" na obu końcach tej sekwencji, więc nie ma tam żadnego
  zbędnego reconnectu/restartu timera. Pokryte testami w
  `console_controller_test.dart`/`server_runtime_sync_controller_test.dart`.

#### Reconnect (WebSocket) i odzyskiwanie (REST)

Reconnect WS opisany już w [Konsola live przez WebSocket](#konsola-live-przez-websocket)
(exponential backoff, brak reconnectu po zamierzonym rozłączeniu/kodach
4409/4400) — bez zmian, powrót na pierwszy plan po prostu woła `connect()`
od nowa na tych samych zasadach.

REST polling nie ma osobnego "reconnectu" — to zwykły cykliczny timer:
nieudany tick (brak internetu, Wings/Panel chwilowo niedostępny) po prostu
zostawia w `ServerRuntimeSyncState.runtimeByServer` **ostatnią znaną**
wartość (nigdy nie czyści jej na `unknown`) i ustawia `status: offline` —
kolejny tick za 30s (albo natychmiastowy tick po powrocie z tła) próbuje
ponownie. Stąd wymóg "nigdy nie pokazuj `installing`, gdy backend już mówi
`running`, przez stary cache" jest spełniony przez konstrukcję: jedyne
źródło prawdy o statusie administracyjnym to zawsze najnowsza odpowiedź
`GET /api/client/servers/...`, nigdy lokalnie wymyślona wartość.

#### Wskaźnik stanu synchronizacji (`SyncStatusIndicator`)

Mały, gęsty `AppStatusBadge` (ten sam język wizualny co
`ConnectionStatusChip`/`ServerStatusChip`) w `AppBar` Dashboardu i listy
serwerów — **nie** duży baner ani tekst debugowy. Trzy stany
(`ServerSyncStatus`): `syncing` (moment przed pierwszym pollem — celowo
**niewidoczny**, żeby nie mrugać na ekranie na te kilkaset milisekund),
`live` (ostatni poll udany dla co najmniej jednego serwera), `offline`
(ostatni poll nieudany dla wszystkich).

#### Fallback, gdy realtime nie działa

REST polling (Ścieżka A) **jest** fallbackiem — działa niezależnie od tego,
czy jakikolwiek WebSocket jest połączony, więc Dashboard/lista zawsze mają
działającą (jeśli wolniejszą) ścieżkę aktualizacji nawet bez otwierania
ekranu szczegółów żadnego serwera. Nie ma dodatkowego, bardziej
agresywnego pollingu "na wypadek gdyby WS nie działał" — 30s to już
świadomie wybrany, nieagresywny interwał (patrz wyżej), nie osobny tryb
awaryjny.

#### Testy

- `server_runtime_state_test.dart` — nowe pola/`copyWith`/`hasResourceReading`.
- `servers_api_test.dart`/`server_repository_impl_test.dart` —
  parsowanie `.../resources` (`ServerResourceUsageDto`), mapowanie
  `current_state`, `getServer`.
- `console_repository_impl_test.dart` — parsowanie WS `stats` do
  `ServerRuntimeState` (pełne i zniekształcone ramki).
- `server_list_controller_test.dart` — `refreshOne` (podmiana jednego
  wpisu, no-op gdy serwera nie ma na liście, zachowanie starego wpisu przy
  błędzie).
- `server_runtime_sync_controller_test.dart` — polling wszystkich
  wczytanych serwerów, `status: live/offline`, pauza/wznowienie przy
  zmianie widoczności aplikacji, dodatkowy fetch tylko dla serwerów w
  trakcie instalacji/przywracania backupu.
- `app_lifecycle_controller_test.dart` — odzwierciedlanie stanu
  `WidgetsBinding`, `isAppVisible`.
- `console_controller_test.dart` — disconnect/reconnect na zmianę
  widoczności aplikacji, edge- a nie level-triggered.
- `server_detail_install_completed_test.dart` — pełny przepływ end-to-end
  (widget test): zdarzenie WS `install completed` → status w UI zmienia
  się z "Instalacja…" na "Aktywny" bez opuszczania ekranu.

### Instance scoping

Krytyczna zasada: **żaden kod nie może użyć tokenu/klienta jednej instancji
dla innej.** Wymuszone strukturalnie, nie konwencją:

- `instanceApiClientProvider` (`features/instances/application/`) to
  `Provider.autoDispose.family<PterodactylApiClient, String instanceId>`.
  Riverpod cache'uje osobną instancję per `instanceId` — nie ma współdzielonego
  `Dio` ani zmiennej globalnej, przez którą dane jednej instancji mogłyby
  wyciec do drugiej. Zbudowany na `resolvedInstanceProvider` (ten sam plik)
  — jedynym miejscu z logiką "znajdź instancję po id albo rzuć błąd";
  `consoleRepositoryProvider` (`console/application/console_providers.dart`)
  używa go dokładnie w tym celu, dla którego został wydzielony w Kroku 4 —
  zbudowania `Origin`/`wss://` z `baseUrl` instancji.
- `ServersApi`/`ServerRepository`/`ServerListController`/
  `ServerPowerActionController` są budowane *na* tym providerze, także jako
  `.family<..., String instanceId>` (lub `ServerActionTarget`, który
  zawiera `instanceId`) — repozytorium dla instancji A nie ma metody
  przyjmującej `instanceId`, bo instancja jest faktem konstrukcyjnym, nie
  parametrem wywołania (patrz doc-comment w `ServerRepository`). `ConsoleApi`/
  `ConsoleRepository`/`ConsoleController` powtarzają ten sam wzorzec, jako
  `.family<..., ConsoleTarget>` (`ConsoleTarget = ({instanceId, serverIdentifier})`
  — strukturalnie identyczny z `ServerActionTarget`, ale świadomie osobny typ
  w `console/domain/`, żeby `console` nie importował nic z `servers`, patrz
  doc-comment `ConsoleTarget`). Każdy `ConsoleTarget` dostaje własny
  `ConsoleRepositoryImpl` — własny transport WS, własny bufor, własny stan —
  nigdy współdzielony między serwerami ani instancjami (testy:
  `console_providers_test.dart`).
- Token API dla danej instancji jest odczytywany z `CredentialStorage`
  osobno przy każdym żądaniu, zawsze pod kluczem `instanceId` przechwyconym
  w domknięciu w momencie budowy klienta — i przechowywany w
  `SecureCredentialStorage` pod kluczem namespacowanym `instanceId`
  (`credentials.<instanceId>`), więc izolacja obowiązuje aż do warstwy
  Keystore/Keychain, nie tylko w kodzie aplikacji.
- Testy: `instance_api_client_provider_test.dart` (dwie instancje o różnych
  `baseUrl` dostają różne klientów) i
  `server_power_action_controller_test.dart` (`instance isolation` — ta sama
  wartość `serverIdentifier` w dwóch różnych instancjach nigdy nie miesza
  repozytoriów ani stanu).

### Secure storage poświadczeń

`SecureCredentialStorage` (`features/authentication/data/`) — Android
Keystore / iOS Keychain przez `flutter_secure_storage`, domyślna
konfiguracja pakietu (AES-GCM + klucz owinięty RSA-OAEP w Keystore, bez
wymogu biometrii). Zasady:

- Metadane instancji (nazwa, URL) nadal w `SharedPreferences` — jawnie
  niewrażliwe. Tylko klucz API idzie przez `CredentialStorage`.
- Każdy credential pod osobnym kluczem `credentials.<instanceId>` — usunięcie
  instancji (`InstanceListController.removeInstance`) usuwa też jej
  credential (`credentialStorage.delete(instanceId)`), bez dotykania innych.
- Błędy platformy (Keystore/Keychain) są łapane i zamieniane na
  `StorageException` z ogólnym, polskim komunikatem — oryginalny wyjątek
  trafia wyłącznie do `AppException.cause` (nigdy pokazywany użytkownikowi,
  nigdy logowany) i **nigdy nie jest interpolowany w treść komunikatu** —
  patrz testy `secure_credential_storage_test.dart`
  ("never leaks the api key into the thrown exception").
- `InstanceCredentials` nie ma nadpisanego `toString()` (domyślny
  `Object.toString()` nie ujawnia pól) — regresja pilnowana testem
  `instance_credentials_test.dart`.
- Debug-logger Dio (`api_client_factory.dart`) ma jawnie wyłączone
  `requestHeader`/`responseHeader` (nagłówek `Authorization` nigdy nie trafia
  do konsoli) i jawnie podpięty `logPrint: debugPrint` — domyślny `logPrint`
  paczki `dio` używa gołego `print()`, nie `debugPrint`, co czyniło go
  niemożliwym do przechwycenia/wyłączenia w testach i mniej idiomatycznym
  dla Fluttera; patrz `api_client_factory_test.dart`.
- Biometria/PIN przed odblokowaniem tego magazynu **nie jest** jeszcze
  zaimplementowana (świadomie, poza zakresem tego kroku).
- Testy `SecureCredentialStorage` używają oficjalnego mechanizmu testowego
  pakietu (`FlutterSecureStorage.setMockInitialValues`, oraz — do testowania
  błędów platformy — podmiany `FlutterSecureStoragePlatform.instance` na
  fałszywą implementację) zamiast fałszywej implementacji `CredentialStorage`
  niezwiązanej z prawdziwym kodem — testowana jest więc rzeczywista klasa
  `SecureCredentialStorage`, nie tylko jej kontrakt.

### Obsługa błędów

Wszystko, co może zawieść w `data`/`core/network`, kończy jako
`AppException` (sealed class, `core/error/app_exception.dart`) — nigdy jako
surowy `DioException`, `PlatformException` czy `FormatException` widoczny
wyżej. Warstwa `presentation` obsługuje to przez
`AsyncValue.when(data:, loading:, error:)` z Riverpoda i wyświetla
`error.message` (już po polsku, gotowe dla użytkownika) przez
`ErrorView`/`SnackBar`.

**Riverpod 3 domyślnie ponawia błąd providera automatycznie, do 10 razy z
rosnącym opóźnieniem** (`ProviderContainer.defaultRetry`). Ta aplikacja to
świadomie wyłącza (`lib/app/app_provider_policy.dart`,
`noAutomaticProviderRetry`, ustawione na `ProviderScope.retry` w `main.dart`
i w każdym `ProviderContainer`/`ProviderScope` w testach) — każdy retry w tej
apce ma być widoczny dla użytkownika (przycisk „Spróbuj ponownie”,
pull-to-refresh), nigdy cichy w tle, żeby nie mnożyć requestów wobec
budżetu rate-limitu Panelu (256/min na użytkownika, współdzielony między
wszystkimi klientami — patrz analiza architektury).

### Paginacja

`GET /api/client` jest paginowane. `ServerListController` pobiera domyślnie
tylko pierwszą stronę (`build()`), z osobną metodą `loadNextPage()` do
doładowania kolejnych (wywoływaną przez scroll listener w `ServersScreen`).
**Świadomie nie pobiera wszystkich stron od razu**: budżet rate-limitu
Panelu jest per-użytkownik i współdzielony ze wszystkimi innymi klientami
(web, inne integracje) — pobieranie każdej strony przy każdym otwarciu/
odświeżeniu ekranu kosztowałoby użytkowników z wieloma serwerami bez
korzyści dla typowego przypadku (większość kont ma mniej serwerów niż
mieści jedna strona). Pełne uzasadnienie w doc-commencie
`ServerListController`.

## Dodawanie kolejnych feature'ów

`servers` i `console` są teraz oba referencyjnymi przykładami pełnego
przekroju — `console` dodatkowo pokazuje wzorzec dla feature'u
streamującego (WebSocket), nie tylko request/response. Dodając kolejny
feature typu `files`/`backups`/`databases`/`schedules`, powtórz:

1. `domain/...` — encje, interfejs repozytorium/serwisu (wzorzec
   `ConsoleRepository`: strumienie `Stream<...>` dla stanu, `Future<void>`
   dla akcji — jeśli feature jest live/streamujący; wzorzec
   `ServerRepository` — jeśli jest zwykłym request/response).
2. `data/xxx_api.dart` — klasa przyjmująca `PterodactylApiClient` (przez
   `instanceApiClientProvider`, wzorzec `ConsoleApi`/`ServersApi`). Dla
   WebSocketu: osobna abstrakcja transportu (`ConsoleTransport`/
   `ConsoleTransportConnector`) zamiast bezpośredniej zależności od
   `package:web_socket_channel` w kodzie orkiestrującym — to jest to, co
   czyni `ConsoleRepositoryImpl` testowalnym bez prawdziwej sieci (patrz
   `test/support/fake_console_transport.dart`).
3. `data/*_impl.dart` — mapowanie DTO → domain, `Result`/callback → `throw`
   albo `Stream` domenowy (wzorzec `ServerRepositoryImpl` /
   `ConsoleRepositoryImpl`).
4. `application/*_controller.dart` — `AsyncNotifier.family<..., ConsoleTarget>`-
   podobny rekord, jeśli stan dotyczy konkretnego serwera, nie całej
   instancji (wzorzec `ServerPowerActionController`/`ConsoleController`).
   Jeśli kontroler subskrybuje strumienie repozytorium, zrób to **przed**
   wywołaniem akcji, która mogłaby wyemitować pierwszą zmianę (wzorzec
   `ConsoleController.build`). Jeśli wywołuje inny provider `autoDispose` po
   `await`, pamiętaj o `ref.mounted`.
5. Ekran/widget podpięty pod `ServerDetailScreen` + nowa trasa w
   `app/router/app_router.dart` + `app/router/app_routes.dart`, jeśli
   feature potrzebuje własnego ekranu.
6. Testy w `test/features/xxx/...`, odzwierciedlające strukturę `lib/` —
   wzorzec w `test/features/servers/` i `test/features/console/` (fake
   `HttpClientAdapter`/`ConsoleTransport`/repository z `test/support/`,
   `ProviderContainer`/`ProviderScope` z `retry: noAutomaticProviderRetry`,
   i — dla providerów `autoDispose` testowanych przez surowy kontener —
   `container.listen(...)` żeby utrzymać je przy życiu i, jeśli test
   dotyczy zachowania przy dispose w trakcie operacji, `container.dispose()`
   w środku testu — patrz `server_power_action_controller_test.dart`).

Ta sama sekwencja dotyczy `files`, `backups`, `databases`, `schedules`.
Żaden z tych katalogów nie powinien powstać, dopóki nie zaczyna się praca
nad danym feature'em.

## Testy

```bash
flutter test                          # cały pakiet (247 testów)
flutter test test/core/theme          # tylko Design System (tokeny + ThemeData)
flutter test test/core/presentation   # tylko wspólne komponenty (AppStatusBadge, SectionHeader, MetricGrid)
flutter test test/features/servers    # tylko feature servers
flutter test test/features/instances  # tylko feature instances
flutter test test/features/authentication  # tylko secure storage
flutter test test/features/console    # cała konsola: protokół, repository, kontroler, UI
```

Pokrycie (nowe w tym kroku pogrubione):

- **Model instancji** — `pterodactyl_instance_test.dart`, `instance_url_validator_test.dart`.
- **Repository instancji** — `local_instance_repository_test.dart` (CRUD, duplikaty, aktywna instancja).
- **Instance Manager** — `instance_list_controller_test.dart` (build, add, remove, setActive).
- **Izolacja instancji** — `instance_api_client_provider_test.dart`.
- **AuthInterceptor** — `auth_interceptor_test.dart`.
- **ServersApi** — `servers_api_test.dart` (GET listy + POST power: sygnały, 204, 401/403, connection error, timeout).
- **ServerRepositoryImpl** — `server_repository_impl_test.dart` (mapowanie DTO + sendPowerAction).
- **ServerListController** — `server_list_controller_test.dart` (loading/success/empty/error/refresh/loadNextPage, autoDispose faktycznie sprząta, `refresh()` nie rzuca przy dispose w trakcie lotu).
- **`ServerPowerActionController`** — `server_power_action_controller_test.dart` (idle/sukces+refresh listy/błąd/blokada podwójnego kliknięcia/izolacja instanceId, `send()` nie rzuca przy dispose w trakcie lotu).
- **`SecureCredentialStorage`** — `secure_credential_storage_test.dart` (round-trip, nadpisanie, izolacja per instanceId, usuwanie, błędy platformy jako `StorageException`, token nigdy nie w treści wyjątku).
- **`InstanceCredentials`** — `instance_credentials_test.dart` (`toString()` nie ujawnia klucza).
- **Bezpieczeństwo logów** — `api_client_factory_test.dart` (token/`Authorization` nigdy w debug-logu).
- **`ServerRuntimeState`** — `server_runtime_state_test.dart` (`unknown`, `hasResourceReading`, `copyWith`, równość/hashCode wrażliwe na `powerState`/`observedAt` i wszystkie pola zasobów).
- **`ConsoleEvent`** — `console_event_test.dart` (równość, wrażliwość na `type`/`message`).
- **ServersScreen (widget)** — `servers_screen_test.dart` (lista, empty state, error state + retry).
- **`ServerPowerActions` (widget)** — `server_power_actions_test.dart` (Start wysyła sygnał, Kill wymaga potwierdzenia, błąd pokazuje SnackBar, przyciski wyłączone gdy serwer nieaktywny).
- **Routing/nawigacja** — `app_test.dart`, `servers_navigation_test.dart` (sekcja „Konsola” widoczna, `consoleRepositoryProvider` nadpisany fejkiem — zero realnego WS w tym teście).
- **`ConsoleProtocolMessage`** — `console_protocol_message_test.dart` (**nowe** — parsowanie, `joinedArgs` łączy wieloelementowy `args`, brakujący/zły typ `event` → `FormatException`, `toJson` pomija puste `args`).
- **`ConsoleWebSocketClient`** — `console_websocket_client_test.dart` (**nowe** — dekodowanie poprawnej ramki, odrzucanie ramek niebędących stringiem/JSON/obiektem/bez `event` bez crasha, `send()` koduje poprawnie, `done`/`closeCode`/`closeReason` po zamknięciu).
- **`ConsoleApi`** — `console_api_test.dart` (**nowe** — GET `.../websocket`, parsowanie bespoke `{"data":{...}}`, 401/connection error/malformed → `AppException`).
- **`WebSocketChannelTransport` — heartbeat** — `web_socket_channel_transport_test.dart` (**nowe** — `kConsoleWebSocketPingInterval`/`kConsoleWebSocketConnectTimeout` ograniczone i dodatnie; dokumentuje, dlaczego nie ma testu formatu ramki heartbeat — protokół go nie ma).
- **`ConsoleRepositoryImpl`** — `console_repository_impl_test.dart` (**nowe, najobszerniejsze** — przejścia stanu połączenia, generowanie ramki `auth`, `send logs` tylko po `auth success`, mapowanie `console output`/`install output`/`daemon message`/`daemon error`/`status`(→`ServerRuntimeState`, nie bufor)/nieznane zdarzenia (→`unknown`, bez crasha), limit bufora z odrzucaniem najstarszych, reconnect po nieoczekiwanym zamknięciu ze świeżym tokenem+czyszczeniem bufora, **brak** reconnectu po 4409, harmonogram backoff (ograniczony, rosnący), **jawny `disconnect()` blokuje reconnect**, **`dispose()` anuluje oczekujący timer reconnectu**, obsługa `jwt error` (naprawialne vs fatalne), odświeżanie tokenu przy `token expiring` bez czyszczenia bufora, `sendCommand` no-op przed auth).
- **`consoleRepositoryProvider` — izolacja instancji** — `console_providers_test.dart` (**nowe** — dwie instancje nigdy nie współdzielą repozytorium, ten sam target cache'owany identycznie, ten sam instanceId + inny serwer → osobne repozytorium).
- **`ConsoleController`** — `console_controller_test.dart` (`connect()` wywoływane w `build()`, subskrypcja aktywna zanim jakakolwiek zmiana mogłaby nadejść, propagacja 3 strumieni do jednego `ConsoleState` bez nadpisywania niepowiązanych pól, delegacja `sendCommand`/`reconnect`/`disconnect`, anulowanie subskrypcji repozytorium przy dispose, **nowe**: disconnect/reconnect na zmianę widoczności aplikacji, edge- a nie level-triggered — patrz [Synchronizacja stanu serwerów w czasie rzeczywistym](#synchronizacja-stanu-serwerów-w-czasie-rzeczywistym)).
- **`ServerRuntimeSyncController`/`AppLifecycleController`/`ServerListController.refreshOne`/stats WS (**nowe**)** — `server_runtime_sync_controller_test.dart`, `app_lifecycle_controller_test.dart`, dodatki w `server_list_controller_test.dart`/`console_repository_impl_test.dart`, oraz end-to-end `server_detail_install_completed_test.dart` — patrz [Synchronizacja stanu serwerów w czasie rzeczywistym](#synchronizacja-stanu-serwerów-w-czasie-rzeczywistym), sekcja "Testy", po pełną listę.
- **`ConsoleView` (widget)** — `console_view_test.dart` (wskaźnik stanu połączenia dla każdego `ConsoleConnectionState`, przycisk reconnect przy błędzie, stan pustki, auto-scroll do dołu gdy użytkownik już tam był, brak wymuszonego scrolla gdy użytkownik przewinął w górę, wysyłka komendy czyści pole, pole komend wyłączone gdy niepołączono).
- **`parseAnsiToSpans`** — `ansi_text_test.dart` (**nowe** — zwykły tekst bez zmian, **`[WARN]`/`[Essentials]` bez poprzedzającego bajtu ESC nie jest dotykane** — regresja pilnująca dokładnie tego bugu, który ta funkcja naprawiła, truecolor `38;2;r;g;b` — dokładnie format używany przez Minecraft/Bukkit, reset, bold/normal-intensity, standardowe 16 kolorów, 256-kolor, nieobsługiwany SGR i nie-SGR CSI nie crashują i nie zostawiają śmieci w tekście).
- **`AppTheme`/tokeny Design Systemu** — `test/core/theme/*` (**nowe** — `AppTypography` mapuje role na sloty M3 i tylko wagi w400/w500, `AppSpacing`/`AppRadius` mają właściwe wartości, `AppSemanticColors`/`AppConsoleColors` mają osobne, spójne presety light/dark i poprawnie rozwiązują się przez `Theme.of(context)`, `AppStatusTone.resolve` mapuje na właściwe pola, `AppTheme.light()`/`.dark()` rejestrują wszystkie extensions i konfigurują button/card/input theme).
- **`AppStatusBadge`/`SectionHeader`/`MetricGrid`** — `test/core/presentation/widgets/*` (**nowe** — poprawny tekst/ikona/spinner, pojedynczy zmergowany `Semantics` z pełną etykietą, `MetricGrid` nie wywala się przy nieparzystej/pustej liście elementów).

`checkConnection` w `InstanceListController` (jedyna metoda w feature
`instances` dotykająca sieci poza akcjami) nadal nie jest testowana
jednostkowo z tych samych powodów co poprzednio. `ConsoleConnectionState`
(prosty enum bez logiki) celowo nie ma dedykowanego testu — kompilator już
gwarantuje jego wartości, test wyliczający je nic by nie dowodził. Testy
`ConsoleRepositoryImpl`/`ConsoleWebSocketClient` używają fejkowego
`ConsoleTransport`/connectora (`test/support/fake_console_transport.dart`) —
zero realnego WebSocketu, zero zależności od osiągalności prawdziwego
Pterodactyla przy `flutter test`.

## Znane ograniczenia tego kroku

- Brak biometrii/PIN przed dostępem do `SecureCredentialStorage`.
- `checkConnection` (instancje) wykonuje generyczny `GET /` na URL instancji —
  status "online" oznacza tylko "host odpowiada na HTTP".
- `Server.status` to stan administracyjny Pterodactyla (installing/suspended/...),
  **nie** żywy stan zasilania (running/starting/stopping/offline) — te dwa
  pozostają świadomie osobnymi typami (patrz doc-comment `ServerPowerState`),
  ale od tego kroku **oba** są już realnie zasilane i synchronizowane w tle,
  patrz [Synchronizacja stanu serwerów w czasie rzeczywistym](#synchronizacja-stanu-serwerów-w-czasie-rzeczywistym).
  Power actions nadal są fire-and-forget na poziomie samego wywołania
  (sukces = "komenda przyjęta", nie "serwer już zmienił stan") — ale teraz
  faktyczny efekt komendy widać na ekranie bez ręcznego odświeżania, dzięki
  temu samemu mechanizmowi.
- Nie ma predykcji, która akcja ma sens przy jakim (nieznanym) żywym stanie —
  jedyna reguła to: wszystkie 4 przyciski wyłączone, gdy status administracyjny
  serwera nie jest `active` (zawieszony/instalujący się/przywracający backup).
- `ServerDetailScreen` nadal czyta bazowy `Server` z już wczytanej listy
  (`serverListControllerProvider`), nie z osobnego zapytania na wejściu —
  ale `refreshOne`/`ServerRuntimeSyncController`/WS `stats` już dowożą do
  tego samego miejsca aktualne dane bez potrzeby takiego zapytania.
- Panel może w praktyce wymagać dodatkowego `allowed_origins` po stronie
  Wings, jeśli `baseUrl` instancji nie jest już domyślnie zaufanym originem
  tego node'a — nie było to możliwe do zweryfikowania bez działającej pary
  Panel+Wings; udokumentowane w procedurze testów integracyjnych poniżej,
  do zweryfikowania w pierwszej realnej sesji z prawdziwą instancją.
- `sendCommand` wymaga uprawnienia `control.console` subusera/API key —
  apka nie sprawdza tego z góry, po prostu wyśle `send command` i Wings
  odrzuci je po cichu, jeśli brak uprawnień (zgodnie z protokołem — apka
  nie wprowadza tu własnej logiki uprawnień).
- Build na iOS nie był w tym kroku uruchamiany (brak środowiska macOS) — kod
  nie zawiera nic platformo-specyficznego (włącznie z `flutter_secure_storage`
  i `web_socket_channel`, które same obsługują iOS), ale warto to
  zweryfikować przy pierwszej okazji na maszynie z Xcode.
- `parseAnsiToSpans` (`console/presentation/widgets/ansi_text.dart`) obsługuje
  kody SGR (kolor/pogrubienie) — dokładnie to, co faktycznie wysyłają
  serwery gier (Minecraft/Bukkit) — oraz bezpiecznie *pomija* (bez
  wyświetlania) inne sekwencje CSI (ruch kursora, czyszczenie linii); nie
  jest to pełny emulator terminala (np. nie obsługuje trybu alternatywnego
  ekranu) — świadomie, bo to log przewijany w jedną stronę, nie interaktywny
  terminal.
- `StatusColors` (płaski, niezależny od motywu zestaw kolorów statusu) został
  usunięty i zastąpiony przez `AppSemanticColors`/`AppStatusBadge` — jeśli
  gdzieś w gałęzi roboczej istnieje kod importujący `core/theme/app_colors.dart`,
  wymaga migracji na nowy system (patrz [Design System](#design-system)).

## Test integracyjny z prawdziwą instancją Pterodactyl

`flutter test`/`flutter analyze`/`flutter build apk --debug` nie wymagają
osiągalnego Pterodactyla (patrz sekcja Testy) — to poniżej jest procedura
**ręcznej** weryfikacji wobec prawdziwego Panelu + Wings:

1. Dodaj instancję (URL Panelu + klucz API `ptlc_...` z uprawnieniem
   `control.console`, najlepiej też `control.start`/`control.stop` do testu
   power actions) i otwórz dowolny serwer → `ServerDetailScreen`.
2. **Połączenie**: sekcja „Konsola” powinna przejść
   Łączenie… → Połączono, i pokazać ostatni backlog konsoli (`send logs`).
   Jeśli od razu `Błąd połączenia` — sprawdź `allowed_origins`/`CheckOrigin`
   po stronie Wings (patrz ograniczenia wyżej) i czy `socket` z odpowiedzi
   REST jest osiągalny z urządzenia (ten sam node, port WS).
3. **Live output**: uruchom/zrestartuj serwer z poziomu apki (Power
   Actions) i zweryfikuj, że linie startu silnika pojawiają się w konsoli
   na żywo, bez ręcznego odświeżania.
4. **Komenda**: wpisz komendę konsolową (np. `list` dla serwera Minecraft) w
   polu na dole i zweryfikuj odpowiedź w outpucie.
5. **Reconnect**: wyłącz Wi-Fi/dane na urządzeniu na kilka-kilkanaście
   sekund, włącz z powrotem — wskaźnik powinien przejść przez
   `Ponowne łączenie…` i wrócić do `Połączono` automatycznie, bez ręcznej
   interwencji, i **bez** zduplikowanego backlogu w outpucie.
6. **Token expiry**: zostaw ekran otwarty >10 minut (dłużej niż ważność
   tokenu WS) i zweryfikuj, że połączenie **nie** rozłącza się — powinno po
   cichu odświeżyć token w tle (`token expiring`/`token expired`).
7. **Wyjście z ekranu**: wróć do listy serwerów i sprawdź (np. przez proxy
   sieciowe albo logi Wings) że WebSocket faktycznie się zamyka, zamiast
   zostać otwarty w tle.
8. **Zawieszony serwer** (jeśli dostępny do testu): zawieś serwer z poziomu
   Panelu i zweryfikuj, że apka pokazuje `Błąd połączenia` bez zapętlonych
   prób reconnectu (kod zamknięcia 4409).
