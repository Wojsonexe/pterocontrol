# Pterocontrol Control Plane — stan implementacji

Ostatnia aktualizacja: 2026-08-16, branch `feature/control-plane-mvp`, ostatni commit `4ebbd3f`.

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

### Notifications — kanał webhook + pierwszy realny konsument `cp.events`
- `NotificationChannel` (Prisma, `type` na razie tylko `WEBHOOK`, `config: {url}`) + `Notification` (append-only log dostaw per `(Alert, Channel)`, `status` `PENDING`/`DELIVERED`/`FAILED`).
- **Refaktor `packages/rabbitmq`**: generyczny `QueueConsumer` (cały loop consume→dispatch→ack/retry/DLQ) wydzielony z `federation-worker`'s `FederationConsumerService` do wspólnego pakietu, bo Notifications potrzebowało dokładnie tej samej logiki — a ta logika miała już jeden prawdziwy, live-znaleziony bug (race przy restarcie brokera, FAZA 9b); druga, prawie identyczna implementacja podwajałaby ryzyko przyszłych bugów zamiast eliminować duplikację. `topology.ts` przeprojektowany pod dwie rodziny kolejek dzielące te same exchange'e `cp.retry`/`cp.dlx`, rozróżniane prefiksem routing-key (`federation.*` vs `alert.*`) — `federation.retry`/`federation.dlq` i `notifications.retry`/`notifications.dlq` nigdy się nie mieszają mimo wspólnych exchange'y (zweryfikowane live osobnymi licznikami wiadomości w każdej kolejce).
- `NotificationsService.notifyAlertTriggered()` — wywoływane przez `AlertsService` natychmiast po utworzeniu **nowego** `Alert` (nie przy re-triggerze na już aktywnym alarmie, nie przy `resolve`) — dla każdego włączonego kanału tenanta tworzy `Notification` (`PENDING`) i publikuje `alert.triggered` na `cp.events` z payloadem `{notificationId}`. Webhook URL przechodzi przez `SsrfValidatorService` przy tworzeniu kanału — ten sam mechanizm co `PterodactylInstance.baseUrl`.
- `POST/GET /notification-channels`, `DELETE /notification-channels/:id`, `GET /notifications`.
- `federation-worker`: **drugi `QueueConsumer` w tym samym procesie** (`NotificationConsumerService`, konsumuje `notifications.worker`) — RabbitMQ daje tu wartość, nie proces-jako-granica, więc nie osobny worker. `NotificationDispatchHandler` pobiera `Notification`+`Channel`+`Alert`, wysyła POST przez nowy `WebhookHttpClient` (SSRF-walidowany, `redirect:'manual'`, timeout — ta sama postawa bezpieczeństwa co `PterodactylHttpClient`, ale mniejszy, jednorazowy klient bez Bearer auth, żyjący w `federation-worker` bez potrzeby dzielenia go z `control-plane-api`). `job-classifier.ts` rozszerzony o `WebhookNetworkError` (transient) i `WebhookResponseError` (4xx permanent, 5xx transient).
- Zweryfikowane REALNIE (tymczasowy Postgres+RabbitMQ w Dockerze, oba serwisy jako prawdziwe procesy, prawdziwy ruch HTTP do zewnętrznych usług — **httpbin.org** jako kontrolowany, realny odbiornik webhooków): SSRF blokuje kanał wskazujący na `169.254.169.254` (`400`, request nigdy nie wychodzi) → `AlertRule`+`NotificationChannel` (httpbin.org/post) → sztuczny `ResourceSnapshot` CPU=97.2% → tick evaluatora → `Alert` → tick konsumenta → **realny POST na httpbin.org** → `Notification` `DELIVERED` z prawdziwym `sentAt` (748ms faktycznego round-trip przez internet, potwierdzone RabbitMQ Management API: `notifications.worker deliver=1/ack=1`). Cooldown poprawnie zablokował natychmiastowy retrigger (odtworzone dwukrotnie — raz przypadkowo tuż przy granicy 60s, raz jednoznacznie po pełnym upływie), a fan-out do **dwóch** kanałów na tym samym `Alert` dał dwa niezależne wyniki: kanał `httpbin.org/post` → `DELIVERED`, kanał `httpbin.org/status/404` → `FAILED` (`lastError: "Webhook responded with 404"`, `sentAt: null`, klasyfikacja `permanent` → prosto do `notifications.dlq` bez retry, potwierdzone Management API i logiem workera).
- Testy: 10 nowych w `packages/rabbitmq` (`queue-consumer.spec.ts` — generyczna wersja retry/DLQ/idempotency, w tym duplikat-po-DLQ i resume-po-reconnect), 7 w `control-plane-api` (`notifications.service.spec.ts`), 24 w `federation-worker` (`webhook-http.client`, `notification-dispatch.handler`, `notification-consumer.service`).

