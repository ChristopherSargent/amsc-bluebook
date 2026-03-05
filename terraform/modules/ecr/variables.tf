variable "repositories" {
  type        = list(string)
  description = "List of ECR repository names to create (e.g. [\"myapp/backend\", \"myapp/frontend\"])"
}

variable "image_retention_count" {
  type        = number
  description = "Number of images to retain per repository"
  default     = 20
}

variable "tags" {
  type    = map(string)
  default = {}
}
