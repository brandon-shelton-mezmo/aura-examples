# OpenWebUI — Chat interface for Aura agents
# Connects to the orchestrator via the external ALB on port 3030.

resource "aws_ecs_task_definition" "openwebui" {
  family                   = "bella-vista-openwebui"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "openwebui"
    image     = "ghcr.io/open-webui/open-webui:main"
    essential = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      # Point OpenWebUI at the Aura orchestrator via the external ALB
      { name = "OPENAI_API_BASE_URL", value = "http://${aws_lb.main.dns_name}:3030/v1" },
      { name = "OPENAI_API_KEY", value = "not-needed" },

      # Branding
      { name = "WEBUI_NAME", value = "Aura" },
      { name = "DEFAULT_MODELS", value = "bedrock/us.anthropic.claude-sonnet-4-20250514-v1:0" },

      # Disable auth for demo — users land directly in the chat
      { name = "WEBUI_AUTH", value = "false" },
      { name = "ENABLE_SIGNUP", value = "false" },
      { name = "ENABLE_LOGIN_FORM", value = "false" },

      # Disable features that don't apply to the demo
      { name = "ENABLE_OLLAMA_API", value = "false" },
      { name = "ENABLE_RAG_WEB_SEARCH", value = "false" },

      # SRE-focused prompt suggestions
      { name = "DEFAULT_PROMPT_SUGGESTIONS", value = jsonencode([
        {
          title = ["Discover my AWS environment"]
          content = "Discover all AWS resources in us-east-1. Catalog VPCs, instances, security groups, S3 buckets, Lambda functions, IAM roles, load balancers, and DynamoDB tables."
        },
        {
          title = ["What's running in this environment?"]
          content = "Search the knowledge base and give me a summary of all infrastructure in this AWS environment. What services are running, how are they connected, and what are the key dependencies?"
        },
        {
          title = ["Find security risks"]
          content = "Search for security concerns in the knowledge base. Check for permissive security groups (0.0.0.0/0), public S3 buckets, overly broad IAM policies, and any other risks."
        },
        {
          title = ["Check collection stats"]
          content = "Use collection_stats to check the aws_resources collection and tell me what has been discovered so far."
        }
      ]) }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "openwebui"
      }
    }
  }])
}

resource "aws_ecs_service" "openwebui" {
  name            = "openwebui"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.openwebui.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.openwebui.arn
    container_name   = "openwebui"
    container_port   = 8080
  }
}

# ALB target group and listener for OpenWebUI on port 3000
resource "aws_lb_target_group" "openwebui" {
  name        = "bv-openwebui"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path    = "/"
    port    = "8080"
    matcher = "200-399"
  }
}

resource "aws_lb_listener" "openwebui" {
  load_balancer_arn = aws_lb.main.arn
  port              = 3000
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.openwebui.arn
  }
}
