aws_region      = "us-east-1"
cluster_name    = "platform-cluster"
cluster_version = "1.29"
vpc_cidr        = "10.0.0.0/16"
environment     = "development"

tags = {
  Project   = "cloud-platform-engineering"
  ManagedBy = "terraform"
  Owner     = "devops-team"
}
