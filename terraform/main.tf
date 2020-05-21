/*
Copyright 2018 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

///////////////////////////////////////////////////////////////////////////////////////
//
// This configuration will create a GKE cluster that will be used for creating
// log information to be used by Stackdriver Logging.  The configuration will
// also create the kubernetes resources and Stackdriver Logging exports for Cloud Storage
// and BigQuery.
//
///////////////////////////////////////////////////////////////////////////////////////

// Provides access to available Google Container Engine versions in a zone for a given project.
// https://www.terraform.io/docs/providers/google/d/google_container_engine_versions.html
data "google_container_engine_versions" "on-prem" {
  zone    = var.zone
  project = var.project
}

///////////////////////////////////////////////////////////////////////////////////////
// Create the resources needed for the Stackdriver Export Sinks
///////////////////////////////////////////////////////////////////////////////////////

// Random string used to create a unique bucket name
resource "random_id" "server" {
  byte_length = 8
}

// Create a Cloud Storage Bucket for long-term storage of logs
// Note: the bucket has force_destroy turned on, so the data will be lost if you run
// terraform destroy
resource "google_storage_bucket" "gke-log-bucket" {
  name          = "stackdriver-gke-logging-bucket-${random_id.server.hex}"
  storage_class = "NEARLINE"
  force_destroy = true
}

// Create a BigQuery Dataset for storage of logs
// Note: only the most recent hour's data will be stored based on the table expiration
resource "google_bigquery_dataset" "gke-bigquery-dataset" {
  dataset_id                  = "gke_logs_dataset"
  location                    = "US"
  default_table_expiration_ms = 3600000

  labels = {
    env = "default"
  }
}

///////////////////////////////////////////////////////////////////////////////////////
// Create the primary cluster for this project.
///////////////////////////////////////////////////////////////////////////////////////

// Create the GKE Cluster
// https://www.terraform.io/docs/providers/google/d/google_container_cluster.html
resource "google_container_cluster" "primary" {
  name               = "stackdriver-logging"
  zone               = var.zone
  initial_node_count = 2
  min_master_version = data.google_container_engine_versions.on-prem.latest_master_version

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }

  // These local-execs are used to provision the sample service
  // These local-execs are used to provision the sample service
  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${google_container_cluster.primary.zone} --project ${var.project}"
  }

  provisioner "local-exec" {
    command = "kubectl --namespace default create deployment hello-server --image gcr.io/google-samples/hello-app:1.0"
  }

  provisioner "local-exec" {
    command = "kubectl --namespace default expose deployment hello-server --type \"LoadBalancer\" --port=8080"
  }
}

///////////////////////////////////////////////////////////////////////////////////////
// Configure the stackdriver sinks and necessary roles.
// To enable writing to the various export sinks we must grant additional permissions.
// Refer to the following URL for details:
// https://cloud.google.com/logging/docs/export/configure_export_v2#dest-auth
///////////////////////////////////////////////////////////////////////////////////////

// Create the Stackdriver Export Sink for Cloud Storage GKE Notifications
resource "google_logging_project_sink" "storage-sink" {
  name        = "gke-storage-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.gke-log-bucket.name}"
  filter      = "resource.type = container"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for BigQuery GKE Notifications
resource "google_logging_project_sink" "bigquery-sink" {
  name        = "gke-bigquery-sink"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gke-bigquery-dataset.dataset_id}"
  filter      = "resource.type = container"

  unique_writer_identity = true
}

// Grant the role of Storage Object Creator
resource "google_project_iam_binding" "log-writer-storage" {
  role = "roles/storage.objectCreator"

  members = [
    google_logging_project_sink.storage-sink.writer_identity,
  ]
}

// Grant the role of BigQuery Data Editor
resource "google_project_iam_binding" "log-writer-bigquery" {
  role = "roles/bigquery.dataEditor"

  members = [
    google_logging_project_sink.bigquery-sink.writer_identity,
  ]
}

