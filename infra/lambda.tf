

data "archive_file" "s3_upload_handler" {
  type        = "zip"
  source_file = "../lambdas/s3-upload-handler/target/lambda/s3-upload-handler/bootstrap"
  output_path = "../lambdas/build/bootstrap.zip"
}

resource "aws_lambda_function" "real_data_to_service_table" {
  function_name = "s3_upload_handler"
  timeout       = 60
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  memory_size   = 128

  filename         = data.archive_file.s3_upload_handler.output_path
  source_code_hash = data.archive_file.s3_upload_handler.output_base64sha256
  role             = aws_iam_role.s3_upload_handler_execution_role.arn

  tracing_config {
    mode = "Active"
  }
}


resource "aws_iam_role" "s3_upload_handler_execution_role" {
  name = "s3_upload_handler_execution_role"

  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
  ] })

  inline_policy {
    name = "s3_upload_handler_policy"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "s3:*",
            "ssm:GetParameter",
            "states:StartExecution"
          ]
          Effect   = "Allow"
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_iam_role_policy_attachment" "s3_upload_handler_policy_BasicExecutionRole_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.s3_upload_handler_execution_role.name
}


# Setup Lambda function on new sales data zip upload
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id
  lambda_function {
    lambda_function_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:s3_upload_handler"
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = "zip"
  }
  depends_on = [aws_lambda_permission.s3_upload_handler_allow_s3]
}

# The resource policy on the s3_upload_handler Lambda function that allows S3 to run it
resource "aws_lambda_permission" "s3_upload_handler_allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = "s3_upload_handler"
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.bucket.arn
}
