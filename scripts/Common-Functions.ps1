# Common validation functions and utilities

$script:WorkDir = $null
$script:VmName = $null
$script:VmCreated = $false
$script:UseHyperV = $false

function Initialize-Validation {
    param(
        [string]$Architecture,
        [string]$ImagePath,
        [int]$VmRam
    )
    
    # Check if image exists
    if (-not (Test-Path $ImagePath)) {
        throw "VM image not found: $ImagePath"
    }
    
    # Determine virtualization platform
    if ($Architecture -eq "amd64") {
        try {
            $vboxVersion = VBoxManage --version
            Write-Host "✅ VirtualBox version: $vboxVersion" -ForegroundColor Green
            $script:UseHyperV = $false
        } catch {
            throw "VirtualBox not found. Please install VirtualBox."
        }
    } else {
        try {
            $hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
            if ($hyperVFeature.State -eq "Enabled") {
                Write-Host "✅ Hyper-V is enabled for ARM64 testing" -ForegroundColor Green
                $script:UseHyperV = $true
            } else {
                throw "Hyper-V is not enabled. Please enable Hyper-V."
            }
        } catch {
            throw "Hyper-V not available. Please ensure Windows supports Hyper-V."
        }
    }
    
    # Create work directory
    $script:WorkDir = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null
    
    # Generate unique VM name
    $script:VmName = "homebridge-test-$(Get-Random)"
    
    return @{
        WorkDir = $script:WorkDir
        VmName = $script:VmName
        UseHyperV = $script:UseHyperV
    }
}

function Prepare-VMImage {
    param(
        [string]$ImagePath,
        [string]$Architecture
    )
    
    $workImg = "$($script:WorkDir)\homebridge-$Architecture-test.img"
    
    if ($ImagePath.EndsWith(".gz")) {
        Write-Host "📦 Extracting compressed image..." -ForegroundColor Yellow
        
        try {
            Write-Host "Extracting $ImagePath to $($script:WorkDir)..." -ForegroundColor Cyan
            & "C:\Program Files\7-Zip\7z.exe" e $ImagePath -o"$($script:WorkDir)" -y
            
            # Find extracted file
            $extractedFiles = Get-ChildItem -Path $script:WorkDir -File -Force
            if ($extractedFiles.Count -gt 0) {
                $largestFile = ($extractedFiles | Sort-Object Length -Descending)[0]
                $workImg = $largestFile.FullName
                Write-Host "✅ Using extracted file: $($largestFile.Name)" -ForegroundColor Green
            } else {
                throw "No files found after extraction"
            }
        } catch {
            throw "Failed to extract image: $_"
        }
    } else {
        Copy-Item $ImagePath $workImg
    }
    
    return $workImg
}

function Cleanup-ValidationResources {
    Write-Host "🧹 Cleaning up..." -ForegroundColor Yellow
    
    if ($script:VmCreated -and $script:VmName) {
        try {
            if ($script:UseHyperV) {
                Cleanup-HyperVVM -VmName $script:VmName
            } else {
                Cleanup-VirtualBoxVM -VmName $script:VmName
            }
        } catch {
            Write-Host "⚠️ Warning: Could not clean up VM: $_" -ForegroundColor Yellow
        }
    }
    
    # Clean up temporary files
    if ($script:WorkDir -and (Test-Path $script:WorkDir)) {
        Remove-Item -Path $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-ValidationReport {
    param(
        [hashtable]$Result,
        [string]$Architecture
    )
    
    $logContent = @"
# Homebridge VM Validation Report  
# Validation Run: $(Get-Date)
# Architecture: $Architecture
# VM Name: $($script:VmName)

## Validation Results:
VM Boot: $($Result.BootSuccess)
Network: $($Result.NetworkSuccess)
Homebridge Service: $($Result.ServiceSuccess)

## Service Details:
$($Result.ServiceDetails)

## Recommendations:
$($Result.Recommendations)
"@
    
    $logContent | Out-File -FilePath "homebridge-validation-$Architecture.log" -Encoding UTF8
    Write-Host "✅ Created validation log: homebridge-validation-$Architecture.log" -ForegroundColor Green
}
