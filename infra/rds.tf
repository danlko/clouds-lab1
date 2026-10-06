resource "aws_db_subnet_group" "main" {
  name       = var.name
  subnet_ids = aws_subnet.db[*].id
}

resource "aws_db_instance" "main" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "books"
  username = "books"
  # Пароль генерує й зберігає сам RDS у Secrets Manager — його немає ні в коді, ні в tfvars
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = 0
  skip_final_snapshot        = true
  deletion_protection        = false
  apply_immediately          = true
  auto_minor_version_upgrade = true
}
