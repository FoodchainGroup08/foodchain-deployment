# Restaurant Microservices — System Design

## Architecture Overview

```
                    ┌──────────────────────────────┐
                    │       Git Config Repo         │
                    │   (restaurant-config)         │
                    │                               │
                    │  application.yml   (shared)   │
                    │  api-gateway.yml              │
                    │  order-service.yml            │
                    │  kitchen-service.yml          │
                    │  menu-service.yml             │
                    │  branch-service.yml           │
                    │  analytics-service.yml        │
                    │  report-service.yml           │
                    └──────────────┬───────────────┘
                                   │ serves config on request
                    ┌──────────────▼───────────────┐
                    │        Config Server          │
                    │           :8888               │
                    │  (registers with Eureka)      │
                    └──────────────┬───────────────┘
                                   │ all services pull config at startup
          ┌────────────────────────┼────────────────────────┐
          │                        │                         │
   ┌──────▼──────┐         ┌───────▼──────┐        ┌───────▼───────┐
   │ API Gateway │         │order-service │        │other services │
   │    :8080    │         │    :8083     │        │               │
   └──────┬──────┘         └───────┬──────┘        └───────┬───────┘
          │                        │                         │
          └────────────────────────┴─────────────────────────┘
                                   │ all register & discover here
                    ┌──────────────▼───────────────┐
                    │        Eureka Server          │
                    │           :8761               │
                    └──────────────────────────────┘
```

---

## Service Port Map

| Service            | Port | Technology                        |
|--------------------|------|-----------------------------------|
| **Eureka Server**  | 8761 | Service registry                  |
| **Config Server**  | 8888 | Centralized Git-backed config     |
| **API Gateway**    | 8080 | Spring Cloud Gateway + JWT auth   |
| Branch Service     | 8081 | REST, JPA, PostgreSQL             |
| Menu Service       | 8082 | REST, JPA, Redis, Kafka           |
| Order Service      | 8083 | REST, JPA, Redis, Kafka, Outbox   |
| Kitchen Service    | 8084 | WebSocket, Redis, Kafka           |
| Analytics Service  | 8085 | REST, JPA, Redis, Kafka           |
| Report Service     | 8086 | REST, JPA, PostgreSQL             |

---

## Startup Order

> Services MUST start in this sequence:

```
1. Eureka Server   → registry must be up before anything registers
2. Config Server   → registers with Eureka; all others fetch config from it
3. API Gateway     → fetches config (routes, JWT secret) from Config Server
4. All services    → any order; each fetches config, then registers with Eureka
```

---

## Request Flow (Happy Path)

```
Browser / Mobile App
        │
        │  POST /api/orders
        │  Authorization: Bearer <jwt-token>
        ▼
┌─────────────────────────────────────┐
│            API Gateway :8080         │
│                                      │
│  1. JwtAuthFilter intercepts         │
│     ├─ path in PUBLIC_PATHS? → skip  │
│     ├─ no Authorization header? →401 │
│     ├─ invalid JWT? → 401            │
│     └─ valid JWT:                    │
│          strip Authorization header  │
│          inject X-User-Id            │
│          inject X-User-Role          │
│          inject X-User-Email         │
│                                      │
│  2. Route matched: /api/orders/**    │
│     → uri: lb://order-service        │
│                                      │
│  3. Eureka lookup                    │
│     "order-service" → 127.0.0.1:8083 │
│                                      │
│  4. Proxy request downstream         │
└─────────────────┬───────────────────┘
                  │
                  ▼
        ┌─────────────────┐
        │  Order Service  │
        │     :8083       │
        │                 │
        │  Validates req  │
        │  Saves Order    │  → PostgreSQL (order_db)
        │  Saves Outbox   │  → PostgreSQL (outbox_events)
        └────────┬────────┘
                 │
                 │ Scheduled every 500ms
                 ▼
        ┌─────────────────┐
        │  OutboxRelay    │
        │                 │
        │  reads unpub.   │
        │  events         │
        └────────┬────────┘
                 │
                 ▼
        ┌─────────────────┐
        │      Kafka      │
        │  order.received │
        └────────┬────────┘
                 │
        ┌────────┴────────┐
        │                 │
        ▼                 ▼
┌───────────────┐  ┌───────────────────┐
│Kitchen Service│  │Analytics Service  │
│    :8084      │  │      :8085        │
│               │  │                   │
│ adds to Redis │  │ records metrics   │
│ queue         │  │                   │
│               │  └───────────────────┘
│ pushes to     │
│ WebSocket     │  → Kitchen displays
│ /topic/kitchen│     update in real-time
└───────────────┘
```

