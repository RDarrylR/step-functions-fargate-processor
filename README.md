# step-functions-fargate-processor

### Purpose
Example Serverless project using a Lambda function listening for new uploaded zip files of JSON data which are unzipped and trigger an AWS Step Function to run a distributed map over the json files with the processing done in ECS Fargate containers.

Lambda function to handle S3 uploads and the fargate container code are written in Rust.

### Key Files

- `containers` - Source for Fargate worker container to process a single store json data
- `lambdas` - Source for Lambda function which reacts to uploaded zip file, unzips file, and triggers AWS Step Function to process
- `sample_data` - Example sales data zip files. Each zip file contains 1 day of sales with a json file inside each for the sales at each location
- `infra` - Terraform files to setup the VPC network for the demo as well as all the other infrastructure

### Requirements

-   Terraform CLI (https://developer.hashicorp.com/terraform/install)
-   Cargo Lambda (https://www.cargo-lambda.info/guide/getting-started.html)
-   Docker

### Deploy the sample project

To deploy the project, you need the following tools:

In the infra/variables.tf file you need to update the following 2 variables:

slack_webhook (This needs to be set to a real slack webhook URL where notifications will be sent - the URL in the repo is not valid)
aws_profile (This needs to be set to the aws profile which you want to deploy all of the infrastructure with)

3 main things are being done here:

1. We're compiling the s3_upload_handler using cargo lambda
2. We're building a docker image of the fargate_rust_worker container, creating an ECR repository for it, and pushing the image to the repository
3. We're using terraform to setup a VPC and tie everything together.

```bash
 Clone the repo
 cd lambdas/s3_upload_handler
 cargo lambda build --release
 cd ../containers/fargate_rust_worker
 ./create_ecr_and_push.sh
 cd ../infra
 terraform apply
```

Once the terraform is applied it will output the newly created S3 bucket name to upload sales data zip files to.

It will look like this:

Outputs:

bucket_to_upload_sales_zip_to = "stepfunctions-fargate-processor-fdsfdfdsffd"  (NOTE - this is not an actual bucket name - yours will be different)

To start the processing you need to upload one of the zip files of data from the sample_data directory to the uploads/ path in the S3 bucket
```bash
 cd sample_data
 aws s3 cp day01.zip s3://<GENERATED_S3_BUCKET_NAME>/uploads/ 
```

This will trigger the lambda function which will trigger the step function which will trigger the Fargate processing tasks in ECS. You will see the progress and results in the slack channel your webhook pushes to.


### Cleanup

To delete the sample project you will need to delete the S3 bucket manually in the AWS console as it will have files in it and it will make you delete the files before deleting the bucket.

You will likely want to delet the ECR repository. You can do this in the AWS console.

Then please use the following terraform command to destroy all the infrastructure.

```bash
terraform destroy (from the infra directory)
```

### Read More

This repository is associated with the following blog [posted here](https://darryl-ruggles.cloud/serverless-data-processor-using-aws-lambda-step-functions-and-fargate-on-ecs-with-rust)
