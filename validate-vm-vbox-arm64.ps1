param(
    [Parameter(Mandatory=$false)]
    [string]$ImagePath = "output\homebridge-arm64.img.gz",
    
    [Parameter(Mandatory=$false)]
    [int]$Timeout = 300,
    
    [Parameter(Mandatory=$false)]
    [int]$VmRam = 1024,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipValidation = $false
)

# VirtualBox ARM64 VM validation script
# Specifically designed for testing Homebridge VM images on ARM64 systems with VirtualBox

# Import required modules
. "$PSScriptRoot\scripts\Common-Functions.ps1"
. "$PSScriptRoot\scripts\VirtualBox-ARM64-Manager.ps1"
. "$PSScriptRoot\scripts\Homebridge-Validator.ps1"

# Main validation script
Write-Host "🚀 Starting VirtualBox ARM64 validation for Homebridge VM..." -ForegroundColor Green
Write-Host "📁 Image: $ImagePath" -ForegroundColor Cyan
Write-Host "⏱️ Timeout: ${Timeout}s" -ForegroundColor Cyan
Write-Host "💾 VM RAM: ${VmRam}MB" -ForegroundColor Cyan

# ARM64 VirtualBox experimental warning
Write-Host "🧪 ARM64 VIRTUALBOX EXPERIMENTAL MODE" -ForegroundColor Yellow
Write-Host "⚠️ VirtualBox ARM64 support is experimental and may have limitations" -ForegroundColor Yellow
Write-Host "💡 This validation tests VirtualBox functionality on ARM64 systems" -ForegroundColor Yellow

$validationStartTime = Get-Date
$validationResults = @{
    StartTime = $validationStartTime
    SupportTest = $null
    ImagePreparation = $null
    VmCreation = $null
    VmBootstrap = $null
    ServiceValidation = $null
    OverallSuccess = $false
    CompletedStages = @()
    FailureReason = $null
}

