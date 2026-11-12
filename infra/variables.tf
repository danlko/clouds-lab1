variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "name" {
  description = "Префікс імен усіх ресурсів. Має збігатися з APP_NAME у .github/workflows/deploy.yml"
  type        = string
  default     = "lab1-books"
}

variable "github_repo" {
  description = "Репозиторій у форматі owner/repo (для OIDC-довіри GitHub Actions)"
  type        = string
}

variable "alert_email" {
  description = "Email для алертів CloudWatch та сповіщень бюджету"
  type        = string
}

variable "demo_user_email" {
  description = "Email тестового користувача Cognito"
  type        = string
}

variable "demo_user_password" {
  description = "Пароль тестового користувача (мін. 8 символів, великі/малі літери, цифра, спецсимвол)"
  type        = string
  sensitive   = true
}

variable "budget_limit_usd" {
  type    = string
  default = "10"
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "autoscaling_min" {
  type    = number
  default = 1
}

variable "autoscaling_max" {
  type    = number
  default = 4
  validation {
    condition     = var.autoscaling_max >= 1 && var.autoscaling_max <= 4
    error_message = "За умовами лабораторної максимум — не більше 4 екземплярів."
  }
}

variable "cpu_target" {
  description = "Цільове середнє завантаження CPU сервісу, %"
  type        = number
  default     = 60
}

variable "scale_out_cooldown" {
  description = "Період стабілізації після додавання екземпляра, с"
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Період стабілізації після вилучення екземпляра, с"
  type        = number
  default     = 180
}

variable "cpu_alarm_threshold" {
  description = "Поріг сповіщення про перевантаження, % CPU протягом 2 хв"
  type        = number
  default     = 70
}

variable "schedule_enabled" {
  description = "Бонус 8: різний мінімум екземплярів удень і вночі"
  type        = bool
  default     = false
}

variable "schedule_day_min" {
  type    = number
  default = 2
}

variable "schedule_night_min" {
  type    = number
  default = 1
}

variable "redis_image" {
  type    = string
  default = "public.ecr.aws/docker/library/redis:7.4-alpine"
}

variable "cache_enabled" {
  description = "Початкове значення прапорця кешу (далі перемикається PUT /admin/cache без передеплою)"
  type        = bool
  default     = true
}

variable "cache_ttl_seconds" {
  type    = number
  default = 30
  validation {
    condition     = var.cache_ttl_seconds >= 30 && var.cache_ttl_seconds <= 60
    error_message = "TTL кешу — 30–60 с."
  }
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "bootstrap_tag" {
  description = "Тег початкового образу, який Terraform збирає й пушить при першому apply"
  type        = string
  default     = "lab2" # змінено в ЛР2: apply перезбирає образ із модулем app.worker
}

variable "worker_min" {
  type    = number
  default = 1
}

variable "worker_max" {
  type    = number
  default = 4
  validation {
    condition     = var.worker_max >= 1 && var.worker_max <= 4
    error_message = "За умовами лабораторної максимум — не більше 4 екземплярів."
  }
}

variable "worker_work_seconds" {
  description = "Імітація тривалої обробки одного повідомлення обробником, с"
  type        = number
  default     = 0.1
}

variable "queue_scale_out_threshold" {
  description = "Довжина черги (видимі повідомлення), понад яку додаються обробники"
  type        = number
  default     = 100
}
