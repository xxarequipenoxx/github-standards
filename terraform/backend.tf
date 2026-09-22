# State on a versioned OVH Object Storage bucket (S3 API), same pattern as kubernetes-infra.
# Locking uses the bucket itself (use_lockfile): no DynamoDB.
#
# bucket, key, region and endpoints.s3 are deliberately absent: the bucket is created once by
# hand and named in a backend.hcl file that stays out of Git (terraform/README.md, step 1),
# passed with `tofu init -backend-config=backend.hcl`. Credentials come from
# AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in the environment.
#
# The skip_* flags are what an S3-compatible endpoint without IAM, STS and the AWS checksum
# extensions needs; they change nothing about the state itself.

terraform {
  backend "s3" {
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
