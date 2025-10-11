# Read input from file (first argument passed by PowerShellExecutor)
param(
    [string]$InputFile
)

# Read the content (should be a number)
if (Test-Path $InputFile) {
    $inputNumber = Get-Content $InputFile -Raw
    $inputNumber = $inputNumber.Trim()
} else {
    # If no input file, use 0
    $inputNumber = "0"
}

# Validate that input is a number
try {
    $inputNumber = [int]$inputNumber
} catch {
    # Not a valid number, treat as 0
    $inputNumber = 0
}

# Generate a random number between 1 and 100
$randomNumber = Get-Random -Minimum 1 -Maximum 101

# Add the numbers
$result = $inputNumber + $randomNumber

# Build output message
$outputMessage = "Input: $inputNumber + Random: $randomNumber = Result: $result"

# Determine tags based on result
$hostname = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { hostname }

# IMPORTANT: Don't include 'automationtest-work' here!
# Only include result/classification tags
$tags = "calculation-result,$hostname"

if ($result -gt 200) {
    $tags += ",high-value"
} elseif ($result -gt 100) {
    $tags += ",medium-value"
} else {
    $tags += ",low-value"
}

# Encode output as base64
$base64content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($outputMessage))

# Output JSON as required by the agent
$output = @{
    tags = $tags
    content = $base64content
}

$output | ConvertTo-Json -Compress