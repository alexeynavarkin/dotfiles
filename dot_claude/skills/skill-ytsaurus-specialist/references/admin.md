# Администрирование YTsaurus: ACLs, квоты, TTL, bundles

Загружайте этот файл для вопросов про permissions, accounts, квоты, bundle tuning, tablet balancer.

## ACLs (Access Control Lists)

### Модель

У каждого Cypress-узла есть атрибут `@acl` — массив ACE (access control entry). Также:
- `@inherit_acl` (bool) — наследовать ACL родителя или нет.
- `@owner` — владелец (обычно создатель или admin-группа).
- Effective ACL вычисляется по пути: от корня вниз, суммируя все ACL с включённой наследуемостью.

### Формат ACE

```yson
{
    "action"          = "allow" | "deny";
    "subjects"        = ["user_name"; "group_name"; ... ];
    "permissions"     = ["read"; "write"; "remove"; "use"; "manage"; "administer"; "modify_children"; "mount"];
    "inheritance_mode" = "object_only" | "object_and_descendants" | "descendants_only" | "immediate_descendants";
}
```

### Разрешения

- `read` — чтение данных и атрибутов.
- `write` — изменение данных (для таблиц — insert/delete rows; для Cypress — set атрибутов).
- `remove` — удалить узел.
- `mount` — mount/unmount table.
- `administer` — менять ACL и owner.
- `use` — для accounts, pools, bundles: использовать ресурс (писать в bundle, счёт в account).
- `manage` — управление объектом (например, изменение конфигурации pool'а).
- `create` — создавать дочерние узлы.

### Типичные команды

```bash
# Посмотреть effective ACL:
yt get //path/@effective_acl

# Посмотреть локальный ACL (без наследования):
yt get //path/@acl

# Проверить permission у пользователя:
yt check-permission <user> read //path

# Добавить ACE (через set с полным массивом — перезаписывает):
yt set //path/@acl '[{action=allow; subjects=[alice]; permissions=[read;write]}]'

# Отключить наследование:
yt set //path/@inherit_acl %false
```

### Управление пользователями и группами

```bash
yt create user --attr '{name=alice}'
yt create group --attr '{name=analytics_team}'
yt add-member alice analytics_team
yt remove-member alice analytics_team
```

Всё хранится в `//sys/users`, `//sys/groups`.

### ACL pattern'ы

- **Shared project directory:** `//home/projects/myproject` с ACL для `myproject_team` на `[read, write, remove, mount, create]` и `inherit_acl=true` вниз. Пользователи — члены группы.
- **Read-only dataset:** ACL с `[read]` для всех; `administer` только у owners.
- **Deny override:** `action=deny` для конкретного user'а работает поверх `allow` группе — используйте для временных блокировок.

## Accounts и квоты

**Account** — ресурсный контейнер. Каждый Cypress-узел (таблица, файл, чанк) принадлежит одному account'у. Квоты ограничивают сколько всего может хранить account.

### Квоты
В `//sys/accounts/<name>/@resource_limits`:
- `disk_space_per_medium` — disk quota по каждому медиуму (ssd_blobs, default, ...).
- `chunk_count` — максимум chunks.
- `node_count` — максимум Cypress-узлов.
- `tablet_count` — максимум таблетов (важно для dyn tables!).
- `tablet_static_memory` — сколько памяти in-memory таблет может держать.
- `master_memory` — нагрузка на master в байтах.

`@resource_usage` — текущее потребление. Сравнивайте.

### Создание account и назначение

```bash
yt create account --attr '{name=myproject; resource_limits={disk_space_per_medium={default=10737418240}}}'  # 10 GB

# Назначить таблице:
yt set //home/project/table/@account myproject

# Наследование: @account наследуется от родителя в большинстве случаев.
```

### Common pitfall
Квоты считаются per-medium; забыли выдать на нужный medium — запись падает. Проверяйте `@resource_limits.disk_space_per_medium.<medium_name>` именно для того медиума, куда пишутся chunks (обычно `default` или `ssd_blobs`).

## TTL для Cypress-узлов

Динамические/static-таблицы и другие узлы могут авто-удаляться.

### `expiration_time` — удалить в абсолютный момент времени
```bash
yt set //tmp/mytable/@expiration_time '2026-12-31T23:59:59.000000Z'
```

### `expiration_timeout` — удалить после N миллисекунд с последнего доступа
```bash
yt set //tmp/mytable/@expiration_timeout 604800000  # 7 дней
```

**Важно:** "доступ" означает любые операции чтения/записи — мгновенно обновляет touch timestamp. Для holdback'а важных таблиц от автоудаления — явно не ставьте или делайте long timeout.

### Cleanup scope

- `//tmp` обычно имеет политику автоудаления всего, что >N дней.
- User'ские директории в `//home` — без expiration по умолчанию.
- Скрипты на CI / ad-hoc output'ы — ставьте `expiration_timeout` сразу, иначе накапливается мусор → account quota exhausted.

## Tablet Cell Bundles

**Bundle** = группа tablet cells с выделенными tablet nodes и своими CPU/memory квотами. Каждая dyn table назначается в bundle.

### Базовая настройка bundle

```bash
yt create tablet_cell_bundle --attr '{name=myproject}'

# Создать N tablet cells в bundle:
for i in $(seq 1 10); do
    yt create tablet_cell --attr '{tablet_cell_bundle=myproject}'
done
# Или через установку:
yt set //sys/tablet_cell_bundles/myproject/@tablet_cell_count 10
```

### Ключевые атрибуты

- `@tablet_cell_count` — сколько cells в bundle.
- `@options/snapshot_primary_medium` и `@options/changelog_primary_medium` — **всегда SSD** для продакшена. На HDD bundle'ы разваливаются.
- `@options/snapshot_account`, `@options/changelog_account` — куда класть служебные данные.
- `@node_tag_filter` — SELECT'ит tablet nodes по tag'у. Используется для изоляции bundle'ов по железу.
- `@resource_limits.tablet_count`, `@resource_limits.tablet_static_memory` — верхние пределы.

### ACL bundle

Нужен `use` permission, чтобы назначать таблицы в bundle:
```bash
yt set //sys/tablet_cell_bundles/myproject/@acl '[{action=allow; subjects=[myproject_team]; permissions=[use]}]'
```

### Bundle Controller (YTsaurus 25.2+)

Управляет распределением tablet nodes между bundles, настройкой CPU/memory пулов, периодом maintenance. Конфигурация хранится в `//sys/bundle_controller/controller/bundles/<bundle>/@bundle_config` (точный путь может отличаться в разных версиях).

Что даёт:
- Dashboards per-bundle (включая flush/compaction throughput, request rates).
- Декларативная настройка "хочу N cores и M gb памяти для тредов в этом bundle".
- Автоматическое добавление/удаление tablet nodes в bundle.
- Seamless tablet migration при maintenance — минимальный downtime.

Для bundle'ов под нагрузкой очень желателен — без него приходится настраивать thread pools вручную через `//sys/tablet_cell_bundles/<b>/@dynamic_options`.

## Tablet Balancer

Фоновый сервис, который:
1. **Сплитит** таблеты > `max_tablet_size` (default ~80 GB).
2. **Мёржит** таблеты < `min_tablet_size`.
3. **Перемещает** таблеты между cells для равномерной загрузки (в parameterized-режиме).

### Конфигурация per-bundle

В `//sys/tablet_cell_bundles/<b>/@tablet_balancer_config`:

```yson
{
    enable_tablet_balancer = %true;
    enable_in_memory_cell_balancer = %true;
    enable_cell_balancer = %true;

    # Scheduler window — когда можно балансировать.
    tablet_balancer_schedule = "minutes % 15 == 0";

    # В parameterized-режиме баланс идёт не только по размеру, но и по request rate.
    default_in_memory_group_config = {...};
}
```

Schedule — cron-подобное выражение. `"minutes % 15 == 0"` = раз в 15 минут. Для продакшена обычно реже — раз в час ночью, чтобы не интерферировать с пиком нагрузки.

### Per-table override

```bash
yt set //path/@tablet_balancer_config/min_tablet_size 5368709120   # 5 GB
yt set //path/@tablet_balancer_config/max_tablet_size 53687091200  # 50 GB
yt set //path/@tablet_balancer_config/enable_auto_reshard %true
yt set //path/@tablet_balancer_config/enable_auto_tablet_move %true
```

### Когда надо выключить balancer

- Большая загрузка: `@enable_auto_reshard=false` на время.
- Таблица с ручным pivot keys (например, ключи по shards партнёров) — `@enable_auto_reshard=false`, иначе balancer сломает разбиение.
- During reshard migration — пусть закончится без helpful interference.

### Ручная балансировка

Если balancer отключён или отстаёт, можно запустить:
```bash
yt reshard-table-automatic //path --keep-actions
# Возвращает action IDs; статус смотреть через:
yt get //sys/tablet_actions/<action_id>
```

## Prerequisites: что всегда проверить перед production

1. **Bundle** таблицы использует SSD для snapshot/changelog.
2. **Account** имеет достаточные `disk_space`, `chunk_count`, `tablet_count`, `tablet_static_memory`.
3. **Tablet balancer** включён и настроен на разумное окно.
4. **ACLs** корректные, inherit_acl согласован с родителем.
5. **Monitoring** — есть dashboard, alerts на compaction backlog, store count, error rate.
6. **TTL / expiration** — таблица не попадёт случайно в GC.
7. **Backup** — есть ли `create_table_backup` в CI?

## Useful one-liners

```bash
# Найти все таблицы в account с их размером:
yt list //home/project --attr resource_usage --format '<format=pretty>yson' | grep disk_space

# Топ-10 таблиц по chunk_count (полезно для debugging "почему account exhausted"):
yt find //home/project --type table --attr chunk_count | sort -k2 -n -r | head -10

# Проверить состояние всех таблетов таблицы:
yt get //path/@tablets | grep -E "state|cell_id|statistics"

# Force compaction для таблицы:
REV=$(yt get //path/@revision)
yt set //path/@forced_compaction_revision $REV
yt remount-table //path
```
