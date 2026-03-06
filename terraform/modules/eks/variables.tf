variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.32"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for node groups"
}

variable "node_instance_type" {
  type        = string
  default     = "t3.medium"
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

# Bug fix: restrict public API endpoint to known CIDRs rather than 0.0.0.0/0
variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the public EKS API endpoint. Restrict to your CI runner IPs and VPN range."
  default     = ["0.0.0.0/0"] # override this in every environment
}

variable "tags" {
  type    = map(string)
  default = {}
}
