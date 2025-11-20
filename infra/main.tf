terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "us-east-1"
}

# ================================
#   REPOSITORIO ECR
# ================================
resource "aws_ecr_repository" "app" {
  name                 = "miapp"
  image_tag_mutability = "MUTABLE"
}

# ================================
#   POLICY DE LIFECYCLE DEL ECR
# ================================
resource "aws_ecr_lifecycle_policy" "app_policy" {
  repository = aws_ecr_repository.app.name

  policy = <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Eliminar imágenes sin tag si hay más de 5",
      "selection": {
        "tagStatus": "untagged",
        "countType": "imageCountMoreThan",
        "countNumber": 5
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF
}

# ================================
#   TABLA DYNAMODB
# ================================
resource "aws_dynamodb_table" "items" {
  name           = "Items"
  billing_mode   = "PAY_PER_REQUEST"

  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Environment = "dev"
    Name        = "items-table"
  }
}

# ================================
#   CLUSTER ECS
# ================================
resource "aws_ecs_cluster" "miapp" {
  name = "nodeappv3-cluster"
}

# ================================
#   IAM ROLE PARA ECS TASK
# ================================
resource "aws_iam_role" "ecs_task_role" {
  name = "access-to-dynamodb"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy attach (DynamoDB Full Access)
resource "aws_iam_role_policy_attachment" "ecs_task_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# ================================
#   IAM ROLE DE EJECUCION
# ================================
resource "aws_iam_role" "ecs_exec_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ================================
#   TASK DEFINITION ECS
# ================================
resource "aws_ecs_task_definition" "miapp" {
  family                   = "miapp-task"
  cpu                      = "1024"
  memory                   = "3072"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "miapp"
    image     = "${aws_ecr_repository.app.repository_url}:latest"
    cpu       = 1024
    memory    = 3072
    essential = true
    portMappings = [{
      containerPort = 3000
      hostPort      = 3000
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/miapp-task"
        "awslogs-region"        = "us-east-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ================================
#   SECURITY GROUP ECS
# ================================
resource "aws_security_group" "ecs_sg" {
  name        = "ecs-miapp-sg"
  description = "Allow inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
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
}

# ================================
#   ECS SERVICE
# ================================
resource "aws_ecs_service" "miapp_service" {
  name            = "miapp-service"
  cluster         = aws_ecs_cluster.miapp.id
  task_definition = aws_ecs_task_definition.miapp.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "miapp"
    container_port   = 3000
  }

}

# ======================================
# VPC Y SUBNETS DEFAULT
# ======================================
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# ======================================
# Security Group para el ALB
# ======================================

resource "aws_security_group" "alb_sg" {
  name        = "alb-miapp-sg"
  description = "Allow inbound HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ======================================
# Target Group ALB
# ======================================

resource "aws_lb_target_group" "ecs_tg" {
  name        = "ecs-miapp-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    unhealthy_threshold = 3
    healthy_threshold   = 2
  }
}


# ======================================
# Application Load Balancer
# ======================================

resource "aws_lb" "ecs_alb" {
  name               = "ecs-miapp-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# ======================================
# Listener del ALB
# ======================================

resource "aws_lb_listener" "listener_http" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

# ======================================
# VPC Y SUBNETS DEFAULT
# ======================================

