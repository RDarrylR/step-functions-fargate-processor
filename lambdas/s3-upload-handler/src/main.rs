use aws_config::meta::region::RegionProviderChain;
use aws_config::BehaviorVersion;
use aws_lambda_events::event::s3::S3Event;
use aws_sdk_s3::error::SdkError;
use aws_sdk_s3::operation::put_object::PutObjectError;
use aws_sdk_s3::operation::put_object::PutObjectOutput;
use aws_sdk_s3::primitives::ByteStream;
use aws_sdk_s3::Client as S3_Client;
use aws_sdk_sfn as sfn;
use aws_sdk_ssm::Client as SSM_Client;
use glob::glob;
use lambda_runtime::Error as Runtime_Error;
use lambda_runtime::{run, service_fn, LambdaEvent};
use std::error::Error;
use std::fs::File;
use std::io;
use std::io::Write;
use std::path::Path;
use zip::ZipArchive;

// Uploads local file data to S3
async fn upload_object(
    client: &S3_Client,
    bucket_name: &str,
    file_name: &str,
    key: &str,
) -> Result<PutObjectOutput, SdkError<PutObjectError>> {
    let body = ByteStream::from_path(Path::new(file_name)).await;
    client
        .put_object()
        .bucket(bucket_name)
        .key(key)
        .body(body.expect("Problem getting data from file to upload"))
        .send()
        .await
}

// Downloads data from S3 to local files
async fn download_object(client: &S3_Client, bucket_name: &str, key: &str) {
    let full_path = format!("/tmp/{}", key);
    tracing::info!("full_path: {:?}", full_path);

    let path = std::path::Path::new(full_path.as_str());
    let prefix = path.parent().expect("Trouble getting parent path");
    std::fs::create_dir_all(prefix)
        .expect("Problem creating all the directories for download file");

    let mut file = File::create(full_path).expect("Problem creating download file");
    let object_result = client
        .get_object()
        .bucket(bucket_name)
        .key(key)
        .send()
        .await;

    match object_result {
        Ok(obj) => {
            let bytes = obj
                .body
                .collect()
                .await
                .expect("Problem getting data downloaded from S3")
                .into_bytes();
            let _file_write_result = file.write_all(&bytes);
        }
        Err(e) => println!("{:?}", e),
    }
}

// Extract contents from a zip file
fn extract_zip(zip_path: String) -> Result<(), Box<dyn Error>> {
    let zip_file_path = Path::new(&zip_path);
    let zip_file = File::open(zip_file_path).expect("Problem opening zip file");
    println!(
        "zip file path: {:?} and file: {:?}",
        zip_file_path, zip_file
    );

    let mut archive = ZipArchive::new(zip_file).expect("Problem reading zip file");
    let extraction_dir = Path::new("/tmp/extract");

    // Create the directory if it does not exist.
    if !extraction_dir.exists() {
        std::fs::create_dir(extraction_dir).expect("Problem creating extraction dir");
    }

    // Iterate through the files in the ZIP archive.
    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let file_name = file.name().to_owned();

        // Create the path to the extracted file in the destination directory.
        let target_path = extraction_dir.join(file_name);

        // Create the destination directory if it does not exist.
        if let Some(parent_dir) = target_path.parent() {
            std::fs::create_dir_all(parent_dir).expect("Problem creating dir for file");
        }

        let mut output_file = File::create(&target_path)?;

        // Read the contents of the file from the ZIP archive and write them to the destination file.
        io::copy(&mut file, &mut output_file)?;
    }

    println!("\nFiles successfully extracted to {:?}\n", extraction_dir);
    Ok(())
}

// Iterates files that were extracted to get list to upload
fn get_files_to_upload(path: &str) -> Vec<(String, String)> {
    let mut file_list: Vec<(String, String)> = vec![];
    for entry in glob([path, "/**/*"].join("").as_str()).expect("Failed to read glob pattern") {
        match entry {
            Ok(path) => {
                if !path.is_dir() {
                    let file_entry = String::from(path.to_string_lossy());
                    let file_name = file_entry[13..].to_string();
                    file_list.push((file_entry, file_name));
                }
            }
            Err(e) => println!("{:?}", e),
        }
    }

    file_list
}

