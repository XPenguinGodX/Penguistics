from database.connection import get_db_connection


class CityStaff:
    """A city employee account and the one city it works for (the city_staff table)."""

    def __init__(self, username: str, city: str, state: str):
        self.username: str = username
        self.city: str = city
        self.state: str = state

    def to_dict(self) -> dict:
        return {"username": self.username, "city": self.city, "state": self.state}

    def save(self) -> dict:
        """Insert this staff member, or move an existing one to this city."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                INSERT INTO city_staff (username, city, state)
                VALUES (%s, %s, %s)
                ON CONFLICT (username) DO UPDATE SET
                    city = EXCLUDED.city,
                    state = EXCLUDED.state;
                """,
                (self.username, self.city, self.state),
            )
            conn.commit()
            return self.to_dict()
        except Exception:
            conn.rollback()
            raise
        finally:
            cursor.close()

    @classmethod
    def get_by_username(cls, username: str) -> "CityStaff | None":
        """Fetch a staff member's city, or None if this username is not city staff."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "SELECT username, city, state FROM city_staff WHERE username = %s;",
                (username,),
            )
            row = cursor.fetchone()
            return cls(username=row[0], city=row[1], state=row[2]) if row else None
        finally:
            cursor.close()


def save_staff_handler(event: dict, context) -> dict:
    """SaveStaffFunction: writes one city_staff row. Only CreateStaffFunction invokes it.

    It lives inside the VPC (the database is private); CreateStaffFunction lives outside
    (Cognito is a public AWS API), the same split as GeocodeFunction.
    """
    event = event if isinstance(event, dict) else {}
    fields = [event.get(name) for name in ("username", "city", "state")]
    if not all(isinstance(value, str) and value.strip() for value in fields):
        raise ValueError("username, city, and state are required")
    username, city, state = (value.strip() for value in fields)
    return CityStaff(username=username, city=city, state=state).save()
