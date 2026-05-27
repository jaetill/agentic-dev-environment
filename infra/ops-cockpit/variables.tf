variable "grafana_url" {
  type        = string
  description = "Grafana Cloud stack URL, e.g. https://<stack>.grafana.net"
}

variable "grafana_api_key" {
  type        = string
  description = "Grafana service-account token with Admin role on the stack (Editor will 403 on datasources:create). Supply via TF_VAR_grafana_api_key -- never commit it."
  sensitive   = true
}

variable "github_token" {
  type        = string
  description = "Fine-grained, READ-ONLY GitHub PAT scoped to the fleet repos (Actions / Issues / Pull requests / Contents / Metadata: Read). Supply via TF_VAR_github_token -- never commit it."
  sensitive   = true
}