# Hyper-V VM management functions

function New-HyperVVM {
    param(
        [string]$VmName,
        [string]$ImagePath,
        [int]$VmRam
    )
    
    Write-Host "🖥️ Creating Hyper-V VM for ARM64..." -ForegroundColor Cyan
    
    # Note: ARM64 VM testing with Hyper-V requires additional setup
    Write-Host "⚠️ ARM64 VM testing with Hyper-V requires manual disk conversion" -ForegroundColor Yellow
    Write-Host "The raw .img format needs to be converted to VHD for Hyper-V usage" -ForegroundColor Yellow
    
    # Create VM - ARM64 Hyper-V requires Generation 2 VMs
    New-VM -Name $VmName -MemoryStartupBytes ($VmRam * 1MB) -Generation 2
    
    # Configure VM
    Set-VM -Name $VmName -ProcessorCount 1
    
    Write-Host "✅ ARM64 VM created successfully (disk attachment requires additional tools)" -ForegroundColor Green
    return $VmName
}

function Start-HyperVVM {
    param([string]$VmName)
    
    Write-Host "▶️ Starting Hyper-V VM..." -ForegroundColor Green
    Start-VM -Name $VmName
}

function Get-HyperVVMState {
    param([string]$VmName)
    
    $vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
    return $vm.State
}

function Cleanup-HyperVVM {
    param([string]$VmName)
    
    $vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
    if ($vm) {
        if ($vm.State -eq "Running") {
            Stop-VM -Name $VmName -Force
            Start-Sleep -Seconds 2
        }
        Remove-VM -Name $VmName -Force
        Write-Host "🗑️ Hyper-V VM $VmName removed" -ForegroundColor Green
    }
}
