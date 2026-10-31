# mongo-sharding-repl

Шардированный MongoDB-кластер с репликацией (вариант 2 схемы) и приложение pymongo-api.
Каждый из двух шардов — replica set из трёх реплик.

| Сервис                           | Роль                                               | Порт  |
|----------------------------------|----------------------------------------------------|-------|
| `configSrv`                      | сервер конфигурации (replica set `config_server`)  | 27017 |
| `shard1-1`, `shard1-2`, `shard1-3` | шард 1, реплики replica set `shard1`             | 27018 |
| `shard2-1`, `shard2-2`, `shard2-3` | шард 2, реплики replica set `shard2`             | 27019 |
| `mongos_router`                  | роутер mongos, точка входа для приложения          | 27020 |
| `pymongo_api`                    | приложение                                         | 8080  |

БД — `somedb`, коллекция — `helloDoc`, ключ шардирования — `{ name: "hashed" }`.

## Как запустить

Все команды выполняются из директории `mongo-sharding-repl`.

Запускаем MongoDB и приложение:

```shell
docker compose up -d
```

Настраиваем репликацию и шардирование, заполняем БД данными — одной командой:

```shell
./scripts/mongo-init.sh
```

Скрипт идемпотентный, его можно запускать повторно.

## Шаги настройки репликации и шардирования вручную

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

2. Настраиваем репликацию для шарда 1: подключаемся к любой из его реплик и инициализируем
   replica set `shard1` со всеми тремя участниками. Один из них будет выбран PRIMARY,
   остальные станут SECONDARY и начнут реплицировать данные с него.

   ```shell
   docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval '
   rs.initiate({
     _id: "shard1",
     members: [
       { _id: 0, host: "shard1-1:27018" },
       { _id: 1, host: "shard1-2:27018" },
       { _id: 2, host: "shard1-3:27018" }
     ]
   })'
   ```

3. Так же настраиваем репликацию для шарда 2 (replica set `shard2`):

   ```shell
   docker compose exec -T shard2-1 mongosh --port 27019 --quiet --eval '
   rs.initiate({
     _id: "shard2",
     members: [
       { _id: 0, host: "shard2-1:27019" },
       { _id: 1, host: "shard2-2:27019" },
       { _id: 2, host: "shard2-3:27019" }
     ]
   })'
   ```

4. Дожидаемся выбора PRIMARY в каждом replica set (несколько секунд) и проверяем состояние реплик:

   ```shell
   docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval 'rs.status().members.map(m => m.name + " " + m.stateStr)'
   docker compose exec -T shard2-1 mongosh --port 27019 --quiet --eval 'rs.status().members.map(m => m.name + " " + m.stateStr)'
   ```

   В каждом шарде должен быть один `PRIMARY` и два `SECONDARY`.

5. Подключаемся к роутеру, добавляем шарды (указывая все реплики replica set),
   включаем шардирование и заполняем коллекцию:

   ```shell
   docker compose exec -it mongos_router mongosh --port 27020
   ```

   ```javascript
   sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018")
   sh.addShard("shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019")

   sh.enableSharding("somedb")
   sh.shardCollection("somedb.helloDoc", { "name": "hashed" })

   use somedb
   for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
   db.helloDoc.countDocuments()   // 1000
   ```

## Как проверить

Количество документов на каждой реплике (реплики одного шарда содержат одинаковые данные,
в сумме по двум шардам — 1000):

```shell
docker compose exec -T shard1-2 mongosh --port 27018 --quiet --eval 'db.getMongo().setReadPref("primaryPreferred"); db.getSiblingDB("somedb").helloDoc.countDocuments()'
docker compose exec -T shard2-2 mongosh --port 27019 --quiet --eval 'db.getMongo().setReadPref("primaryPreferred"); db.getSiblingDB("somedb").helloDoc.countDocuments()'
```

Откройте в браузере http://localhost:8080 (или `http://<ip виртуальной машины>:8080`).
В ответе должны быть `"mongo_topology_type": "Sharded"`, в `shards` — два шарда со списком
из трёх реплик у каждого, и `"documents_count": 1000` для коллекции `helloDoc`.

Swagger: http://localhost:8080/docs
