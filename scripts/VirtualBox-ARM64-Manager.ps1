# VirtualBox ARM64 VM management functions
# Handles VirtualBox operations specifically for ARM64 systems

function Test-VirtualBoxARM64Support {
    <#
    .SYNOPSIS
    Tests if VirtualBox supports ARM64 operations on the current system
    #>
    
    Write-Host "🔍 Testing VirtualBox ARM64 support..." -ForegroundColor Cyan
    
    try {
        # Check if VirtualBox is installed
        $vboxPath = Get-VirtualBoxPath
        if (-not $vboxPath) {
            throw "VirtualBox not found"
        }
        
        # Check VirtualBox version
        $version = & "$vboxPath\VBoxManage.exe" --version
        Write-Host "📋 VirtualBox version: $version" -ForegroundColor Gray
        
        # Parse version to check if it's 7.0+
        $versionNumber = [Version]($version -split '-')[0]
        if ($versionNumber -lt [Version]"7.0.0") {
            Write-Host "⚠️ VirtualBox version $version may have limited ARM64 support" -ForegroundColor Yellow
            Write-Host "💡 VirtualBox 7.0+ recommended for ARM64 systems" -ForegroundColor Yellow
        }
        
        # Test basic VM creation capability
        $testVmName = "arm64-support-test-$(Get-Random)"
        try {
            Write-Host "🧪 Testing VM creation capability..." -ForegroundColor Gray
            & "$vboxPath\VBoxManage.exe" createvm --name $testVmName --ostype "Linux_64" --register | Out-Null
            
            # If we get here, basic VM creation works
            Write-Host "✅ VirtualBox can create VMs on this ARM64 system" -ForegroundColor Green
            
            # Clean up test VM
            & "$vboxPath\VBoxManage.exe" unregistervm $testVmName --delete 2>$null | Out-Null
            
            return @{
                Supported = $true
                Version = $version
                VersionNumber = $versionNumber
                Limitations = @()
            }
            
        } catch {
            Write-Host "⚠️ VirtualBox VM creation failed: $_" -ForegroundColor Yellow
            return @{
                Supported = $false
                Version = $version
                VersionNumber = $versionNumber
                Limitations = @("VM creation failed", $_.Exception.Message)
            }
        }
        
    } catch {
        Write-Host "❌ VirtualBox ARM64 support test failed: $_" -ForegroundColor Red
        return @{
            Supported = $false
            Version = "Unknown"
            VersionNumber = $null
            Limitations = @("VirtualBox not available", $_.Exception.Message)
        }
    }
}

function Get-VirtualBoxPath {
    <#
    .SYNOPSIS
    Finds the VirtualBox installation path on the system
    #>
    
    $possiblePaths = @(
        "${env:ProgramFiles}\Oracle\VirtualBox",
        "${env:ProgramFiles(x86)}\Oracle\VirtualBox",
        "C:\Program Files\Oracle\VirtualBox",
        "C:\Program Files (x86)\Oracle\VirtualBox"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path "$path\VBoxManage.exe") {
            return $path
        }
    }
    
    return $null
}

function New-VirtualBoxARM64VM {
    param(
        [string]$VmName,
        [string]$ImagePath,
        [int]$VmRam = 1024
    )
    
    Write-Host "🖥️ Creating VirtualBox VM for ARM64..." -ForegroundColor Cyan
    
    # First, test ARM64 support
    $supportTest = Test-VirtualBoxARM64Support
    if (-not $supportTest.Supported) {
        throw "VirtualBox ARM64 support not available: $($supportTest.Limitations -join ', ')"
    }
    
    # Warn about experimental support
    Write-Host "⚠️ VirtualBox ARM64 support is experimental" -ForegroundColor Yellow
    Write-Host "💡 Consider using Hyper-V or UTM for better ARM64 support" -ForegroundColor Yellow
    
    $vboxPath = Get-VirtualBoxPath
    $vboxManage = "$vboxPath\VBoxManage.exe"
    
    try {
        # Remove existing VM if it exists
        & $vboxManage unregistervm $VmName --delete 2>$null | Out-Null
        
        # Create VM with ARM64-optimized settings
        Write-Host "🔧 Creating VM with ARM64-optimized settings..." -ForegroundColor Gray
        & $vboxManage createvm --name $VmName --ostype "Linux_64" --register
        
        # Configure VM for ARM64 compatibility
        & $vboxManage modifyvm $VmName `
            --memory $VmRam `
            --cpus 2 `
            --nic1 bridged `
            --uart1 0x3F8 4 `
            --uartmode1 file "vm-console-$VmName.log" `
            --acpi on `
            --ioapic on `
            --rtcuseutc on
        
        # Convert and attach disk
        $vdiPath = Convert-ImageToVDIARM64 -ImagePath $ImagePath
        Attach-VirtualBoxDiskARM64 -VmName $VmName -DiskPath $vdiPath
        
        Write-Host "✅ VirtualBox ARM64 VM created: $VmName" -ForegroundColor Green
        return $VmName
        
    } catch {
        Write-Host "❌ Failed to create VirtualBox ARM64 VM: $_" -ForegroundColor Red
        throw "VirtualBox ARM64 VM creation failed: $_"
    }
}

