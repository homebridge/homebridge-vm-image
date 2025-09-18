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
    Write-ValidationReport -Result $validationResult -Architecture $Architecture
    
    Write-Host "🎉 VM image validation completed successfully for $Architecture!" -ForegroundColor Green
    exit 0
    
} catch {
    Write-Host "❌ Validation failed: $_" -ForegroundColor Red
    exit 1
} finally {
    # Cleanup is handled by individual modules
    Cleanup-ValidationResources
}