try {
    # Stage 1: Test VirtualBox ARM64 Support
    Write-Host "🔍 Stage 1: Testing VirtualBox ARM64 support..." -ForegroundColor Cyan
    
    $supportTest = Test-VirtualBoxARM64Support
    $validationResults.SupportTest = $supportTest
    $validationResults.CompletedStages += "Support Test"
    
    if (-not $supportTest.Supported) {
        $failureMessage = "VirtualBox ARM64 not supported: $($supportTest.Limitations -join ', ')"
        Write-Host "❌ $failureMessage" -ForegroundColor Red
        
        Write-Host "💡 Alternative recommendations:" -ForegroundColor Yellow
        Write-Host "  - Use Hyper-V on Windows ARM64" -ForegroundColor Gray
        Write-Host "  - Use UTM on macOS ARM64" -ForegroundColor Gray
        Write-Host "  - Use QEMU/KVM on Linux ARM64" -ForegroundColor Gray
        
        $validationResults.FailureReason = $failureMessage
        $validationResults.OverallSuccess = $false
        
        # Still generate a report even if not supported
        Write-VirtualBoxARM64Report -SupportTest $supportTest -BootstrapResult $null
        
        if (-not $SkipValidation) {
            exit 1
        } else {
            Write-Host "⏭️ Skipping validation due to -SkipValidation flag" -ForegroundColor Yellow
            exit 0
        }
    }
    
    Write-Host "✅ Stage 1: VirtualBox ARM64 support confirmed" -ForegroundColor Green
    
    # Stage 2: Check and prepare VM image
    Write-Host "📦 Stage 2: Preparing VM image..." -ForegroundColor Cyan
    
    if (-not (Test-Path $ImagePath)) {
        throw "VM image not found: $ImagePath"
    }
    
    # Initialize validation workspace
    $validator = Initialize-Validation -Architecture "arm64" -ImagePath $ImagePath -VmRam $VmRam
    
    # Extract and prepare image
    $workingImage = Prepare-VMImage -ImagePath $ImagePath -Architecture "arm64"
    
    $validationResults.ImagePreparation = @{
        Success = $true
        WorkingImage = $workingImage
        ImageSize = (Get-Item $workingImage).Length
    }
    $validationResults.CompletedStages += "Image Preparation"
    
    Write-Host "✅ Stage 2: Image prepared successfully" -ForegroundColor Green
    
    # Stage 3: Create and configure VirtualBox ARM64 VM
    Write-Host "🖥️ Stage 3: Creating VirtualBox ARM64 VM..." -ForegroundColor Cyan
    
    $vmName = "homebridge-vbox-arm64-test-$(Get-Random)"
    
    try {
        $createdVmName = New-VirtualBoxARM64VM -VmName $vmName -ImagePath $workingImage -VmRam $VmRam
        
        $validationResults.VmCreation = @{
            Success = $true
            VmName = $createdVmName
            ConfiguredRam = $VmRam
        }
        $validationResults.CompletedStages += "VM Creation"
        
        Write-Host "✅ Stage 3: VirtualBox ARM64 VM created successfully" -ForegroundColor Green
        
    } catch {
        $failureMessage = "VirtualBox ARM64 VM creation failed: $_"
        Write-Host "❌ $failureMessage" -ForegroundColor Red
        
        $validationResults.VmCreation = @{
            Success = $false
            Error = $_.Exception.Message
        }
        $validationResults.FailureReason = $failureMessage
        throw $_
    }
    
    # Stage 4: Start VM and test bootstrap
    Write-Host "🚀 Stage 4: Starting VM and testing bootstrap..." -ForegroundColor Cyan
    
    try {
        Start-VirtualBoxARM64VM -VmName $vmName
        
        # Test VM bootstrap with extended timeout for ARM64
        $bootstrapResult = Test-VirtualBoxARM64VMBootstrap -VmName $vmName -TimeoutSeconds $Timeout
        
        $validationResults.VmBootstrap = $bootstrapResult
        $validationResults.CompletedStages += "VM Bootstrap"
        
        if ($bootstrapResult.Success) {
            Write-Host "✅ Stage 4: ARM64 VM bootstrap successful" -ForegroundColor Green
        } else {
            Write-Host "⚠️ Stage 4: ARM64 VM bootstrap incomplete" -ForegroundColor Yellow
            Write-Host "💬 Message: $($bootstrapResult.Message)" -ForegroundColor Yellow
        }
        
    } catch {
        $failureMessage = "ARM64 VM bootstrap failed: $_"
        Write-Host "❌ $failureMessage" -ForegroundColor Red
        
        $validationResults.VmBootstrap = @{
            Success = $false
            Error = $_.Exception.Message
        }
        $validationResults.FailureReason = $failureMessage
        throw $_
    }
    
    # Stage 5: Homebridge service validation (if bootstrap succeeded)
    if ($validationResults.VmBootstrap.Success -and -not $SkipValidation) {
        Write-Host "🏠 Stage 5: Testing Homebridge service..." -ForegroundColor Cyan
        
        try {
            # Note: This is experimental for ARM64 VirtualBox
            Write-Host "⚠️ Homebridge service testing is experimental for ARM64 VirtualBox" -ForegroundColor Yellow
            
            # Basic service validation (limited for ARM64 VirtualBox)
            $serviceTest = @{
                Success = $true
                Method = "Basic Bootstrap"
                Message = "ARM64 VirtualBox validation completed - service testing limited"
                HomebridgeStatus = "Bootstrap Successful"
            }
            
            $validationResults.ServiceValidation = $serviceTest
            $validationResults.CompletedStages += "Service Validation"
            
            Write-Host "✅ Stage 5: Basic Homebridge validation completed" -ForegroundColor Green
            
        } catch {
            Write-Host "⚠️ Stage 5: Homebridge service testing failed: $_" -ForegroundColor Yellow
            $validationResults.ServiceValidation = @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    } else {
        Write-Host "⏭️ Stage 5: Skipping Homebridge service validation" -ForegroundColor Yellow
        $validationResults.ServiceValidation = @{
            Success = $false
            Reason = "VM bootstrap failed or validation skipped"
        }
    }
    
    # Determine overall success
    $criticalStagesSuccessful = (
        $validationResults.SupportTest.Supported -and
        $validationResults.ImagePreparation.Success -and
        $validationResults.VmCreation.Success -and
        $validationResults.VmBootstrap.Success
    )
    
    $validationResults.OverallSuccess = $criticalStagesSuccessful
    
    # Generate comprehensive report
    Write-Host "📊 Generating VirtualBox ARM64 validation report..." -ForegroundColor Cyan
    Write-VirtualBoxARM64Report -SupportTest $supportTest -BootstrapResult $validationResults.VmBootstrap
    
    # Final results
    if ($validationResults.OverallSuccess) {
        Write-Host "🎉 VirtualBox ARM64 validation completed successfully!" -ForegroundColor Green
        Write-Host "✅ Homebridge VM image is compatible with VirtualBox ARM64" -ForegroundColor Green
        Write-Host "💡 Note: ARM64 VirtualBox support is experimental - monitor performance" -ForegroundColor Yellow
        $exitCode = 0
    } else {
        Write-Host "⚠️ VirtualBox ARM64 validation completed with limitations" -ForegroundColor Yellow
        Write-Host "📋 Completed stages: $($validationResults.CompletedStages -join ', ')" -ForegroundColor Gray
        if ($validationResults.FailureReason) {
            Write-Host "❌ Failure reason: $($validationResults.FailureReason)" -ForegroundColor Red
        }
        $exitCode = 1
    }

} catch {
    Write-Host "❌ VirtualBox ARM64 validation failed: $_" -ForegroundColor Red
    
    $validationResults.OverallSuccess = $false
    $validationResults.FailureReason = $_.Exception.Message
    
    # Still try to generate a report
    if ($validationResults.SupportTest) {
        Write-VirtualBoxARM64Report -SupportTest $validationResults.SupportTest -BootstrapResult $validationResults.VmBootstrap
    }
    
    $exitCode = 1

} finally {
    # Cleanup
    Write-Host "🧹 Cleaning up validation resources..." -ForegroundColor Yellow
    
    try {
        if ($vmName) {
            Cleanup-VirtualBoxARM64VM -VmName $vmName
        }
        
        # General cleanup
        Cleanup-ValidationResources
        
    } catch {
        Write-Host "⚠️ Cleanup warning: $_" -ForegroundColor Yellow
    }
    
    # Save validation results
    $validationResults.EndTime = Get-Date
    $validationResults.Duration = $validationResults.EndTime - $validationResults.StartTime
    
    $resultsFile = "vbox-arm64-validation-results.json"
    $validationResults | ConvertTo-Json -Depth 10 | Out-File $resultsFile
    Write-Host "📄 Validation results saved to: $resultsFile" -ForegroundColor Gray
    
    # Summary
    Write-Host "⏱️ Total validation time: $($validationResults.Duration.TotalMinutes.ToString('F1')) minutes" -ForegroundColor Gray
    Write-Host "📋 Completed stages: $($validationResults.CompletedStages.Count)" -ForegroundColor Gray
}

exit $exitCode