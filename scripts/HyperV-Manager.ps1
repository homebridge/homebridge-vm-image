# Hyper-V VM management functions

function New-HyperVVM {
    param(
        [string]$VmName,
        [string]$ImagePath,
        [int]$VmRam
    )

    Write-Host "🖥️ Creating Hyper-V VM for ARM64..." -ForegroundColor Cyan

    # For ARM64, we need special handling
    Write-Host "🔄 Preparing disk image for ARM64 Hyper-V..." -ForegroundColor Yellow
    $vhdxPath = $ImagePath -replace '\.img$', '.vhdx'

    try {
        # Check if qemu-img is available (best option for conversion)
        $qemuPath = "C:\Program Files\qemu\qemu-img.exe"
        if (-not (Test-Path $qemuPath)) {
            # Try to download qemu-img for Windows
            Write-Host "📥 Downloading qemu-img for proper disk conversion..." -ForegroundColor Yellow
            $qemuUrl = "https://qemu.weilnetz.de/w64/qemu-w64-setup-20231224.exe"
            $installerPath = "$env:TEMP\qemu-installer.exe"

            try {
                Invoke-WebRequest -Uri $qemuUrl -OutFile $installerPath -ErrorAction Stop
                Write-Host "📦 Installing qemu-img..." -ForegroundColor Yellow
                Start-Process -FilePath $installerPath -ArgumentList "/S", "/D=C:\Program Files\qemu" -Wait
            } catch {
                Write-Host "⚠️ Could not install qemu-img, using fallback method" -ForegroundColor Yellow
            }
        }

        if (Test-Path $qemuPath) {
            # Use qemu-img for proper conversion
            Write-Host "🎉 Using qemu-img for conversion (best method)..." -ForegroundColor Green
            $process = Start-Process -FilePath $qemuPath -ArgumentList "convert", "-f", "raw", "-O", "vhdx", "`"$ImagePath`"", "`"$vhdxPath`"" -Wait -PassThru -NoNewWindow
            if ($process.ExitCode -ne 0) {
                throw "qemu-img conversion failed with exit code $($process.ExitCode)"
            }
            Write-Host "✅ Successfully converted using qemu-img" -ForegroundColor Green
        } else {
            # Fallback: Simple raw copy to VHDX
            Write-Host "🔧 Using fallback conversion method..." -ForegroundColor Yellow

            # Get image info
            $imageInfo = Get-Item $ImagePath
            $imageSize = $imageInfo.Length

            # For ARM64, we need to ensure the VHDX is properly formatted
            # Create a slightly larger VHDX to ensure all data fits
            $vhdSize = [Math]::Ceiling($imageSize * 1.1 / 1GB) * 1GB
            if ($vhdSize -lt 4GB) { $vhdSize = 4GB }  # Minimum 4GB

            Write-Host "📦 Creating VHDX with size: $($vhdSize / 1GB) GB" -ForegroundColor Yellow

            # Create a fixed VHDX (more compatible with ARM64)
            New-VHD -Path $vhdxPath -SizeBytes $vhdSize -Fixed | Out-Null

            # Direct binary copy
            Write-Host "📋 Performing direct binary copy..." -ForegroundColor Yellow

            # Use certutil for binary copy (built into Windows)
            $tempBin = "$env:TEMP\temp_img.bin"

            # First ensure the image is accessible
            Copy-Item -Path $ImagePath -Destination $tempBin -Force

            # Mount VHD and get disk number
            $vhd = Mount-VHD -Path $vhdxPath -Passthru
            $diskNumber = $vhd.DiskNumber

            try {
                # Initialize the disk without creating partitions (keep raw)
                Write-Host "🗑️ Keeping disk raw for Linux boot..." -ForegroundColor Yellow

                # Get disk path for raw write
                $diskPath = "\\\\.\\PhysicalDrive$diskNumber"

                # Use PowerShell to copy
                Write-Host "📝 Writing image data to disk $diskNumber..." -ForegroundColor Yellow

                $sourceFile = [System.IO.File]::OpenRead($tempBin)
                $destFile = [System.IO.FileStream]::new($diskPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

                try {
                    $buffer = New-Object byte[] (1MB)
                    $totalBytes = $sourceFile.Length
                    $copiedBytes = 0
                    $lastPercent = -1

                    while ($copiedBytes -lt $totalBytes) {
                        $bytesRead = $sourceFile.Read($buffer, 0, $buffer.Length)
                        if ($bytesRead -eq 0) { break }
                        $destFile.Write($buffer, 0, $bytesRead)
                        $copiedBytes += $bytesRead

                        $percent = [Math]::Floor(($copiedBytes / $totalBytes) * 100)
                        if ($percent -ne $lastPercent -and $percent % 5 -eq 0) {
                            Write-Host "  Progress: $percent%" -ForegroundColor Cyan
                            $lastPercent = $percent
                        }
                    }

                    Write-Host "  Progress: 100%" -ForegroundColor Green
                    $destFile.Flush()
                } finally {
                    $sourceFile.Close()
                    $destFile.Close()
                }

            } finally {
                # Dismount the VHD
                Dismount-VHD -Path $vhdxPath
                Remove-Item $tempBin -Force -ErrorAction SilentlyContinue
            }
        }

    } catch {
        Write-Host "❌ Failed to prepare disk: $_" -ForegroundColor Red
        if (Test-Path $vhdxPath) {
            try { Dismount-VHD -Path $vhdxPath -ErrorAction SilentlyContinue } catch {}
            Remove-Item $vhdxPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }

    Write-Host "✅ Disk preparation complete" -ForegroundColor Green

    # Create VM - Try Generation 1 first for better compatibility
    Write-Host "🔧 Creating VM for ARM64..." -ForegroundColor Yellow

    # For ARM64 Windows, we still need Gen 2, but configure it differently
    try {
        # Create Generation 2 VM (required for ARM64)
        $vm = New-VM -Name $VmName -MemoryStartupBytes ($VmRam * 1MB) -Generation 2 -NoVHD

        # Attach the VHDX as SCSI (required for Gen 2)
        Write-Host "💾 Attaching VHDX to VM (SCSI)..." -ForegroundColor Yellow
        Add-VMHardDiskDrive -VMName $VmName -Path $vhdxPath -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0

        # Configure firmware settings for Linux boot
        Write-Host "🔧 Configuring firmware for Linux boot..." -ForegroundColor Yellow
        $bootDisk = Get-VMHardDiskDrive -VMName $VmName | Where-Object {$_.Path -eq $vhdxPath}
        Set-VMFirmware -VMName $VmName -EnableSecureBoot Off
        Set-VMFirmware -VMName $VmName -FirstBootDevice $bootDisk

        # Configure VM
        Set-VM -Name $VmName -ProcessorCount 2 -DynamicMemory -MemoryMinimumBytes (512MB) -MemoryMaximumBytes (2GB)
        Set-VMProcessor -VMName $VmName -ExposeVirtualizationExtensions $false

    } catch {
        Write-Host "❌ Failed to create VM: $_" -ForegroundColor Red
        throw
    }

    # Network configuration
    Write-Host "🌐 Configuring network..." -ForegroundColor Yellow

    # First, check for Default Switch (best for NAT)
    $switch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue

    if (-not $switch) {
        # Look for any External switch
        $switch = Get-VMSwitch | Where-Object { $_.SwitchType -eq "External" } | Select-Object -First 1
    }

    if (-not $switch) {
        # Create an Internal switch with NAT
        Write-Host "🌐 Creating NAT switch for VM..." -ForegroundColor Yellow
        New-VMSwitch -Name "NATSwitch" -SwitchType Internal

        # Configure NAT
        $natIP = "192.168.200.1"
        $natPrefix = "192.168.200.0/24"

        # Add IP to the switch
        $adapter = Get-NetAdapter | Where-Object {$_.Name -like "*NATSwitch*"}
        if ($adapter) {
            New-NetIPAddress -IPAddress $natIP -PrefixLength 24 -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
            New-NetNat -Name "VMNat" -InternalIPInterfaceAddressPrefix $natPrefix -ErrorAction SilentlyContinue
        }

        $switch = Get-VMSwitch -Name "NATSwitch"
    }

    Write-Host "📡 Using switch: $($switch.Name) (Type: $($switch.SwitchType))" -ForegroundColor Cyan

    # Add network adapter
    Add-VMNetworkAdapter -VMName $VmName -SwitchName $switch.Name
    Set-VMNetworkAdapter -VMName $VmName -MacAddressSpoofing On

    # Enable guest services for better integration
    Enable-VMIntegrationService -VMName $VmName -Name "Guest Service Interface" -ErrorAction SilentlyContinue

    Write-Host "✅ VM created and configured!" -ForegroundColor Green
    Write-Host "📁 VHDX Path: $vhdxPath" -ForegroundColor Cyan

    # Show VM details
    $vm = Get-VM -Name $VmName
    Write-Host "📊 VM Configuration:" -ForegroundColor Cyan
    Write-Host "  - Generation: $($vm.Generation)" -ForegroundColor Gray
    Write-Host "  - Processors: $($vm.ProcessorCount)" -ForegroundColor Gray
    Write-Host "  - Memory: $($vm.MemoryStartup / 1MB) MB" -ForegroundColor Gray
    Write-Host "  - Network: $($switch.Name)" -ForegroundColor Gray

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
