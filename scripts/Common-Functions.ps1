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
        # For ARM64, check both VirtualBox and Hyper-V options
        $vboxAvailable = $false
        $hyperVAvailable = $false
        
        # Check VirtualBox ARM64 support first
        try {
            $vboxVersion = VBoxManage --version
            Write-Host "✅ VirtualBox version: $vboxVersion (ARM64)" -ForegroundColor Green
            
            # Test if VirtualBox supports ARM64 operations
            $testResult = & { 
                try {
                    VBoxManage createvm --name "arm64-test-$(Get-Random)" --ostype "Linux_64" --register 2>$null
                    VBoxManage unregistervm "arm64-test-$(Get-Random)" --delete 2>$null
                    return $true
                } catch {
                    return $false
                }
            }
            
            if ($testResult) {
                Write-Host "✅ VirtualBox ARM64 support detected" -ForegroundColor Green
                $vboxAvailable = $true
                $script:UseHyperV = $false
            } else {
                Write-Host "⚠️ VirtualBox found but ARM64 support limited" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "⚠️ VirtualBox not available for ARM64" -ForegroundColor Yellow
        }
        
        # Check Hyper-V as fallback
        if (-not $vboxAvailable) {
            try {
                $hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
                if ($hyperVFeature.State -eq "Enabled") {
                    Write-Host "✅ Hyper-V is enabled for ARM64 fallback" -ForegroundColor Green
                    $hyperVAvailable = $true
                    $script:UseHyperV = $true
                } else {
                    Write-Host "⚠️ Hyper-V not enabled" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "⚠️ Hyper-V not available" -ForegroundColor Yellow
            }
        }
        
        # Determine final platform choice
        if (-not $vboxAvailable -and -not $hyperVAvailable) {
            throw "Neither VirtualBox ARM64 nor Hyper-V is available. Please install VirtualBox 7.0+ with ARM64 support or enable Hyper-V."
        }
        
        if ($vboxAvailable) {
            Write-Host "🎯 Using VirtualBox for ARM64 validation" -ForegroundColor Cyan
        } else {
            Write-Host "🎯 Using Hyper-V for ARM64 validation (VirtualBox fallback)" -ForegroundColor Cyan
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
                # Check if this is an ARM64 VirtualBox cleanup
                if ($script:VmName -like "*arm64*" -or $script:VmName -like "*vbox-arm64*") {
                    # Use ARM64-specific cleanup if available
                    if (Get-Command "Cleanup-VirtualBoxARM64VM" -ErrorAction SilentlyContinue) {
                        Cleanup-VirtualBoxARM64VM -VmName $script:VmName
                    } else {
                        Cleanup-VirtualBoxVM -VmName $script:VmName
                    }
                } else {
                    Cleanup-VirtualBoxVM -VmName $script:VmName
                }
            }
        } catch {
            Write-Host "⚠️ Warning: Could not clean up VM: $_" -ForegroundColor Yellow
        }
    }
    
    # Clean up temporary files
    if ($script:WorkDir -and (Test-Path $script:WorkDir)) {
        Remove-Item -Path $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Clean up ARM64-specific artifacts
    Get-ChildItem -Path "." -Filter "*arm64*.vdi" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Force
            Write-Host "🗑️ Cleaned up ARM64 VDI: $($_.Name)" -ForegroundColor Gray
        } catch {
            Write-Host "⚠️ Could not clean up $($_.Name): $_" -ForegroundColor Yellow
        }
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
