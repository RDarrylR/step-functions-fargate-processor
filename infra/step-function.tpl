{
  "Comment": "Process all daily store data using ECS Fargate tasks",
  "StartAt": "Send slack starting",
  "States": {
    "Send slack starting": {
      "Type": "Task",
      "Next": "Map",
      "Resource": "arn:aws:states:::http:invoke",
      "Parameters": {
        "ApiEndpoint": "${slack_webhook}",
        "Method": "POST",
        "Authentication": {
          "ConnectionArn": "${connection_notif_arn}"
        },
        "RequestBody": {
          "text.$": "States.Format('Starting to process Bucket=\"{}\" at Path=\"{}\"',$.input.source_bucket_name, $.input.bucket_path)"
        }
      },
      "ResultPath": null
    },
    "Map": {
      "Type": "Map",
      "ItemProcessor": {
        "ProcessorConfig": {
          "Mode": "DISTRIBUTED",
          "ExecutionType": "STANDARD"
        },
        "StartAt": "ECS invoke for daily store data",
        "States": {
          "ECS invoke for daily store data": {
            "Type": "Task",
            "Resource": "arn:aws:states:::ecs:runTask.waitForTaskToken",
            "Parameters": {
              "LaunchType": "FARGATE",
              "PlatformVersion": "LATEST",
              "Cluster": "${ecs_cluster}",
              "TaskDefinition": "${task_def_name}",
              "NetworkConfiguration": {
                "AwsvpcConfiguration": {
                  "Subnets": [
                    "${fargate_subnet}"
                  ],
                  "SecurityGroups": [
                    "${vpc_default_sg}"
                  ]
                }
              },
              "Overrides": {
                "ContainerOverrides": [
                  {
                    "Name": "store_data_processor_daily",
                    "Environment": [
                      {
                        "Name": "TASK_TOKEN",
                        "Value.$": "$$.Task.Token"
                      },
                      {
                        "Name": "S3_BUCKET",
                        "Value.$": "$.BatchInput.source_bucket_name"
                      },
                      {
                        "Name": "S3_KEY",
                        "Value.$": "$.Items[0].Key"
                      }
                    ]
                  }
                ]
              }
            },
            "End": true
          }
        }
      },
      "Next": "Send slack results",
      "Label": "Map",
      "MaxConcurrency": 10,
      "ItemReader": {
        "Resource": "arn:aws:states:::s3:listObjectsV2",
        "Parameters": {
          "Bucket.$": "$.input.source_bucket_name",
          "Prefix.$": "$.input.bucket_path"
        }
      },
      "ItemBatcher": {
        "MaxItemsPerBatch": 1,
        "BatchInput": {
          "source_bucket_name.$": "$.input.source_bucket_name"
        }
      },
      "ResultPath": "$.mapResults"
    },
    "Send slack results": {
      "Type": "Task",
      "Resource": "arn:aws:states:::http:invoke",
      "Parameters": {
        "ApiEndpoint": "${slack_webhook}",
        "Method": "POST",
        "Authentication": {
          "ConnectionArn": "${connection_notif_arn}"
        },
        "RequestBody": {
          "text.$": "States.Format('Results:\n\n{}\n',$.mapResults)"
        }
      },
      "ResultPath": null,
      "End": true
    }
  }
}