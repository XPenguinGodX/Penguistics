"""Script to verify that user/report insertions are working in PostgreSQL.

The RDS database is private, so this only reaches it from inside the VPC. From a laptop,
point it at a local Postgres instead: DB_HOST=localhost DB_PASSWORD=... python -m database.verify_db
For RDS, set DB_HOST and DB_SECRET_ARN (stack outputs) and run it somewhere inside the VPC.
"""

import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from database.connection import DB_HOST, DB_NAME, DB_PORT, connect  # noqa: E402

print(f"\n[1/3] Connecting to {DB_NAME} at {DB_HOST}:{DB_PORT}...")

try:
    conn = connect()
    print("  [SUCCESS] Connected to database!")
except Exception as e:
    print(f"  [FAILED] Could not connect: {e}")
    sys.exit(1)

cursor = conn.cursor()

# 2. Check existing users in the table (from Cognito confirmations)
print("\n[2/3] Checking existing rows in 'users' table...")
try:
    cursor.execute("SELECT id, username, email, firstname, lastname, city, state, created_at FROM users;")
    rows = cursor.fetchall()
    if rows:
        print(f"  Found {len(rows)} registered user(s):")
        for r in rows:
            print(f"    - ID: {r[0]}")
            print(f"      Username: {r[1]}")
            print(f"      Email: {r[2]}")
            print(f"      Name: {r[3]} {r[4]}")
            print(f"      Location: {r[5]}, {r[6]}")
            print(f"      Created At: {r[7]}\n")
    else:
        print("  Table 'users' is currently empty (no users have confirmed registration yet).")
except Exception as e:
    print(f"  [ERROR] querying users table: {e}")

# 3. Test a live INSERT to prove write capability
print("[3/3] Testing a live INSERT operation...")
test_user_id = str(uuid.uuid4())
test_username = f"test_verifier_{uuid.uuid4().hex[:6]}"

try:
    cursor.execute(
        """
        INSERT INTO users (id, username, email, firstname, lastname, state, city)
        VALUES (%s, %s, %s, %s, %s, %s, %s);
        """,
        (test_user_id, test_username, "test@penguistics.com", "Test", "User", "MD", "Baltimore"),
    )
    conn.commit()
    print(f"  [SUCCESS] Successfully inserted test record with username: '{test_username}'")

    # Read it back to verify
    cursor.execute("SELECT username, email, city FROM users WHERE username = %s;", (test_username,))
    verified = cursor.fetchone()
    print(f"  [SUCCESS] Verified written data from database: {verified}")

    # Clean up test record
    cursor.execute("DELETE FROM users WHERE username = %s;", (test_username,))
    conn.commit()
    print("  [CLEANUP] Deleted test record.")
    print("\nDatabase insertion is working 100%!")

except Exception as e:
    conn.rollback()
    print(f"  [INSERT FAILED]: {e}")

finally:
    cursor.close()
    conn.close()

