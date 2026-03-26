# Aura Agent Layer — Orchestrator + 4 Specialized Agents
# Each agent runs as a multi-container task with MCP server sidecars.
# MCP servers connect to the shared Qdrant via internal ALB.
# Agent connects to sidecars via localhost — no network hop, no race condition.

locals {
  aura_agents = {
    orchestrator = {
      config_key = "aws-orchestrator-agent.toml"
      # Orchestrator needs: qdrant-mcp (search KB) + aura-worker-mcp (delegate to workers)
      sidecars = ["qdrant-mcp", "aura-worker-mcp"]
    }
    incident-response = {
      config_key = "aws-incident-response-agent.toml"
      sidecars = ["qdrant-mcp", "aws-api-mcp"]
    }
    change-audit = {
      config_key = "aws-change-audit-agent.toml"
      sidecars = ["qdrant-mcp", "aws-api-mcp"]
    }
    post-mortem = {
      config_key = "aws-postmortem-agent.toml"
      sidecars = ["qdrant-mcp", "aws-api-mcp"]
    }
    capacity-planning = {
      config_key = "aws-capacity-planning-agent.toml"
      sidecars = ["qdrant-mcp", "aws-api-mcp"]
    }
  }

  # Sidecar container definitions (reused across agents)
  sidecar_qdrant_mcp = {
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
        "awslogs-stream-prefix" = "sidecar-qdrant-mcp"
      }
    }
  }

  sidecar_aws_api_mcp = {
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
        "awslogs-stream-prefix" = "sidecar-aws-api-mcp"
      }
    }
  }

  sidecar_aura_worker_mcp = {
    name      = "aura-worker-mcp"
    image     = local.worker_mcp_img
    essential = false
    portMappings = [{ containerPort = 8095, protocol = "tcp" }]
    environment = [
      { name = "AURA_WORKER_URL", value = "http://${aws_lb.internal.dns_name}:3030" },
      { name = "WORKER_TIMEOUT", value = "300" },
      { name = "MAX_PARALLEL", value = "5" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "sidecar-worker-mcp"
      }
    }
  }
}

# Upload agent configs to S3
resource "aws_s3_object" "agent_configs" {
  for_each = local.aura_agents

  bucket = aws_s3_bucket.configs.id
  key    = "configs/${each.value.config_key}"
  source = "${path.module}/../configs/${each.value.config_key}"
  etag   = filemd5("${path.module}/../configs/${each.value.config_key}")
}

resource "aws_s3_object" "discovery_config" {
  bucket = aws_s3_bucket.configs.id
  key    = "configs/aws-discovery-agent.toml"
  source = "${path.module}/../configs/aws-discovery-agent.toml"
  etag   = filemd5("${path.module}/../configs/aws-discovery-agent.toml")
}

# Task Definitions — multi-container with MCP sidecars
resource "aws_ecs_task_definition" "agents" {
  for_each = local.aura_agents

  family                   = "bella-vista-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  # Larger CPU/memory to accommodate sidecars
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.aura_agent_task.arn

  container_definitions = jsonencode(concat(
    # Main agent container
    [{
      name      = each.key
      image     = local.aura_image
      essential = true
      portMappings = [{ containerPort = 3030, protocol = "tcp" }]

      entryPoint = ["/bin/sh", "-c"]
      command = [
        "curl -sf https://aura-demo-bundle.s3.amazonaws.com/configs/${each.value.config_key} -o /app/config.toml && echo 'Waiting for sidecars...' && sleep 10 && /app/aura-web-server"
      ]

      # MCP URLs point to localhost — sidecars in the same task
      environment = concat(
        [
          { name = "AWS_REGION", value = var.aws_region },
          { name = "AWS_MCP_URL", value = "http://localhost:8091/mcp" },
          { name = "QDRANT_MCP_URL", value = "http://localhost:8000/mcp" },
          { name = "AURA_WORKER_MCP_URL", value = "http://localhost:8095/mcp" },
          { name = "CONFIG_PATH", value = "/app/config.toml" }
        ],
        # Cross-account Bedrock creds (when SCP blocks native Bedrock)
        var.bedrock_access_key_id != "" ? [
          { name = "AWS_ACCESS_KEY_ID", value = var.bedrock_access_key_id },
          { name = "AWS_SECRET_ACCESS_KEY", value = var.bedrock_secret_access_key }
        ] : []
      )

      dependsOn = [for s in each.value.sidecars : { containerName = s, condition = "START" }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = each.key
        }
      }
    }],
    # Sidecar containers based on what this agent needs
    [for s in each.value.sidecars :
      s == "qdrant-mcp" ? local.sidecar_qdrant_mcp :
      s == "aws-api-mcp" ? local.sidecar_aws_api_mcp :
      s == "aura-worker-mcp" ? local.sidecar_aura_worker_mcp :
      null
    ]
  ))
}

# ECS Services
resource "aws_ecs_service" "agents" {
  for_each = local.aura_agents

  name            = each.key
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.agents[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    assign_public_ip   = true
    security_groups = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.agents[each.key].arn
    container_name   = each.key
    container_port   = 3030
  }

  depends_on = [aws_ecs_service.qdrant]
}

# Force task definition update - diagnostic build
