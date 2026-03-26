# Internal ALB — shared Qdrant access + discovery worker routing
# Only Qdrant and discovery-worker need to be on the internal ALB.
# MCP servers are sidecars (localhost) — no ALB routing needed for them.

resource "aws_lb" "internal" {
  name               = "bella-vista-internal"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = { Name = "bella-vista-internal-alb" }
}

# Qdrant — shared vector database (all sidecars connect here)
resource "aws_lb_target_group" "qdrant" {
  name        = "bv-qdrant"
  port        = 6333
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/"
    port = "6333"
  }
}

resource "aws_lb_listener" "qdrant" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 6333
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.qdrant.arn
  }
}

# Discovery worker — orchestrator's worker-mcp sidecar delegates here
resource "aws_lb_target_group" "discovery_worker" {
  name        = "bv-discovery-worker"
  port        = 3030
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path     = "/health"
    port     = "3030"
    matcher  = "200-499"
  }
}

resource "aws_lb_listener" "discovery_worker" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 3030
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.discovery_worker.arn
  }
}

output "internal_alb_dns" {
  description = "Internal ALB DNS for service-to-service communication"
  value       = aws_lb.internal.dns_name
}
