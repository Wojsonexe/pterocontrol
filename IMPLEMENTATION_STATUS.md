# Pterocontrol Control Plane — stan implementacji

Ostatnia aktualizacja: 2026-08-16, branch `feature/control-plane-mvp`, ostatni commit `568c68f`.

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

### FAZA 9b — federation-worker + realne podłączenie RabbitMQ (kolejki genuinely w użyciu, nie tylko w docker-compose)
- Nowy `packages/secrets` — `SecretsService` (AES-256-GCM) wydzielony z `control-plane-api/src/secrets/` z tego samego powodu co pterodactyl-sdk w FAZA 9a: `federation-worker` musi odszyfrowywać te same `InstanceCredential.ciphertext` co API, jednym, współdzielonym implementacją, nie kopią.
- Nowy serwis `services/federation-worker/` — osobny proces NestJS **bez HTTP** (`NestFactory.createApplicationContext`, `app.enableShutdownHooks()` na SIGTERM/SIGINT). Własny `PrismaService` (osobne połączenie/pool — inny proces OS, nie może dzielić live-instancji klienta z API), ale **ten sam schemat Prisma** (`services/control-plane-api/prisma/schema.prisma` pozostaje jedynym źródłem prawdy — worker konsumuje wygenerowany `@prisma/client` przez hoisting npm workspace, nie ma własnej migracji).
- `ProcessedJob` (Prisma, nowa migracja `20260816181440_add_processed_job`) + `IdempotencyService` — `jobId` sprawdzany (`isProcessed`) przed dispatch; `markProcessed()` wywoływane **zarówno przy sukcesie, jak i przy dotarciu do DLQ** (oba to stany terminalne — patrz niżej, prawdziwy bug znaleziony live).
- `InstanceSyncHandler` / `ServerSyncHandler` / `ResourcesCollectHandler` — odtwarzają dokładnie logikę, która wcześniej była synchroniczna w `control-plane-api` (ten sam upsert po `(instanceId, pterodactylUuid)`, ten sam `dedupKey` dla `Event`, ta sama konwersja BigInt dla `ResourceSnapshot`). Błędy domenowe własne workera (brak instancji/credentiala w DB) sygnalizowane przez `PermanentJobError` — nigdy nie retry'owane.
- `job-classifier.ts` — `classifyError()`: `PterodactylAuthError`/`PterodactylNotFoundError`/`PermanentJobError`/dowolny `HttpException` (np. odrzucenie SSRF) → `permanent`; `PterodactylNetworkError`/`PterodactylUnexpectedResponseError`/`PterodactylUpstreamError` z `statusCode >= 500` → `transient`; wszystko nierozpoznane → `transient` (bezpieczny domyślny, ograniczony przez `MAX_RETRY_ATTEMPTS`). `PterodactylUpstreamError` w `@pterocontrol/pterodactyl-sdk` zyskało pole `statusCode` (potrzebne do tego rozróżnienia bez parsowania stringa błędu).
- `FederationConsumerService` — manualny ack (`channel.consume(..., {noAck:false})`, `prefetch(1)`). Sukces → `markProcessed` + `ack`. Transient → republikacja do `cp.retry` z `expiration = computeRetryDelayMs(attempt)`, `attempt` inkrementowany (`withIncrementedAttempt`), `ack` oryginału (retry już bezpiecznie leży w `cp.retry`). Permanent lub wyczerpane retry → publikacja wprost do `cp.dlx` + `markProcessed` + `ack`. Nieparsowalny JSON → publikacja surowego contentu do `cp.dlx` + `ack` (bez `markProcessed` — nie ma `jobId` do zapisania). Awaria publikacji retry/DLQ (broker padł w trakcie) → `nack(msg, false, true)` — requeue, nigdy утrata wiadomości.
- `control-plane-api`: `POST /instances/:id/sync` i `POST /servers/sync/:instanceId` **nie wykonują już blokującego wywołania do Pterodactyla** — publikują `MessageEnvelope` do `cp.federation` i zwracają `202 {status:'queued', jobId}` (zweryfikowane live: **46ms**, wcześniej blokowało na realnym wywołaniu sieciowym). `ResourceCollectionScheduler` (`@nestjs/schedule`, `EVERY_MINUTE`) publikuje `federation.resources.collect` dla każdego `Server` — to jest tło, którego brakowało od FAZA 8 (dotąd próbki powstawały wyłącznie przy ręcznym `GET /resources`). `GET /health/ready` zwraca teraz `{status:'degraded', dependencies:{database,rabbitmq}}` (`200`, nie `503`) gdy RabbitMQ jest niedostępny — Postgres pozostaje jedyną twardą zależnością.
- `RabbitmqModule` (w obu serwisach) — `RabbitMqConnectionService.connect()` odpalane w fabryce providera bez `await` ("fire and forget") — broker niedostępny przy starcie nie blokuje bootowania procesu; auto-reconnect działa w tle.

