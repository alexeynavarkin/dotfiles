# YTsaurus Go SDK — паттерны и идиомы

Загружайте этот файл перед написанием любого нетривиального Go-кода для YT.

## Пакеты

Основной модуль: `go.ytsaurus.tech/yt/go`. Важные под-пакеты:

- `yt` — интерфейс `Client` и все опции операций (`LookupRowsOptions`, `InsertRowsOptions`, ...).
- `yt/ythttp` — HTTP-клиент (`ythttp.NewClient`).
- `yt/ytrpc` — RPC-клиент (`ytrpc.NewClient`). Быстрее, особенно на таблетных операциях. По умолчанию предпочтительнее для продакшена с дин. таблицами.
- `ypath` — типизированные пути (`ypath.Path`, `ypath.Rich`).
- `yson` — (де)сериализация YSON (используется для row struct тегов).
- `schema` — описание схем (`schema.Schema`, `schema.Column`).
- `migrate` — helper `migrate.EnsureTables` для создания/миграции схем декларативно.
- `yterrors` — работа с YT-шными ошибками (`ErrorCode`, `FindMatching`, `ContainsErrorCode`).
- `mapreduce` — клиент для MR операций.
- `guid` — YT'шные guid'ы (`guid.GUID`).

Если вы не уверены в точном имени метода или поля структуры — всегда лучше написать в ответе: "проверьте `go doc go.ytsaurus.tech/yt/go/yt.<Имя>`". API стабилен, но добавляются новые поля/опции.

## Создание клиента

```go
import (
    "context"
    "time"

    "go.ytsaurus.tech/yt/go/yt"
    "go.ytsaurus.tech/yt/go/yt/ythttp"
    "go.ytsaurus.tech/yt/go/yt/ytrpc"
)

func newClient() (yt.Client, error) {
    // RPC предпочтительнее для дин. таблиц — меньше latency, поддерживает batch-запросы эффективнее.
    return ytrpc.NewClient(&yt.Config{
        Proxy:             "hahn",                   // имя кластера или hostname
        Token:             os.Getenv("YT_TOKEN"),    // либо через ~/.yt/token
        ReadTokenFromFile: true,                     // прочитает из ~/.yt/token если Token пустой
        // Timeout обычно переопределяется через ctx; тут можно задать дефолт.
    })
}
```

**Закрытие клиента:** у `yt.Client` есть `Stop()` (или аналог — проверьте актуальный интерфейс). Один клиент держится на весь lifetime процесса — не создавайте по одному на запрос.

## Row struct'ы

Строки описываются структурами с YSON-тегами:

```go
type UserRow struct {
    UserID    uint64  `yson:"user_id,key"`      // key-column (см. ниже про "key")
    CreatedAt int64   `yson:"created_at"`
    Email     string  `yson:"email"`
    Name      *string `yson:"name,omitempty"`   // optional column
}
```

**Важно про теги:**
- `yson:"name"` — имя колонки в таблице.
- `,omitempty` — не включать при записи, если zero value. Используйте для optional-колонок в Go-структуре с value-типами.
- `,key` — **не** автоматически делает колонку ключевой при создании таблицы через `CreateTable`. Ключевые колонки задаются через `Schema.Columns[i].SortOrder = schema.SortAscending`. Тег `key` встречается в некоторых helper'ах `migrate`, но лучше задавать схему явно.

Для значений-опционалов YTsaurus различает: отсутствует (не писалось), записан NULL, записан value. В Go:
- Указатель `*T` — может быть nil = NULL.
- Value-тип + `omitempty` — не запишется, если zero. Это не то же самое, что NULL.

## Создание таблицы

### Через `migrate.EnsureTables` (декларативный способ — предпочтительнее)

