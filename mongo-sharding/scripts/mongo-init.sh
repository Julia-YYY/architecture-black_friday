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
# 2. Инициализируем шарды
###

docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
try { rs.status() } catch (e) { rs.initiate({ _id: "shard1", members: [{ _id: 0, host: "shard1:27018" }] }) }
while (!db.hello().isWritablePrimary) { sleep(1000) }
print("shard1: OK")
EOF

docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
try { rs.status() } catch (e) { rs.initiate({ _id: "shard2", members: [{ _id: 0, host: "shard2:27019" }] }) }
while (!db.hello().isWritablePrimary) { sleep(1000) }
print("shard2: OK")
EOF

###
# 3. Добавляем шарды в роутер, включаем шардирование и заполняем БД
###

docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
var shards = db.adminCommand({ listShards: 1 }).shards.map(s => s._id)
if (!shards.includes("shard1")) { sh.addShard("shard1/shard1:27018") }
if (!shards.includes("shard2")) { sh.addShard("shard2/shard2:27019") }
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name": "hashed" })
var somedb = db.getSiblingDB("somedb")
if (somedb.helloDoc.countDocuments() === 0) { for (var i = 0; i < 1000; i++) somedb.helloDoc.insertOne({ age: i, name: "ly" + i }) }
print("Всего документов: " + somedb.helloDoc.countDocuments())
EOF

###
# 4. Проверяем распределение документов по шардам
###

docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
print("shard1: " + db.getSiblingDB("somedb").helloDoc.countDocuments())
EOF

docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
print("shard2: " + db.getSiblingDB("somedb").helloDoc.countDocuments())
EOF
