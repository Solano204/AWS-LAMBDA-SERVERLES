# ============================================
# Lambda Deployment Script - PowerShell
# ============================================

Write-Host "🚀 Lambda Deployment Script" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

# ============================================
# Function: Build Lambda
# ============================================
function Build-Lambda {
    Write-Host "`n📦 Building Lambda JAR..." -ForegroundColor Yellow

    Push-Location lambda\DataTransformationExample

    try {
        mvn clean package
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Build successful!" -ForegroundColor Green
        } else {
            Write-Host "❌ Build failed!" -ForegroundColor Red
            Pop-Location
            exit 1
        }
    } catch {
        Write-Host "❌ Build error: $_" -ForegroundColor Red
        Pop-Location
        exit 1
    }

    Pop-Location
}

# ============================================
# Function: Deploy with Terraform
# ============================================
function Deploy-Terraform {
    Write-Host "`n🔧 Deploying with Terraform..." -ForegroundColor Yellow

    terraform apply -auto-approve

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Deployment successful!" -ForegroundColor Green
        Show-Outputs
    } else {
        Write-Host "❌ Deployment failed!" -ForegroundColor Red
        exit 1
    }
}

# ============================================
# Function: Show Outputs
# ============================================
function Show-Outputs {
    Write-Host "`n📊 Deployment Information:" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    terraform output
}

# ============================================
# Function: Test API
# ============================================
function Test-API {
    Write-Host "`n🧪 Testing API..." -ForegroundColor Yellow

    $apiUrl = (terraform output -raw api_gateway_url)

    $body = @{
        clientName = "Test User"
        clientEmail = "test@example.com"
        clientPassword = "TestPassword123!"
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method POST -Body $body -ContentType "application/json"
        Write-Host "✅ API Test successful!" -ForegroundColor Green
        Write-Host "Response:" -ForegroundColor Cyan
        $response | ConvertTo-Json
    } catch {
        Write-Host "❌ API Test failed!" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

# ============================================
# Function: Show Lambda Info
# ============================================
function Show-LambdaInfo {
    Write-Host "`n📋 Lambda Version Information:" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan

    $functionName = terraform output -raw lambda_function_name

    Write-Host "`nVersions:" -ForegroundColor Yellow
    aws lambda list-versions-by-function --function-name $functionName --query 'Versions[*].[Version,LastModified]' --output table

    Write-Host "`nAliases:" -ForegroundColor Yellow
    aws lambda list-aliases --function-name $functionName --output table
}

# ============================================
# Function: Rollback to Previous Version
# ============================================
function Rollback-Lambda {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Version,

        [Parameter(Mandatory=$false)]
        [string]$Alias = "prod"
    )

    Write-Host "`n⏮️ Rolling back $Alias alias to version $Version..." -ForegroundColor Yellow

    $functionName = terraform output -raw lambda_function_name

    aws lambda update-alias `
        --function-name $functionName `
        --name $Alias `
        --function-version $Version

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Rollback successful! $Alias now points to version $Version" -ForegroundColor Green
    } else {
        Write-Host "❌ Rollback failed!" -ForegroundColor Red
    }
}

# ============================================
# Function: Update Alias to Version
# ============================================
function Update-LambdaAlias {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Alias,

        [Parameter(Mandatory=$true)]
        [string]$Version
    )

    Write-Host "`n🔄 Updating $Alias alias to version $Version..." -ForegroundColor Yellow

    $functionName = terraform output -raw lambda_function_name

    aws lambda update-alias `
        --function-name $functionName `
        --name $Alias `
        --function-version $Version

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Alias updated! $Alias now points to version $Version" -ForegroundColor Green
    } else {
        Write-Host "❌ Update failed!" -ForegroundColor Red
    }
}

# ============================================
# Main Menu
# ============================================
function Show-Menu {
    Write-Host "`n📋 Available Commands:" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "1. Full Deploy (Build + Deploy)"
    Write-Host "2. Build Lambda Only"
    Write-Host "3. Deploy Terraform Only"
    Write-Host "4. Test API"
    Write-Host "5. Show Lambda Info (Versions & Aliases)"
    Write-Host "6. Rollback to Previous Version"
    Write-Host "7. Update Alias to Specific Version"
    Write-Host "8. Exit"
    Write-Host ""
}

# ============================================
# Main Script Logic
# ============================================
if ($args.Length -eq 0) {
    # Interactive mode
    while ($true) {
        Show-Menu
        $choice = Read-Host "Enter your choice (1-8)"

        switch ($choice) {
            "1" {
                Build-Lambda
                Deploy-Terraform
            }
            "2" {
                Build-Lambda
            }
            "3" {
                Deploy-Terraform
            }
            "4" {
                Test-API
            }
            "5" {
                Show-LambdaInfo
            }
            "6" {
                $version = Read-Host "Enter version number to rollback to"
                $alias = Read-Host "Enter alias name (default: prod)"
                if ([string]::IsNullOrWhiteSpace($alias)) { $alias = "prod" }
                Rollback-Lambda -Version $version -Alias $alias
            }
            "7" {
                $alias = Read-Host "Enter alias name"
                $version = Read-Host "Enter version number"
                Update-LambdaAlias -Alias $alias -Version $version
            }
            "8" {
                Write-Host "`n👋 Goodbye!" -ForegroundColor Cyan
                exit 0
            }
            default {
                Write-Host "❌ Invalid choice. Please try again." -ForegroundColor Red
            }
        }

        Write-Host "`nPress any key to continue..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Clear-Host
    }
} else {
    # Command line mode
    switch ($args[0]) {
        "deploy" {
            Build-Lambda
            Deploy-Terraform
        }
        "build" {
            Build-Lambda
        }
        "test" {
            Test-API
        }
        "info" {
            Show-LambdaInfo
        }
        "rollback" {
            if ($args.Length -lt 2) {
                Write-Host "Usage: ./deployment-commands.ps1 rollback <version> [alias]" -ForegroundColor Red
                exit 1
            }
            $version = $args[1]
            $alias = if ($args.Length -ge 3) { $args[2] } else { "prod" }
            Rollback-Lambda -Version $version -Alias $alias
        }
        "update-alias" {
            if ($args.Length -lt 3) {
                Write-Host "Usage: ./deployment-commands.ps1 update-alias <alias> <version>" -ForegroundColor Red
                exit 1
            }
            Update-LambdaAlias -Alias $args[1] -Version $args[2]
        }
        default {
            Write-Host "Unknown command: $($args[0])" -ForegroundColor Red
            Write-Host "`nAvailable commands:" -ForegroundColor Yellow
            Write-Host "  deploy        - Build and deploy"
            Write-Host "  build         - Build Lambda only"
            Write-Host "  test          - Test API"
            Write-Host "  info          - Show Lambda info"
            Write-Host "  rollback      - Rollback to version"
            Write-Host "  update-alias  - Update alias to version"
        }
    }
}