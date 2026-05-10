# foodchain-deployment

Docker Compose orchestration for the FoodChain microservices stack: infrastructure (**MySQL**, **Redis**, **Kafka** + Zookeeper), **Spring Cloud Config**, **Eureka**, **API Gateway**, and application services (**branch**, **user**, **menu**, **order**, **kitchen**, **analytics-report**, **notifications**).

## Layout

- **`docker-compose.yml`** — service definitions, health checks, and published ports.
- **`docker/mysql-init/`** — SQL init scripts for databases.
- **`.env`** — secrets and host port overrides (copy from your team’s template; never commit real secrets).

Sibling repositories are expected next to this folder (Compose `build.context` uses `../branch-service`, `../api-gateway`, etc.).

## Quick start

1. Copy / adjust **`.env`** (at minimum **`JWT_SECRET`** and DB passwords).
2. From this directory:

```bash
docker compose build
docker compose up -d
```

3. Wait for health checks (**config-server** → **eureka** → gateway and apps).

Common published ports:

| Service | Host port (default) |
|---------|---------------------|
| API Gateway | **8080** |
| Config Server | **8888** |
| Eureka | **8761** |
| MySQL | **3306** (override `MYSQL_HOST_PORT` if busy) |
| Redis | **6379** |
| Kafka | **9092** |

Individual Spring services map **8081–8087** depending on service — see `docker-compose.yml` (`user-service` defaults to host **8086** via `USER_SERVICE_HOST_PORT`).

## Documentation per component

Each runnable module keeps its own README (ports, REST paths, Kafka topics): **api-gateway**, **user-service**, **order-service**, etc.
