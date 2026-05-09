# Dynamic Tables — глубокий разбор

Загружайте этот файл, когда вопрос связан с любыми динамическими таблицами: проектирование, транзакции, locks, TTL, репликация, компакция, tablet'ы.

## 1. Sorted vs Ordered

### Sorted dynamic tables
- Ключевые колонки задают первичный ключ, по нему всё шардируется.
- Все ключи уникальны в пределах таблицы.
- Строки — версионированные (MVCC), у каждой записи есть commit timestamp.
- Поддерживают: `lookup_rows` (точечное чтение по полному ключу), `select_rows` (SQL по диапазонам), `insert_rows`, `delete_rows`, `lock_rows`.
- Основной use case: key-value хранилище, OLTP, справочники с частыми чтениями.

### Ordered dynamic tables
- Нет первичного ключа. Шардирование — по `tablet_index` (round-robin при записи или вручную).
- Внутри таблета строки идут в порядке вставки и получают монотонный `$row_index`.
- Чтение: только по диапазону `(tablet_index, row_index)`. Нет `lookup` по значениям.
- Основной use case: очереди, логи, стриминг. См. Queue API — это надстройка над ordered tables.

**Как выбрать:** если вы хотите обновлять строки или искать по ключу — sorted. Если append-only лог — ordered.

## 2. Transactions и atomicity

### Режимы atomicity

- **`atomicity=full`** (default) — настоящий 2-phase commit. Multi-row, multi-table атомарность. Write locks на строках. Это **единственный** режим, в котором можно писать multi-row атомарно.
- **`atomicity=none`** — writes применяются независимо, без локов и без координации. Нет MVCC-защиты от конфликтов.

**Когда `atomicity=none` оправдан:** только если:
- Вы пишете с очень высоким RPS по одному и тому же ключу.
- Вам не нужна строгая консистентность (логи событий, метрики).
- Вы **осознали**, что если две транзакции запишут один ключ одновременно, результат непредсказуем.

**Распространённый антипаттерн:** включили `atomicity=none`, потом частые обновления одного ключа привели к накоплению > 2^16 версий → ошибка `Too many versions`. Лечится переключением на `@optimize_for=scan` и/или `@merge_rows_on_flush=true` с правильным TTL, но лучше не попадать туда.

### Как работает 2PC внутри YT

1. Клиент начинает tablet tx, получает `tx_id` у выбранного transaction coordinator (обычно один из tablet cells).
2. `insert_rows` / `delete_rows` отправляют операции на правильные таблет-клетки по ключу. Строки **пре-блокируются** (write intent).
3. На commit координатор запускает prepare phase → все участники отвечают OK/conflict → commit phase с timestamp.
4. До окончания commit phase читатели с `sync_last_committed` **ждут**; с `async_last_committed` — нет.

### Locks

- **Write lock** (exclusive) — автоматический при `insert_rows`/`delete_rows`. Конфликт → ошибка с tx_id конфликтующей транзакции.
- **Shared lock** (read) — явный через `lock_rows` с `lock_mode=shared`. Несколько tx могут держать одновременно. Риск **write starvation** — непрерывный поток shared locks не даёт никому записать.
- **Shared lock в weak vs strong режиме:**
  - `strong` — после коммита timestamp'ы сохраняются; последующая запись дождётся.
  - `weak` — timestamp'ы не сохраняются, запись не блокируется. Спасает от starvation, но не даёт full isolation.

### Типичные ошибки

- **`Transaction ... has expired or was aborted`** — tx не пинговался вовремя. У таблетных транзакций короткий timeout (по умолчанию 15s). В Go SDK используйте `AutoPingable: true` либо явно пингуйте через `client.PingTx`.
- **`Sticky transaction ... is not found`** — эта tx жила на конкретном proxy/координаторе, и тот больше её не знает. Причины: proxy рестартовал, tablet cell переехал, tx уже закоммитилась/абортилась. Нельзя "переподключиться" — начинайте новую tx.
- **Write conflict** — нормальная ситуация при конкуренции. Ретрайте на уровне приложения с backoff. Не делайте бесконечные ретраи на один и тот же ключ — это признак дизайн-проблемы.

## 3. MVCC, timestamps, compaction

Каждая запись получает **commit timestamp** — глобально монотонное число от cluster clock.

**Режимы чтения по timestamp:**
- `sync_last_committed` — видите все закоммиченные до момента запроса. Может ждать завершения текущих 2PC.
- `async_last_committed` — видите недавно закоммиченные, с задержкой десятки мс. Не ждёт 2PC. Быстрее, но не strict.
- Явный timestamp (число) — snapshot read в прошлое. Ограничено `retained_timestamp` таблицы.

### Compaction

Фоновый процесс мёржит chunk'и и удаляет старые версии, tombstone'ы и expired rows (по TTL).

**Что про неё надо знать:**
- Compaction запускается автоматически; её нагрузка отражается в метриках таблета.
- `@min_data_ttl` (по умолчанию 30 мин) — не удалять версии моложе этого. Это **минимум**, который должен пережить snapshot reader.
- `@max_data_ttl` — максимум хранения версии (помимо самой свежей).
- `@min_data_versions` / `@max_data_versions` — сколько версий хранить.
- Можно форсировать: `yt set //path/@forced_compaction_revision` или через `@force_compaction` (в новых версиях).
- Если compaction отстаёт — у таблета растёт число chunks и dynamic stores → деградация чтений.

