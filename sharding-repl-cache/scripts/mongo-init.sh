#!/bin/bash
set -e

# Скрипт запускается из любого места, docker compose выполняется в директории проекта
cd "$(dirname "$0")/.."

###
# 1. Инициализируем сервер конфигурации
###

docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
try { rs.status() } catch (e) { rs.initiate({ _id: "config_server", configsvr: true, members: [{ _id: 0, host: "configSrv:27017" }] }) }
while (!db.hello().isWritablePrimary) { sleep(1000) }
print("configSrv: OK")
EOF

###
# 2. Настраиваем репликацию для каждого шарда (по три реплики)
###

docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
try { rs.status() } catch (e) { rs.initiate({ _id: "shard1", members: [{ _id: 0, host: "shard1-1:27018" }, { _id: 1, host: "shard1-2:27018" }, { _id: 2, host: "shard1-3:27018" }] }) }
while (!db.hello().isWritablePrimary) { sleep(1000) }
print("shard1: OK, primary " + db.hello().primary)
EOF

docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
try { rs.status() } catch (e) { rs.initiate({ _id: "shard2", members: [{ _id: 0, host: "shard2-1:27019" }, { _id: 1, host: "shard2-2:27019" }, { _id: 2, host: "shard2-3:27019" }] }) }
while (!db.hello().isWritablePrimary) { sleep(1000) }
print("shard2: OK, primary " + db.hello().primary)
EOF

###
# 3. Добавляем шарды в роутер, включаем шардирование и заполняем БД
###

docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
var shards = db.adminCommand({ listShards: 1 }).shards.map(s => s._id)
if (!shards.includes("shard1")) { sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018") }
if (!shards.includes("shard2")) { sh.addShard("shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019") }
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name": "hashed" })
var somedb = db.getSiblingDB("somedb")
if (somedb.helloDoc.countDocuments() === 0) { for (var i = 0; i < 1000; i++) somedb.helloDoc.insertOne({ age: i, name: "ly" + i }) }
print("Всего документов: " + somedb.helloDoc.countDocuments())
EOF

###
# 4. Проверяем распределение документов по шардам и репликам
###

for node in shard1-1 shard1-2 shard1-3; do
docker compose exec -T "$node" mongosh --port 27018 --quiet <<EOF
db.getMongo().setReadPref("primaryPreferred")
print("$node (" + (db.hello().isWritablePrimary ? "PRIMARY" : "SECONDARY") + "): " + db.getSiblingDB("somedb").helloDoc.countDocuments())
EOF
done

for node in shard2-1 shard2-2 shard2-3; do
docker compose exec -T "$node" mongosh --port 27019 --quiet <<EOF
db.getMongo().setReadPref("primaryPreferred")
print("$node (" + (db.hello().isWritablePrimary ? "PRIMARY" : "SECONDARY") + "): " + db.getSiblingDB("somedb").helloDoc.countDocuments())
EOF
done
