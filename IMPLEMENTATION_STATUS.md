# Pterocontrol Control Plane — stan implementacji

Ostatnia aktualizacja: 2026-08-16, branch `feature/control-plane-mvp`, ostatni commit `96b40a9`.

Dokument-punkt-kontrolny w trybie autonomicznej implementacji. Kolejna sesja: przeczytaj to w całości, potem kontynuuj od sekcji "Następny konkretny krok" — nie projektuj architektury od nowa, jest już ustalona i częściowo zaimplementowana.

## Co zostało wykonane (real, przetestowane, zweryfikowane end-to-end)

### FAZA 0 — Audyt
Repo to Flutter (`lib/`, `android/`, `ios/`, `test/`, korzeń repo) + backend obok (`services/control-plane-api`, `infra/`), zgodnie z decyzją z wcześniejszej rozmowy. Flutter nietknięty przez cały czas trwania tej sesji.

### FAZA 1 — Foundation
- `ConfigModule.forRoot({ validate: validateEnv })` — fail-fast przy starcie, jeden czytelny błąd zamiast wielu rozrzuconych.
- `AllExceptionsFilter` (global) — spójny JSON, nieoczekiwane błędy (5xx/nie-HttpException) logowane server-side ze stackiem, nigdy nie wyciekają do klienta.
- Docker Compose (PostgreSQL + Redis + RabbitMQ + Management UI) — z wcześniejszej sesji, nadal aktualne w `infra/docker-compose.yml`.

### FAZA 2 — Auth + multi-tenancy
- `POST /tenants` — bootstrap Tenant+owner User+Membership atomowo, gated przez `BOOTSTRAP_TOKEN` (brak zmiennej = endpoint całkowicie wyłączony).
- `GET /tenants/me` — tenant zalogowanego usera, `tenantId` wyłącznie z JWT.
- `AuthService.login()` dołącza `tenantId`+`role` do JWT (pierwszy `Membership` usera — MVP: jeden tenant na usera).
- `JwtAuthGuard` + `RolesGuard` zarejestrowane globalnie (`APP_GUARD`) — **secure-by-default**, wszystko wymaga ważnego JWT poza `@Public()` (`health*`, `auth/login`, `tenants` bootstrap).
- Zweryfikowane realnie: dwaj różni tenanci (A, B), każdy widzi WYŁĄCZNIE swój `/tenants/me`.

### FAZA 3 — Federation MVP (onboarding, bez sync engine)
- `PterodactylInstance` + `InstanceCredential` (Prisma) — `global_id` własny, `InstanceCredential.ciphertext` szyfrowany przez `SecretsService` (AES-256-GCM, z wcześniejszej sesji).
- `SsrfValidatorService` — realna rezolucja DNS (`dns.resolve4/6`), blokuje loopback/private/link-local/metadata (IPv4 i IPv6, w tym IPv4-mapped), wywoływana dwukrotnie (zapis + tuż przed każdym połączeniem — obrona przed DNS rebinding).
- `PterodactylHttpClient` + `PterodactylApplicationApiClient` — natywny `fetch` (Node 22, zero nowej zależności), `redirect: 'manual'`, timeout przez `AbortController`, taksonomia błędów lustrzana do `AppException` z apki Flutter.
- `POST/GET/DELETE /instances` + `POST /instances/:id/sync` — tenant-scoped, create/sync/delete ograniczone do `owner`/`admin`.
- Zweryfikowane realnym ruchem sieciowym: próba dodania instancji na `127.0.0.1`/`169.254.169.254` → 400, `http://` → 400, prawdziwe `https://example.com` → SSRF przepuszcza, realny request → 404 → instancja zapisana jako `UNREACHABLE` z prawdziwym `lastError`.

### FAZA 4 — Global server model
- Refaktor: `SsrfValidatorService`/`PterodactylHttpClient`/`PterodactylApplicationApiClient` → własny `PterodactylModule` (Federation Layer), żeby `ServersModule` mógł z nich korzystać bez cyklu z `InstancesModule`.
- `Server` (Prisma) — mapowanie local→global przez `(instanceId, pterodactylUuid)`, `tenantId` zdenormalizowany (zawsze server-side, nigdy z requestu).
- `ServersService.syncInstance()` — pobiera listę serwerów z Application API, upsert. `GET /servers` z filtrami `instanceId`/`q` (wyszukiwanie po nazwie), zawsze tenant-scoped.
- Realny bug znaleziony i naprawiony przy weryfikacji na żywo: błąd Pterodactyla podczas syncu przechodził jako nieobsłużony wyjątek → goły `500`. Naprawione: `PterodactylError` łapany → `BadGatewayException` (502) z konkretnym komunikatem.

### FAZA 5/6 — Client API + Power Control + Audit Log
- `PterodactylClientApiClient` — `GET /api/client/servers/{id}/resources`, `POST /api/client/servers/{id}/power {signal}`. `PterodactylHttpClient` rozszerzony o `post()` (ten sam SSRF/redirect/timeout/error-mapping co `get()`, 204 No Content obsłużone bez próby parsowania JSON).
- `AuditLog` (Prisma, append-only) + `AuditService.record()` — każda akcja zasilania zapisuje wpis niezależnie od wyniku.
- `ServersService.getResources()`/`sendPowerAction()` — wymagają osobnego credentiala `CLIENT_API_KEY` (inny niż `APPLICATION_API_KEY` używany do syncu), jasny `400` jeśli brak, `502` (nie `500`) przy błędzie Pterodactyla.
- `POST /servers/:id/power` (RBAC `owner`/`admin`) + `GET /servers/:id/resources`.
- Zweryfikowane end-to-end na realnej bazie: ręcznie wstawiony `Server` (imitujący udany sync) + `POST /servers/:id/power` na `https://example.com` → `502` (405 z prawdziwego servera, poprawnie zmapowane) **i realny wpis w tabeli `AuditLog` w Postgresie** (nie mock — prawdziwy zapis).