### TTL по значениям (`$ttl` column)
Sorted dyn tables поддерживают **row-level TTL**: специальная колонка `$ttl` в миллисекундах. Работает только в связке с `@enable_replicated_table_tracker` и особыми настройками; см. "row-level TTL" в оф. доках. Альтернатива — удалять строки через `delete_rows` вручную или батчами.

## 4. `optimize_for`: lookup vs scan

- **`lookup`** (по умолчанию для новых dyn tables) — row-oriented chunks. Быстрые `lookup_rows`, быстрые записи. Медленный анализ всей таблицы.
- **`scan`** — column-oriented chunks (~Parquet). Дёшевые колоночные чтения, большое сжатие, но `lookup_rows` становится дороже.

**Правило:** OLTP-паттерн (частые точечные чтения по ключу) → `lookup`. Аналитика / MR / много версий на ключ → `scan`.

Менять можно через `@optimize_for=scan` + `alter_table` + re-compact (старые chunk'и останутся в старом формате до следующей компакции; можно форсировать `remount`+`forced_compaction_revision`).

## 5. In-memory modes

Атрибут `@in_memory_mode`:

- **`none`** — данные на диске, кэшируются обычным block cache. Lookups идут через диск.
- **`compressed`** — все chunks таблета резидентны в RAM в сжатом виде.
- **`uncompressed`** — полностью распакованы в RAM. Самый быстрый lookup, самый дорогой по памяти.

Лимит — память tablet node (видно в bundle). Для hot lookup-таблиц с небольшим объёмом `uncompressed` — стандартный способ получить < 1ms latency.

**Важно:** in-memory применяется при маунте; после `@in_memory_mode=...` нужен `remount_table`.

## 6. Шардирование и tablet-ы

### Pivot keys
Таблица sorted dyn делится на таблеты по `pivot_keys` — массив начальных ключей. Первый таблет начинается с `[null, null, ...]`.

### Resharding
- **Ручной:** `reshard_table //path --pivot-keys '[[...], [...]]'` или с количеством: `reshard_table //path 64` (равномерно по данным).
- **Автоматический:** tablet balancer — фоновый процесс, который:
  - Сплитит слишком большие таблеты (> `@max_tablet_size`, по умолчанию ~80 GB).
  - Мёржит слишком маленькие (< `@min_tablet_size`).
  - Перемещает таблеты между cells для баланса нагрузки (в режиме `parameterized`).

Целевой размер таблета — 10–50 GB. Больше — проблемы с мёржем и recovery; меньше — overhead на координацию.

### `reshard_table` vs `reshard_table_automatic`
- `reshard_table` — принудительный, требует **unmount** (кроме частичных случаев).
- `reshard_table_automatic` — работает на mounted table, опирается на настройки balancer'а. Подходит для онлайн-реорганизации.

## 7. Replicated tables

Одна логическая таблица с несколькими физическими replicas на разных кластерах.

**Структура:**
- Meta-таблица (replicated table) хранит только список replicas и их состояния. Живёт на одном кластере.
- Replicas — обычные sorted/ordered dyn tables на других кластерах.
- Каждая replica в одном из режимов: `sync` (коммит блокируется до ack) или `async` (fire-and-forget).

**Write path:**
1. Клиент пишет в meta-таблицу.
2. Tablet node копирует транзакцию sync-репликам, ждёт ack.
3. Async-репликам пишет фоном через replication log.

**Чтение:** с любой реплики, либо через meta-таблицу (она проксирует на доступную in-sync).

**Частая ошибка — "No in-sync replicas"**: все sync-реплики отстали или недоступны. Читайте с async с `async_last_committed` или перестройте набор sync.

**Chaos tables** — обобщение: multi-master, координаторы на каждом кластере, нет single point of truth. Сложнее в настройке, но выдерживают падение целого кластера.

## 8. Hunks

Отдельное хранилище для больших blob-значений в колонках. Вместо inline в chunk — ссылка на hunk chunk. Позволяет держать таблицу с 10MB-строками без раздувания основных chunk'ов.

Настраивается через `@hunk_storage_node` (новее) или атрибутами типа `@max_inline_hunk_size`.

Для большинства пользователей hunks включаются автоматически при превышении размера значения. Знать об этом надо в основном для performance-диагностики.

## 9. Queue API (надстройка над ordered tables)

Queue = ordered dyn table + queue agent. Агент:
- Трекает consumer'ов (`register_queue_consumer`).
- Даёт гарантии at-least-once чтения.
- Умеет делать cross-cluster репликацию очередей.
- Поддерживает exactly-once write с помощью queue producer sessions (новее).

Создание: обычная `create table --dynamic` с `dynamic=true` + регистрация как queue через `register_queue_consumer`/`queue_agent`.

## 10. Checklist перед созданием production-таблицы

1. **Sorted или ordered?**
2. **Схема:** key columns → value columns, типы с `optional<T>` где нужно.
3. **`optimize_for`:** `lookup` или `scan`?
4. **`in_memory_mode`:** `none` / `compressed` / `uncompressed`?
5. **`atomicity`:** `full` (почти всегда)?
6. **Начальное кол-во таблетов:** прикиньте размер; начните с N, чтобы каждый был 10–50 GB.
7. **Bundle:** какой? В нём достаточно tablet cells и памяти?
8. **TTL:** нужен? `@min_data_ttl`, `@max_data_ttl`, row-level?
9. **ACLs:** кто читает, кто пишет, `inherit_acl`?
10. **Compression codec:** `@compression_codec=zstd_5` для scan-таблиц разумный default.
11. **Account и quotas:** хватит ли `disk_space_per_medium`, `chunk_count`, `tablet_count`?
12. **Monitoring:** dashboard по bundle'у настроен?
