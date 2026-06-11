output "public_ip" {
  description = "Public IP of the demo instance."
  value       = aws_instance.demo.public_ip
}

output "ssh_command" {
  description = "Copy-paste SSH command (assumes your key is at ~/.ssh/<key_name>.pem)."
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_instance.demo.public_ip}"
}

output "aura_chat_url" {
  description = "AURA web-server URL for the aura-cli AURA_AGENT_API_URL env var. Reachable only from var.your_ip_cidr."
  value       = "http://${aws_instance.demo.public_ip}:8090"
}

output "bootstrap_readiness_tail" {
  description = "After SSH in, tail this file to watch boot finish; then check sregym-status."
  value       = "tail -f /var/log/aura-demo-bootstrap.log  (ready sentinel: /var/log/aura-demo-bootstrap.ready)"
}
