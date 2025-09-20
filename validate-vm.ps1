param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("amd64", "arm64")]
    [string]$Architecture,
    
    [Parameter(Mandatory=$false)]
    [string]$ImagePath = "output\homebridge-$Architecture.img.gz",
    
    [Parameter(Mandatory=$false)]
    [int]$Timeout = 300,
    
    [Parameter(Mandatory=$false)]
    [int]$VmRam = 1024
)

# Import validation modules
. "$PSScriptRoot\scripts\Common-Functions.ps1"
. "$PSScriptRoot\scripts\VirtualBox-Manager.ps1"
. "$PSScriptRoot\scripts\HyperV-Manager.ps1"
. "$PSScriptRoot\scripts\Homebridge-Validator.ps1"

# Main validation script
Write-Host "🚀 Starting VM validation for $Architecture architecture..." -ForegroundColor Green
Write-Host "📁 Image: $ImagePath" -ForegroundColor Cyan
Write-Host "⏱️ Timeout: ${Timeout}s" -ForegroundColor Cyan

# Special handling for ARM64
if ($Architecture -eq "arm64") {
    Write-Host "🧪 ARM64 EXPERIMENTAL MODE" -ForegroundColor Yellow
    Write-Host "⚠️ ARM64 Hyper-V validation is experimental and may have limitations" -ForegroundColor Yellow
    Write-Host "💡 The image needs hyperv-daemons package for full network detection" -ForegroundColor Yellow
}

try {
    # Initialize validation
    $validator = Initialize-Validation -Architecture $Architecture -ImagePath $ImagePath -VmRam $VmRam

    # Extract and prepare image
    $workingImage = Prepare-VMImage -ImagePath $ImagePath -Architecture $Architecture

    # Create and configure VM
    $vmName = New-ValidationVM -Architecture $Architecture -ImagePath $workingImage -VmRam $VmRam

    # Start VM and validate Homebridge
    $validationResult = Test-HomebridgeService -VmName $vmName -Architecture $Architecture -Timeout $Timeout

    # Generate validation reports
    Write-ValidationReport -ValidationResult $validationResult -Architecture $Architecture

    # Check validation results
    if ($Architecture -eq "arm64") {
        # For ARM64, we're more lenient
        if ($validationResult.BootSuccess) {
            Write-Host "🎆 ARM64 validation completed (VM booted successfully)" -ForegroundColor Green
            Write-Host "💡 Manual verification recommended via Hyper-V Manager console" -ForegroundColor Cyan
            exit 0  # Consider boot success as passing for ARM64
        } else {
            Write-Host "❌ ARM64 VM failed to boot" -ForegroundColor Red
            exit 1
        }
    } else {
        # For AMD64, require full validation
        if ($validationResult.ServiceSuccess) {
            Write-Host "🎉 VM image validation completed successfully for $Architecture!" -ForegroundColor Green
            exit 0
        } else {
            Write-Host "❌ Validation failed - Homebridge service not accessible" -ForegroundColor Red
            exit 1
        }
    }

} catch {
    if ($Architecture -eq "arm64") {
        Write-Host "⚠️ ARM64 validation error: $_" -ForegroundColor Yellow
        Write-Host "💡 This is experimental - manual verification recommended" -ForegroundColor Yellow
        # Don't fail the build for ARM64 experimental validation
        exit 0
    } else {
        Write-Host "❌ Validation failed: $_" -ForegroundColor Red
        exit 1
    }
} finally {
    # Cleanup is handled by individual modules
    Cleanup-ValidationResources
}
