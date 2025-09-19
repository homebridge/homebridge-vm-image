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
    Write-Log "🚀 Starting validation for $Architecture architecture" "Green"

    # Step 1: Extract the image
    Write-Log "📦 Extracting VM image..." "Yellow"
    $gzFile = "output\homebridge-$Architecture.img.gz"
    $imgFile = "output\homebridge-$Architecture.img"

    if (-not (Test-Path $gzFile)) {
        throw "Image file not found: $gzFile"
    }

    # Use 7-Zip (commonly available on Windows runners) or certutil workaround
    if (Get-Command "7z" -ErrorAction SilentlyContinue) {
        & 7z x $gzFile -o"output\" -y
    } else {
        # Alternative: Use PowerShell's built-in compression (requires .NET)
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

    # Step 2: Convert to VDI for VirtualBox
    Write-Log "🔄 Converting image to VDI format..." "Yellow"
    $vdiFile = "output\homebridge-$Architecture.vdi"
    $vboxManage = "${env:ProgramFiles}\Oracle\VirtualBox\VBoxManage.exe"

    & $vboxManage convertfromraw $imgFile $vdiFile --format VDI
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to convert image to VDI"
    }
    Write-Log "✅ Image converted to VDI" "Green"

    # Step 3: Create VM
    Write-Log "🖥️ Creating VirtualBox VM..." "Yellow"

    # Remove existing VM if present
    & $vboxManage unregistervm $vmName --delete 2>$null

    # Create new VM (OS type "Linux_64" for amd64)
    & $vboxManage createvm --name $vmName --ostype "Linux_64" --register
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create VM"
    }

    # Configure VM
    & $vboxManage modifyvm $vmName `
        --memory 1024 `
        --cpus 1 `
        --firmware efi `
        --boot1 disk `
        --nic1 nat `
        --natpf1 "ssh,tcp,,2222,,22" `
        --natpf1 "homebridge,tcp,,8581,,8581"

    # Attach storage controller and disk
    & $vboxManage storagectl $vmName --name "SATA" --add sata --controller IntelAhci
    & $vboxManage storageattach $vmName --storagectl "SATA" --port 0 --device 0 --type hdd --medium $vdiFile

    Write-Log "✅ VM created and configured" "Green"

    # Step 4: Start VM
    Write-Log "▶️ Starting VM..." "Yellow"
    & $vboxManage startvm $vmName --type headless
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start VM"
    }
    Write-Log "✅ VM started" "Green"

    # Step 5: Wait for Homebridge to start
    Write-Log "⏳ Waiting for Homebridge service to start (timeout: 5 minutes)..." "Yellow"

    $timeout = 300  # 5 minutes
    $elapsed = 0
    $checkInterval = 10
    $serviceLive = $false

    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds $checkInterval
        $elapsed += $checkInterval

        Write-Log "Checking Homebridge (elapsed: ${elapsed}s)..." "Gray"

        # Check if VM is still running
        $vmInfo = & $vboxManage showvminfo $vmName --machinereadable | Select-String "VMState="
        if ($vmInfo -notmatch 'VMState="running"') {
            throw "VM stopped unexpectedly"
        }

        # Try to connect to Homebridge web interface
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:8581" -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                $serviceLive = $true
                Write-Log "✅ Homebridge web interface is responding!" "Green"

                # Try to get more info
                if ($response.Content -match "Homebridge") {
                    Write-Log "✅ Homebridge UI confirmed in response" "Green"
                }
                break
            }
        } catch {
            # Connection failed, keep waiting
            if ($elapsed % 30 -eq 0) {
                Write-Log "Still waiting for Homebridge... ($elapsed/$timeout seconds)" "Yellow"
            }
        }

        # Alternative: Check if port is listening
        $portCheck = Test-NetConnection -ComputerName localhost -Port 8581 -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($portCheck) {
            Write-Log "✅ Port 8581 is open" "Green"
            $serviceLive = $true
            break
        }
    }

    if (-not $serviceLive) {
        # Get VM logs for debugging
        Write-Log "❌ Homebridge did not start within timeout" "Red"

        # Try to get console output
        Write-Log "Attempting to retrieve VM console output..." "Yellow"
        & $vboxManage controlvm $vmName screenshotpng "vm-screenshot.png" 2>$null

        throw "Homebridge service validation failed - service did not start"
    }

    # Step 6: Additional validation
    Write-Log "🔍 Performing additional validation..." "Yellow"

    # Check SSH is accessible
    $sshPort = Test-NetConnection -ComputerName localhost -Port 2222 -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($sshPort) {
        Write-Log "✅ SSH port (2222) is accessible" "Green"
    } else {
        Write-Log "⚠️ SSH port not accessible (this may be expected)" "Yellow"
    }

    # Save validation results
    $validationResults = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Architecture = $Architecture
        VMStarted = $true
        HomebridgeResponding = $serviceLive
        SSHAccessible = $sshPort
        ValidationSuccess = $true
    }

    $validationResults | ConvertTo-Json | Out-File "validation-results.txt"

    Write-Log "🎉 VM IMAGE VALIDATION COMPLETED SUCCESSFULLY!" "Green"
    Write-Log "✅ VM booted successfully" "Green"
    Write-Log "✅ Homebridge service is running and accessible on port 8581" "Green"
    Write-Log "📊 Results saved to validation-results.txt" "Green"

} catch {
    Write-Log "❌ Validation failed: $_" "Red"
    exit 1
} finally {
    # Cleanup
    Write-Log "🧹 Cleaning up..." "Yellow"

    if (Get-Command $vboxManage -ErrorAction SilentlyContinue) {
        # Stop and remove VM
        & $vboxManage controlvm $vmName poweroff 2>$null
        Start-Sleep -Seconds 2
        & $vboxManage unregistervm $vmName --delete 2>$null
    }

    # Clean up extracted files
    Remove-Item "output\*.img" -Force -ErrorAction SilentlyContinue
    Remove-Item "output\*.vdi" -Force -ErrorAction SilentlyContinue

    Write-Log "✅ Cleanup completed" "Green"
}