# Pterocontrol Control Plane — stan implementacji

Ostatnia aktualizacja: 2026-08-16, branch `feature/control-plane-mvp`, ostatni commit `c5bfef8`.

Dokument-punkt-kontrolny w trybie autonomicznej implementacji. Kolejna sesja: przeczytaj to w całości, potem kontynuuj od sekcji "Następny konkretny krok" — nie projektuj architektury od nowa, jest już ustalona i częściowo zaimplementowana.

## Co zostało wykonane (real, przetestowane, zweryfikowane end-to-end)

### FAZA 0 — Audyt
Repo to Flutter (`lib/`, `android/`, `ios/`, `test/`, korzeń repo) + backend obok (`services/control-plane-api`, `infra/`). Flutter nietknięty przez cały czas trwania tej sesji.

### FAZA 1 — Foundation
- `ConfigModule.forRoot({ validate: validateEnv })` — fail-fast przy starcie.
- `AllExceptionsFilter` (global) — spójny JSON, nieoczekiwane błędy logowane server-side, nigdy nie wyciekają do klienta.
- Docker Compose (PostgreSQL + Redis + RabbitMQ + Management UI) — z wcześniejszej sesji.

### FAZA 2 — Auth + multi-tenancy
- `POST /tenants` — bootstrap Tenant+owner User+Membership atomowo, gated przez `BOOTSTRAP_TOKEN`.
- `GET /tenants/me` — `tenantId` wyłącznie z JWT.
- `AuthService.login()` dołącza `tenantId`+`role` do JWT.
- `JwtAuthGuard` + `RolesGuard` globalnie (`APP_GUARD`) — secure-by-default, `@Public()` dla wyjątków.
- Zweryfikowane realnie: dwaj tenanci, każdy widzi wyłącznie swój `/tenants/me`.

### FAZA 3 — Federation MVP (onboarding, bez sync engine)
- `PterodactylInstance` + `InstanceCredential` (Prisma), szyfrowanie przez `SecretsService`.
- `SsrfValidatorService` — realna rezolucja DNS, blokuje loopback/private/link-local/metadata (IPv4+IPv6), wywoływana dwukrotnie (obrona przed DNS rebinding).
- `PterodactylHttpClient` + `PterodactylApplicationApiClient` — natywny `fetch`, `redirect:'manual'`, timeout, taksonomia błędów.
- `POST/GET/DELETE /instances` + `POST /instances/:id/sync`, tenant-scoped, RBAC.
- Zweryfikowane realnym ruchem sieciowym (127.0.0.1/metadata → 400, `https://example.com` → SSRF przepuszcza, realny request → 404 → `UNREACHABLE`).

### FAZA 4 — Global server model
- Refaktor do `PterodactylModule` (Federation Layer), unika cyklu z `ServersModule`.
- `Server` (Prisma) — mapowanie local→global przez `(instanceId, pterodactylUuid)`.
- `ServersService.syncInstance()`, `GET /servers` z filtrami, tenant-scoped.
- Realny bug znaleziony i naprawiony live: błąd Pterodactyla dawał goły `500` → naprawione na `502`.

### FAZA 5/6 — Client API + Power Control + Audit Log
- `PterodactylClientApiClient` (resources, power). `PterodactylHttpClient.post()`.
- `AuditLog` (append-only) + `AuditService.record()` — każda akcja zasilania, sukces i porażka.
- `POST /servers/:id/power` (RBAC) + `GET /servers/:id/resources`, osobny credential `CLIENT_API_KEY`.
- Zweryfikowane end-to-end na realnej bazie: `502` z realnego ruchu + **realny wpis w `AuditLog`**.

### FAZA 7 — Events
- `Event` (Prisma, append-only, `dedupKey` unique) — "co się wydarzyło", osobne od `AuditLog` ("kto co zrobił"). `EventsService.record()` traktuje duplikat `dedupKey` (P2002) jako cichy no-op.
- `InstancesService`: emituje `instance_status_changed` tylko gdy status faktycznie się zmienił.
- `ServersService.syncInstance()`: emituje `server_created` wyłącznie dla nowych serwerów (nie przy każdym sync istniejącego).
- `GET /events` (tenant-scoped, filtry).
- Zweryfikowane end-to-end: 1 realna zmiana statusu → dokładnie 1 Event; identyczny ponowny sync → brak duplikatu; Tenant B nie widzi eventów Tenant A.

## Stan testów

```
17 suit, 104 testy, wszystkie przechodzą
npm run typecheck  -> czysty
npm run lint        -> czysty
```

