# Query Language: SelectRows vs YQL

YTsaurus имеет **два разных** query-языка. Путать их — первая и самая частая ошибка. Загружайте этот файл при любых вопросах о запросах.

## Где что выполняется

| | SelectRows (dyn table query) | YQL |
|---|---|---|
| Где исполняется | Прямо на tablet node | В Query Tracker (отдельный сервис) |
| Источник данных | Только **смонтированные** sorted dyn tables (в основном) | Любые таблицы: static, dynamic (через snapshot), результаты других query |
| Язык | Подмножество SQL + YT-специфика | Диалект SQL, сильно расширенный |
| Latency | Миллисекунды — десятки мс | Секунды — минуты (запускает MR-подобные джобы) |
| Join | Ограниченные (по ключевому префиксу, inner) | Полноценные |
| Назначение | Online point/range queries | Analytics, ETL, отчёты |

**Когда писать SelectRows:** online-запросы с низкой latency, key-prefix range scans, агрегации по маленьким диапазонам.

**Когда писать YQL:** offline-аналитика, cross-table joins, большие агрегации, обработка static-таблиц.

## SelectRows — синтаксис

Базовая структура:
```sql
[<select_list>] FROM [//path/to/table] [JOIN ...] [WHERE ...] [GROUP BY ...] [HAVING ...] [ORDER BY ...] [LIMIT N]
```

Путь к таблице — в квадратных скобках с `//`:
```sql
user_id, email FROM [//home/project/users] WHERE user_id = 42
```

### Поддерживаемые операции

- `WHERE`, `AND`, `OR`, `NOT`
- Сравнения, `IN`, `BETWEEN`, `LIKE` (на string/utf8)
- `GROUP BY` + агрегаты: `SUM`, `COUNT`, `MIN`, `MAX`, `AVG`, `FIRST`, `LAST`, некоторые percentile.
- Арифметика и функции: `IF`, `COALESCE`, `IS NULL`, `CAST`.
- `ORDER BY` — только по ключевым колонкам и только в направлении сортировки.
- `WITH TOTALS` — summary row.
- Inner JOIN **только если** условие join'а включает равенство по первым key columns правой таблицы (для push-down'а).

### Push-down: что важно знать

SelectRows выбирает **tablet range** для чтения на основе `WHERE` по ключевым колонкам. Это критически важно для performance.

**Хорошо** (читается один/несколько таблетов):
```sql
WHERE user_id = 42
WHERE user_id >= 1000 AND user_id < 2000
WHERE user_id IN (1, 2, 3)
```

**Плохо** (full scan по всем таблетам):
```sql
WHERE email = 'x@example.com'      -- email не ключевая
WHERE user_id > 0                  -- почти вся таблица
WHERE LENGTH(name) > 10            -- функция, не push-downable
```

Если без выбора по ключу никак — используйте secondary index (если настроен) или YQL (с MR).

### Timestamp

```sql
user_id, email FROM [//home/users] WITH TIMESTAMP 1234567890123 WHERE user_id = 42
```
Без указания — `sync_last_committed`. В SDK чаще опция в options, чем в SQL.

### Ограничения

- Нет оконных функций (WINDOW / OVER).
- Нет UNION.
- Нет подзапросов в FROM (кроме очень ограниченных случаев).
- Нет модификации (INSERT/UPDATE/DELETE через SelectRows — нельзя; для изменений используйте `InsertRows`/`DeleteRows`).

## YQL на YT

YQL — отдельный декларативный язык, исполняется Query Tracker'ом через MapReduce. Более мощный, но дороже.

### Путь к таблице

Двумя способами:
```sql
USE hahn;
SELECT * FROM `//home/project/users` WHERE user_id = 42;
```

Либо через алиас кластера:
```sql
SELECT * FROM hahn.`//home/project/users`;
```

Пути можно без `//` если первая часть — алиас:
```sql
SELECT * FROM hahn.`home/project/users`;
```

### Практика

