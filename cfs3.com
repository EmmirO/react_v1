# S3 buckets test
resource "aws_s3_bucket" "dev.com" {
  bucket = "dev.com"
  acl    = "public-read"

  website {
    index_document = "index.html"
  }
}

resource "aws_s3_bucket_policy" "dev.com" {
  bucket = aws_s3_bucket.dev_com.id
  policy = data.aws_iam_policy_document.dev_com.json
}

data "aws_iam_policy_document" "dev_com" {
  statement {
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.dev_com.arn}/*",
    ]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.dev_com.iam_arn]
    }
  }

  statement {
    actions = ["s3:ListBucket"]
    resources = [
      aws_s3_bucket.dev_com.arn,
    ]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.dev_com.iam_arn]
    }
  }
}

resource "aws_cloudfront_distribution" "dev_com" {
  web_acl_id   = var.web_acl
  http_version = "http2"

  origin {
    domain_name = aws_s3_bucket.dev_com.website_endpoint
    origin_id   = "S3-dev.com"

    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled             = true
  default_root_object = "index.html"
  is_ipv6_enabled     = true

  aliases = ["task.com"]

  
  default_cache_behavior {
    allowed_methods  = ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"]
    cached_methods   = ["HEAD", "GET"]
    target_origin_id = "S3-dev.com"

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  custom_error_response {
    error_caching_min_ttl = "300"
    error_code            = "404"
    response_code         = "200"
    response_page_path    = "/index.html"
  }

  
}

