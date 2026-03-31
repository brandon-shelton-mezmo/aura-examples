# Aura Infrastructure Layer — Qdrant (shared) + Discovery Worker (with sidecars)
# MCP servers run as sidecars in each agent task — localhost communication.
# All sidecars share the single Qdrant instance via internal ALB.

# ============================================================
# Qdrant — Shared Vector Database (single instance)
# ============================================================

resource "aws_ecs_task_definition" "qdrant" {
  family                   = "bella-vista-qdrant"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_qdrant_cpu
  memory                   = var.ecs_qdrant_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  volume {
    name = "qdrant-data"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.qdrant.id
      root_directory = "/"
    }
  }

  container_definitions = jsonencode([{
    name      = "qdrant"
    image     = local.qdrant_image
    essential = true
    portMappings = [{ containerPort = 6333, protocol = "tcp" }]
    mountPoints = [{ sourceVolume = "qdrant-data", containerPath = "/qdrant/storage" }]
    healthCheck = {
      command     = ["CMD-SHELL", "bash -c 'echo > /dev/tcp/localhost/6333'"]
      interval    = 10
      timeout     = 5
      retries     = 5
      startPeriod = 10
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "qdrant"
      }
    }
  }])
}

resource "aws_ecs_service" "qdrant" {
  name            = "qdrant"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.qdrant.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    assign_public_ip   = true
    security_groups = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.qdrant.arn
    container_name   = "qdrant"
    container_port   = 6333
  }
}

# ============================================================
# Discovery Worker — Aura agent with MCP sidecars
# ============================================================

resource "aws_ecs_task_definition" "discovery_worker" {
  family                   = "bella-vista-discovery-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.aura_agent_task.arn

  container_definitions = jsonencode([
    # Main agent
    {
      name      = "discovery-worker"
      image     = local.aura_image
      essential = true
      portMappings = [{ containerPort = 3030, protocol = "tcp" }]
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "curl -sf https://aura-demo-bundle.s3.amazonaws.com/configs/aws-discovery-agent.toml -o /app/config.toml && echo 'Waiting for sidecars...' && sleep 10 && /app/aura-web-server --verbose"
      ]
      environment = concat(
        [
          { name = "CONFIG_PATH", value = "/app/config.toml" },
          { name = "AWS_REGION", value = var.aws_region },
          { name = "AWS_MCP_URL", value = "http://localhost:8091/mcp" },
          { name = "QDRANT_MCP_URL", value = "http://localhost:8000/mcp" },
          { name = "AURA_WORKER_MCP_URL", value = "http://localhost:8095/mcp" }
        ],
        var.bedrock_access_key_id != "" ? [
          { name = "AWS_ACCESS_KEY_ID", value = var.bedrock_access_key_id },
          { name = "AWS_SECRET_ACCESS_KEY", value = var.bedrock_secret_access_key }
        ] : []
      )
      dependsOn = [
        { containerName = "qdrant-mcp", condition = "START" },
        { containerName = "aws-api-mcp", condition = "START" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "discovery-worker"
        }
      }
    },
    # Sidecar: qdrant-mcp (connects to shared Qdrant via internal ALB)
    {
      name      = "qdrant-mcp"
      image     = local.qdrant_mcp_img
      essential = false
      portMappings = [{ containerPort = 8000, protocol = "tcp" }]
      environment = [
        { name = "QDRANT_URL", value = "http://${aws_lb.internal.dns_name}:6333" },
        { name = "AWS_REGION", value = var.aws_region }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "dw-qdrant-mcp"
        }
      }
    },
    # Sidecar: aws-api-mcp (uses task role for AWS API calls)
    {
      name      = "aws-api-mcp"
      image     = local.aws_mcp_img
      essential = false
      portMappings = [{ containerPort = 8091, protocol = "tcp" }]
      environment = [
        { name = "READ_OPERATIONS_ONLY", value = "true" },
        { name = "AWS_REGION", value = var.aws_region }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "dw-aws-api-mcp"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "discovery_worker" {
  name            = "discovery-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.discovery_worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    assign_public_ip   = true
    security_groups = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.discovery_worker.arn
    container_name   = "discovery-worker"
    container_port   = 3030
  }

  depends_on = [aws_ecs_service.qdrant]
}
