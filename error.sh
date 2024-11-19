curl -X POST http://10.0.34.138:8000/api/v1/create-agent/ \
    -H "Content-Type: application/json" \
    -d '{
        "host_name": "AAdmin-new1",
        "ip_port": "199.162.1.777:8080",
        "keycloak_id": "a00e1a35-1550-4215-930a-1468298be901",
        "agent_name": "Linux123",
        "status": "Active"
    }'