**Несколько таблиц по префиксу / диапазону:**
```sql
SELECT COUNT(*)
FROM RANGE(`//home/logs`, `2026-04-01`, `2026-04-15`);
-- Или:
SELECT COUNT(*) FROM CONCAT(`//home/logs/2026-04-01`, `//home/logs/2026-04-02`);
```

**PRAGMA — управление поведением:**
```sql
PRAGMA yt.InferSchema = '1';                -- инферить схему по первым строкам
PRAGMA yt.MaxRowWeight = '128M';            -- лимит размера строки
PRAGMA yt.Pool = 'my_pool';                 -- в каком пуле запускать джобы
PRAGMA yt.DataSizePerJob = '1G';            -- управлять параллелизмом
PRAGMA yt.UseTypeV3;                        -- типизация v3
```

**Вывод в таблицу:**
```sql
INSERT INTO `//home/project/out` WITH TRUNCATE
SELECT user_id, SUM(amount) AS total
FROM `//home/project/events`
GROUP BY user_id;
```

`INSERT INTO` в YQL — это "создать или перезаписать/дополнить" static таблицу. Без `WITH TRUNCATE` — append. Для динамических output — см. bulk-insert (разные механизмы).

### Join'ы

В YQL доступны все типы: INNER, LEFT/RIGHT/FULL OUTER, LEFT SEMI/ONLY, CROSS. Есть hint'ы: `/*+ merge() */`, `/*+ broadcast(right) */` и пр.

Для больших joins с одним "маленьким словарём" — broadcast:
```sql
SELECT /*+ broadcast(b) */ a.*, b.name
FROM `//home/events` AS a
INNER JOIN `//home/dict` AS b USING(user_id);
```

### Ограничения и аккаунты

Все YQL-джобы потребляют CPU и диск квоты вашего pool'а и account'а. Проверяйте перед запуском больших запросов: `yt get //sys/pools/<pool>/@`.

## Когда SelectRows неожиданно медленный

Диагностический чеклист:

1. **Проверьте push-down.** Какие ключевые колонки фильтруются? Если нет равенства/префикса по первым key columns — читается вся таблица.
2. **Сколько таблетов в таблице?** Один запрос может обращаться ко многим таблетам, и это окей, но если таблет один — весь запрос на одном node.
3. **`@in_memory_mode`?** Для hot-таблиц должно быть `compressed` или `uncompressed`.
4. **`@optimize_for`?** Если `lookup`, а запрос сканирует диапазоны и читает много колонок — рассмотрите `scan`.
5. **Дин. stores.** Если между последним flush'ем много записей, SelectRows сольёт их с chunks — медленнее. Метрика dynamic store count в bundle dashboard.
6. **Output row limit.** Ударились в `max_output_row_count` (default 100_000 для SelectRows)? Переключите опцию или постраничьте.
7. **Input row limit.** Бывает, что чтение до фильтра прочитало слишком много — `max_input_row_count` (default ~1M).

## Шаблоны запросов

### Point lookup по полному ключу — используйте `LookupRows`, не SelectRows
`LookupRows` дешевле на один запрос, и делает ровно то, что нужно.

### Range по ключевому префиксу
```sql
* FROM [//home/events]
WHERE user_id = 42 AND event_time >= '2026-04-10' AND event_time < '2026-04-15'
ORDER BY event_time
LIMIT 1000
```

### Top-N с агрегацией (если диапазон небольшой)
```sql
country, COUNT(*) AS cnt
FROM [//home/events]
WHERE event_time >= '2026-04-15 00:00' AND event_time < '2026-04-15 01:00'
GROUP BY country
ORDER BY country
LIMIT 200
```
Помните: `ORDER BY` только по ключевым. Если надо сортировать по COUNT — читайте в приложение и сортируйте там, либо YQL.

### Join справочника к логу (по ключу справочника)
```sql
e.user_id, e.event_type, u.country
FROM [//home/events] AS e
JOIN [//home/users] AS u ON e.user_id = u.user_id
WHERE e.user_id BETWEEN 1000 AND 2000
```
Работает, потому что `u.user_id` — ключевая колонка в `users`.
