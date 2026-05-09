# Bulk Insert и MapReduce над динамическими таблицами

Загружайте этот файл для ETL / data migration / массовых загрузок.

## Три способа массово записать в dyn-таблицу

| Способ | Когда | Плюсы | Минусы |
|---|---|---|---|
| `InsertRows` в цикле | Streaming, ручные потоки | Простой код, дёшево для RPS < 50k | Неэффективно на больших объёмах; грузит tablet node'ы |
| `bulk_insert` (MR → dyn table) | Разовая / батч-загрузка, трансформация static → dyn | Использует скедулер, параллелизм, эффективная передача | Создаёт много мелких chunks → нужна фоновая компакция |
| `alter_table --dynamic` | In-place конвертация static → dyn | Метаданные, мгновенно, 0 движения данных | Только для таблиц с совместимой схемой; сразу нужна mount + часто compaction |

## Bulk insert — MR с dyn output

Обычный MapReduce (map, reduce, merge — любой тип), где output таблица — sorted dyn table.

### Требования
- Output — **только sorted dyn table** (ordered не поддерживается для bulk insert).
- Оператор должен работать **не под user transaction** (нельзя оборачивать в master tx).
- Output path указывается с атрибутом `<append=%true>` (для append) или без (overwrite).

### Append vs overwrite

```yaml
# Append: данные добавляются к существующим (обычное поведение для дин-таблиц).
<append=%true>//home/project/dyn_table

# Overwrite: существующие данные заменяются. Опасно, если таблица в продакшене.
//home/project/dyn_table
```

В Go:
```go
output := ypath.Rich{
    Path:   dynTablePath,
    Append: ptr(true),
}
```

### CLI-пример

```bash
yt map-reduce \
    --src //home/project/events_raw \
    --dst '<append=%true>//home/project/events_dyn' \
    --reduce-by user_id \
    --reducer 'python3 transform.py'
```

### Особенности

- **Shared lock**, а не exclusive — несколько операций могут писать в одну таблицу одновременно.
- Commit атомарен: либо все output-таблицы видят новые данные, либо ни одна.
- Во время commit таблица **читается блокируется** для writes и for `sync_last_committed` reads. `async_last_committed` — видит старую версию, не блокируется.
- Каждый job производит минимум один chunk. Если у вас 10k jobs → 10k chunks. Это **создаст** нагрузку на компакцию.

### После bulk insert — всегда компакция

После большого bulk insert tablets содержат много мелких несложенных chunks. Без компакции lookup/select будут медленными.

**Варианты форсировать компакцию:**
1. `@forced_compaction_revision` + remount:
   ```bash
   REV=$(yt get //path/@revision)
   yt set //path/@forced_compaction_revision $REV
   yt remount-table //path
   ```