```go
import (
    "go.ytsaurus.tech/yt/go/migrate"
    "go.ytsaurus.tech/yt/go/schema"
    "go.ytsaurus.tech/yt/go/ypath"
)

tablePath := ypath.Path("//home/project/users")

tableSchema := schema.MustInfer(&UserRow{})
// Если нужен явный контроль — собирайте руками:
tableSchema = schema.Schema{
    Strict:     &[]bool{true}[0],
    UniqueKeys: true,
    Columns: []schema.Column{
        {Name: "user_id",    ComplexType: schema.TypeUint64,  SortOrder: schema.SortAscending},
        {Name: "created_at", ComplexType: schema.TypeInt64},
        {Name: "email",      ComplexType: schema.TypeString},
        {Name: "name",       ComplexType: schema.Optional{Item: schema.TypeString}},
    },
}

err := migrate.EnsureTables(ctx, yc, map[ypath.Path]migrate.Table{
    tablePath: {
        Schema: tableSchema,
        Attributes: map[string]any{
            "dynamic":             true,
            "optimize_for":        "lookup",
            "tablet_cell_bundle":  "default",
            "in_memory_mode":      "none",
        },
    },
}, migrate.OnConflictTryAlter(ctx, yc))
```

**`migrate.OnConflictTryAlter`** пытается `alter_table` при несовпадении схемы. Для дин. таблиц требуется unmount — оберните в `migrate.UnmountAndAlterAndMount` если есть такой helper, или делайте руками: `unmount → alter → mount`.

### Через `CreateTable`

```go
_, err := yc.CreateNode(ctx, tablePath, yt.NodeTable, &yt.CreateNodeOptions{
    Attributes: map[string]any{
        "schema":             tableSchema,
        "dynamic":            true,
        "optimize_for":       "lookup",
        "tablet_cell_bundle": "default",
    },
    Recursive: true,
})
```

После создания — **mount**:
```go
if err := yc.MountTable(ctx, tablePath, nil); err != nil { ... }
// Подождать пока таблеты перейдут в mounted:
err := migrate.MountAndWait(ctx, yc, tablePath)
```

## LookupRows (точечное чтение)

```go
keys := []any{
    &UserRow{UserID: 42},
    &UserRow{UserID: 43},
}

reader, err := yc.LookupRows(ctx, tablePath, keys, &yt.LookupRowsOptions{
    KeepMissingRows: true, // вернёт nil в позиции отсутствующих ключей; иначе просто пропустит
    // Timestamp: &someTs,   // для snapshot read
    // Columns: []string{"email", "name"},
})
if err != nil { return err }
defer reader.Close()

var row UserRow
for reader.Next() {
    if err := reader.Scan(&row); err != nil { return err }
    // использовать row
}
if err := reader.Err(); err != nil { return err }
```

**Тонкости:**
- Ключи — это полный set key columns. Частичный ключ в lookup нельзя (для этого нужен `select_rows`).
- `KeepMissingRows: true` обязателен, если вам важно, какие из ключей не нашлись.
- Для больших batch'ей (> 10k ключей за раз) разбивайте на части — одиночный lookup может упереться в RPC timeout.

## SelectRows (SQL по диапазонам)

```go
query := fmt.Sprintf(
    "user_id, email FROM [%s] WHERE user_id >= %d AND user_id < %d LIMIT 1000",
    tablePath, start, end,
)

reader, err := yc.SelectRows(ctx, query, &yt.SelectRowsOptions{
    // Timestamp: ...
    // InputRowLimit / OutputRowLimit для защиты от OOM на нодах
})
if err != nil { return err }
defer reader.Close()

for reader.Next() {
    var r struct {
        UserID uint64 `yson:"user_id"`
        Email  string `yson:"email"`
    }
    if err := reader.Scan(&r); err != nil { return err }
    // ...
}
```

**Фильтр по ключевому префиксу `user_id >= X AND user_id < Y` push-down'ится** до tablet node и читает только нужные chunk'и. Фильтр по неключевым колонкам — post-filtering уже прочитанных строк. Помните об этом при оптимизации.

## InsertRows и tablet transactions

### Простой insert (неявная tx)

