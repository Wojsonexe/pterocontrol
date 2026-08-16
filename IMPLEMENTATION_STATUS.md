# Pterocontrol Control Plane — stan implementacji

Ostatnia aktualizacja: 2026-08-16, branch `feature/control-plane-mvp`, ostatni commit `4f502c2`.

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

### FAZA 8 — ResourceSnapshot (historia metryk)
- `ResourceSnapshot` (Prisma, append-only): cpuAbsolutePercent, memoryBytes, diskBytes, networkRxBytes/TxBytes, uptimeMs (kolumny BigInt), indeksy `(serverId, observedAt)` i `(tenantId, observedAt)`.
- `ServersService.getResources()` zapisuje próbkę do `ResourceSnapshot` po każdym udanym odczycie z Pterodactyla (na razie jedyne źródło — cykliczny background poll to FAZA 9b, patrz niżej).
- `GET /servers/:id/resources/history` (`getResourceHistory`, limit domyślnie 100, twardy cap 500) — `ResourceSnapshotDto` z jawną konwersją BigInt→string.
- Realny, live-odtworzony bug: `Do not know how to serialize a BigInt` w `res.json()` — Express/`JSON.stringify` nie serializuje `BigInt` natywnie. Naprawione mapperem `toSnapshotDto()`; regresja pokryta testem wołającym prawdziwy `JSON.stringify()` na wyniku; zweryfikowane live curl: przed fixem `500`, po fixie `200` z `"memoryBytes":"2147483648"` jako string.

### FAZA 9a — packages/pterodactyl-sdk + packages/rabbitmq (przygotowanie pod federation-worker)
- npm workspaces rozszerzone o `packages/*`.
- Cała Federation Layer (`SsrfValidatorService`, `PterodactylHttpClient`, `PterodactylApplicationApiClient`, `PterodactylClientApiClient`) wydzielona (`git mv`, zero zmian w treści) z `services/control-plane-api/src/pterodactyl/` do nowego pakietu `@pterocontrol/pterodactyl-sdk` — powód: `federation-worker` będzie potrzebował dokładnie tych samych, bezpiecznych wywołań HTTP do Pterodactyla co `control-plane-api`; duplikacja kodu krytycznego dla bezpieczeństwa (SSRF) uznana za niedopuszczalne ryzyko rozjazdu. `pterodactyl.module.ts` w `control-plane-api` jest teraz tylko cienkim wire-upem providerów NestJS wokół klas z pakietu.
- Nowy, w pełni przetestowany, ale **jeszcze niepodłączony do żadnego działającego serwisu** pakiet `@pterocontrol/rabbitmq`:
  - `topology.ts` — exchange'e `cp.federation` (komendy), `cp.events` (zdarzenia), `cp.retry` (wewnętrzny holding exchange oparty o TTL per-wiadomość), `cp.dlx` (dead-letter); kolejki `federation.worker`, `federation.retry` (bez konsumenta — istnieje wyłącznie po to, by wiadomości „odczekały" swój `expiration`, po czym RabbitMQ automatycznie dead-letteruje je z powrotem do `cp.federation` pod oryginalnym routing key), `federation.dlq`. `setupTopology(channel)` deklaruje wszystko idempotentnie.
  - `envelope.ts` — `MessageEnvelope<T>` (jobId stabilne między retry, correlationId, tenantId, instanceId, serverId, createdAt, attempt) — projekt pod **at-least-once delivery** i idempotentne przetwarzanie po stronie konsumenta.
  - `retry.ts` — `computeRetryDelayMs` (5s/15s/30s + jitter ±20%), `isRetryExhausted` (MAX_RETRY_ATTEMPTS=3, czyli 4 próby łącznie).
  - `connection.service.ts` / `publisher.service.ts` — połączenie AMQP z auto-reconnect (`scheduleReconnect`), publisher z opcjami per-message.