### Backups — proxy do Pterodactyl Client API
- Synchroniczny proxy (jak Power Control z FAZA 5/6 — Pterodactyl sam planuje faktyczne tworzenie backupu asynchronicznie po swojej stronie, więc żaden nowy przepływ RabbitMQ nie jest tu potrzebny). `PterodactylHttpClient` zyskał `delete()`. `PterodactylClientApiClient`: `listBackups`/`createBackup`/`getBackup`/`getBackupDownloadUrl`/`deleteBackup`/`restoreBackup`/`toggleBackupLock`.
- **Ważne zastrzeżenie co do źródła kontraktu API** (uczciwie, nie ukryte): ten kontrakt **nie został zweryfikowany względem tej apki Flutter** — sprawdzone bezpośrednio w kodzie (`server_detail_screen.dart`): Flutter nie ma żadnej implementacji backupów, zakładka to dosłowny placeholder "Kopie zapasowe — pojawi się w kolejnej aktualizacji". Endpointy (`GET/POST .../backups`, `GET .../backups/{uuid}`, `.../download`, `DELETE`, `.../restore`, `.../lock`) pochodzą z rzeczywistego, publicznie udokumentowanego kontraktu Pterodactyl Client API v1 (ogólna wiedza o tym open source projekcie) — to samo już wcześniej udokumentowane ograniczenie co cała reszta Federation Layer: nigdy nie uderzyły w żywy panel. Do zweryfikowania/poprawienia, jeśli/gdy dostęp do prawdziwego panelu Pterodactyla stanie się dostępny.
- `BackupsController`/`BackupsService` (nowy moduł `backups`, `/servers/:serverId/backups`) — tenant-scoped przez `ServersService`/`InstancesService.findOneForTenant()`, RBAC (`owner`/`admin` dla create/delete/restore/lock), `AuditLog` na każdą mutującą operację (sukces i porażka, ten sam wzorzec co `sendPowerAction`), błędy Pterodactyla → `502` (nie surowy `500`). Brak lokalnej tabeli `Backup` w tym MVP — lista zawsze pobierana live.
- Zweryfikowane REALNIE (ta sama metodologia co cała reszta Federation Layer — realny ruch sieciowy do `https://example.com`, jedyny publicznie dostępny substytut bez prawdziwego Pterodactyla): `GET /servers/:id/backups` → realny request → `404` od `example.com` → `502` z czytelnym komunikatem; `POST /servers/:id/backups` → `405` od `example.com` → `502` + **potwierdzony realny wpis w `AuditLog`** (`result:"error"`, `metadata.message` dokładnie taki jak w odpowiedzi).
- Testy: 14 nowych w `pterodactyl-sdk` (`delete()` + wszystkie 7 metod backupów), 11 w `backups.service.spec.ts` (tenant isolation, mapowanie 502, `AuditLog` sukces/porażka).

## Stan testów

