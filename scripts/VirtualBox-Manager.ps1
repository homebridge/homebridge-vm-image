# VirtualBox VM management functions

function New-VirtualBoxVM {
    param(
        [string]$VmName,
        [string]$ImagePath,
        [int]$VmRam
    )
    
    Write-Host "🖥️ Creating VirtualBox VM..." -ForegroundColor Cyan
    
    # Create VM
    VBoxManage createvm --name $VmName --ostype "Linux_64" --register
    
    # Configure VM
    VBoxManage modifyvm $VmName --memory $VmRam --cpus 1
    VBoxManage modifyvm $VmName --nic1 nat
    VBoxManage modifyvm $VmName --natpf1 "ssh,tcp,,2222,,22"
    VBoxManage modifyvm $VmName --natpf1 "web,tcp,,8581,,8581"
    VBoxManage modifyvm $VmName --uart1 0x3F8 4
    VBoxManage modifyvm $VmName --uartmode1 file vm-console.log
    
    # Convert and attach disk
    $vdiPath = Convert-ImageToVDI -ImagePath $ImagePath
    Attach-VirtualBoxDisk -VmName $VmName -DiskPath $vdiPath
    
    return $VmName
}

function Convert-ImageToVDI {
    param([string]$ImagePath)
    
    Write-Host "🔄 Converting disk image to VDI format..." -ForegroundColor Cyan
    $vdiPath = $ImagePath -replace '\.(img|raw)$', '.vdi'
    
    try {
        VBoxManage convertfromraw $ImagePath $vdiPath --format VDI
        if (Test-Path $vdiPath) {
            Write-Host "✅ Successfully converted to VDI format" -ForegroundColor Green
            return $vdiPath
        } else {
            throw "VDI conversion failed - file not created"
        }
    } catch {
        throw "Failed to convert disk image to VDI format: $_"
    }
}

function Attach-VirtualBoxDisk {
    param(
        [string]$VmName,
        [string]$DiskPath
    )
    
    Write-Host "💾 Attaching VDI disk image..." -ForegroundColor Cyan
    VBoxManage storagectl $VmName --name "SATA" --add sata --bootable on
    VBoxManage storageattach $VmName --storagectl "SATA" --port 0 --device 0 --type hdd --medium $DiskPath
}

function Start-VirtualBoxVM {
    param([string]$VmName)
    
    Write-Host "▶️ Starting VirtualBox VM..." -ForegroundColor Green
    VBoxManage startvm $VmName --type headless
}

function Get-VirtualBoxVMState {
    param([string]$VmName)
    
    $vmState = VBoxManage showvminfo $VmName --machinereadable | Select-String "VMState=" | ForEach-Object { $_.ToString().Split('=')[1].Trim('"') }
    return $vmState
}

function Cleanup-VirtualBoxVM {
    param([string]$VmName)
    
    VBoxManage controlvm $VmName poweroff 2>$null
    Start-Sleep -Seconds 2
    VBoxManage unregistervm $VmName --delete 2>$null
    Write-Host "🗑️ VirtualBox VM $VmName removed" -ForegroundColor Green
}