- Przy okazji naprawiono kosmetyczne ostrzeżenie `ts-jest[ts-compiler] WARN ... allowJs` (jest.transform zawężony do `*.ts`, bo skompilowane `*.js` w `node_modules/@pterocontrol/*/dist` i tak nie potrzebują transformacji).
- Zweryfikowane: typecheck + lint + testy czyste we wszystkich trzech projektach (control-plane-api, pterodactyl-sdk, rabbitmq) — **120 testów, 20 suit, wszystkie przechodzą**, zero ostrzeżeń.

## Stan testów

```
20 suit, 120 testów, wszystkie przechodzą (66 control-plane-api + 42 pterodactyl-sdk + 12 rabbitmq)
npm run typecheck  -> czysty (wszystkie 3 workspace'y)
npm run lint        -> czysty (wszystkie 3 workspace'y)
```

Uruchom: `cd "E:\Projekty\pterodactyl-analysis\mobile" && npm run typecheck --workspaces --if-present && npm run lint --workspaces --if-present && npm run test --workspaces --if-present`

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

- **`@pterocontrol/rabbitmq` jest napisany i przetestowany jednostkowo, ale jeszcze niepodłączony do żadnego działającego procesu.** Ani `control-plane-api` (publisher), ani `federation-worker` (konsument — jeszcze nie istnieje jako serwis) go realnie nie używają. Brak jeszcze integracyjnego testu z prawdziwym RabbitMQ w Dockerze, testu restartu workera, testu duplikatu wiadomości, testu DLQ — to wszystko wymaga najpierw istniejącego workera do przetestowania.
- **Cały sync (instances, servers) jest wciąż synchroniczny, na żądanie** — HTTP request nadal blokuje na wywołaniu do Pterodactyla. To jest dokładnie to, co FAZA 9b ma zmienić.
- **Brak cyklicznego, tło-działającego pollingu `ResourceSnapshot`** — `ResourceSnapshot` istnieje i działa, ale próbki powstają wyłącznie przy ręcznym `GET /servers/:id/resources`, nie ma jeszcze harmonogramu/workera zbierającego je automatycznie.
- **RBAC nie ma jeszcze prawdziwego testu wielo-rolowego na żywo** — bootstrap tworzy tylko rolę `owner`, brak endpointu zapraszania członków z inną rolą. `RolesGuard` w pełni jednostkowo przetestowany, ale nie na żywym requeście z rolą `viewer`.
- **Brak Prisma `Permission`** (fine-grained RBAC) — świadomie, zgodnie z MVP.
- **Brak plików/konsoli WebSocket** przez Control Plane.
- **Nic z Alert Engine wzwyż nie istnieje**: Notifications, Backups, Server Configuration, Schedules/Allocations/Databases (Pterodactyl-side), Database Gateway (osobny serwis), Mobile client (tryb Control Plane), Security hardening review, pełne testy integracyjne/E2E, produkcyjny deployment (Prometheus/Grafana/Traefik/TLS).

## Znane ograniczenia środowiska (nie kod, ale warte zapisania)

- Ta maszyna (Windows, gdzie ta sesja pracowała) ma inne, niezwiązane projekty zajmujące standardowe porty Dockera (5432/6379). Każda weryfikacja live używała tymczasowych, jednorazowych kontenerów na innych portach (5442-5447), zawsze sprzątanych po weryfikacji. `infra/docker-compose.yml` zakłada standardowe porty — na tej maszynie do lokalnego developmentu trzeba by je zremapować (lokalna specyfika, nie coś do zmiany w repo).
- **Brak dostępu do prawdziwej instancji Pterodactyla.** Cała weryfikacja Federation Layer jest zweryfikowana jednostkowo (mockowany `fetch`/DNS) i/lub realnym ruchem sieciowym do `https://example.com` (prawdziwe DNS/TCP/TLS/HTTP, ale nie prawdziwy Pterodactyl) i/lub ręcznie wstawionymi rekordami DB. Kod jest napisany zgodnie z realnym, udokumentowanym kontraktem Pterodactyl API (zweryfikowanym wcześniej w tej samej sesji na podstawie już działającej apki Flutter), ale nigdy nie uderzył w żywy panel.

