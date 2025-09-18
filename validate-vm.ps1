param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("amd64")]
    [string]$Architecture,
    
    [Parameter(Mandatory=$false)]
    [string]$ImagePath = "output\homebridge-$Architecture.img.gz",
    
    [Parameter(Mandatory=$false)]
    [int]$Timeout = 300,
    
    [Parameter(Mandatory=$false)]
    [int]$VmRam = 1024
)

# VM Image Validation Script for Windows with VirtualBox
# Tests that the VM image boots properly and Homebridge starts correctly

Write-Host "🚀 Starting VM validation for $Architecture architecture..." -ForegroundColor Green
Write-Host "📁 Image: $ImagePath" -ForegroundColor Cyan
Write-Host "⏱️ Timeout: ${Timeout}s" -ForegroundColor Cyan

# Check if image exists
if (-not (Test-Path $ImagePath)) {
    Write-Host "❌ VM image not found: $ImagePath" -ForegroundColor Red
    exit 1
}

# Check VirtualBox installation
try {
    $vboxVersion = VBoxManage --version
    Write-Host "✅ VirtualBox version: $vboxVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ VirtualBox not found. Please install VirtualBox." -ForegroundColor Red
    exit 1
}

# Extract image if compressed
$workDir = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$workImg = "$workDir\homebridge-$Architecture-test.img"

if ($ImagePath.EndsWith(".gz")) {
    Write-Host "📦 Extracting compressed image..." -ForegroundColor Yellow
    
    # Extract using 7-Zip (should be available on GitHub Actions Windows runners)
    try {
        & "C:\Program Files\7-Zip\7z.exe" e $ImagePath -o$workDir -y
        $extractedFiles = Get-ChildItem -Path $workDir -Filter "*.img"
        if ($extractedFiles.Count -gt 0) {
            $workImg = $extractedFiles[0].FullName
        } else {
            throw "No .img file found after extraction"
        }
    } catch {
        Write-Host "❌ Failed to extract image: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Copy-Item $ImagePath $workImg
}

# Create unique VM name
$vmName = "homebridge-test-$(Get-Random)"
$vmCreated = $false

# Cleanup function
function Cleanup {
    Write-Host "🧹 Cleaning up..." -ForegroundColor Yellow
    
    if ($vmCreated) {
        try {
            # Stop VM if running
            VBoxManage controlvm $vmName poweroff 2>$null
            Start-Sleep -Seconds 2
            
            # Remove VM
            VBoxManage unregistervm $vmName --delete 2>$null
            Write-Host "🗑️ VM $vmName removed" -ForegroundColor Green
        } catch {
            Write-Host "⚠️ Warning: Could not clean up VM: $_" -ForegroundColor Yellow
        }
    }
    
    # Clean up temporary files
    if (Test-Path $workDir) {
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Set up cleanup on exit
$cleanupRegistered = $false
try {
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Cleanup } | Out-Null
    $cleanupRegistered = $true
} catch {
    # Fallback cleanup approach
}

try {
    # Create VM
    Write-Host "🖥️ Creating VirtualBox VM..." -ForegroundColor Cyan
    VBoxManage createvm --name $vmName --ostype "Linux_64" --register
    $vmCreated = $true
    
    # Configure VM
    VBoxManage modifyvm $vmName --memory $VmRam --cpus 1
    VBoxManage modifyvm $vmName --nic1 nat
    VBoxManage modifyvm $vmName --natpf1 "ssh,tcp,,2222,,22"
    VBoxManage modifyvm $vmName --natpf1 "web,tcp,,8581,,8581"
    VBoxManage modifyvm $vmName --uart1 0x3F8 4
    VBoxManage modifyvm $vmName --uartmode1 file vm-console.log
    
    # Attach disk
    Write-Host "💾 Attaching disk image..." -ForegroundColor Cyan
    VBoxManage storagectl $vmName --name "SATA" --add sata --bootable on
    VBoxManage storageattach $vmName --storagectl "SATA" --port 0 --device 0 --type hdd --medium $workImg
    
    # Start VM
    Write-Host "▶️ Starting VM..." -ForegroundColor Green
    VBoxManage startvm $vmName --type headless
    
    # Wait for VM to boot and services to start
    Write-Host "⏳ Waiting for VM to boot and services to start..." -ForegroundColor Yellow
    $bootSuccess = $false
    $startTime = Get-Date
    $httpPort = 8581
    
    for ($i = 0; $i -lt $Timeout; $i += 5) {
        $elapsed = (Get-Date) - $startTime
        $elapsedSeconds = [int]$elapsed.TotalSeconds
        
        if ($elapsedSeconds -gt $Timeout) {
            Write-Host "❌ Timeout waiting for VM to boot (${Timeout}s)" -ForegroundColor Red
            exit 1
        }
        
        # Check if VM is still running
        $vmState = VBoxManage showvminfo $vmName --machinereadable | Select-String "VMState=" | ForEach-Object { $_.ToString().Split('=')[1].Trim('"') }
        if ($vmState -ne "running") {
            Write-Host "❌ VM stopped unexpectedly. State: $vmState" -ForegroundColor Red
            
            # Try to get console output for debugging
            if (Test-Path "vm-console.log") {
                Write-Host "📋 Last console output:" -ForegroundColor Yellow
                Get-Content "vm-console.log" -Tail 20 | Write-Host
            }
            exit 1
        }
        
        # Try to connect to HTTP port (Homebridge web interface)
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$httpPort" -TimeoutSec 5 -ErrorAction Stop
            $bootSuccess = $true
            Write-Host "✅ VM booted successfully and Homebridge web interface is accessible!" -ForegroundColor Green
            break
        } catch {
            # Continue waiting
        }
        
        Write-Host "⏳ Still waiting... (${elapsedSeconds}s/${Timeout}s)" -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
    
    if (-not $bootSuccess) {
        Write-Host "❌ VM failed to boot properly or Homebridge web interface not accessible within ${Timeout}s" -ForegroundColor Red
        
        # Try to get console output for debugging
        if (Test-Path "vm-console.log") {
            Write-Host "📋 Console output:" -ForegroundColor Yellow
            Get-Content "vm-console.log" | Write-Host
        }
        exit 1
    }
    
    # Additional validation: Check if we can get a response from Homebridge
    Write-Host "🔍 Validating Homebridge web interface..." -ForegroundColor Cyan
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$httpPort" -TimeoutSec 10
        $content = $response.Content
        
        Write-Host "✅ Homebridge web interface responded successfully!" -ForegroundColor Green
        
        # Check if response looks like Homebridge (should contain some typical content)
        if ($content -match "homebridge|login|dashboard") {
            Write-Host "✅ Response appears to be from Homebridge application" -ForegroundColor Green
        } else {
            Write-Host "⚠️ Warning: Response doesn't appear to be from Homebridge, but service is running" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "❌ No response from Homebridge web interface: $_" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "🎉 VM image validation completed successfully for $Architecture!" -ForegroundColor Green
    Write-Host "✅ VM boots properly" -ForegroundColor Green
    Write-Host "✅ Homebridge service starts" -ForegroundColor Green
    Write-Host "✅ Web interface accessible on port $httpPort" -ForegroundColor Green
    
} finally {
    # Ensure cleanup runs
    if (-not $cleanupRegistered) {
        Cleanup
    }
}

exit 0