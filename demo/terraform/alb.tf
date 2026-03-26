# Application Load Balancer — routes to Bella Vista and Aura agents

resource "aws_lb" "main" {
  name               = "bella-vista-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = { Name = "bella-vista-alb" }
}

# Default listener → Bella Vista app
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bella_vista.arn
  }
}

# Target Group: Bella Vista (default)
resource "aws_lb_target_group" "bella_vista" {
  name        = "bella-vista-web"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 15
  }

  tags = { Name = "bella-vista-web" }
}

# Target Groups: Aura agents
resource "aws_lb_target_group" "agents" {
  for_each = local.aura_agents

  name        = "aura-${each.key}"
  port        = 3030
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 15
  }

  tags = { Name = "aura-${each.key}" }
}

# Path-based routing rules for each Aura agent
resource "aws_lb_listener_rule" "orchestrator" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents["orchestrator"].arn
  }

  condition {
    path_pattern { values = ["/v1/*", "/health"] }
  }
}

resource "aws_lb_listener_rule" "incident_response" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents["incident-response"].arn
  }

  condition {
    path_pattern { values = ["/incident/*"] }
  }
}

resource "aws_lb_listener_rule" "change_audit" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents["change-audit"].arn
  }

  condition {
    path_pattern { values = ["/audit/*"] }
  }
}

resource "aws_lb_listener_rule" "post_mortem" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents["post-mortem"].arn
  }

  condition {
    path_pattern { values = ["/postmortem/*"] }
  }
}

resource "aws_lb_listener_rule" "capacity_planning" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents["capacity-planning"].arn
  }

  condition {
    path_pattern { values = ["/capacity/*"] }
  }
}

# Port-based listeners for direct agent access (simpler than path rewriting)
# Learners use: curl http://ALB:3031/v1/chat/completions
resource "aws_lb_listener" "orchestrator_direct" {
  load_balancer_arn = aws_lb.main.arn
  port              = 3030
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents["orchestrator"].arn
  }
}

resource "aws_lb_listener" "incident_direct" {
  load_balancer_arn = aws_lb.main.arn
  port              = 3031
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents["incident-response"].arn
  }
}

resource "aws_lb_listener" "audit_direct" {
  load_balancer_arn = aws_lb.main.arn
  port              = 3032
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents["change-audit"].arn
  }
}

resource "aws_lb_listener" "postmortem_direct" {
  load_balancer_arn = aws_lb.main.arn
  port              = 3033
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents["post-mortem"].arn
  }
}

resource "aws_lb_listener" "capacity_direct" {
  load_balancer_arn = aws_lb.main.arn
  port              = 3034
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents["capacity-planning"].arn
  }
}
