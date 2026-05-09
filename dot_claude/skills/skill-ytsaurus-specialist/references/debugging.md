# Debugging YTsaurus — систематический подход

Загружайте этот файл, когда пользователь:
- прислал YT-ошибку;
- описывает медленный запрос/джоб;
- столкнулся с зависшими tablet'ами, timeout'ами, OOM'ами.

## Общие инструменты диагностики

### Orchid
Каждая компонента (master, node, scheduler, tablet cell) экспонирует внутреннее состояние через Orchid — виртуальное поддерево Cypress под `//sys/.../orchid`. Пример:
```
yt get //sys/cluster_nodes/<node_addr>/orchid/tablet_cells/<cell_id>
```

Что там смотреть:
- `//sys/cluster_nodes/<addr>/orchid/tablet_cells/<cell_id>/tablets/<tablet_id>` — состояние конкретного таблета.
- `//sys/tablet_cell_bundles/<bundle>/@tablet_balancer_config`
- `//sys/tablet_cells/<cell_id>/@` — общие атрибуты ячейки.

### CLI — быстрые команды

```bash
# Состояние всех таблетов таблицы:
yt get //home/project/table/@tablets

# Количество таблетов:
yt get //home/project/table/@tablet_count

# Полный путь до cell'а таблета №0:
yt get //home/project/table/@tablets/0/cell_id

# Атрибуты таблицы целиком:
yt get //home/project/table/@

# Список operation'ов:
yt list //sys/operations

# Стейт конкретной operation:
yt get //sys/operations/<op_id>/@state
yt get //sys/operations/<op_id>/@result
```

### Профилирование и метрики
Bundle dashboard (в UI) показывает:
- Compaction/flush throughput.
- Dynamic store count per tablet.
- Read/write request rate и latency.
- Memory использование tablet node'ов.
- Tablet balancer moves.

Для операций — UI operation page → вкладки "Statistics", "Jobs", "Progress".

## Типичные ошибки и что они значат

### `Sticky transaction ... is not found`

**Что это:** транзакция существовала на конкретном proxy/RPC-connection'е, но этот proxy больше её не помнит.

**Причины:**
1. Proxy рестартовал.
2. Сессия timeout'нулась.
3. Tablet cell, на котором жил coordinator, переехал или упал и поднялся.
4. Tx уже была абортирована/закоммичена.
5. (редко) — cluster имел сбой, и транзакции были потеряны.

**Что делать:**
- Убедиться, что tx пингуется (в Go SDK — `AutoPingable: true` или ручной `PingTx`).
- Ловите ошибку, абортите старую (best-effort), начинайте новую. Идемпотентные операции можно ретраить.
- Если воспроизводится часто — проверьте `tx_timeout` (default 15s) и реальный интервал между операциями.

### `Transaction ... has expired or was aborted`

**Что это:** tx истёк (ни одного ping'а в течение timeout'а) либо был явно абортирован.

**Что делать:** то же, что выше. Для long-running операций увеличьте `timeout` через `StartTxOptions`/`StartTabletTxOptions`.

### `Too many versions in row` / `Row has too many versions`

**Что это:** в sorted dyn table накоплено > 2^16 версий одного ключа (в lookup-формате).

