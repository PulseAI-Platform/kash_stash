#!/bin/bash

Read input from file (first argument passed by BashExecutor)
input_file=“$1”

Read the content (should be a number)
if [ -f “$input_file” ]; then
input_number=$(cat “$input_file”)
else
# If no input file, try to read from stdin or use 0
input_number=“${1:-0}”
fi

Validate that input is a number
if ! [[ “$input_number” =~ ^-?[0-9]+$ ]]; then
# Not a valid number, treat as 0
input_number=0
fi

Generate a random number between 1 and 100
random_number=$((RANDOM % 100 + 1))

Add the numbers
result=$((input_number + random_number))

Build output message
output_message=“Input: $input_number + Random: $random_number = Result: $result”

Determine tags based on result
hostname=$(hostname)

IMPORTANT: Don’t include ‘automationtest-work’ here!
Only include result/classification tags
tags=“calculation-result,$hostname”

if [ “$result” -gt 200 ]; then
tags=“$tags,high-value”
elif [ “$result” -gt 100 ]; then
tags=“$tags,medium-value”
else
tags=“$tags,low-value”
fi

Encode output as base64
base64content=$(echo “$output_message” | base64 -w 0)

Output JSON as required by the agent
echo “{"tags": "$tags", "content": "$base64content"}”