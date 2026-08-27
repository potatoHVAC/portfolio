output "originals_bucket_name" {
  value = aws_s3_bucket.media["originals"].bucket
}

output "originals_bucket_arn" {
  value = aws_s3_bucket.media["originals"].arn
}

output "delivery_bucket_name" {
  value = aws_s3_bucket.media["delivery"].bucket
}

output "delivery_bucket_arn" {
  value = aws_s3_bucket.media["delivery"].arn
}

output "delivery_bucket_regional_domain_name" {
  value = aws_s3_bucket.media["delivery"].bucket_regional_domain_name
}