**Zweryfikowane REALNIE** (tymczasowy Postgres + tymczasowy RabbitMQ w Dockerze na portach 5446/5677/15677, oba serwisy uruchomione jako prawdziwe, długo działające procesy przez `npm run start:dev`, ruch przez prawdziwe HTTP/AMQP, RabbitMQ Management API do inspekcji kolejek):
1. **Pełny happy-path**: bootstrap tenanta → login → `POST /instances` (baseUrl `https://example.com`, ten sam substytut co w FAZA 3, brak dostępu do realnego Pterodactyla) → `POST /instances/:id/sync` → **202 w 46ms** → worker konsumuje → `testConnection` → `404` → `PterodactylNotFoundError` → `permanent` → `federation.dlq`. Potwierdzone przez RabbitMQ Management API: `federation.dlq messages=1`, `federation.worker deliver=1/ack=1`.
2. **Utrata połączenia z RabbitMQ**: `docker stop` na brokerze → `POST /instances/:id/sync` → **503** (`Could not queue instance sync: ...`, kontrolowany błąd, nie crash) → `GET /health/ready` → **200** `status:"degraded"` → `GET /health` (bez zależności) nadal **200** — cały proces API żyje. `docker start` → auto-reconnect w ~5s (bez restartu API) → `/health/ready` wraca do `status:"ok"`.
3. **Prawdziwy bug znaleziony i naprawiony live**: `docker restart` na RabbitMQ **podczas** działania workera powodował **crash całego procesu** — `IllegalOperationError: Channel closed`, nieobsłużony reject w `startConsuming()` (wyścig między zamknięciem starego kanału a próbą `channel.consume()` na kanale już w trakcie zamykania, odtwarzalny realnie, nie hipotetyczny). Naprawa: `getChannel()` i `channel.consume()` owinięte w `try/catch` z retry (rekurencyjne wywołanie `startConsuming()`) zamiast pozwolić na nieobsłużony reject. Ponownie zweryfikowane tym samym scenariuszem (`docker restart`) — worker przetrwał, zalogował `Could not start consuming (channel closed mid-setup), retrying`, wznowił konsumpcję automatycznie po odzyskaniu brokera.
4. **Duplikat wiadomości**: ta sama wiadomość (ten sam `jobId`) opublikowana dwukrotnie ręcznym skryptem `amqplib`. **Przed fixem** (patrz punkt 3 obok — inny, drugi realny bug): oba dostarczenia w pełni przetworzone niezależnie, **2 wpisy w DLQ dla jednego `jobId`** (przyczyna: `markProcessed()` wywoływane wcześniej wyłącznie przy sukcesie, nigdy przy trafieniu do DLQ). **Po fixie** (`markProcessed` też przy permanent/wyczerpanych retry — to też stan terminalny): drugie dostarczenie → log `already processed - skipping redelivery`, **tylko 1 nowy wpis w DLQ**. Potwierdzone liczbą wiadomości w `federation.dlq` przez Management API przed i po.
5. **Restart workera bez utraty wiadomości**: worker zatrzymany (`Stop-Process`), wiadomość opublikowana bez żadnego konsumenta — potwierdzone Management API (`federation.worker messages=1, consumers=0`, wiadomość trwale w kolejce durable). Worker uruchomiony ponownie → natychmiast podjął i przetworzył zaległą wiadomość (widoczne w logu tuż po `Consuming from federation.worker`).

