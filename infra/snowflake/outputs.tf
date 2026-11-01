output "storage_aws_iam_user_arn" {
  description = "STORAGE_AWS_IAM_USER_ARN de BIGDATA_S3_INT. Va como Principal en la trust policy del rol (infra/aws, fase 2)."
  value       = snowflake_storage_integration_aws.s3.describe_output[0].iam_user_arn
}

output "storage_aws_external_id" {
  description = "STORAGE_AWS_EXTERNAL_ID de BIGDATA_S3_INT. Va como sts:ExternalId en la trust policy del rol (infra/aws, fase 2)."
  value       = snowflake_storage_integration_aws.s3.describe_output[0].external_id
}
