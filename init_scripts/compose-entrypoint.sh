#!/bin/bash
set -euo pipefail

ready=/var/opt/mssql/indexlab-ready

if [ -f /var/opt/mssql/data/master.mdf ]; then
    if [ ! -s "$ready" ]; then
        echo "Error: import did not complete. Fix the error and reset with compose down -v." >&2
        exit 1
    fi
fi

export SQLCMDPASSWORD="$MSSQL_SA_PASSWORD"
sqlcmd=/opt/mssql-tools18/bin/sqlcmd
/opt/mssql/bin/sqlservr &
server_pid=$!
trap 'kill -TERM "$server_pid" 2>/dev/null || true; wait "$server_pid" || true' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

connected=false
for ((attempt = 0; attempt < 120; attempt++)); do
    if "$sqlcmd" -S localhost -U sa -C -b -l 2 -Q 'SELECT 1' > /dev/null 2>&1; then
        connected=true
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "Error: SQL Server exited during startup. See the server log above." >&2
        exit 1
    fi
    sleep 1
done
if [ "$connected" != true ]; then
    echo "Error: SQL Server did not become ready before the startup timeout." >&2
    exit 1
fi

if [ ! -s "$ready" ]; then
    "$sqlcmd" -S localhost -U sa -C -b -i /init_scripts/init.sql
    printf '%s' ready > "$ready.tmp"
    mv "$ready.tmp" "$ready"
    echo "Indexlab: import complete."
fi

wait "$server_pid"
