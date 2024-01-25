
variable "project_name" {
  default = "stepfunctions-fargate-processor"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "az_count" {
  default = "2"
}

variable "task_container_name" {
  default = "store_data_processor_daily"
}

variable "task_definition_name" {
  default = "store_data_processor_daily_fargate"
}

variable "fargate_cpu" {
  default = "256"
}

variable "fargate_memory" {
  default = "512"
}

variable "slack_webhook" {
  default = "https://hooks.slack.com/triggers/AAAAAAA/BAHDDHKDJHDKJHDKHDKDHKDHD
}

variable "aws_profile" {
  default = "personal"
}
