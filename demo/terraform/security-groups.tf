# ALB Security Group — public HTTP/HTTPS
resource "aws_security_group" "alb" {
  name        = "bella-vista-alb-sg"
  description = "ALB - allow HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Aura agent ports (3030-3034)"
    from_port   = 3030
    to_port     = 3034
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "OpenWebUI chat interface"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bella-vista-alb-sg" }
}

# ECS Tasks Security Group — allow traffic from ALB + internal
resource "aws_security_group" "ecs" {
  name        = "bella-vista-ecs-sg"
  description = "ECS tasks - allow traffic from ALB and internal"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Internal - service mesh"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bella-vista-ecs-sg" }
}

# Database Security Group — allow from ECS only
resource "aws_security_group" "db" {
  name        = "bella-vista-db-sg"
  description = "RDS - allow PostgreSQL from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bella-vista-db-sg" }
}

# INTENTIONAL ISSUE: Legacy SSH security group open to the world
resource "aws_security_group" "legacy_ssh" {
  name        = "bella-vista-legacy-ssh-sg"
  description = "LEGACY - SSH open to the world (INTENTIONAL DEMO ISSUE)"
  vpc_id      = aws_vpc.main.id

  # This is intentionally insecure for the demo
  # Aura's agents will flag this as a HIGH severity finding
  ingress {
    description = "SSH from anywhere - INSECURE"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bella-vista-legacy-ssh-sg" }
}

# EFS Security Group — allow NFS from ECS
resource "aws_security_group" "efs" {
  name        = "bella-vista-efs-sg"
  description = "EFS - allow NFS from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "NFS from ECS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bella-vista-efs-sg" }
}
