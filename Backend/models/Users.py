import uuid

from database.connection import get_db_connection


class User:
    def __init__(self,firstName,lastName,username,email,state,city,id: uuid.UUID | None = None):
        self.firstName: str = firstName
        self.lastName: str = lastName
        self.username: str = username
        self.email: str = email
        self.state: str = state
        self.city: str = city
        self.id: uuid.UUID = id if id is not None else uuid.uuid4()
        
    def __str__(self) -> str:
        return f"""
        Id: {self.id}
        Username: {self.username}
        Email: {self.email}
        FirstName: {self.firstName}
        LastName: {self.lastName}
        State: {self.state}
        City: {self.city}
        """
    
    def to_dict(self) -> dict:
        return{
            "id": str(self.id),
            "username": self.username,
            "email": self.email,
            "firstname": self.firstName,
            "lastname": self.lastName,
            "state": self.state,
            "city": self.city
        }

    @classmethod
    def from_dict(cls, data: dict) -> "User":
        raw_id = data.get("id")
        parsed_id = uuid.UUID(str(raw_id)) if raw_id is not None and not isinstance(raw_id, uuid.UUID) else raw_id
        return cls(
            firstName=data.get("firstname") or data.get("firstName", ""),
            lastName=data.get("lastname") or data.get("lastName", ""),
            username=data["username"],
            email=data.get("email", ""),
            state=data.get("state", ""),
            city=data.get("city", ""),
            id=parsed_id,
        )

    def save(self) -> dict:
        """Save or update this user in the PostgreSQL users table."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                INSERT INTO users (id, username, email, firstname, lastname, state, city)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (username) DO UPDATE SET
                    email = EXCLUDED.email,
                    firstname = EXCLUDED.firstname,
                    lastname = EXCLUDED.lastname,
                    state = EXCLUDED.state,
                    city = EXCLUDED.city;
                """,
                (
                    str(self.id),
                    self.username,
                    self.email,
                    self.firstName,
                    self.lastName,
                    self.state,
                    self.city,
                ),
            )
            conn.commit()
            return self.to_dict()
        except Exception:
            conn.rollback()
            raise
        finally:
            cursor.close()

    @classmethod
    def get_by_username(cls, username: str) -> "User | None":
        """Fetch a user from PostgreSQL by their username."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                SELECT id, username, email, firstname, lastname, state, city
                FROM users
                WHERE username = %s;
                """,
                (username,),
            )
            row = cursor.fetchone()
            if not row:
                return None
            return cls.from_dict(
                {
                    "id": row[0],
                    "username": row[1],
                    "email": row[2],
                    "firstname": row[3],
                    "lastname": row[4],
                    "state": row[5],
                    "city": row[6],
                }
            )
        finally:
            cursor.close()

    @classmethod
    def update_location(cls, username: str, state: str, city: str) -> "User | None":
        """Change only a user's state and city. Returns None if the user doesn't exist."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                UPDATE users
                SET state = %s, city = %s
                WHERE username = %s
                RETURNING id, username, email, firstname, lastname, state, city;
                """,
                (state, city, username),
            )
            row = cursor.fetchone()
            conn.commit()
            if not row:
                return None
            return cls.from_dict(
                {
                    "id": row[0],
                    "username": row[1],
                    "email": row[2],
                    "firstname": row[3],
                    "lastname": row[4],
                    "state": row[5],
                    "city": row[6],
                }
            )
        except Exception:
            conn.rollback()
            raise
        finally:
            cursor.close()

    @classmethod
    def delete_by_username(cls, username: str) -> None:
        """Delete a user from PostgreSQL by their username."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute("DELETE FROM users WHERE username = %s;", (username,))
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            cursor.close()


def post_confirmation_handler(event: dict, context) -> dict:
    """Cognito Post-Confirmation trigger that saves the verified user to PostgreSQL."""
    if event.get("triggerSource") == "PostConfirmation_ConfirmSignUp":
        request = event.get("request", {})
        attrs = request.get("userAttributes", {})
        metadata = request.get("clientMetadata") or {}

        raw_sub = attrs.get("sub")
        user_id = uuid.UUID(raw_sub) if raw_sub else uuid.uuid4()

        user = User(
            id=user_id,
            username=event["userName"],
            email=attrs.get("email", ""),
            firstName=attrs.get("given_name", ""),
            lastName=attrs.get("family_name", ""),
            state=metadata.get("state", ""),
            city=metadata.get("city", ""),
        )
        user.save()

    return event