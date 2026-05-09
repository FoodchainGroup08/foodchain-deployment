# FoodChain — AWS Free Tier Deployment Guide

Two AWS free-tier accounts + Confluent Cloud (Kafka) + Redis Cloud.  
No paid infrastructure required.

---

## Architecture at a Glance

```
Internet
    │
    ▼
[ Account 1 EC2 — t2.micro ]           [ Managed Cloud ]
  ├─ config-eureka-server  :8761   ◄──  GitHub (config repo)
  ├─ api-gateway            :8080   ◄──  Confluent Cloud (Kafka)
  ├─ branch-service         :8081   ◄──  Redis Cloud
  └─ notifications-service  :8087        AWS RDS MySQL

[ Account 2 EC2 — t2.micro ]
  ├─ order-service          :8083
  ├─ menu-service           :8082
  ├─ kitchen-service        :8084
  └─ analytics-report-service :8085
```

All services on Account 2 register with Eureka on Account 1 over the public IP.

> **Pre-deployment merges required**
> 1. `config-server` + `eureka-server` → single `config-eureka-server` app
> 2. `analytics-service` + `report-service` → single `analytics-report-service` app

---

## Step 1 — Confluent Cloud (Kafka)

1. Sign up at **confluent.cloud** (free Basic cluster, no credit card needed for basic)
2. Create a cluster → **Basic** → AWS → pick the region closest to your EC2s (e.g. `us-east-1`)
3. Go to **Clients → Java** → note the bootstrap server, e.g.:
   ```
   pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
   ```
4. Create an **API Key** (Cluster API Key) — save the Key and Secret
5. Go to **Topics** → Create these topics manually (or enable auto-create):

   | Topic | Partitions |
   |-------|-----------|
   | `order.received` | 6 |
   | `order.status.updated` | 6 |
   | `order.ready` | 6 |
   | `menu.item.updated` | 3 |
   | `analytics.daily.rollup` | 3 |

6. Note down:
   ```
   KAFKA_BOOTSTRAP=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
   KAFKA_API_KEY=<your-api-key>
   KAFKA_API_SECRET=<your-api-secret>
   ```

---

## Step 2 — Redis Cloud

1. Sign up at **redis.io/try-free** (30 MB free, no credit card)
2. Create a **Free** subscription → AWS → same region as your EC2s
3. Create a database — note the **Public Endpoint** and **Password**:
   ```
   REDIS_HOST=redis-xxxxx.cloud.redislabs.com
   REDIS_PORT=12345
   REDIS_PASSWORD=<your-password>
   ```

---

## Step 3 — AWS RDS (already provisioned)

Your existing RDS instance is reused. Ensure `notifications_db` exists alongside the others:
```sql
CREATE DATABASE IF NOT EXISTS notifications_db CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS analytics_report_db CHARACTER SET utf8mb4;
```

---

## Step 4 — AWS Account 1 EC2

### 4.1 Launch Instance
- AMI: **Amazon Linux 2023** (free tier eligible)
- Instance type: **t2.micro**
- Storage: 20 GB gp2
- Security Group — inbound rules:

  | Port | Source | Purpose |
  |------|--------|---------|
  | 22 | Your IP | SSH |
  | 8080 | 0.0.0.0/0 | API Gateway (public) |
  | 8761 | 0.0.0.0/0 | Eureka + Config (needed by Account 2) |
  | 8081 | Account 2 Security Group | branch-service (internal) |
  | 8087 | Account 2 Security Group | notifications-service (internal) |

- Allocate an **Elastic IP** and attach it to this instance. Note it as `ACCOUNT1_IP`.

### 4.2 Install Docker
```bash
sudo yum update -y
sudo yum install -y docker git
sudo service docker start
sudo usermod -aG docker ec2-user
# log out and back in, then:
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### 4.3 Clone and configure
```bash
git clone https://github.com/<your-org>/foodchain-deployment.git
cd foodchain-deployment
cp .env.account1.example .env
nano .env   # fill in all values (see section 6)
```

### 4.4 Deploy
```bash
docker-compose -f docker-compose.account1.yml up -d --build
docker-compose -f docker-compose.account1.yml ps
```

---

## Step 5 — AWS Account 2 EC2

### 5.1 Launch Instance
Same as Account 1 but Security Group inbound:

| Port | Source | Purpose |
|------|--------|---------|
| 22 | Your IP | SSH |
| 8082 | Account 1 Security Group | menu-service (via gateway) |
| 8083 | Account 1 Security Group | order-service (via gateway) |
| 8084 | Account 1 Security Group | kitchen-service (via gateway) |
| 8085 | Account 1 Security Group | analytics-report-service (via gateway) |

> No port needs to be public — all traffic routes through Account 1's API Gateway.

- Allocate an **Elastic IP**, note it as `ACCOUNT2_IP`.

### 5.2 Install Docker
Same commands as Account 1.

### 5.3 Clone and configure
```bash
git clone https://github.com/<your-org>/foodchain-deployment.git
cd foodchain-deployment
cp .env.account2.example .env
nano .env   # fill in all values (see section 6)
```

### 5.4 Deploy
```bash
docker-compose -f docker-compose.account2.yml up -d --build
docker-compose -f docker-compose.account2.yml ps
```

---

## Step 6 — Environment Variables

### `.env` for Account 1
```env
# Database
RDS_ENDPOINT=my-rds-mysql.c4hs6um4wrpt.us-east-1.rds.amazonaws.com
RDS_PORT=3306
RDS_USERNAME=admin
RDS_PASSWORD=<your-rds-password>