**Testy**: 47 nowych testów jednostkowych w `federation-worker` (idempotency, job-classifier, 3 handlery, `FederationConsumerService` — w tym dedykowany test regresji na duplikat-po-DLQ odpowiadający dokładnie bugowi #3/#4 znalezionemu live) + 3 nowe w `packages/secrets`. **168 testów łącznie w 5 workspace'ach (control-plane-api 64, federation-worker 47, pterodactyl-sdk 42, rabbitmq 12, secrets 3), wszystkie przechodzą.** typecheck/lint czyste we wszystkich 5 projektach.

Świadoma decyzja zakresu: `EventsService` (dedup przez P2002 na `dedupKey`) **nie** został wydzielony do wspólnego pakietu — zduplikowany wprost jako `federation-worker/src/events/record-event.ts` (~15 linii). W odróżnieniu od SSRF/sekretów to nie jest kod krytyczny dla bezpieczeństwa, a wydzielenie wymagałoby przebudowy sposobu wstrzykiwania `PrismaService` między dwoma osobnymi aplikacjami dla niewielkiej korzyści — nie warte tego kosztu na obecnym etapie.

### Alert Engine — AlertRule/Alert + evaluator (pierwsza rzecz czytająca historię ResourceSnapshot)
- `AlertRule` (Prisma): `metric` (`CPU_PERCENT`/`MEMORY_BYTES`/`DISK_BYTES`/`SERVER_OFFLINE`/`INSTANCE_OFFLINE`), `operator` (`GREATER_THAN`/`LESS_THAN`, null dla reguł offline), `threshold`, `serverId`/`instanceId` (dokładnie jeden zasób na regułę — świadomie bez semantyki "zastosuj do wszystkich serwerów tenanta" w tym MVP), `cooldownSeconds` (domyślnie 300). `Alert` — append-only historia, `resolvedAt: null` = aktywny, nigdy nie usuwany.
- `AlertsService.evaluate()` — wywoływane co minutę przez `AlertEvaluationScheduler` (`@nestjs/schedule`, tick po `ResourceCollectionScheduler` z tego samego modułu schedulingu, żeby ewaluacja miała szansę zobaczyć snapshot zebrany w tym samym ticku). Czyta wyłącznie to, co już jest w Postgresie (nigdy nic live z Pterodactyla — zgodnie z zasadą "Postgres jest source of truth" z mandatu RabbitMQ). Dedup/cooldown po `(ruleId, resourceId)`: aktywny `Alert` nigdy nie tworzy duplikatu; po `resolve` nowy `Alert` nie powstaje przed upływem `cooldownSeconds` od `resolvedAt`. Jedna reguła rzucająca wyjątkiem (np. serwer usunięty po utworzeniu reguły) jest łapana i logowana per-regułę, nigdy nie przerywa reszty przemiatania — ten sam wzorzec izolacji błędów co w `federation-worker`.
- `POST/GET /alert-rules`, `DELETE /alert-rules/:id`, `GET /alerts` (filtry `ruleId`/`serverId`/`instanceId`/`active`) — RBAC (`owner`/`admin` dla mutacji rule), tenant-scoped wszędzie, walidacja cross-field (serverId+operator+threshold wymagane dla metryk progowych, instanceId dla `INSTANCE_OFFLINE`) w `AlertsService.createRule()`, z tenant-ownership-check na wskazanym serwerze/instancji.
- Zweryfikowane REALNIE (tymczasowy Postgres+RabbitMQ w Dockerze, prawdziwy proces, prawdziwy upływ czasu między tickami crona — nie mockowany zegar): `POST /alert-rules` przez HTTP → `Server`+`ResourceSnapshot` (CPU=95.5%) wstawione bezpośrednio przez Prisma (brak dostępu do prawdziwego Pterodactyla, ta sama udokumentowana granica co w FAZA 3+) → po ~60s realnego oczekiwania na tick crona → `Alert` utworzony z poprawnym payloadem (`observedValue:95.5, threshold:90`) → kolejny tick przy niezmienionym stanie → **brak duplikatu** (identyczny `triggeredAt`) → snapshot z CPU=5% wstawiony → kolejny tick → `Alert` **auto-resolved** (`resolvedAt` ustawiony), `GET /alerts?active=true` poprawnie zwraca `[]`. Dodatkowo: brak `threshold`/`operator` → `400`; `DELETE /alert-rules/:id` → `204`.
- Testy: 20 nowych jednostkowych w `alerts.service.spec.ts` (walidacja `createRule`, wszystkie 5 typów reguł, dedup, cooldown, resolve, izolacja błędów per-regułę, filtry `findAllAlertsForTenant`).

## Stan testów

```
29 suit, 188 testów, wszystkie przechodzą
  (84 control-plane-api + 47 federation-worker + 42 pterodactyl-sdk + 12 rabbitmq + 3 secrets)
npm run typecheck  -> czysty (wszystkie 5 workspace'ów)
npm run lint        -> czysty (wszystkie 5 workspace'ów)
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

- **Alert Engine ewaluuje w pętli w `control-plane-api` (scheduled job), nie jako konsument RabbitMQ** — świadoma decyzja opisana wyżej ("prostszy wariant, nie przepisuj architektury bez potrzeby"). `cp.events` exchange jest zadeklarowany w topologii, ale nic jeszcze go nie publikuje/konsumuje — zarezerwowany pod Notifications, jeśli okaże się, że Alert Engine i Notifications faktycznie powinny być rozdzielone przez kolejkę (do zweryfikowania przy budowie Notifications, nie zakładane z góry).
- **Brak powiadomień o alertach** — `Alert` powstaje i jest widoczny przez `GET /alerts`, ale nic jeszcze nie informuje operatora aktywnie (email/push/webhook). To jest dokładnie zakres Notifications, patrz niżej.
- **RBAC nie ma jeszcze prawdziwego testu wielo-rolowego na żywo** — bootstrap tworzy tylko rolę `owner`, brak endpointu zapraszania członków z inną rolą. `RolesGuard` w pełni jednostkowo przetestowany, ale nie na żywym requeście z rolą `viewer`.
- **Brak Prisma `Permission`** (fine-grained RBAC) — świadomie, zgodnie z MVP.
- **Brak plików/konsoli WebSocket** przez Control Plane.
- **Brak testów kolejności wiadomości (message-ordering)** w `federation-worker` — nie było jeszcze przypadku w kodzie, gdzie kolejność między dwiema wiadomościami faktycznie ma znaczenie (każdy handler operuje na innym jobId niezależnie).
- **Nic z Notifications wzwyż nie istnieje**: Backups, Server Configuration, Schedules/Allocations/Databases (Pterodactyl-side), Database Gateway (osobny serwis), Mobile client (tryb Control Plane), Security hardening review, pełne testy integracyjne/E2E, produkcyjny deployment (Prometheus/Grafana/Traefik/TLS).
- **`infra/docker-compose.yml` wystawia RabbitMQ Management UI na `0.0.0.0:15672`** — akceptowalne dla lokalnego dev, ale mandat RabbitMQ wymaga wprost, żeby nigdy nie było to publicznie dostępne w produkcji; do naprawienia w fazie production/deployment (osobny compose/profil, port bindowany tylko na localhost albo VPN).

## Znane ograniczenia środowiska (nie kod, ale warte zapisania)

- Ta maszyna (Windows, gdzie ta sesja pracowała) ma inne, niezwiązane projekty zajmujące standardowe porty Dockera (5432/6379). Każda weryfikacja live używała tymczasowych, jednorazowych kontenerów na innych portach (5442-5447), zawsze sprzątanych po weryfikacji. `infra/docker-compose.yml` zakłada standardowe porty — na tej maszynie do lokalnego developmentu trzeba by je zremapować (lokalna specyfika, nie coś do zmiany w repo).
- **Brak dostępu do prawdziwej instancji Pterodactyla.** Cała weryfikacja Federation Layer jest zweryfikowana jednostkowo (mockowany `fetch`/DNS) i/lub realnym ruchem sieciowym do `https://example.com` (prawdziwe DNS/TCP/TLS/HTTP, ale nie prawdziwy Pterodactyl) i/lub ręcznie wstawionymi rekordami DB. Kod jest napisany zgodnie z realnym, udokumentowanym kontraktem Pterodactyl API (zweryfikowanym wcześniej w tej samej sesji na podstawie już działającej apki Flutter), ale nigdy nie uderzył w żywy panel.

## Następny konkretny krok

**Notifications.** `Alert` teraz powstaje i auto-resolve'uje się poprawnie (Alert Engine, wyżej), ale nic jeszcze nie informuje operatora aktywnie — `GET /alerts` trzeba dziś odpytać ręcznie. To jest dokładnie zakres tej fazy. W tej kolejności:

1. **Wybór kanału do zaimplementowania jako pierwszy: webhook (outbound HTTP POST), nie email.** Powód: SMTP wymaga prawdziwych danych logowania, których nie mam (a "NIE UDAWAJ IMPLEMENTACJI" wyklucza fake providera) — webhook da się w pełni, realnie przetestować bez żadnego sekretu (np. lokalny nasłuchujący serwer HTTP albo publiczny endpoint testowy). Prisma: `NotificationChannel` (tenantId, type na razie tylko `WEBHOOK`, config Json `{url}`, enabled) + `Notification` (append-only log dostaw: channelId, alertId, status pending/delivered/failed, attempt, lastError, sentAt).
2. **To jest prawdziwy, uzasadniony przypadek na użycie `cp.events`, zarezerwowanego od FAZA 9b.** Wysyłka webhooka to wychodzące wywołanie sieciowe z realnym ryzykiem timeoutu/niedostępności - dokładnie to, co mandat RabbitMQ każe robić asynchronicznie, a nie synchronicznie w pętli evaluatora. `AlertsService.applyEvaluation()` (w momencie tworzenia nowego `Alert`) publikuje event na `cp.events` (routing key np. `alert.triggered`); nowy handler w `federation-worker` (`NotificationDispatchHandler`, wzorowany dokładnie na `ResourcesCollectHandler` co do struktury) konsumuje, wysyła POST na skonfigurowany webhook URL, zapisuje wynik do `Notification`. Ten sam retry/DLQ/idempotency stack co reszta `federation-worker` (transient network error → retry przez `cp.retry`; webhook zwracający 4xx → permanent → DLQ) — zero nowej infrastruktury kolejkowej do zbudowania, tylko nowy routing key + handler + queue binding w `topology.ts` (`packages/rabbitmq`).
3. `POST/GET/DELETE /notification-channels` (podobny wzorzec CRUD co `alert-rules`), `GET /notifications` (log dostaw, tenant-scoped).
4. SSRF: webhook URL to również wychodzące wywołanie do adresu podanego przez usera — **musi przejść przez `SsrfValidatorService`** dokładnie tak samo jak `baseUrl` instancji Pterodactyla, żeby nie dało się skonfigurować webhooka wskazującego na metadata/localhost/private IP.
5. Testy: unit (dispatch handler, klasyfikacja błędów webhooka permanent/transient, SSRF-reject na złym URL), integracyjny live z prawdziwym HTTP serverem nasłuchującym lokalnie jako "webhook receiver" (zamiast `https://example.com` jak dotąd dla Pterodactyla - tu akurat MOŻNA mieć w pełni realny, kontrolowany endpoint odbierający, więc zrobić to porządnie, nie substytutem).

Po Notifications: Backups → Server Configuration → Schedules/Allocations/Databases/Activity → Database Gateway → Flutter → security review → E2E → production/deployment, zgodnie z listą uzgodnioną z użytkownikiem. Kontynuować autonomicznie, bez zatrzymywania się na potwierdzenie między etapami.