Uruchom: `cd services/control-plane-api && npm run typecheck && npm run lint && npm run test`

## Jak uruchomić lokalnie

```bash
cd infra && docker compose up -d postgres redis rabbitmq
cd ../services/control-plane-api
cp .env.example .env   # wypełnij realnymi wygenerowanymi kluczami (patrz komentarze w .env.example)
npx prisma migrate deploy
npx prisma db seed     # opcjonalnie, tworzy dev@pterocontrol.local + Dev Tenant
npm run start:dev
```

## Świadomie NIEkompletne w tej fazie (uczciwie, nie udawane)

- **Brak federation-worker / BullMQ.** Cały sync (instances, servers) jest synchroniczny, na żądanie — brak tła, harmonogramu, kolejki, retry/backoff/rate-limiting per instancja.
- **Brak `ResourceSnapshot`.** `getResources()` zwraca tylko bieżący, pojedynczy odczyt — zero trwałej historii metryk, zero retencji/rollupów.
- **RBAC nie ma jeszcze prawdziwego testu wielo-rolowego na żywo** — bootstrap tworzy tylko rolę `owner`, brak endpointu zapraszania członków z inną rolą. `RolesGuard` w pełni jednostkowo przetestowany, ale nie na żywym requeście z rolą `viewer`.
- **Brak Prisma `Permission`** (fine-grained RBAC) — świadomie, zgodnie z MVP.
- **Brak plików/konsoli WebSocket** przez Control Plane.
- **Nic z FAZA 8 wzwyż nie istnieje**: Monitoring/historia metryk, Alert Engine, Notifications, Backups, Server Configuration, Schedules/Allocations/Databases (Pterodactyl-side), Database Gateway (osobny serwis), Mobile client (tryb Control Plane), Security hardening review, pełne testy integracyjne/E2E, produkcyjny deployment (Prometheus/Grafana/Traefik/TLS).

## Znane ograniczenia środowiska (nie kod, ale warte zapisania)

- Ta maszyna (Windows, gdzie ta sesja pracowała) ma inne, niezwiązane projekty zajmujące standardowe porty Dockera (5432/6379). Każda weryfikacja live używała tymczasowych, jednorazowych kontenerów na innych portach (5442-5447), zawsze sprzątanych po weryfikacji. `infra/docker-compose.yml` zakłada standardowe porty — na tej maszynie do lokalnego developmentu trzeba by je zremapować (lokalna specyfika, nie coś do zmiany w repo).
- **Brak dostępu do prawdziwej instancji Pterodactyla.** Cała weryfikacja Federation Layer jest zweryfikowana jednostkowo (mockowany `fetch`/DNS) i/lub realnym ruchem sieciowym do `https://example.com` (prawdziwe DNS/TCP/TLS/HTTP, ale nie prawdziwy Pterodactyl) i/lub ręcznie wstawionymi rekordami DB. Kod jest napisany zgodnie z realnym, udokumentowanym kontraktem Pterodactyl API (zweryfikowanym wcześniej w tej samej sesji na podstawie już działającej apki Flutter), ale nigdy nie uderzył w żywy panel.

## Następny konkretny krok

**FAZA 8-9: Monitoring history + Alert Engine**, w tej kolejności:
1. `ResourceSnapshot` (Prisma) — próbki CPU/RAM/dysk/sieć per serwer. Zaprojektować retencję/rollupy świadomie (nie trzymać wszystkiego bez limitu — patrz dokument architektoniczny, sekcja Monitoring: surowe próbki krótko, potem downsampling).
2. `ServersService.getResources()` dodatkowo zapisuje próbkę do `ResourceSnapshot` przy każdym odczycie (na razie jedyne źródło - brak jeszcze background pollingu).
3. `federation-worker` (BullMQ, Redis już jest w docker-compose) — pierwszy prawdziwy background job: cykliczny poll `getResources()` dla wszystkich serwerów, zastępujący dzisiejsze "tylko na żądanie". To jest właściwy moment, żeby to zbudować — wcześniej nie było jeszcze nic sensownego do pollowania w tle.
4. `AlertRule`/`Alert` (Prisma) + evaluator (interval/cron czytający najnowsze `ResourceSnapshot`) — 5 reguł z dokumentu MVP Plan: CPU/RAM/disk threshold, server offline, instance offline. Cooldown + dedup po `(ruleId, resourceId)`.

Nie przeskakiwać do Database Gateway/Mobile/Production zanim Monitoring + Alerty nie będą realne — to jest reszta rdzenia MVP (patrz oryginalny dokument MVP Implementation Plan, sekcja MVP scope).