# Kafka (Confluent Cloud)
KAFKA_BOOTSTRAP_SERVERS=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
KAFKA_API_KEY=<confluent-api-key>
KAFKA_API_SECRET=<confluent-api-secret>

# Redis (Redis Cloud)
REDIS_HOST=redis-xxxxx.cloud.redislabs.com
REDIS_PORT=12345
REDIS_PASSWORD=<redis-password>

# Config / Eureka
CONFIG_REPO_URI=https://github.com/<your-org>/foodchain-config

# Security
JWT_SECRET=foodchain-super-secret-key-2026-capstone-demo-min-32-chars
```

### `.env` for Account 2
```env
# Database
RDS_ENDPOINT=my-rds-mysql.c4hs6um4wrpt.us-east-1.rds.amazonaws.com
RDS_PORT=3306
RDS_USERNAME=admin
RDS_PASSWORD=<your-rds-password>

# Kafka (Confluent Cloud)
KAFKA_BOOTSTRAP_SERVERS=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
KAFKA_API_KEY=<confluent-api-key>
KAFKA_API_SECRET=<confluent-api-secret>

# Redis (Redis Cloud)
REDIS_HOST=redis-xxxxx.cloud.redislabs.com
REDIS_PORT=12345
REDIS_PASSWORD=<redis-password>

# Point to Account 1
EUREKA_SERVER_URL=http://<ACCOUNT1_IP>:8761/eureka/
CONFIG_SERVER_URL=optional:configserver:http://<ACCOUNT1_IP>:8761
```

---

## Step 7 — Config Server YAML updates

In `foodchain-config`, every service YAML needs the Kafka config updated for Confluent Cloud (SASL_SSL auth):

```yaml
# Add to every service that uses Kafka (order, kitchen, menu, analytics-report, notifications)
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS}
    properties:
      security.protocol: SASL_SSL
      sasl.mechanism: PLAIN
      sasl.jaas.config: >
        org.apache.kafka.common.security.plain.PlainLoginModule required
        username="${KAFKA_API_KEY}"
        password="${KAFKA_API_SECRET}";
    consumer:
      group-id: <service>-group
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      auto-offset-reset: earliest
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer
```

And Redis config for services that use it:
```yaml
spring:
  data:
    redis:
      host: ${REDIS_HOST}
      port: ${REDIS_PORT}
      password: ${REDIS_PASSWORD}
```

Push these changes to the config repo before deploying.

---

## Step 8 — Verification Checklist

```bash
# On Account 1 EC2
docker ps                                          # all 4 containers Up
curl http://localhost:8761/actuator/health         # config-eureka: UP
curl http://localhost:8080/actuator/health         # api-gateway: UP

# From your local machine
curl http://<ACCOUNT1_IP>:8761                     # Eureka dashboard HTML
# Open http://<ACCOUNT1_IP>:8761 in browser
# You should see ALL 7 services registered (4 from Acc1, 3 more from Acc2 as they start)

# Swagger UI
# http://<ACCOUNT1_IP>:8080/swagger-ui.html
```

**Expected Eureka registrations:**
- `API-GATEWAY`
- `BRANCH-SERVICE`
- `NOTIFICATIONS-SERVICE`
- `ORDER-SERVICE`
- `MENU-SERVICE`
- `KITCHEN-SERVICE`
- `ANALYTICS-REPORT-SERVICE`

---

## Memory Budget

JVM flags are set in each Dockerfile / docker-compose via `JAVA_OPTS=-Xmx180m -Xms64m`.

| Account 1 | Heap cap | Est. total |
|-----------|---------|------------|
| config-eureka-server | 200m | ~320 MB |
| api-gateway | 180m | ~270 MB |
| branch-service | 150m | ~230 MB |
| notifications-service | 150m | ~230 MB |
| OS + Docker overhead | — | ~100 MB |
| **Total** | | **~1.15 GB** ⚠ tight |

| Account 2 | Heap cap | Est. total |
|-----------|---------|------------|
| order-service | 160m | ~250 MB |
| menu-service | 150m | ~240 MB |
| kitchen-service | 140m | ~220 MB |
| analytics-report-service | 160m | ~260 MB |
| OS + Docker overhead | — | ~100 MB |
| **Total** | | **~1.07 GB** ✓ |

> If Account 1 runs out of memory, move `notifications-service` to Account 2 — it has headroom.

---

## Startup Order

Services must come up in this order (the compose files enforce this with `depends_on`):

```
Confluent Cloud & Redis Cloud (external — always up)
        │
        ▼
config-eureka-server  (Account 1, boots first)
        │
        ├──► api-gateway          (Account 1)
        ├──► branch-service       (Account 1)
        ├──► notifications-service (Account 1)
        │
        └──► order-service        (Account 2)
             menu-service         (Account 2)
             kitchen-service      (Account 2)
             analytics-report-service (Account 2)
```

Account 2 services will retry connecting to Eureka until Account 1 is healthy — `restart: on-failure` handles this automatically.

---

## Teardown (avoid accidental billing)

```bash
# On each EC2
docker-compose -f docker-compose.accountX.yml down

# In AWS Console
# EC2 → Instances → Stop (not Terminate — you keep the Elastic IP free while stopped)
# RDS → Stop temporarily (restarts after 7 days automatically — stop again if needed)
```

Free tier gives 750 hours/month per account. Two t2.micro instances running 24/7 = 744 hours — right at the limit. Stop them when not demoing.