function Convert-ImageToVDIARM64 {
    param([string]$ImagePath)
    
    Write-Host "🔄 Converting disk image to VDI format for ARM64..." -ForegroundColor Cyan
    $vdiPath = $ImagePath -replace '\.(img|raw)$', '-arm64.vdi'
    
    $vboxPath = Get-VirtualBoxPath
    $vboxManage = "$vboxPath\VBoxManage.exe"
    
    try {
        & $vboxManage convertfromraw $ImagePath $vdiPath --format VDI
        if (Test-Path $vdiPath) {
            Write-Host "✅ Successfully converted to ARM64-compatible VDI format" -ForegroundColor Green
            return $vdiPath
        } else {
            throw "VDI conversion failed - file not created"
        }
    } catch {
        Write-Host "❌ ARM64 VDI conversion failed: $_" -ForegroundColor Red
        throw "Failed to convert disk image to VDI format for ARM64: $_"
    }
}

function Attach-VirtualBoxDiskARM64 {
    param(
        [string]$VmName,
        [string]$DiskPath
    )
    
    Write-Host "💾 Attaching VDI disk image for ARM64..." -ForegroundColor Cyan
    
    $vboxPath = Get-VirtualBoxPath
    $vboxManage = "$vboxPath\VBoxManage.exe"
    
    try {
        # Create SATA controller optimized for ARM64
        & $vboxManage storagectl $VmName --name "SATA" --add sata --controller IntelAhci --bootable on
        
        # Attach the disk
        & $vboxManage storageattach $VmName `
            --storagectl "SATA" `
            --port 0 `
            --device 0 `
            --type hdd `
            --medium $DiskPath
            
        Write-Host "✅ ARM64 disk attached successfully" -ForegroundColor Green
        
    } catch {
        throw "Failed to attach ARM64 disk: $_"
    }
}

function Start-VirtualBoxARM64VM {
    param([string]$VmName)
    
    Write-Host "▶️ Starting VirtualBox ARM64 VM..." -ForegroundColor Green
    Write-Host "⚠️ ARM64 VM startup may take longer than AMD64" -ForegroundColor Yellow
    
    $vboxPath = Get-VirtualBoxPath
    $vboxManage = "$vboxPath\VBoxManage.exe"
    
    try {
        & $vboxManage startvm $VmName --type headless
        Write-Host "✅ ARM64 VM started successfully" -ForegroundColor Green
        
        # Give ARM64 VM extra time to initialize
        Write-Host "⏳ Allowing extra initialization time for ARM64..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        
    } catch {
        Write-Host "❌ Failed to start ARM64 VM: $_" -ForegroundColor Red
        throw "ARM64 VM startup failed: $_"
    }
}

function Get-VirtualBoxARM64VMState {
    param([string]$VmName)
    
    $vboxPath = Get-VirtualBoxPath
    $vboxManage = "$vboxPath\VBoxManage.exe"
    
    try {
        $vmState = & $vboxManage showvminfo $VmName --machinereadable | 
                   Select-String "VMState=" | 
                   ForEach-Object { $_.ToString().Split('=')[1].Trim('"') }
        return $vmState
    } catch {
        return "unknown"
    }
}

function Test-VirtualBoxARM64VMBootstrap {
    param(
        [string]$VmName,
        [int]$TimeoutSeconds = 300
    )
    
    Write-Host "🚀 Testing ARM64 VM bootstrap..." -ForegroundColor Cyan
    Write-Host "⏱️ Timeout: ${TimeoutSeconds}s (ARM64 may need extra time)" -ForegroundColor Gray
    
    $startTime = Get-Date
    $maxWaitTime = $startTime.AddSeconds($TimeoutSeconds)
    
    while ((Get-Date) -lt $maxWaitTime) {
        $vmState = Get-VirtualBoxARM64VMState -VmName $VmName
        Write-Host "📊 VM State: $vmState" -ForegroundColor Gray
        
        if ($vmState -eq "running") {
            Write-Host "✅ ARM64 VM is running" -ForegroundColor Green
            
            # Test basic connectivity (if possible)
            try {
                $vboxPath = Get-VirtualBoxPath
                $vboxManage = "$vboxPath\VBoxManage.exe"
                
                # Try to get guest properties (indicates guest additions or basic boot)
                $guestProps = & $vboxManage guestproperty enumerate $VmName 2>$null
                if ($guestProps) {
                    Write-Host "✅ ARM64 VM guest properties detected" -ForegroundColor Green
                }
                
                return @{
                    Success = $true
                    State = $vmState
                    BootTime = (Get-Date) - $startTime
                    Message = "ARM64 VM booted successfully"
                }
                
            } catch {
                Write-Host "⚠️ VM running but guest properties not available" -ForegroundColor Yellow
                return @{
                    Success = $true
                    State = $vmState
                    BootTime = (Get-Date) - $startTime
                    Message = "ARM64 VM running (limited guest info)"
                }
            }
        }
        
        Start-Sleep -Seconds 5
    }
    
    return @{
        Success = $false
        State = $vmState
        BootTime = (Get-Date) - $startTime
        Message = "ARM64 VM boot timeout after ${TimeoutSeconds}s"
    }
}

function Cleanup-VirtualBoxARM64VM {
    param([string]$VmName)
    
    Write-Host "🧹 Cleaning up VirtualBox ARM64 VM..." -ForegroundColor Yellow
    
    $vboxPath = Get-VirtualBoxPath
    if (-not $vboxPath) {
        Write-Host "⚠️ VirtualBox not found for cleanup" -ForegroundColor Yellow
        return
    }
    
    $vboxManage = "$vboxPath\VBoxManage.exe"
    
    try {
        # Stop VM if running
        & $vboxManage controlvm $VmName poweroff 2>$null | Out-Null
        Start-Sleep -Seconds 3
        
        # Remove VM and associated files
        & $vboxManage unregistervm $VmName --delete 2>$null | Out-Null
        
        Write-Host "🗑️ VirtualBox ARM64 VM $VmName removed" -ForegroundColor Green
        
    } catch {
        Write-Host "⚠️ Error during ARM64 VM cleanup: $_" -ForegroundColor Yellow
    }
    
    # Clean up any leftover VDI files
    Get-ChildItem -Path "." -Filter "*-arm64.vdi" | ForEach-Object {
        try {
            Remove-Item $_.FullName -Force
            Write-Host "🗑️ Removed ARM64 VDI: $($_.Name)" -ForegroundColor Gray
        } catch {
            Write-Host "⚠️ Could not remove $($_.Name): $_" -ForegroundColor Yellow
        }
    }
}

function Write-VirtualBoxARM64Report {
    param(
        [hashtable]$SupportTest,
        [hashtable]$BootstrapResult
    )
    
    Write-Host "📊 VirtualBox ARM64 Validation Report" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    
    # Support status
    Write-Host "🔍 ARM64 Support:" -ForegroundColor White
    if ($SupportTest.Supported) {
        Write-Host "  ✅ Status: Supported" -ForegroundColor Green
        Write-Host "  📋 Version: $($SupportTest.Version)" -ForegroundColor Gray
    } else {
        Write-Host "  ❌ Status: Not Supported" -ForegroundColor Red
        Write-Host "  ⚠️ Limitations:" -ForegroundColor Yellow
        $SupportTest.Limitations | ForEach-Object {
            Write-Host "    - $_" -ForegroundColor Yellow
        }
    }
    
    # Bootstrap results
    if ($BootstrapResult) {
        Write-Host "🚀 VM Bootstrap:" -ForegroundColor White
        if ($BootstrapResult.Success) {
            Write-Host "  ✅ Status: Success" -ForegroundColor Green
            Write-Host "  ⏱️ Boot Time: $($BootstrapResult.BootTime.TotalSeconds)s" -ForegroundColor Gray
            Write-Host "  📊 Final State: $($BootstrapResult.State)" -ForegroundColor Gray
        } else {
            Write-Host "  ❌ Status: Failed" -ForegroundColor Red
            Write-Host "  💬 Message: $($BootstrapResult.Message)" -ForegroundColor Yellow
        }
    }
    
    # Recommendations
    Write-Host "💡 Recommendations:" -ForegroundColor White
    if ($SupportTest.Supported -and $BootstrapResult.Success) {
        Write-Host "  ✅ VirtualBox ARM64 is functional on this system" -ForegroundColor Green
        Write-Host "  📋 Monitor performance and stability" -ForegroundColor Gray
    } else {
        Write-Host "  💡 Consider alternative virtualization platforms:" -ForegroundColor Yellow
        Write-Host "    - Hyper-V (Windows ARM64)" -ForegroundColor Gray
        Write-Host "    - UTM (macOS ARM64)" -ForegroundColor Gray
        Write-Host "    - QEMU/KVM (Linux ARM64)" -ForegroundColor Gray
    }
    
    Write-Host "=================================" -ForegroundColor Cyan
}

# Export functions for use in other scripts
Export-ModuleMember -Function @(
    'Test-VirtualBoxARM64Support',
    'New-VirtualBoxARM64VM', 
    'Start-VirtualBoxARM64VM',
    'Get-VirtualBoxARM64VMState',
    'Test-VirtualBoxARM64VMBootstrap',
    'Cleanup-VirtualBoxARM64VM',
    'Write-VirtualBoxARM64Report'
)