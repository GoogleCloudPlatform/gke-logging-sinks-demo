#!/usr/bin/env bash

# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# "---------------------------------------------------------"
# "-                                                       -"
# "-  Create starts a GKE Cluster and installs             -"
# "-  a Cassandra StatefulSet                              -"
# "-                                                       -"
# "---------------------------------------------------------"

set -o errexit
set -o nounset
set -o pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
# shellcheck source=scripts/common.sh
source "$ROOT"/scripts/common.sh

# Enable needed APIs
gcloud services enable \
 bigquery-json.googleapis.com \
 cloudresourcemanager.googleapis.com \
 compute.googleapis.com \
 container.googleapis.com \
 logging.googleapis.com \
 monitoring.googleapis.com \

# Generate the variables to be used by Terraform if it doesn't not already exist.
# shellcheck source=scripts/generate-tfvars.sh
source "$ROOT/scripts/generate-tfvars.sh"

# Initialize and run Terraform
(cd "$ROOT/terraform"; terraform init -input=false)
(cd "$ROOT/terraform"; terraform apply -input=false -auto-approve)
