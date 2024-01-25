use aws_config::meta::region::RegionProviderChain;
use aws_config::BehaviorVersion;
use aws_sdk_s3::Client as S3_Client;
use aws_sdk_s3::Error as S3_Error;
use aws_sdk_sfn as sfn;
use rand::Rng;
use serde_json::json;
use std::env;
use std::error::Error;
use std::fs::File;
use std::io::Write;
use std::path::Path;
use std::thread;
use std::time::Duration;
use std::time::Instant;

#[derive(Debug, PartialEq, serde::Deserialize)]
struct Transaction {
    InvoiceNo: String,
    StockCode: String,
    Description: String,
    Quantity: String,
    InvoiceDate: String,
    UnitPrice: String,
    CustomerID: String,
    Country: String,
}

pub async fn download_object(
    client: &S3_Client,
    bucket_name: &str,
    key: &str,
) -> Result<String, S3_Error> {
    let mut object = client
        .get_object()
        .bucket(bucket_name)
        .key(key)
        .send()
        .await?;

    let filename = Path::new(key)
        .file_name()
        .expect("Key is empty")
        .to_str()
        .expect("Problem converting string");

    let mut file =
        File::create(["/tmp/", filename].join("").as_str()).expect("Error creating file");

    while let Some(bytes) = object
        .body
        .try_next()
        .await
        .expect("Error getting stream of data from s3 object")
    {
        let _write_result = file.write_all(&bytes);
    }

    println!("Successfully downloaded file {} from S3", filename);
    Ok(filename.to_string())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    // Need these key values to know what to process and how to send status
    let task_token = env::var("TASK_TOKEN").expect("No task token was set");
    let s3_bucket = env::var("S3_BUCKET").expect("No S3 bucket was set");
    let s3_key = env::var("S3_KEY").expect("No S3 key was set");

    // Want to keep track of processing time
    let run_time = Instant::now();

    // Setup AWS credentials
    let region_provider = RegionProviderChain::default_provider().or_else("us-east-1");
    let config = aws_config::defaults(BehaviorVersion::latest())
        .profile_name("blog-admin")
        .region(region_provider)
        .load()
        .await;

    let s3_client = S3_Client::new(&config);

    // File we will save S3 data to
    let mut input_file: String = String::from("");

    // Get the file from S3 and save locally
    let download_s3_result = download_object(&s3_client, &s3_bucket, &s3_key).await;
    match download_s3_result {
        Ok(filename) => {
            println!("s3 download worked {}\n", filename);
            input_file = filename.to_string();
        }
        Err(e) => println!("s3 download problem: {e:?}"),
    }

    // Get local file path of the S3 data
    let json_file_path = Path::new("/tmp/").join(&input_file);
    let file = File::open(json_file_path).expect("Error opening file we just saved to");

    // Deserialize array of JSON Transactions into vector of objects
    let transaction_vec: Vec<Transaction> =
        serde_json::from_reader(file).expect("Error parsing json file");

    let item_line_count = transaction_vec.len();

    // Calculate total sales for the json data
    let mut total_sales: f32 = 0_f32;
    for next_transaction in transaction_vec {
        total_sales = total_sales
            + (next_transaction
                .Quantity
                .parse::<f32>()
                .expect("Error processing sales transaction quantity")
                * next_transaction
                    .UnitPrice
                    .parse::<f32>()
                    .expect("Error processing sales transaction unit price"))
    }

    println!("Total sales is {}", total_sales);

    println!("Before business logic processing");

    // Sleep to simulate real business logic processing data
    let num = rand::thread_rng().gen_range(4..20);
    thread::sleep(Duration::from_secs(num));

    println!("After business logic processing");

    let sfn_client = sfn::Client::new(&config);

    // Send back the task token to state machine to mark this processing run as successful
    if task_token.len() > 0 {
        let response = json!({
            "status": "Success",
            "store_number": input_file[6..input_file.len()-4],
            "processing_time": format!("{} seconds", run_time.elapsed().as_secs()),
            "item_transaction_count": item_line_count,
            "total_sales": format!("${:.2}", total_sales)
        });
        let success_result = sfn_client
            .send_task_success()
            .task_token(task_token)
            .output(response.to_string())
            .send()
            .await;

        match success_result {
            Ok(_) => {
                println!("Sucessfully updated task status.")
            }
            Err(e) => println!("Error updating task status error: {e:?}"),
        }
    }

    Ok(())
}
