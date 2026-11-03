import json
import os
import urllib.request

from database.connection import DB_HOST, DB_NAME, DB_PORT, connect


def send_response(event, context, response_status, response_data=None, physical_resource_id=None):
    """Notify CloudFormation of Custom Resource execution status."""
    response_url = event.get("ResponseURL")
    if not response_url:
        print("No ResponseURL found, skipping CloudFormation callback.")
        return

    body = json.dumps({
        "Status": response_status,
        "Reason": f"See CloudWatch Log Stream: {getattr(context, 'log_stream_name', 'local')}",
        "PhysicalResourceId": physical_resource_id or getattr(context, "log_stream_name", "db-initializer"),
        "StackId": event.get("StackId"),
        "RequestId": event.get("RequestId"),
        "LogicalResourceId": event.get("LogicalResourceId"),
        "Data": response_data or {},
    }).encode("utf-8")

    req = urllib.request.Request(
        response_url,
        data=body,
        headers={"content-type": "", "content-length": str(len(body))},
        method="PUT",
    )
    with urllib.request.urlopen(req) as response:
        print(f"CloudFormation response delivered with status: {response.status}")


def handler(event, context):
    """CloudFormation Custom Resource handler to initialize PostgreSQL schema."""
    print(f"Received CloudFormation event: {json.dumps(event)}")
    request_type = event.get("RequestType", "Create")

    # On stack deletion, do not drop or alter tables
    if request_type == "Delete":
        print("Stack is deleting. Skipping database initialization.")
        send_response(event, context, "SUCCESS")
        return {"status": "SUCCESS"}

    conn = None
    try:
        sql_path = os.path.join(os.path.dirname(__file__), "startup", "InitialScheme.sql")
        print(f"Reading SQL script from: {sql_path}")
        with open(sql_path, "r", encoding="utf-8") as f:
            sql_script = f.read()

        print(f"Connecting to database {DB_NAME} at {DB_HOST}:{DB_PORT}...")
        conn = connect()

        cursor = conn.cursor()
        print("Executing InitialScheme.sql...")
        cursor.execute(sql_script)
        conn.commit()
        cursor.close()

        print("Database schema initialized successfully.")
        send_response(event, context, "SUCCESS", {"Message": "Schema initialized"})
        return {"status": "SUCCESS"}

    except Exception as e:
        print(f"Error during database initialization: {e}")
        send_response(event, context, "FAILED", {"Error": str(e)})
        raise e

    finally:
        if conn is not None:
            conn.close()


if __name__ == "__main__":
    handler({}, None)

