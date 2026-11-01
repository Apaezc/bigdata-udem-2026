# Estado remoto en el bucket creado por bootstrap (output TfStateBucket).
# bucket, key y region se pasan en init, ver backend.hcl.example:
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    use_lockfile = true
  }
}