## Następny konkretny krok

**FAZA 9b: `federation-worker` jako osobny proces NestJS + realne podłączenie RabbitMQ.** Architektura RabbitMQ (topologia, envelope, retry) jest już zaprojektowana i przetestowana jednostkowo w `packages/rabbitmq` (patrz FAZA 9a wyżej) — to, co brakuje, to realny proces, który ją używa. W tej kolejności:

1. `services/federation-worker/` — nowa aplikacja NestJS (osobny `package.json`, osobny proces, osobny Dockerfile), konsumuje `@pterocontrol/rabbitmq` i `@pterocontrol/pterodactyl-sdk` (dokładnie te same klasy co control-plane-api — bez duplikacji).
2. Prisma: nowy model `ProcessedJob` (idempotencja — `jobId` unikalny, `processedAt`) tak, żeby redelivery tej samej wiadomości (at-least-once) był bezpieczny; worker sprawdza `ProcessedJob` przed wykonaniem efektu ubocznego i zapisuje po sukcesie w tej samej transakcji co właściwy zapis.
3. Konsument w `federation-worker`: `federation.instance.sync`, `federation.server.sync`, `federation.resources.collect` — manual ack (`channel.ack`/`channel.nack`), ack wyłącznie po pełnym sukcesie. Klasyfikacja błędów: permanent (401/403/zły credential/nieistniejąca instancja/invalid request) → od razu DLQ, nigdy retry; transient (timeout/connection refused/502/503/504) → publikacja do `cp.retry` z `expiration` z `computeRetryDelayMs(attempt)`, `attempt` inkrementowany przez `withIncrementedAttempt`; po wyczerpaniu (`isRetryExhausted`) → DLQ.
4. `control-plane-api`: podłączyć `RabbitMqPublisherService` jako realny publisher — `POST /instances/:id/sync` i background-resource-collection mają publikować `MessageEnvelope` zamiast (lub obok, na start) dzisiejszego blokującego wywołania synchronicznego. `/health` musi pokazywać stan RabbitMQ jako degraded/unavailable gdy broker nie żyje, a endpointy zależne od kolejki muszą zwracać kontrolowany błąd (nie crashować) gdy broker jest niedostępny.
5. Cykliczny harmonogram zbierania zasobów (np. `@nestjs/schedule` w control-plane-api publikujący `federation.resources.collect` dla wszystkich aktywnych serwerów, albo odpowiednik w workerze) — to jest to, co ostatecznie zapełnia `ResourceSnapshot` w tle zamiast tylko na żądanie.
6. Testy wymagane wprost przez mandat RabbitMQ: unit testy producenta i konsumenta, testy retry, testy DLQ, testy idempotencji/duplikatu wiadomości, **integracyjny test z prawdziwym RabbitMQ w Dockerze** (tymczasowy kontener, ta sama metodologia co dla Postgresa), test odporności na restart workera (wiadomości nie giną), test utraty połączenia z RabbitMQ (API nie pada, worker wznawia po odzyskaniu brokera), testy kolejności wiadomości tam, gdzie ma to znaczenie.
7. Po zbudowaniu i przetestowaniu workera: Alert Engine (`AlertRule`/`Alert`, evaluator czytający `ResourceSnapshot`, 5 reguł z MVP Plan — CPU/RAM/disk threshold, server offline, instance offline, cooldown + dedup po `(ruleId, resourceId)`) — naturalnie pasuje jako kolejny konsument na `cp.events`/nowy exchange, korzystający z tej samej infrastruktury kolejkowej.

Po Alert Engine: Notifications → Backups → Server Configuration → Schedules/Allocations/Databases/Activity → Database Gateway → Flutter → security review → E2E → production/deployment, zgodnie z listą uzgodnioną z użytkownikiem. Kontynuować autonomicznie, bez zatrzymywania się na potwierdzenie między etapami.
