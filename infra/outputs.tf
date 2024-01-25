
output "bucket_to_upload_sales_zip_to" {
  value = "${var.project_name}-${random_string.s3_bucket_randomness.result}"
}
