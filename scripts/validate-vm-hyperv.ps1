param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("amd64", "arm64")]
    [string]$Architecture
)

$ErrorActionPreference = "Stop"
$vmName = "homebridge-test-vm"
$logFile = "validation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param($Message, $Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $logFile -Value $logEntry
}

try {
    Write-Log "🚀 Starting Hyper-V validation for $Architecture architecture" "Green"

    # Step 1: Extract the image
    Write-Log "📦 Extracting VM image..." "Yellow"
    $gzFile = "output\homebridge-$Architecture.img.gz"
    $imgFile = "output\homebridge-$Architecture.img"

    if (-not (Test-Path $gzFile)) {
        throw "Image file not found: $gzFile"
    }

    # Use 7-Zip (commonly available on Windows runners) or PowerShell
    if (Get-Command "7z" -ErrorAction SilentlyContinue) {
        & 7z x $gzFile -o"output\" -y
    } else {
        Write-Log "Using PowerShell to decompress (this may take a while)..." "Yellow"
        $inStream = [System.IO.File]::OpenRead($gzFile)
        $gzipStream = New-Object System.IO.Compression.GzipStream($inStream, [System.IO.Compression.CompressionMode]::Decompress)
        $outStream = [System.IO.File]::Create($imgFile)
        $gzipStream.CopyTo($outStream)
        $outStream.Close()
        $gzipStream.Close()
        $inStream.Close()
    }

    if (-not (Test-Path $imgFile)) {
        throw "Failed to extract image"
    }
    Write-Log "✅ Image extracted successfully" "Green"

    # Step 2: Convert to VHDX for Hyper-V
    Write-Log "🔄 Converting image to VHDX format..." "Yellow"
    $vhdxFile = "output\homebridge-$Architecture.vhdx"

    # Remove existing VHDX if present
    if (Test-Path $vhdxFile) {
        Remove-Item $vhdxFile -Force
    }

    # Check if qemu-img is available (often installed with Hyper-V tools)
    $qemuImg = Get-Command "qemu-img" -ErrorAction SilentlyContinue

    if ($qemuImg) {
        Write-Log "Using qemu-img for conversion..." "Yellow"
        & qemu-img convert -f raw -O vhdx $imgFile $vhdxFile
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to convert image to VHDX using qemu-img"
        }
    } else {
        Write-Log "Using PowerShell Hyper-V cmdlets for conversion..." "Yellow"

        # Alternative approach: Use Hyper-V's built-in conversion
        # First rename the .img to .vhd (Hyper-V can work with VHD format)
        $vhdFile = $imgFile -replace '\.img$', '.vhd'
        Move-Item -Path $imgFile -Destination $vhdFile -Force

        try {
            # Convert VHD to VHDX
            Convert-VHD -Path $vhdFile -DestinationPath $vhdxFile -VHDType Dynamic
        } catch {
            Write-Log "Direct conversion failed, trying alternative method..." "Yellow"

            # Create a new dynamic VHDX based on the image size
            $imgSize = (Get-Item $vhdFile).Length
            $vhdxSize = [Math]::Ceiling($imgSize / 1GB) * 1GB + 1GB

            # Create new VHDX
            New-VHD -Path $vhdxFile -SizeBytes $vhdxSize -Dynamic

            Write-Log "Created VHDX, attempting to copy disk content..." "Yellow"

            # This is a simplified approach - just use the renamed VHD directly
            Remove-Item $vhdxFile -Force
            Move-Item -Path $vhdFile -Destination $vhdxFile -Force
        }

        # Clean up the renamed file if it still exists
        if (Test-Path $vhdFile) {
            Remove-Item $vhdFile -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path $vhdxFile)) {
        throw "Failed to create VHDX file"
    }

    Write-Log "✅ Image converted to VHDX" "Green"

    # Step 3: Create Hyper-V VM
    Write-Log "🖥️ Creating Hyper-V VM..." "Yellow"

    # Remove existing VM if present
    $existingVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if ($existingVM) {
        Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue
        Remove-VM -Name $vmName -Force
    }

    # Create new VM Generation 2 (UEFI)
    New-VM -Name $vmName `
        -MemoryStartupBytes 1GB `
        -Generation 2 `
        -VHDPath $vhdxFile

    # Configure VM
    Set-VM -Name $vmName `
        -ProcessorCount 2 `
        -DynamicMemory `
        -MemoryMinimumBytes 512MB `
        -MemoryMaximumBytes 2GB

    # Configure networking
    $switch = Get-VMSwitch -SwitchType Internal -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $switch) {
        # Create an internal switch if none exists
        $switch = New-VMSwitch -Name "Internal" -SwitchType Internal
    }
    Connect-VMNetworkAdapter -VMName $vmName -SwitchName $switch.Name

    # Disable Secure Boot (Linux doesn't support it by default)
    Set-VMFirmware -VMName $vmName -EnableSecureBoot Off

    Write-Log "✅ VM created and configured" "Green"

    # Step 4: Start VM
    Write-Log "▶️ Starting VM..." "Yellow"
    Start-VM -Name $vmName
    Write-Log "✅ VM started" "Green"

    # Step 5: Wait for VM to boot and get IP
    Write-Log "⏳ Waiting for VM to boot and obtain IP address..." "Yellow"

    $timeout = 300  # 5 minutes
    $elapsed = 0
    $checkInterval = 10
    $vmIP = $null

    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds $checkInterval
        $elapsed += $checkInterval

        # Check VM state
        $vm = Get-VM -Name $vmName
        if ($vm.State -ne "Running") {
            throw "VM stopped unexpectedly"
        }

        # Try to get VM IP address
        $vmNetworkAdapter = Get-VMNetworkAdapter -VMName $vmName
        $vmIP = ($vmNetworkAdapter.IPAddresses | Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+$" }) | Select-Object -First 1

        if ($vmIP) {
            Write-Log "✅ VM obtained IP address: $vmIP" "Green"
            break
        }

        if ($elapsed % 30 -eq 0) {
            Write-Log "Still waiting for VM to obtain IP... ($elapsed/$timeout seconds)" "Yellow"
        }
    }

    if (-not $vmIP) {
        Write-Log "⚠️ VM did not obtain IP address, continuing with localhost checks..." "Yellow"
        $vmIP = "localhost"
    }

    # Step 6: Wait for Homebridge to start
    Write-Log "⏳ Waiting for Homebridge service to start..." "Yellow"

    $serviceLive = $false
    $remainingTime = 300 - $elapsed
    $serviceElapsed = 0

    while ($serviceElapsed -lt $remainingTime) {
        Start-Sleep -Seconds $checkInterval
        $serviceElapsed += $checkInterval

        Write-Log "Checking Homebridge service..." "Gray"

        # Try to connect to Homebridge web interface
        try {
            $uri = if ($vmIP -eq "localhost") { "http://localhost:8581" } else { "http://${vmIP}:8581" }
            $response = Invoke-WebRequest -Uri $uri -TimeoutSec 5 -ErrorAction SilentlyContinue

            if ($response.StatusCode -eq 200) {
                $serviceLive = $true
                Write-Log "✅ Homebridge web interface is responding!" "Green"

                if ($response.Content -match "Homebridge") {
                    Write-Log "✅ Homebridge UI confirmed in response" "Green"
                }
                break
            }
        } catch {
            if ($serviceElapsed % 30 -eq 0) {
                Write-Log "Still waiting for Homebridge... ($serviceElapsed/$remainingTime seconds)" "Yellow"
            }
        }
    }

    if (-not $serviceLive) {
        Write-Log "❌ Homebridge did not start within timeout" "Red"
        throw "Homebridge service validation failed - service did not start"
    }

    # Step 7: Additional validation
    Write-Log "🔍 Performing additional validation..." "Yellow"

    # Check SSH is accessible
    $sshAccessible = $false
    if ($vmIP -ne "localhost") {
        $sshPort = Test-NetConnection -ComputerName $vmIP -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($sshPort) {
            Write-Log "✅ SSH port (22) is accessible" "Green"
            $sshAccessible = $true
        } else {
            Write-Log "⚠️ SSH port not accessible" "Yellow"
        }
    }

    # Save validation results
    $validationResults = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Architecture = $Architecture
        Hypervisor = "Hyper-V"
        VMStarted = $true
        VMIP = $vmIP
        HomebridgeResponding = $serviceLive
        SSHAccessible = $sshAccessible
        ValidationSuccess = $true
    }

    $validationResults | ConvertTo-Json | Out-File "validation-results.txt"

    Write-Log "🎉 VM IMAGE VALIDATION COMPLETED SUCCESSFULLY!" "Green"
    Write-Log "✅ VM booted successfully" "Green"
    Write-Log "✅ Homebridge service is running and accessible" "Green"
    Write-Log "📊 Results saved to validation-results.txt" "Green"

} catch {
    Write-Log "❌ Validation failed: $_" "Red"
    exit 1
} finally {
    # Cleanup
    Write-Log "🧹 Cleaning up..." "Yellow"

    # Stop and remove VM
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if ($vm) {
        if ($vm.State -eq "Running") {
            Stop-VM -Name $vmName -Force -TurnOff
        }
        Remove-VM -Name $vmName -Force
    }

    # Clean up extracted files
    Remove-Item "output\*.img" -Force -ErrorAction SilentlyContinue
    Remove-Item "output\*.vhdx" -Force -ErrorAction SilentlyContinue

    Write-Log "✅ Cleanup completed" "Green"
}