## Stan testów

```
16 suit, 99 testów, wszystkie przechodzą
npm run typecheck  -> czysty
npm run lint        -> czysty
```

Uruchom: `cd services/control-plane-api && npm run typecheck && npm run lint && npm run test`

## Jak uruchomić lokalnie

```bash
cd infra && docker compose up -d postgres redis rabbitmq
cd ../services/control-plane-api
cp .env.example .env   # i wypełnij realnymi wygenerowanymi kluczami (patrz komentarze w .env.example)
npx prisma migrate deploy
npx prisma db seed     # opcjonalnie, tworzy dev@pterocontrol.local + Dev Tenant (bez BOOTSTRAP_TOKEN nie zadziała bootstrap innych tenantów)
npm run start:dev
```

## Świadomie NIEkompletne w tej fazie (uczciwie, nie udawane)

- **Brak federation-worker / BullMQ.** Cały sync (`POST /instances/:id/sync`, `POST /servers/sync/:instanceId`) jest **synchroniczny, na żądanie** — nie ma tła, harmonogramu, kolejki, retry/backoff/rate-limiting per instancja.
- **RBAC nie ma jeszcze prawdziwego testu wielo-rolowego na żywo.** `RolesGuard` jest w pełni jednostkowo przetestowany, ale bootstrap tworzy tylko rolę `owner` — nie ma jeszcze endpointu do zapraszania członków z inną rolą, więc "czy `viewer` faktycznie nie może wykonać power action" nie zostało zweryfikowane na żywym requeście, tylko przez unit test guarda.
- **Brak Prisma `Permission`** (fine-grained RBAC) — świadomie, zgodnie z MVP.
- **Brak plików/konsoli WebSocket** przez Control Plane — Client API to obsługuje (Pterodactyl), ale `PterodactylClientApiClient` na razie ma tylko `resources`/`power`.
- **Nic z FAZA 7 wzwyż nie istnieje**: Events (jako osobny, przeszukiwalny feed — dziś jest tylko `AuditLog` dla akcji power), Monitoring/historia metryk (`ResourceSnapshot` nie istnieje, `getResources()` zwraca tylko bieżący odczyt), Alert Engine, Notifications, Backups, Server Configuration, Schedules/Allocations/Databases (Pterodactyl-side), Database Gateway (osobny serwis), Mobile client (tryb Control Plane), Security hardening review, pełne testy integracyjne/E2E, produkcyjny deployment (Prometheus/Grafana/Traefik/TLS).

## Znane ograniczenia środowiska (nie kod, ale warte zapisania)

- Ta maszyna (Windows, gdzie ta sesja pracowała) ma **inne, niezwiązane projekty** zajmujące standardowe porty Dockera (5432/6379 zajęte przez `goodloop-postgres`/`goodloop-redis`). Każda weryfikacja live w tej sesji używała **tymczasowych, jednorazowych kontenerów** na innych portach (5442-5446), zawsze sprzątanych po weryfikacji. `infra/docker-compose.yml` sam w sobie zakłada standardowe porty — na tej konkretnej maszynie do lokalnego developmentu trzeba by zremapować porty (lokalna specyfika tej maszyny, nie coś do zmiany w repo).
- **Brak dostępu do prawdziwej instancji Pterodactyla** w tym środowisku — cała weryfikacja Federation Layer jest zweryfikowana albo jednostkowo (mockowany `fetch`/DNS) albo realnym ruchem sieciowym do `https://example.com` (prawdziwe DNS/TCP/TLS/HTTP, ale nie prawdziwy Pterodactyl) albo ręcznie wstawionymi rekordami DB (dla power/audit-log). Kod jest napisany zgodnie z realnym, udokumentowanym kontraktem Pterodactyl Client/Application API (zweryfikowanym wcześniej w tej samej sesji na podstawie już działającej apki Flutter), ale nigdy nie uderzył w żywy panel.

## Następny konkretny krok

**FAZA 7-9: Events + Monitoring history + Alert Engine**, w tej kolejności:
1. `ResourceSnapshot` (Prisma) — jedna tabela na próbki CPU/RAM/dysk/sieć per serwer, z retencją/rollupami zaprojektowanymi w dokumencie architektonicznym (nie trzymać wszystkiego bez limitu — patrz sekcja "Monitoring" tamtego dokumentu).
2. `Event` (Prisma) — osobny od `AuditLog`: `AuditLog` to "kto co zrobił" (akcje operatora), `Event` to "co się wydarzyło" (zmiany stanu wykryte przy syncu — `power_state_changed`, `server_offline` itp.). Na razie brak źródła zdarzeń poza syncem na żądanie — pierwsza wersja: `syncInstance()` zapisuje `Event` przy wykrytej zmianie statusu.
3. Dopiero potem `federation-worker` (BullMQ) — pierwszy prawdziwy background job zastępujący dzisiejszy "tylko na żądanie" sync, żeby `Event`/`ResourceSnapshot` miały realną częstotliwość, nie tylko ręczne wywołanie.
4. `AlertRule`/`Alert` (Prisma) + prosty evaluator (cron/interval) czytający najnowszy `ResourceSnapshot` — 5 reguł z dokumentu MVP Plan (CPU/RAM/disk threshold, server offline, instance offline).

Nie przeskakiwać do Database Gateway/Mobile/Production zanim Events + Monitoring + Alerty nie będą realne — to jest reszta rdzenia MVP (patrz oryginalny dokument MVP Implementation Plan, sekcja MVP scope, i FAZA 1 tego zadania).
