# S3 Buckets — App assets, logs, and an INTENTIONALLY public bucket

# Private: App assets (menu images, static files)
resource "aws_s3_bucket" "assets" {
  bucket = "bella-vista-assets-${local.suffix}"
  tags   = { Name = "bella-vista-assets" }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Private: Application logs
resource "aws_s3_bucket" "logs" {
  bucket = "bella-vista-logs-${local.suffix}"
  tags   = { Name = "bella-vista-logs" }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration { days = 30 }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# INTENTIONAL ISSUE: Public uploads bucket
# Aura's agents will flag this as HIGH severity — public data exposure
resource "aws_s3_bucket" "uploads" {
  bucket = "bella-vista-uploads-${local.suffix}"
  tags   = { Name = "bella-vista-uploads" }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "uploads_public" {
  bucket = aws_s3_bucket.uploads.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.uploads.arn}/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.uploads]
}
