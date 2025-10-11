# test_script.ps1
$result = @{
    hostname = $env:COMPUTERNAME
    user = $env:USER
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    message = "PowerShell is working on Linux, somehow"
}

$output = @{
    tags = "powershell-test,success"
    content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($result | ConvertTo-Json)))
}

$output | ConvertTo-Json