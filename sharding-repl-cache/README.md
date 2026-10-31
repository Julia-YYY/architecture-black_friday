# sharding-repl-cache

Шардированный MongoDB-кластер с репликацией, кеширование в Redis (вариант 3 схемы)
и приложение pymongo-api.

| Сервис                           | Роль                                               | Порт  |
|----------------------------------|----------------------------------------------------|-------|
| `configSrv`                      | сервер конфигурации (replica set `config_server`)  | 27017 |
| `shard1-1`, `shard1-2`, `shard1-3` | шард 1, реплики replica set `shard1`             | 27018 |
| `shard2-1`, `shard2-2`, `shard2-3` | шард 2, реплики replica set `shard2`             | 27019 |
| `mongos_router`                  | роутер mongos, точка входа для приложения          | 27020 |
| `redis`                          | кеш запросов приложения к MongoDB                  | 6379  |
| `pymongo_api`                    | приложение (`REDIS_URL=redis://redis:6379`)        | 8080  |

БД — `somedb`, коллекция — `helloDoc`, ключ шардирования — `{ name: "hashed" }`.

## Как запустить

Все команды выполняются из директории `sharding-repl-cache`.

Запускаем MongoDB, Redis и приложение:

```shell
docker compose up -d
```

Настраиваем репликацию и шардирование, заполняем БД данными:

```shell
./scripts/mongo-init.sh
```

Скрипт идемпотентный, его можно запускать повторно. Пошаговое описание настройки
репликации и шардирования — в [README проекта mongo-sharding-repl](../mongo-sharding-repl/README.md):
шаги полностью совпадают.

## Кеширование

Кеширование включается переменной окружения приложения `REDIS_URL: "redis://redis:6379"`.
Кешируется эндпоинт `GET /<collection_name>/users`, время жизни записи в кеше — 60 секунд.

## Как проверить

Откройте в браузере http://localhost:8080 (или `http://<ip виртуальной машины>:8080`).
В ответе должны быть `"mongo_topology_type": "Sharded"`, два шарда по три реплики в `shards`,
`"documents_count": 1000` для `helloDoc` и `"cache_enabled": true`.

Проверяем скорость повторных запросов. Первый запрос идёт в MongoDB и выполняется больше 1 секунды,
повторные (в течение 60 секунд) берутся из Redis и выполняются заметно быстрее (<100 мс):

```shell
for i in 1 2 3; do
  curl -s -o /dev/null -w "%{time_total}s\n" http://localhost:8080/helloDoc/users
done
```

Ключи кеша в Redis:

```shell
docker compose exec -T redis redis-cli --scan --pattern 'api:cache*'
```

Swagger: http://localhost:8080/docs
