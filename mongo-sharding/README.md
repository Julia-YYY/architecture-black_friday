# mongo-sharding

Шардированный MongoDB-кластер (вариант 1 схемы) и приложение pymongo-api.

| Сервис          | Роль                                        | Порт  |
|-----------------|---------------------------------------------|-------|
| `configSrv`     | сервер конфигурации (replica set `config_server`) | 27017 |
| `shard1`        | шард 1 (replica set `shard1`)               | 27018 |
| `shard2`        | шард 2 (replica set `shard2`)               | 27019 |
| `mongos_router` | роутер mongos, точка входа для приложения   | 27020 |
| `pymongo_api`   | приложение                                  | 8080  |

БД — `somedb`, коллекция — `helloDoc`, ключ шардирования — `{ name: "hashed" }`.

## Как запустить

Все команды выполняются из директории `mongo-sharding`.

Запускаем MongoDB и приложение:

```shell
docker compose up -d
```

Инициализируем шардирование и заполняем БД данными — одной командой:

```shell
./scripts/mongo-init.sh
```

Скрипт идемпотентный, его можно запускать повторно.

## Шаги инициализации шардирования вручную

То же самое, что делает `scripts/mongo-init.sh`.

1. Инициализируем сервер конфигурации:

   ```shell
   docker compose exec -T configSrv mongosh --port 27017 --quiet --eval '
   rs.initiate({
     _id: "config_server",
     configsvr: true,
     members: [{ _id: 0, host: "configSrv:27017" }]
   })'
   ```

2. Инициализируем шарды:

   ```shell
   docker compose exec -T shard1 mongosh --port 27018 --quiet --eval '
   rs.initiate({ _id: "shard1", members: [{ _id: 0, host: "shard1:27018" }] })'

   docker compose exec -T shard2 mongosh --port 27019 --quiet --eval '
   rs.initiate({ _id: "shard2", members: [{ _id: 0, host: "shard2:27019" }] })'
   ```

3. Подключаемся к роутеру, добавляем шарды, включаем шардирование и заполняем коллекцию:

   ```shell
   docker compose exec -it mongos_router mongosh --port 27020
   ```

   ```javascript
   sh.addShard("shard1/shard1:27018")
   sh.addShard("shard2/shard2:27019")

   sh.enableSharding("somedb")
   sh.shardCollection("somedb.helloDoc", { "name": "hashed" })

   use somedb
   for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
   db.helloDoc.countDocuments()   // 1000
   ```

## Как проверить

Количество документов на каждом шарде (в сумме — 1000):

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet --eval 'db.getSiblingDB("somedb").helloDoc.countDocuments()'
docker compose exec -T shard2 mongosh --port 27019 --quiet --eval 'db.getSiblingDB("somedb").helloDoc.countDocuments()'
```

Статус шардирования:

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet --eval 'sh.status()'
```

Откройте в браузере http://localhost:8080 (или `http://<ip виртуальной машины>:8080`).
В ответе должны быть `"mongo_topology_type": "Sharded"`, список из двух шардов в `shards`
и `"documents_count": 1000` для коллекции `helloDoc`.

Swagger: http://localhost:8080/docs