---

## Auth Flow (JWT)

**user-service** issues access and refresh tokens (HS256) with the same `jwt.secret` the **api-gateway** uses to validate requests.

```
Step 1 — Login
  Client → POST {gateway}/api/v1/auth/login  (public — no Bearer token)
  user-service returns JSON: accessToken, refreshToken, expiresIn, user (UserResponse)

Step 2 — Subsequent requests
  Client sends: Authorization: Bearer <access-token>
  Gateway JwtAuthFilter validates JWT (same shared secret as user-service)
  Strips Authorization, injects trusted headers for downstream:
    X-User-Id:     <UUID from "sub" claim>
    X-User-Role:   <from "role" claim, e.g. CUSTOMER>
    X-User-Email:  <from "email" claim>
    X-User-BranchId: <optional, from "branchId" claim>

Step 3 — Downstream services
  Typically read X-User-* headers (behind the gateway). Do not trust client-supplied user id in the body.

Public gateway paths (no Bearer required):
  /api/v1/auth/** except GET /api/v1/auth/me (requires Bearer)
  /actuator/** (where exposed), Swagger/OpenAPI docs routes as configured

Frontend must set VITE_API_BASE_URL to the gateway base including **/api/v1** (e.g. http://localhost:8080/api/v1),
because gateway routes are registered under `/api/v1/...`, not `/api/auth/...`.
```

---

## Config Management Flow

```
┌────────────────────────────────────────────────┐
│  Developer changes config in Git config repo   │
│  e.g. updates a DB URL or adds a new route     │
└──────────────────────┬─────────────────────────┘
                       │ git push
                       ▼
              Git Config Repo (GitHub)
                       │
                       │ Config Server polls / serves on request
                       ▼
              Config Server :8888
                       │
                       │ POST /actuator/refresh on target service
                       ▼
              Service hot-reloads changed properties
              (no restart needed for @RefreshScope beans)

To trigger a config refresh:
  curl -X POST http://localhost:<service-port>/actuator/refresh
```

---

## Kafka Event Flow

```
Producer              Topic                    Consumers
─────────             ──────                   ─────────
Order Service  ──▶  order.received      ──▶  Kitchen Service
                                         ──▶  Analytics Service

Order Service  ──▶  order.status.updated──▶  Kitchen Service
                                         ──▶  Analytics Service

Python Auth    ──▶  auth.user.events    ──▶  Analytics Service
(future)
```

---

## Service Communication Patterns

| Pattern               | Used By                         | Technology                    |
|-----------------------|---------------------------------|-------------------------------|
| REST (sync)           | Gateway → any service           | Spring Cloud Gateway (WebFlux)|
| REST (sync)           | Client → services via Gateway   | Spring MVC                    |
| Transactional Outbox  | Order Service → Kafka           | PostgreSQL + @Scheduled       |
| Event Streaming       | Order → Kitchen, Analytics      | Apache Kafka                  |
| Real-time push        | Kitchen → browser               | WebSocket (STOMP over SockJS) |
| Idempotency cache     | Order Service                   | Redis (60s TTL)               |
| Menu/data cache       | Menu Service                    | Redis                         |
| Kitchen queue         | Kitchen Service                 | Redis List + ZSet             |
| Service discovery     | All services                    | Netflix Eureka                |
| Centralized config    | All services                    | Spring Cloud Config + Git     |

---

## Infrastructure Dependencies

```
PostgreSQL (one DB per service)
  order_db      ← Order Service
  menu_db       ← Menu Service
  branch_db     ← Branch Service
  analytics_db  ← Analytics Service
  report_db     ← Report Service

Redis (shared instance)
  Order Service     → idempotency keys (60s TTL)
  Menu Service      → menu item cache
  Kitchen Service   → branch queues (List + ZSet for SLA)
  Analytics Service → aggregation buffers

Kafka (shared cluster)
  Topics:
    order.received          (produced by Order, consumed by Kitchen + Analytics)
    order.status.updated    (produced by Order, consumed by Kitchen + Analytics)

Git Config Repo (separate GitHub repository)
  All environment-specific config lives here
  Set CONFIG_REPO_URI env var on Config Server at deploy time
```

---

## Environment Variables

