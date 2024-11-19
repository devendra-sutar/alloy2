curl -X POST http://10.0.34.138:8000/api/v1/create-agent/ \
-H "Content-Type: application/json" \
-d '{
    "host_name": "AAdmin-new",
    "ip_port": "192.162.1.12:8080",
    "keycloak_id": "a00e1a35-1550-4215-930a-1468298be901",
    "agent_name": "Gitlab",
    "status": "Active"
}'
