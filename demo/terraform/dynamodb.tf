# DynamoDB — Session store for Bella Vista

resource "aws_dynamodb_table" "sessions" {
  name         = "bella-vista-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"

  attribute {
    name = "session_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = { Name = "bella-vista-sessions" }
}