**Причины:**
- `atomicity=none` + частые апдейты одного ключа.
- TTL слишком длинный, `min_data_versions` слишком большой.
- Compaction отстаёт (низкий throughput bundle'а, перегружен).

**Что делать:**
1. Установите `@optimize_for=scan` — в scan-формате лимит версий намного больше.
2. Настройте TTL: `@max_data_ttl`, `@min_data_versions=1`, `@max_data_versions=1`.
3. Включите `@merge_rows_on_flush=true` — версии мёржатся уже при flush, а не ждут compaction.
4. Форсируйте compaction: `@forced_compaction_revision = <current_revision>` + remount.

### `Tablet ... is not mounted`

Таблица (или конкретный tablet) в состоянии `unmounted`/`frozen`/`mounting`.

**Что делать:**
- `yt get //path/@tablet_state` — какое состояние целиком.
- `yt get //path/@tablets/<i>/state` — какое у конкретного таблета.
- Если `unmounted` — `yt mount-table //path`.
- Если залипло в `mounting`/`unmounting` — проверить health tablet cell'а, посмотреть в master logs.

### `No in-sync replicas available`

**Контекст:** replicated table; все sync-replicas отстали или недоступны.

**Что делать:**
- Для чтения — использовать `async_last_committed` и позволить читать с async-replicas.
- Посмотреть лаг: `yt get //path/@replicas` и для каждой replica `//.../@replication_lag_time`.
- Переконфигурировать: возможно, sync-replica фактически не должна быть sync (подтормаживает).

### `Account ... exceeds disk_space limit` / `chunk_count limit` / `node_count limit`

Квота account'а исчерпана. Проверить:
```bash
yt get //sys/accounts/<account>/@
```

Интересные поля:
- `resource_limits.disk_space_per_medium.default`
- `resource_usage.disk_space_per_medium.default`
- `resource_limits.chunk_count`
- `resource_limits.tablet_count`, `tablet_static_memory`.

### `Row lock conflict` / `Write conflict`

Две транзакции пытались записать одну строку. Ошибка содержит tx_id конфликтующей.

**Что делать:**
- Идемпотентный ретрай с backoff.
- Если конфликтов много — значит дизайн предполагает одновременные записи в одни ключи. Рассмотрите: шардирование ключа, увеличение fan-out, `shared write lock`, `atomicity=none` (с осторожностью).

### `Timed out waiting for tablet ... to become served`

Tablet node перегружен либо в процессе recovery. Проверьте:
- Health bundle'а (есть ли decommissioning nodes).
- Memory pressure на tablet node.
- Long-running compaction'ы.

## Диагностика медленного запроса

### SelectRows медленный
1. **Что в `WHERE`?** Если нет равенства по первым ключевым колонкам — full scan. Перепишите запрос или добавьте вторичный индекс.
2. **`@in_memory_mode` == `none`, но таблица hot?** → `compressed` / `uncompressed`.
3. **Dynamic store count per tablet?** Если велико (> 2-3) — flush не успевает, читать дорого. Посмотрите график flush'а в bundle dashboard.
4. **Chunk count per tablet?** Если > ~100 — compaction отстаёт; проверьте CPU tablet node'ов.
5. **`optimize_for`** — для большого scan'а строк с многими колонками `lookup` хуже чем `scan`.

### LookupRows медленный
1. **Сколько keys за раз?** Больше ~10k может упираться в RPC limit; разбейте.
2. **In-memory mode.** Hot таблицы почти всегда должны быть in-memory.
3. **Compaction/dynamic store** — те же чеки.
4. **Network RTT.** Если клиент далеко от кластера — это секунды. Используйте RPC proxy + keep-alive.

### MR-операция медленная
1. **"Slowest" / "lagging" jobs** — в UI operation page; один застрявший job тормозит весь этап.
2. **Skew данных** — один reducer получил 80% строк. Смотрите `input_row_count` per job.
3. **Job count.** Спек с 10 job'ами на 1TB данных — каждый job огромный. Настройте `data_size_per_job`.
4. **Memory / CPU пределы.** `"memory_limit"` слишком низкий → OOM-retry → медленно; слишком высокий → job долго висит в очереди.

## Diagnostics: failed jobs

```bash
# Список job'ов с failure:
yt list-jobs <op_id> --job-state failed

# Stderr job'а:
yt get-job-stderr <op_id> <job_id>

# Spec job'а (что именно запускалось):
yt get-job-spec <op_id> <job_id>

# Core dump (если настроен):
yt get-job-input <op_id> <job_id> > input.bin  # воспроизвести локально
```

Для повторного прогона job'а локально используйте `yt run-job-shell` или выгружайте input + запускайте ваш бинарь.

## Tablet-level диагностика

Когда проблема в конкретном таблете:

```bash
# Найти cell'у для таблета:
yt get //home/table/@tablets/5/cell_id  # -> <cell_id>

# Посмотреть на orchid tablet'а:
yt get //sys/cluster_nodes/<node>/orchid/tablet_cells/<cell_id>/tablets/<tablet_id>
```

Интересные поля:
- `partitions` — как таблет поделён на partitions (внутри него).
- `store_count` — сколько stores (chunks + dynamic stores).
- `preload_state` — статус preload'а in-memory данных.
- `last_commit_timestamp`, `last_write_timestamp` — когда последний раз менялся.
- `performance_counters` — read/write/lookup rates.

## Корректная передача контекста ошибки

Когда пользователь присылает YT-ошибку, попросите (если не видно):
1. **Полный текст ошибки с её inner errors** — `yt cli` и SDK выводят иерархию; она важна.
2. **Имя таблицы / operation ID / тransaction ID.**
3. **Версию кластера** (`yt get //sys/@version`).
4. **Версию клиента** (`yt --version` или commit go.ytsaurus.tech/yt/go).
5. **Timestamp происшествия** — чтобы можно было смотреть метрики.
