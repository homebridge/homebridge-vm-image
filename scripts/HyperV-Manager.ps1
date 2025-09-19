# Hyper-V VM management functions

function New-HyperVVM {
    param(
        [string]$VmName,
        [string]$ImagePath,
        [int]$VmRam
    )

    Write-Host "🖥️ Creating Hyper-V VM for ARM64..." -ForegroundColor Cyan

    # Convert raw image to VHDX for Hyper-V
    Write-Host "🔄 Converting raw image to VHDX format..." -ForegroundColor Yellow
    $vhdxPath = $ImagePath -replace '\.img$', '.vhdx'

    try {
        # Method 1: Use Hyper-V's Convert-VHD if available (simplest approach)
        Write-Host "📦 Using simplified VHDX conversion..." -ForegroundColor Yellow

        # Get the size of the raw image
        $imageInfo = Get-Item $ImagePath
        $imageSizeGB = [Math]::Ceiling($imageInfo.Length / 1GB)
        Write-Host "Image size: $imageSizeGB GB" -ForegroundColor Cyan

        # Create a dynamic VHDX (more efficient than fixed)
        Write-Host "💾 Creating dynamic VHDX..." -ForegroundColor Yellow
        $vhd = New-VHD -Path $vhdxPath -SizeBytes ($imageSizeGB * 1GB) -Dynamic

        # Mount the VHDX
        Write-Host "🔧 Mounting VHDX..." -ForegroundColor Yellow
        $mountedVhd = Mount-VHD -Path $vhdxPath -Passthru
        $disk = Get-Disk | Where-Object { $_.Location -eq $vhdxPath }
        $diskNumber = $disk.Number

        Write-Host "📋 Copying raw image to disk $diskNumber..." -ForegroundColor Yellow

        # Use direct disk write (faster than stream copy)
        $destPath = "\\\\.\\PhysicalDrive$diskNumber"

        # Copy the raw image data directly to the physical disk
        $copyCommand = "cmd /c type `"$ImagePath`" > `"$destPath`""

        # Alternative: Use PowerShell streaming
        $source = [System.IO.File]::OpenRead($ImagePath)
        $dest = [System.IO.File]::OpenWrite($destPath)

        try {
            Write-Host "Copying image data (this may take a few minutes)..." -ForegroundColor Yellow
            $buffer = New-Object byte[] (64MB)  # Larger buffer for faster copy
            $totalBytes = $source.Length
            $copiedBytes = 0
            $lastPercent = 0

            while ($copiedBytes -lt $totalBytes) {
                $bytesRead = $source.Read($buffer, 0, $buffer.Length)
                if ($bytesRead -eq 0) { break }
                $dest.Write($buffer, 0, $bytesRead)
                $copiedBytes += $bytesRead

                $percentComplete = [Math]::Floor(($copiedBytes / $totalBytes) * 100)
                if ($percentComplete -ne $lastPercent -and $percentComplete % 10 -eq 0) {
                    Write-Host "  Progress: $percentComplete%" -ForegroundColor Cyan
                    $lastPercent = $percentComplete
                }
            }
            Write-Host "  Progress: 100%" -ForegroundColor Green
        } finally {
            $source.Close()
            $dest.Close()
        }

        # Dismount the VHDX
        Write-Host "🔓 Dismounting VHDX..." -ForegroundColor Yellow
        Dismount-VHD -Path $vhdxPath

    } catch {
        Write-Host "❌ Failed to convert image to VHDX: $_" -ForegroundColor Red
        if (Test-Path $vhdxPath) {
            try { Dismount-VHD -Path $vhdxPath -ErrorAction SilentlyContinue } catch {}
            Remove-Item $vhdxPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }

    Write-Host "✅ Successfully converted image to VHDX" -ForegroundColor Green

    # Create VM - ARM64 Hyper-V requires Generation 2 VMs
    Write-Host "🔧 Creating Generation 2 VM for ARM64..." -ForegroundColor Yellow
    $vm = New-VM -Name $VmName -MemoryStartupBytes ($VmRam * 1MB) -Generation 2 -BootDevice VHD

    # Attach the VHDX to the VM
    Write-Host "💾 Attaching VHDX to VM..." -ForegroundColor Yellow
    Add-VMHardDiskDrive -VMName $VmName -Path $vhdxPath

    # Configure VM settings
    Set-VM -Name $VmName -ProcessorCount 2
    Set-VMFirmware -VMName $VmName -EnableSecureBoot Off  # Disable secure boot for custom Linux image
    Set-VMProcessor -VMName $VmName -ExposeVirtualizationExtensions $false

    # Add network adapter
    Write-Host "🌐 Configuring network adapter..." -ForegroundColor Yellow
    $switch = Get-VMSwitch | Where-Object { $_.SwitchType -eq "External" } | Select-Object -First 1
    if (-not $switch) {
        # Try to find or create a Default Switch
        $switch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
        if (-not $switch) {
            Write-Host "⚠️ No external virtual switch found, creating Default Switch..." -ForegroundColor Yellow
            New-VMSwitch -Name "Default Switch" -SwitchType Internal
            $switch = Get-VMSwitch -Name "Default Switch"
        }
    }

    # Remove default network adapter and add a new one
    Get-VMNetworkAdapter -VMName $VmName | Remove-VMNetworkAdapter
    Add-VMNetworkAdapter -VMName $VmName -SwitchName $switch.Name

    Write-Host "✅ ARM64 VM created and configured successfully!" -ForegroundColor Green
    Write-Host "📁 VHDX Path: $vhdxPath" -ForegroundColor Cyan
    return $VmName
}

function Start-HyperVVM {
    param([string]$VmName)

    Write-Host "▶️ Starting Hyper-V VM..." -ForegroundColor Green

    try {
        Start-VM -Name $VmName -ErrorAction Stop

        # Give VM time to initialize
        Start-Sleep -Seconds 3

        # Check VM state
        $vm = Get-VM -Name $VmName
        Write-Host "✅ VM started - State: $($vm.State)" -ForegroundColor Green
        Write-Host "📊 VM Details:" -ForegroundColor Cyan
        Write-Host "  - CPUs: $($vm.ProcessorCount)" -ForegroundColor Gray
        Write-Host "  - RAM: $($vm.MemoryStartup/1MB)MB" -ForegroundColor Gray
        Write-Host "  - Generation: $($vm.Generation)" -ForegroundColor Gray

        # Check network adapter
        $netAdapter = Get-VMNetworkAdapter -VMName $VmName
        Write-Host "🌐 Network Adapter:" -ForegroundColor Cyan
        Write-Host "  - Switch: $($netAdapter.SwitchName)" -ForegroundColor Gray
        Write-Host "  - Connected: $($netAdapter.Connected)" -ForegroundColor Gray
        Write-Host "  - MAC: $($netAdapter.MacAddress)" -ForegroundColor Gray

        # Check disk
        $disk = Get-VMHardDiskDrive -VMName $VmName
        if ($disk) {
            Write-Host "💾 Disk:" -ForegroundColor Cyan
            Write-Host "  - Path: $($disk.Path)" -ForegroundColor Gray
            Write-Host "  - Controller: $($disk.ControllerType)" -ForegroundColor Gray
        }

        Write-Host "⏳ Waiting for VM to fully boot (15 seconds)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 15

    } catch {
        Write-Host "❌ Failed to start VM: $_" -ForegroundColor Red
        throw
    }
}

function Get-HyperVVMState {
    param([string]$VmName)

    $vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
    return $vm.State
}

function Get-HyperVVMIP {
    param(
        [string]$VmName,
        [int]$Timeout = 300
    )

    Write-Host "🔍 Attempting to get VM IP address..." -ForegroundColor Yellow
    Write-Host "💡 Note: Linux VMs need hyperv-daemons for IP detection via Integration Services" -ForegroundColor Yellow

    $startTime = Get-Date
    $checkCount = 0

    while ((Get-Date) -lt $startTime.AddSeconds($Timeout)) {
        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
        $checkCount++

        # Check VM state first
        $vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
        if (-not $vm) {
            Write-Host "❌ VM not found!" -ForegroundColor Red
            return $null
        }

        if ($vm.State -ne "Running") {
            Write-Host "⚠️ VM is not running (State: $($vm.State))" -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            continue
        }

        # Show VM heartbeat status (indicates if integration services are working)
        if ($checkCount % 6 -eq 1) {  # Show every 30 seconds
            Write-Host "💓 VM Heartbeat: $($vm.Heartbeat)" -ForegroundColor Cyan
            if ($vm.Heartbeat -eq "OkApplicationsUnknown" -or $vm.Heartbeat -eq "OkApplicationsHealthy") {
                Write-Host "  Integration Services detected!" -ForegroundColor Green
            } else {
                Write-Host "  Integration Services not responding (may need hyperv-daemons package)" -ForegroundColor Yellow
            }
        }

        # Method 1: Try Integration Services (requires hyperv-daemons in Linux)
        try {
            $networks = Get-VMNetworkAdapter -VMName $VmName | Select-Object -ExpandProperty IPAddresses -ErrorAction SilentlyContinue
            if ($networks) {
                $ipv4 = $networks | Where-Object {
                    $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' -and
                    $_ -notmatch '^169\.254' -and
                    $_ -ne '127.0.0.1'
                } | Select-Object -First 1

                if ($ipv4) {
                    Write-Host "✅ VM obtained IP via Integration Services: $ipv4" -ForegroundColor Green
                    return $ipv4
                }
            }
        } catch {
            # Integration services not available
        }

        # Method 2: Try ARP cache
        if ($checkCount % 4 -eq 0) {  # Check every 20 seconds
            try {
                $mac = (Get-VMNetworkAdapter -VMName $VmName).MacAddress
                if ($mac) {
                    # Format MAC for ARP lookup
                    $formattedMac = ($mac -replace '(..)', '$1-').TrimEnd('-').ToLower()
                    $arp = arp -a | Select-String $formattedMac
                    if ($arp) {
                        $ip = ($arp -split '\s+')[1]
                        if ($ip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                            Write-Host "✅ VM IP found via ARP: $ip" -ForegroundColor Green
                            return $ip
                        }
                    }
                }
            } catch {}
        }

        # Method 3: For Default Switch, scan known ranges
        $switch = (Get-VMNetworkAdapter -VMName $VmName).SwitchName
        if ($switch -eq "Default Switch" -and $checkCount % 10 -eq 0) {  # Check every 50 seconds
            Write-Host "🔍 Scanning Default Switch IP ranges..." -ForegroundColor Cyan
            $ranges = @("172.17", "172.18", "172.19", "172.20", "172.21", "172.22", "172.23")
            foreach ($range in $ranges) {
                for ($i = 2; $i -le 10; $i++) {
                    $testIP = "$range.0.$i"
                    $ping = Test-Connection -ComputerName $testIP -Count 1 -Quiet -ErrorAction SilentlyContinue
                    if ($ping) {
                        Write-Host "  Found active IP: $testIP - checking if it's our VM..." -ForegroundColor Gray
                        # Verify it's our VM by checking for Homebridge port
                        try {
                            $tcp = Test-NetConnection -ComputerName $testIP -Port 22 -WarningAction SilentlyContinue
                            if ($tcp.TcpTestSucceeded) {
                                Write-Host "✅ VM found via network scan: $testIP" -ForegroundColor Green
                                return $testIP
                            }
                        } catch {}
                    }
                }
            }
        }

        # Progress message
        Write-Host "Still waiting for VM to obtain IP... ($elapsed/$Timeout seconds)" -ForegroundColor Yellow

        # Provide more detailed info every 60 seconds
        if ($elapsed % 60 -eq 0 -and $elapsed -gt 0) {
            Write-Host "🔧 Debug Information:" -ForegroundColor Cyan
            Write-Host "  VM State: $($vm.State)" -ForegroundColor Gray
            Write-Host "  VM Uptime: $($vm.Uptime)" -ForegroundColor Gray
            Write-Host "  Switch: $switch" -ForegroundColor Gray

            # Suggest troubleshooting
            Write-Host "💡 Troubleshooting tips:" -ForegroundColor Yellow
            Write-Host "  1. The Linux image may need 'hyperv-daemons' package installed" -ForegroundColor Gray
            Write-Host "  2. Check if the VM console shows boot errors" -ForegroundColor Gray
            Write-Host "  3. The image may not be compatible with Hyper-V Generation 2" -ForegroundColor Gray
        }

        Start-Sleep -Seconds 5
    }

    Write-Host "⚠️ Timeout waiting for VM IP address after ${Timeout}s" -ForegroundColor Yellow
    Write-Host "💡 The VM may have booted but without Integration Services we cannot detect its IP" -ForegroundColor Yellow
    Write-Host "💡 Consider installing hyperv-daemons in the image during build" -ForegroundColor Yellow

    # Return a fallback IP if we're reasonably sure the VM is running
    if ($vm.State -eq "Running" -and $vm.Uptime.TotalSeconds -gt 30) {
        Write-Host "🎯 Attempting fallback: Assuming VM is at Default Switch gateway range" -ForegroundColor Yellow
        # Try common Default Switch IPs
        $fallbackIPs = @("172.17.0.2", "172.18.0.2", "172.19.0.2")
        foreach ($ip in $fallbackIPs) {
            $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue
            if ($ping) {
                Write-Host "🎯 Using fallback IP: $ip (unverified)" -ForegroundColor Yellow
                return $ip
            }
        }
    }

    return $null
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