| Variable                   | Service        | Description                                    |
|----------------------------|----------------|------------------------------------------------|
| `CONFIG_REPO_URI`          | Config Server  | Git URL of the config repo                     |
| `JWT_SECRET`               | API Gateway    | HMAC secret (min 32 chars, same as Python auth)|
| `DB_HOST`                  | All DB services| PostgreSQL hostname                            |
| `DB_USERNAME`              | All DB services| PostgreSQL username                            |
| `DB_PASSWORD`              | All DB services| PostgreSQL password                            |
| `REDIS_HOST`               | Redis services | Redis hostname                                 |
| `KAFKA_BOOTSTRAP_SERVERS`  | All services   | Kafka broker address (e.g. localhost:9092)     |

---

## How to Run Locally

```bash
# 1. Start infrastructure (Docker)
docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=password postgres:15
docker run -d -p 6379:6379 redis:7
docker run -d -p 9092:9092 apache/kafka:3.7.0

# 2. Start Spring Cloud servers (in order)
mvn spring-boot:run -pl eureka-server
mvn spring-boot:run -pl config-server -Dspring-boot.run.jvmArguments="-DCONFIG_REPO_URI=https://github.com/your-org/restaurant-config"
mvn spring-boot:run -pl api-gateway    -Dspring-boot.run.jvmArguments="-DJWT_SECRET=your-secret-key-min-32-chars"

# 3. Start business services (any order)
mvn spring-boot:run -pl order-service
mvn spring-boot:run -pl kitchen-service
mvn spring-boot:run -pl menu-service
mvn spring-boot:run -pl branch-service
mvn spring-boot:run -pl analytics-service
mvn spring-boot:run -pl report-service

# 4. Verify
open http://localhost:8761                          # Eureka dashboard
curl http://localhost:8888/order-service/default    # Config Server check
curl http://localhost:8080/actuator/health          # Gateway health
```

---

## Project File Structure

```
Dreamdev/
├── pom.xml                          ← Parent POM (Spring Boot 3.2.3, Spring Cloud 2023.0.3)
│
├── eureka-server/                   ← Service registry
│   └── src/main/
│       ├── java/.../EurekaServerApplication.java
│       └── resources/application.yml
│
├── config-server/                   ← Centralized config (Git-backed)
│   └── src/main/
│       ├── java/.../ConfigServerApplication.java
│       └── resources/application.yml
│
├── api-gateway/                     ← Entry point + JWT validation
│   └── src/main/
│       ├── java/.../
│       │   ├── ApiGatewayApplication.java
│       │   └── filter/JwtAuthFilter.java
│       └── resources/application.yml
│
├── config-repo/                     ← Push this to your Git config repo
│   ├── application.yml              ← Shared config (Eureka URL, Kafka)
│   ├── api-gateway.yml              ← Gateway routes + JWT secret
│   ├── order-service.yml
│   ├── kitchen-service.yml
│   ├── menu-service.yml
│   ├── branch-service.yml
│   ├── analytics-service.yml
│   └── report-service.yml
│
├── order-service/
├── kitchen-service/
├── menu-service/
├── branch-service/
├── analytics-service/
└── report-service/
```

---

## Running with Docker

### First time (builds all images)
```bash
docker-compose up --build
```

### Subsequent runs (uses cached images)
```bash
docker-compose up
```

### Full reset (removes containers + volumes)
```bash
docker-compose down -v
```

### Rebuild a single service
```bash
docker-compose up --build order-service
```

### View logs for a specific service
```bash
docker-compose logs -f order-service
```

### Startup order (enforced via healthchecks)
```
mysql + redis + zookeeper
        ↓
      kafka
        ↓
   config-server
        ↓
   eureka-server
        ↓
  all other services
```

### Service URLs (after `docker-compose up`)
| Service        | URL                              |
|----------------|----------------------------------|
| Eureka         | http://localhost:8761            |
| Config Server  | http://localhost:8888            |
| API Gateway    | http://localhost:8080            |
| Branch Service | http://localhost:8081/api        |
| Menu Service   | http://localhost:8082/api        |
| Order Service  | http://localhost:8083/api        |
| Kitchen Service| http://localhost:8084            |
| Analytics      | http://localhost:8085/api        |
| Report Service | http://localhost:8086/api        |
| Kafka (ext)    | localhost:29092                  |
| MySQL          | localhost:3306                   |
| Redis          | localhost:6379                   |