2. Дождаться, пока фоновая компакция догонит (может занять часы для больших таблиц).
3. На маленьких таблицах — unmount → mount (при unmount данные flush'атся в chunks, при mount компакция обычно запустится).

### Chunk/block size для dyn output

В spec MR-операции укажите:
```yaml
job_io:
  dynamic_table_writer:
    desired_chunk_size: 100M   # default уже 100M
    block_size: 256K           # default 256K
```

Slightly smaller, чем для static, потому что dyn chunks мёржатся в фоне.

## `alter_table --dynamic` — in-place конвертация

```bash
yt unmount-table //path    # если уже dyn — пропустить
yt alter-table //path --dynamic
yt mount-table //path
```

### Когда работает

- Таблица уже sorted (есть sort order на key columns).
- Тип `schema` совместим с dyn table (все типы поддерживаются в dyn).
- UniqueKeys=true, иначе придётся дедуплицировать вручную перед.

### Что происходит под капотом
Ничего фактически не копируется. Просто меняется атрибут `dynamic` на `true`, и таблица становится динамической. Но:
- У dyn tables по-другому устроены chunks и block index. Если старые chunks созданы без `block_size`, lookup будет медленным (см. FAQ YT).
- Решение: после `alter` сделать `remount` + форсировать компакцию с нужным `block_size`:
  ```bash
  yt set //path/@chunk_writer/block_size 262144
  yt set //path/@forced_compaction_revision $(yt get //path/@revision)
  yt remount-table //path
  ```

## MR-чтение из dyn-таблиц

Да, `read_table` и MR operations могут читать из смонтированных dyn-таблиц.

### Снэпшот-чтение
Чтобы гарантировать консистентность, используйте **snapshot transaction** + snapshot lock + timestamp.

```bash
TX=$(yt start-tx)
yt lock //path --mode snapshot --tx $TX
yt --tx $TX read //path --format yson > out.yson
yt commit-tx $TX
```

Или в spec: `"input_table_paths": ["<timestamp=12345>//path"]` для чтения на конкретном TS.

### Dynamic store read (enable_dynamic_store_read)

По умолчанию чтение из смонтированной dyn-таблицы **видит и dynamic stores** (свежие записи, ещё не flush'нутые). Для идемпотентности (два прогона одного джоба видят одно и то же) это плохо.

Варианты:
1. **Заморозить таблицу:** `yt freeze-table //path` — tablets в состоянии frozen, dynamic stores flush'ены на диск, writes запрещены.
2. **Отключить dynamic store read:** `@enable_dynamic_store_read = false` на таблице. Тогда MR видит только данные в chunks. Компромисс — read увидит данные с задержкой до flush (default 15 мин).
3. **Чтение по явному timestamp** — `<timestamp=X>//path`; всегда видит один и тот же срез.

В YQL с `@enable_dynamic_store_read=true` **кэш автоматически отключается** — вы не получите idempotent planning между прогонами.

## Конвертация dyn → static

Нужно для архивации, отправки на другой кластер, экспорта в ClickHouse и т.п.

### Вариант 1: MR merge с dyn input
```bash
yt merge --mode ordered \
    --src '<timestamp=1234567890000>//home/project/dyn_table' \
    --dst //home/project/archive/2026-04-15
```
`ordered` сохраняет порядок строк (по ключу для sorted). Timestamp — snapshot.

### Вариант 2: `remote_copy` (между кластерами)
Если нужно скопировать как static на другой кластер:
```bash
yt remote-copy \
    --cluster hahn \
    --src //home/project/dyn_snapshot \
    --dst //home/project/archive
```
Предварительно dyn нужно сделать "readable" — либо sorted snapshot через merge.

## Паттерны ETL для dyn-таблиц

### "Лог событий → aggregated dyn table"

1. Сырые события пишутся в ordered dyn table (queue) или static table (по дням).
2. Периодический MR (hourly/daily) агрегирует → пишет `bulk_insert` в агрегированную sorted dyn table.
3. Клиенты читают sorted dyn через `lookup_rows` / `select_rows`.

### "CDC из OLTP базы"

1. Кафка / logical replication → static или ordered dyn table на YT.
2. Stream processor (SPYT / Flink / кастомный Go) читает очередь, пишет в sorted dyn table через `InsertRows` (явная tablet tx).
3. Для at-least-once защиты — используйте queue producer sessions (exactly-once semantic) либо делайте операции идемпотентными через ключ.

### "Snapshot перед alter'ом схемы"

Нельзя сделать backward-incompatible alter на mounted dyn table. Pattern:
1. `yt unmount-table //path`
2. `yt copy //path //path.backup` (в рамках master tx — атомарно).
3. `yt alter-table //path --schema '<new_schema>'`
4. `yt mount-table //path`
5. Если что-то не так — `yt remove //path` + `yt move //path.backup //path`.

Для дополнительной надёжности есть также **backup API** (`create_table_backup` / `restore_table_backup`) — делает consistent snapshot через `checkpoint_timestamp`.

## Production-чеклист перед bulk insert на большую таблицу

1. **Account quota:** хватит ли `chunk_count` и `disk_space`? Bulk insert создаст много chunks.
2. **Bundle capacity:** не перегружен ли? Pre-insert проверьте compaction backlog.
3. **Атрибут `@tablet_count`:** если после insert нужен reshard — спланируйте.
4. **Режим:** append или overwrite? Как откатить если пошло не так?
5. **Мониторинг таблеты**: настроить dashboard, следить за store_count и compaction throughput после.
6. **Downstream consumers:** уведомить, что во время commit будет кратковременный lock для sync reads.
7. **Post-insert compaction:** запланировать forced compaction, если объём большой.