```go
rows := []any{
    &UserRow{UserID: 1, Email: "a@example.com"},
    &UserRow{UserID: 2, Email: "b@example.com"},
}

err := yc.InsertRows(ctx, tablePath, rows, &yt.InsertRowsOptions{
    Update: ptr(true),    // UPSERT-поведение: обновляет указанные колонки, не затирает остальные
    // Atomicity: ptr(yt.AtomicityFull),  // default; менять только осознанно
})
```

Без явной транзакции SDK сам открывает одноразовую tablet tx. Для multi-row / multi-table атомарности нужна явная tx.

### Явная tablet transaction

```go
tx, err := yc.BeginTabletTx(ctx, &yt.StartTabletTxOptions{
    // Atomicity, Type и др.
})
if err != nil { return err }

// ВАЖНО: defer Abort ДО первого действия, чтобы не протечь tx при panic/early return.
committed := false
defer func() {
    if !committed {
        _ = tx.Abort()
    }
}()

if err := tx.InsertRows(ctx, tableA, rowsA, nil); err != nil { return err }
if err := tx.DeleteRows(ctx, tableB, keysB, nil); err != nil { return err }

if err := tx.Commit(); err != nil {
    return fmt.Errorf("commit tablet tx: %w", err)
}
committed = true
return nil
```

**Ретраи write-conflict'ов:**
```go
import "go.ytsaurus.tech/yt/go/yterrors"

for attempt := 0; attempt < maxAttempts; attempt++ {
    err := doTabletTx(ctx, yc)
    if err == nil { return nil }

    if yterrors.ContainsErrorCode(err, yterrors.CodeTransactionLockConflict) {
        // exponential backoff с jitter
        time.Sleep(backoff(attempt))
        continue
    }
    return err
}
```

Точный код ошибки уточняйте через `go doc go.ytsaurus.tech/yt/go/yterrors` — имена констант могут варьироваться (например, `CodeTabletRowLockConflict`).

## BatchRequest — много мелких операций одной RPC

Для множества мелких чтений/вставок по Cypress или дин. таблицам эффективнее пакетировать:

```go
batch, err := yc.NewBatchRequest()
if err != nil { return err }

exists1 := batch.NodeExists(ctx, ypath.Path("//home/a"), nil)
exists2 := batch.NodeExists(ctx, ypath.Path("//home/b"), nil)
// ... десятки операций ...

if err := batch.ExecuteBatch(ctx); err != nil { return err }

r1, err := exists1.Result()
// ...
```

Каждый вызов на `batch` возвращает future-подобный объект; реальный результат — после `ExecuteBatch`. Batch хорош для сотен операций; тысячи — уже лучше параллельный worker pool.

## MountTable / UnmountTable / Reshard

```go
err := yc.MountTable(ctx, tablePath, &yt.MountTableOptions{
    CellID: &cellID,   // опционально — для точного размещения
    Freeze: ptr(false),
})

err = yc.UnmountTable(ctx, tablePath, &yt.UnmountTableOptions{
    Force: ptr(false), // true = abort unfinished tx
})

err = yc.ReshardTable(ctx, tablePath, &yt.ReshardTableOptions{
    PivotKeys: [][]any{
        {int64(0)},
        {int64(1_000_000)},
        {int64(2_000_000)},
    },
})
```

Для большинства операций нужен **unmount**. `reshard_table_automatic` работает на смонтированной таблице через tablet balancer:

```go
// Псевдо — уточните метод в SDK; команда называется "reshard_table_automatic".
// Возможно у вас: yc.ReshardTableAutomatic(ctx, path, &yt.ReshardTableAutomaticOptions{KeepActions: true})
```

## Работа с Cypress

Обычные операции на Cypress:

