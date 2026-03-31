# Bella Vista Application — Restaurant app on ECS Fargate

resource "aws_ecs_task_definition" "bella_vista" {
  family                   = "bella-vista-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.bella_vista_task.arn

  container_definitions = jsonencode([{
    name      = "bella-vista"
    image     = local.bella_vista_img
    essential = true
    portMappings = [
      { containerPort = 8080, protocol = "tcp" },
      { containerPort = 3001, protocol = "tcp" }
    ]
    environment = [
      { name = "NODE_ENV", value = "production" },
      { name = "PORT", value = "3001" },
      { name = "DISABLE_AUTO_TRAFFIC", value = "false" }
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "curl -sf http://localhost:3001/api/health || exit 1"]
      interval    = 15
      timeout     = 5
      retries     = 5
      startPeriod = 60
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "bella-vista"
      }
    }
  }])
}

resource "aws_ecs_service" "bella_vista" {
  name            = "bella-vista-web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.bella_vista.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    assign_public_ip   = true
    security_groups = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.bella_vista.arn
    container_name   = "bella-vista"
    container_port   = 3001
  }
}
