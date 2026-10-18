# Books API — лабораторна 1 (AWS)

REST API (FastAPI + PostgreSQL), запакований в Docker, розгорнутий на AWS через Terraform:
ECS Fargate за ALB, RDS PostgreSQL у приватній підмережі, автодеплой через GitHub Actions (OIDC),
автентифікація Cognito (JWT), моніторинг CloudWatch.

**Публічна адреса:** http://lab1-books-640699101.eu-north-1.elb.amazonaws.com · [Swagger UI](http://lab1-books-640699101.eu-north-1.elb.amazonaws.com/docs)

## Ендпоінти

| Метод | Шлях | Доступ |
|---|---|---|
| GET | `/health`, `/health/db` | публічний |
| GET | `/books`, `/books/{id}` | публічний |
| POST / PUT / DELETE | `/books`, `/books/{id}` | Bearer JWT (інакше 401) |
| GET | `/me` | Bearer JWT |
| GET | `/docs`, `/openapi.json` | публічний (OpenAPI) |

## Структура

```
app/                     код застосунку (FastAPI, SQLAlchemy, перевірка JWT Cognito)
Dockerfile               образ: python 3.12.7-slim, залежності окремим шаром, non-root
compose.yaml             локально: app + postgres, volume pgdata
infra/                   Terraform (network, security, ecr, rds, alb, ecs, cognito, github_oidc, monitoring, budget)
.github/workflows/       deploy.yml — push у main → build → ECR (тег = SHA) → ECS
scripts/get_token.sh     отримання JWT для тестового користувача
```

## 1. Локальний запуск (завдання 1)

```bash
docker compose up --build
curl localhost:8000/health
curl -X POST localhost:8000/books -H 'Content-Type: application/json' \
     -d '{"title":"Kobzar","author":"Taras Shevchenko","year":1840}'   # локально AUTH_ENABLED=false
docker compose down && docker compose up -d && curl localhost:8000/books   # дані збереглися
```

## 2. Підготовка AWS

1. Root: увімкнути MFA; створити IAM-користувача (напр. з `AdministratorAccess` для лабораторної), створити access key
   для **локального** CLI: `aws configure` (CI/CD ключів не використовує).
2. Для IAM-користувача увімкнути доступ до Billing (Account → *IAM user and role access to Billing information*),
   інакше `aws_budgets_budget` не створиться.
3. Потрібні локально: `terraform >= 1.6`, `aws cli v2`, `docker`, `bash` (Git Bash/WSL на Windows).

## 3. Розгортання (завдання 2–4, 6–8)

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # заповнити github_repo, email, пароль
terraform init
terraform apply        # ~15 хв: створює все, сам збирає й пушить перший образ у ECR
```

Після apply: підтвердити підписку SNS (лист на `alert_email`), відкрити `terraform output app_url`.

## 4. CI/CD (завдання 5)

1. Запушити репозиторій у GitHub (`github_repo` у tfvars має збігатися з `owner/repo`).
2. GitHub → Settings → Secrets and variables → Actions → **Variables**:
   `AWS_REGION` (напр. `eu-central-1`), `AWS_ROLE_ARN` = `terraform output github_actions_role_arn`.
3. Зробити зміну в коді → `git push origin main` → workflow збирає образ з тегом = SHA коміту й оновлює сервіс.

## 5. Перевірка автентифікації (бонус 6)

```bash
URL=$(terraform -chdir=infra output -raw app_url)
curl -i -X POST $URL/books -H 'Content-Type: application/json' -d '{"title":"x","author":"y"}'   # 401
TOKEN=$(DEMO_EMAIL=you@example.com DEMO_PASSWORD='...' ./scripts/get_token.sh)
curl -i -X POST $URL/books -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
     -d '{"title":"Kobzar","author":"Shevchenko","year":1840}'                                    # 201
```

## 6. Видалення ресурсів

```bash
cd infra && terraform destroy
```

## Архітектура та відповіді на типові питання

- **Мережа:** VPC 10.0.0.0/16, 2 AZ. Публічні підмережі — лише ALB і NAT. Контейнери — у приватних `app`-підмережах,
  БД — у `db`-підмережах без маршруту в інтернет, `publicly_accessible = false`.
- **Security groups:** `alb` ← 0.0.0.0/0:80; `app` ← лише SG `alb`:8000; `db` ← лише SG `app`:5432 (за посиланням на SG, не CIDR).
- **Секрети:** пароль БД генерує RDS (`manage_master_user_password`) і зберігає в Secrets Manager; ECS підставляє його
  в контейнер як змінну `DB_PASSWORD`. У коді, образі, git і tfstate пароль відсутній. `terraform.tfvars` у `.gitignore`.
- **OIDC:** GitHub отримує коротко­живучі токени; роль довіряє лише `repo:<owner/repo>:ref:refs/heads/main`.
- **Чому CD не конфліктує з Terraform:** сервіс має `ignore_changes = [task_definition]`; CD реєструє нову ревізію
  task definition з новим образом.
- **Health check:** ALB перевіряє `GET /health` (200); ECS circuit breaker відкочує невдалий деплой.
- **HTTP, не HTTPS:** для HTTPS потрібен власний домен + сертифікат ACM; у лабораторній це поза вимогами.
- **Вартість:** NAT Gateway і ALB тарифікуються погодинно — після захисту обов'язково `terraform destroy`.
