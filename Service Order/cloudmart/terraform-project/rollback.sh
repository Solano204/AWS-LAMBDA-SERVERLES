#!/bin/bash
set -e

echo "🔄 Rolling back infrastructure..."

# Destroy all resources
terraform destroy -auto-approve

echo "✅ Rollback complete - all resources deleted"