```
39 suit, 246 testów, wszystkie przechodzą
  (100 control-plane-api + 65 federation-worker + 56 pterodactyl-sdk + 22 rabbitmq + 3 secrets)
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

- **Alert Engine ewaluuje w pętli w `control-plane-api` (scheduled job), nie jako konsument RabbitMQ** — świadoma decyzja ("prostszy wariant, nie przepisuj architektury bez potrzeby"). Notifications natomiast POKAZAŁO realny, uzasadniony przypadek dla `cp.events` (patrz wyżej) — więc rozdzielenie evaluacji od dispatchu przez kolejkę jest już częściowo prawdą (evaluacja lokalna, powiadamianie przez kolejkę).
- **RBAC nie ma jeszcze prawdziwego testu wielo-rolowego na żywo** — bootstrap tworzy tylko rolę `owner`, brak endpointu zapraszania członków z inną rolą. `RolesGuard` w pełni jednostkowo przetestowany, ale nie na żywym requeście z rolą `viewer`.
- **Brak Prisma `Permission`** (fine-grained RBAC) — świadomie, zgodnie z MVP.
- **Brak plików/konsoli WebSocket** przez Control Plane.
- **Brak testów kolejności wiadomości (message-ordering)** w `federation-worker` — nie było jeszcze przypadku w kodzie, gdzie kolejność między dwiema wiadomościami faktycznie ma znaczenie (każdy handler operuje na innym jobId niezależnie).
- **Notifications ma tylko jeden typ kanału (WEBHOOK)** — enum otwarty na SLACK/EMAIL, ale niezaimplementowane (EMAIL wymagałby prawdziwych danych SMTP, których nie mam — świadomie odłożone, nie fake'owane).
- **Kontrakt API dla Backups nie jest zweryfikowany względem Flutter/istniejącego kodu** (patrz sekcja Backups wyżej) — pochodzi z ogólnej wiedzy o publicznym Pterodactyl API, nie z lokalnego źródła prawdy. To samo dotyczyć będzie Server Configuration (Startup/Environment) — Flutter ma to jako `ComingSoonView` bez REST, więc kontrakt też będzie trzeba oprzeć na ogólnej wiedzy o Pterodactyl API, jawnie to zaznaczając.
- **Nic z Backups wzwyż nie istnieje**: Server Configuration, Schedules/Allocations/Databases (Pterodactyl-side), Database Gateway (osobny serwis), Mobile client (tryb Control Plane), Security hardening review, pełne testy integracyjne/E2E, produkcyjny deployment (Prometheus/Grafana/Traefik/TLS).
- **`infra/docker-compose.yml` wystawia RabbitMQ Management UI na `0.0.0.0:15672`** — akceptowalne dla lokalnego dev, ale mandat RabbitMQ wymaga wprost, żeby nigdy nie było to publicznie dostępne w produkcji; do naprawienia w fazie production/deployment (osobny compose/profil, port bindowany tylko na localhost albo VPN).

## Znane ograniczenia środowiska (nie kod, ale warte zapisania)

- Ta maszyna (Windows, gdzie ta sesja pracowała) ma inne, niezwiązane projekty zajmujące standardowe porty Dockera (5432/6379). Każda weryfikacja live używała tymczasowych, jednorazowych kontenerów na innych portach (5442-5447), zawsze sprzątanych po weryfikacji. `infra/docker-compose.yml` zakłada standardowe porty — na tej maszynie do lokalnego developmentu trzeba by je zremapować (lokalna specyfika, nie coś do zmiany w repo).
- **Brak dostępu do prawdziwej instancji Pterodactyla.** Cała weryfikacja Federation Layer jest zweryfikowana jednostkowo (mockowany `fetch`/DNS) i/lub realnym ruchem sieciowym do `https://example.com` (prawdziwe DNS/TCP/TLS/HTTP, ale nie prawdziwy Pterodactyl) i/lub ręcznie wstawionymi rekordami DB. Kod jest napisany zgodnie z realnym, udokumentowanym kontraktem Pterodactyl API (zweryfikowanym wcześniej w tej samej sesji na podstawie już działającej apki Flutter), ale nigdy nie uderzył w żywy panel.

## Następny konkretny krok

**Server Configuration** (Startup variables + Environment). Real, publicznie udokumentowany kontrakt Pterodactyl Client API v1: `GET /api/client/servers/{id}/startup` (lista zmiennych startowych z ich aktualnymi wartościami, opisami, regułami walidacji), `PUT /api/client/servers/{id}/startup/variable` (body `{key, value}`, aktualizuje jedną zmienną). **To samo zastrzeżenie co przy Backups** — Flutter (`server_detail_screen.dart`) ma zakładkę Startup/Environment jako `ComingSoonView` bez REST, więc ten kontrakt też pochodzi z ogólnej wiedzy o Pterodactyl API, nie z lokalnego źródła prawdy — zaznaczyć to jawnie w kodzie i w tym dokumencie, tak jak przy Backups. W tej kolejności:

1. Ten sam profil architektoniczny co Backups/Power Control: proxy synchroniczny, bez nowego przepływu RabbitMQ.
2. `PterodactylClientApiClient`: `getStartupVariables(baseUrl, apiKey, serverIdentifier)` (zwraca listę `{envVariable, name, description, defaultValue, serverValue, isEditable, rules}`), `updateStartupVariable(baseUrl, apiKey, serverIdentifier, key, value)`.
3. `ServerConfigController`/`ServerConfigService` w `control-plane-api` — `GET /servers/:id/startup`, `PUT /servers/:id/startup/variable` (RBAC `owner`/`admin` dla update, `AuditLog` na update sukces/porażka).
4. Testy: unit (proxy, tenant isolation, walidacja `isEditable` po stronie klienta — nie polegać wyłącznie na Pterodactylu do odrzucenia edycji niedozwolonej zmiennej), weryfikacja live do `https://example.com` (ta sama metodologia).

Po Server Configuration: Schedules/Allocations/Databases/Activity → Database Gateway → Flutter → security review → E2E → production/deployment, zgodnie z listą uzgodnioną z użytkownikiem. Kontynuować autonomicznie, bez zatrzymywania się na potwierdzenie między etapami.