// Gets a param value from SSM Param store with little (no) error handling
async fn get_parameter_value(client: &SSM_Client, param_name: &str) -> String {
    let get_parameter_output: aws_sdk_ssm::operation::get_parameter::GetParameterOutput = client
        .get_parameter()
        .name(param_name)
        .send()
        .await
        .expect("Problem getting SSM param for Step Function ARN");

    String::from(
        get_parameter_output
            .parameter
            .expect("Problem getting SSM param for Step Function ARN")
            .value
            .expect("Problem getting SSM param for Step Function ARN"),
    )
}

async fn function_handler(event: LambdaEvent<S3Event>) -> Result<(), Runtime_Error> {
    tracing::info!(records = ?event.payload.records.len(), "Received request from S3");

    let region_provider = RegionProviderChain::default_provider().or_else("us-east-1");
    let config = aws_config::defaults(BehaviorVersion::latest())
        // .profile_name("blog-admin")
        .region(region_provider)
        .load()
        .await;

    let ssm_client = SSM_Client::new(&config);

    let state_machine_arn = get_parameter_value(&ssm_client, "/config/step_function_arn").await;

    println!("State machine ARN: {}", state_machine_arn);

    let s3_client = S3_Client::new(&config);

    let mut the_key = String::from("");
    let mut the_bucket: String = String::from("");

    if event.payload.records.len() == 0 {
        tracing::info!("Empty S3 event received");
    } else {
        // Lets determine the path of the zip file that was uploaded (should only be a single file)
        for next in event.payload.records {
            tracing::info!("S3 Event Record: {:?}", next);
            tracing::info!("Uploaded object: {:?}", next.s3.object.key);

            the_bucket = next
                .s3
                .bucket
                .name
                .expect("Trouble getting S3 bucket name for uploaded zip file");
            tracing::info!("the_bucket: {:?}", the_bucket);

            the_key = next
                .s3
                .object
                .key
                .expect("Trouble getting key for uploaded zip file");
            tracing::info!("the_key: {:?}", the_key);

            // Let's download the zip file
            let _get_s3_result = download_object(&s3_client, &the_bucket, &the_key).await;
        }
    }

    let the_zip_file_name = the_key[8..].to_string();
    let full_path = ["/tmp/", the_key.as_str()].join("");

    // Unzip the file locally
    let unzip_result = extract_zip(full_path);
    match unzip_result {
        Ok(_) => println!("unzip worked\n"),
        Err(e) => println!("error parsing unzip: {e:?}"),
    }

    // Get the list of unzipped files so we can upload them back to S3 so they can be processed by the
    // state machine
    let list_path_result = get_files_to_upload("/tmp/extract");
    println!("list_path worked {:?}\n", list_path_result);

    // Upload the extracted files back to S3 for processing
    for next_file in list_path_result {
        tracing::info!("next_file: {:?}", next_file);
        let upload_path = ["processed/", the_zip_file_name.as_str(), "/", &next_file.1].join("");
        tracing::info!("upload_path: {:?}", upload_path);

        let upload_s3_result = upload_object(
            &s3_client,
            the_bucket.as_str(),
            next_file.0.as_str(),
            upload_path.as_str(),
        )
        .await;
        match upload_s3_result {
            Ok(_) => {
                println!("S3 upload worked\n");
                std::fs::remove_file(next_file.0.as_str())?;
            }
            Err(e) => println!("s3 upload problem: {e:?}"),
        }
    }

    // We have extracted all the store sales files from the uploaded zip so lets start the state machine to process
    // all the sales data files
    let sfn_client = sfn::Client::new(&config);

    let state_machine_input = format!(
        "{{\"input\": {{ \"source_bucket_name\": \"{}\", \"bucket_path\": \"processed/{}/\" }} }}",
        the_bucket, the_zip_file_name
    );

    println!("The state machine input is {}\n", state_machine_input);

    // Start execution of the state machine to process the uploaded data
    let sf_resp = sfn_client
        .start_execution()
        .state_machine_arn(state_machine_arn)
        .input(state_machine_input)
        .send()
        .await;
    match sf_resp {
        Ok(_) => {
            println!("Started state machine successully\n");
        }
        Err(e) => println!("Start state machine problem: {e:?}"),
    }
    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Runtime_Error> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        // disable printing the name of the module in every log line.
        .with_target(false)
        // disabling time is handy because CloudWatch will add the ingestion time.
        .without_time()
        .init();

    run(service_fn(function_handler)).await
}