```go
// Создание директории (recursive — создаст всю цепочку).
_, err := yc.CreateNode(ctx, ypath.Path("//home/project/logs/2026"),
    yt.NodeMap,
    &yt.CreateNodeOptions{Recursive: true, IgnoreExisting: true})

// Чтение атрибута.
var count int64
err = yc.GetNode(ctx, tablePath.Attr("tablet_count"), &count, nil)

// Установка атрибута.
err = yc.SetNode(ctx, tablePath.Attr("expiration_timeout"), 86400000, nil) // ms

// Список нод.
var items []struct {
    Name string `yson:",value"`
    Type string `yson:"type,attr"`
}
err = yc.ListNode(ctx, ypath.Path("//home/project"), &items,
    &yt.ListNodeOptions{Attributes: []string{"type"}})
```

## Общие ошибки и как их ловить

```go
import "go.ytsaurus.tech/yt/go/yterrors"

err := yc.InsertRows(ctx, path, rows, nil)
if yterrors.ContainsErrorCode(err, yterrors.CodeResolveErrorNoSuchTransaction) {
    // tx expired — начать заново
}
if yterrors.ContainsErrorCode(err, yterrors.CodeResolveErrorTabletNotMounted) {
    // таблета нет или unmounted
}
// Достать первую ошибку по предикату:
if e := yterrors.FindMatching(err, func(e *yterrors.Error) bool {
    return e.Code == yterrors.CodeAccountLimitExceeded
}); e != nil {
    // превышена квота аккаунта
}
```

**Точные имена констант `yterrors.Code*` проверяйте через `go doc go.ytsaurus.tech/yt/go/yterrors`** — их много и список расширяется.

## MapReduce из Go

```go
import "go.ytsaurus.tech/yt/go/mapreduce"

type Mapper struct{}

func (m *Mapper) InputTypes() []any  { return []any{&UserRow{}} }
func (m *Mapper) OutputTypes() []any { return []any{&UserRow{}} }

func (m *Mapper) Do(ctx mapreduce.JobContext, in mapreduce.Reader, out []mapreduce.Writer) error {
    var row UserRow
    for in.Next() {
        if err := in.Scan(&row); err != nil { return err }
        // ... трансформация ...
        if err := out[0].Write(&row); err != nil { return err }
    }
    return nil
}

func init() { mapreduce.Register(&Mapper{}) }

// Запуск:
mr := mapreduce.New(yc)
op, err := mr.Map(&Mapper{}, mapreduce.Spec{
    InputTablePaths:  []ypath.YPath{input},
    OutputTablePaths: []ypath.YPath{output},
})
if err != nil { return err }

if err := op.Wait(); err != nil { return err }
```

Для bulk-insert в dyn-таблицу используйте output path с атрибутом `<append=%true>` или префиксом `<append=true>`:

```go
mapreduce.Spec{
    OutputTablePaths: []ypath.YPath{
        ypath.Rich{Path: dynTablePath, Append: ptr(true)},
    },
}
```

## Типичные подводные камни

1. **Забыли `defer Abort`.** Tx утекает, держит локи на строках. Всегда `defer` с флагом `committed`.
2. **Один глобальный `context.Background()` без deadline.** Запросы зависают на проблемном кластере. Всегда делайте `ctx, cancel := context.WithTimeout(ctx, 10*time.Second)`.
3. **Создание клиента в hot path.** Держите один `yt.Client` на процесс.
4. **Игнорирование `reader.Err()` после цикла `Next()`.** `Next() == false` не значит "успех" — может быть ошибка. Всегда проверяйте `Err()` после.
5. **`InsertRows` без `Update: true` при апсертах.** Дефолтный режим — replace (перезатирает nil'ами незаписанные колонки). Почти всегда хочется `Update: true`.
6. **Пинг транзакции.** Если сами держите long-running tx, либо создавайте с `AutoPingable`, либо пингуйте вручную.
7. **Слишком большие batch'и в `InsertRows`.** Одна RPC не должна писать > ~10-50 MB данных. Разбивайте.

## Тестирование

Для integration-тестов используйте `github.com/nebius/testcontainers-ytsaurus` — поднимает локальный YT в docker-контейнере.

Для юнит-тестов `yt.Client` — это интерфейс, мокайте его через любой подходящий инструмент (gomock, testify/mock).
