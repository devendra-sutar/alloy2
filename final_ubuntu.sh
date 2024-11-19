# Check Alloy service status
echo "Checking Alloy service status..."
sudo systemctl status alloy

# Send POST request to the provided URL with JSON data
echo "Sending POST request to create new agent..."

# Capture the full response body and status code
response=$(curl -s -w "%{http_code}" -o /dev/null -X POST http://10.0.34.138:8000/api/v1/create-agent/ \
    -H "Content-Type: application/json" \
    -d '{
        "host_name": "AAdmin-new",
        "ip_port": "192.162.1.12:8080",
        "keycloak_id": "a00e1a35-1550-4215-930a-1468298be901",
        "agent_name": "Linuxagent",
        "status": "Active"
    }')

# Capture the full response body (for debugging)
full_response=$(curl -s -X POST http://10.0.34.138:8000/api/v1/create-agent/ \
    -H "Content-Type: application/json" \
    -d '{
        "host_name":"AAdmin-new",
        "ip_port": "192.162.1.12:8080",
        "keycloak_id": "a00e1a35-1550-4215-930a-1468298be901",
        "agent_name": "Linuxagent",
        "status": "Active"
    }')

# Log the response code and full response body for debugging
echo "Response Code: $response"
echo "Full Response Body: $full_response"
#full_response1=$(cat /dev/null)

# Check if the response is 200 (success)
if [[ "$response" == "201" ]]; then
    echo "Agent created successfully."
elif [[ "$full_response" == *"UNIQUE constraint failed"* ]];then
    echo "ERROR:IP:PORT combination already exists"
else
    echo "Agent creation failed. Response code: $response"
    echo "Full response body: $full_response"
fi
