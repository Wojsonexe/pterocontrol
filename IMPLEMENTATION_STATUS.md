# Pterocontrol Control Plane — stan implementacji

Ostatnia aktualizacja: 2026-08-16, branch `feature/control-plane-mvp`, ostatni commit `fad4e19`.

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
- **Zweryfikowane realnym ruchem sieciowym** (nie tylko mockami): próba dodania instancji na `127.0.0.1`/`169.254.169.254` → 400, `http://` → 400, prawdziwe `https://example.com` → SSRF przepuszcza, realny request → 404 → instancja zapisana jako `UNREACHABLE` z prawdziwym `lastError`.

### FAZA 4 — Global server model
- Refaktor: `SsrfValidatorService`/`PterodactylHttpClient`/`PterodactylApplicationApiClient` → własny `PterodactylModule` (Federation Layer), żeby `ServersModule` mógł z nich korzystać bez cyklu z `InstancesModule`.
- `Server` (Prisma) — mapowanie local→global przez `(instanceId, pterodactylUuid)`, `tenantId` zdenormalizowany (zawsze server-side, nigdy z requestu).
- `ServersService.syncInstance()` — pobiera listę serwerów z Application API, upsert. `GET /servers` z filtrami `instanceId`/`q` (wyszukiwanie po nazwie), zawsze tenant-scoped.
- **Realny bug znaleziony i naprawiony przy weryfikacji na żywo**: błąd Pterodactyla podczas syncu przechodził jako nieobsłużony wyjątek → goły `500`. Naprawione: `PterodactylError` łapany → `BadGatewayException` (502) z konkretnym komunikatem.

## Stan testów

```
14 suit, 81 testów, wszystkie przechodzą
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
npx prisma db seed     # opcjonalnie, tworzy dev@pterocontrol.local + Dev Tenant
npm run start:dev
```

## Świadomie NIEkompletne w tej fazie (uczciwie, nie udawane)

- **Brak federation-worker / BullMQ.** Cały sync (`POST /instances/:id/sync`, `POST /servers/sync/:instanceId`) jest **synchroniczny, na żądanie** — nie ma tła, harmonogramu, kolejki, retry/backoff/rate-limiting per instancja. To jest realny, świadomy dług — architektura (`docs`/wcześniejsza rozmowa) zakłada `federation-worker` jako osobny proces z BullMQ+RabbitMQ.
- **Brak Client API.** Wszystko dotąd to Application API (bulk inventory: nodes, servers). Live resources (CPU/RAM/dysk/sieć), power actions (start/stop/restart/kill), pliki, konsola WebSocket — nic z tego nie istnieje jeszcze w backendzie. To jest Client API i wymaga osobnego `PterodactylClientApiClient`.
- **RBAC nie ma jeszcze prawdziwego testu wielo-rolowego na żywo.** `RolesGuard` jest w pełni jednostkowo przetestowany, ale bootstrap tworzy tylko rolę `owner` — nie ma jeszcze endpointu do zapraszania członków z inną rolą (`admin`/`operator`/`viewer`), więc "czy `viewer` faktycznie nie może utworzyć instancji" nie zostało zweryfikowane na żywym requeście, tylko przez unit test guarda.
- **Brak Prisma `Permission`** (fine-grained RBAC) — dokument architektoniczny to zakładał jako osobny, późniejszy etap; obecne RBAC jest płaskie (rola → lista dozwolonych ról na endpoincie), co jest zgodne z tym, co było ustalone dla MVP.
- **Nic z FAZA 5 wzwyż nie istnieje**: Global Dashboard, Power Control (start/stop/restart/kill), Events, Monitoring/historia metryk, Alert Engine, Notifications, Backups, Server Configuration, Schedules/Allocations/Databases (Pterodactyl-side), Database Gateway (osobny serwis), Mobile client (tryb Control Plane), Security hardening review, pełne testy integracyjne/E2E, produkcyjny deployment (Prometheus/Grafana/Traefik/TLS).

## Znane ograniczenia środowiska (nie kod, ale warte zapisania)

- Ta maszyna (Windows, gdzie ta sesja pracowała) ma **inne, niezwiązane projekty** zajmujące standardowe porty Dockera (5432/6379 zajęte przez `goodloop-postgres`/`goodloop-redis`). Każda weryfikacja live w tej sesji używała **tymczasowych, jednorazowych kontenerów** na innych portach (5442-5445), zawsze sprzątanych po weryfikacji. `infra/docker-compose.yml` sam w sobie zakłada standardowe porty — na tej konkretnej maszynie do lokalnego developmentu trzeba by zremapować porty (nie zrobione, bo to nie jest coś do zmiany w repo, tylko lokalna specyfika tej maszyny).
- **Brak dostępu do prawdziwej instancji Pterodactyla** w tym środowisku — cała weryfikacja Federation Layer (SSRF, HTTP client, error mapping) jest zweryfikowana albo jednostkowo (mockowany `fetch`/DNS) albo realnym ruchem sieciowym do `https://example.com` (prawdziwe DNS/TCP/TLS/HTTP, ale nie prawdziwy Pterodactyl). Kod jest napisany zgodnie z realnym, udokumentowanym kontraktem Pterodactyl Client/Application API (zweryfikowanym wcześniej w tej samej sesji na podstawie już działającej apki Flutter), ale nigdy nie uderzył w żywy panel.

## Następny konkretny krok

**FAZA 5/6: Client API + Power Control + Live Resources**, w tej kolejności:
1. `PterodactylClientApiClient` w `src/pterodactyl/` (analogicznie do `PterodactylApplicationApiClient`): `GET /api/client/servers/{id}/resources`, `POST /api/client/servers/{id}/power`. Wymaga `Client API key` — już mamy `InstanceCredential` z `CredentialKind.CLIENT_API_KEY`, opcjonalny przy tworzeniu instancji (dziś nieużywany nigdzie dalej).
2. `POST /servers/:globalId/power` (Control Plane) — RBAC (`owner`/`admin`), audit log (**nowa tabela `AuditLog`**, jeszcze nieistniejąca w schemacie — potrzebna teraz).
3. `GET /servers/:globalId/resources` — live CPU/RAM/dysk/sieć, bez trwałej historii jeszcze (to FAZA 8).
4. Dopiero potem: `federation-worker` (BullMQ) — pierwszy prawdziwy background job (inventory poll co N minut), zastępujący dzisiejszy "tylko na żądanie" sync.

Nie przeskakiwać do Database Gateway/Mobile/Production zanim Power Control + Events nie będą realne — to jest rdzeń tego, co MVP miało robić najpierw (patrz oryginalny dokument MVP Implementation Plan, sekcja MVP scope).
