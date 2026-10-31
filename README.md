# pymongo-api

## Структура решения

| Задание | Где смотреть |
|---------|--------------|
| 1, 5, 6. Схемы | [task1.drawio](task1.drawio) — страницы: «1. Шардирование», «2. Репликация», «3. Кеширование», «4. API Gateway + Consul», «5. CDN» |
| 2. Шардирование | [mongo-sharding](mongo-sharding/README.md) |
| 3. Репликация | [mongo-sharding-repl](mongo-sharding-repl/README.md) |
| 4. Кеширование | [sharding-repl-cache](sharding-repl-cache/README.md) |

Каждый проект запускается из своей директории: `docker compose up -d`, затем `./scripts/mongo-init.sh`.
Ниже инструкция для исходного варианта (один инстанс MongoDB).

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Заполняем mongodb данными

```shell
./scripts/mongo-init.sh
```

## Как проверить

### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080

### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины

```shell
curl --silent http://ifconfig.me
```

Откройте в браузере http://<ip виртуальной машины>:8080

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs