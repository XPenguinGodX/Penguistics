import uuid

from database.connection import get_db_connection


class Report:
    def __init__(
        self,
        username: str,
        imagepath: str,
        long: float,
        lat: float,
        confidencelvl: float | None,
        description: str,
        city: str,
        status: str = "PENDING",
        id: uuid.UUID | None = None,
    ):
        self.username: str = username
        self.imagepath: str = imagepath
        self.long: float = float(long)
        self.lat: float = float(lat)
        self.confidencelvl: float | None = (
            float(confidencelvl) if confidencelvl is not None else None
        )
        self.description: str = description
        self.city: str = city
        self.status: str = status
        self.id: uuid.UUID = id if id is not None else uuid.uuid4()

    def __str__(self) -> str:
        return f"""
        Id: {self.id}
        Reporter: {self.username}
        ImagePath: {self.imagepath}
        Longitude: {self.long}
        Latitude: {self.lat}
        ConfidenceLvl: {self.confidencelvl}
        Description: {self.description}
        Status: {self.status}
        City: {self.city}
        """

    def to_dict(self) -> dict:
        return {
            "id": str(self.id),
            "username": self.username,
            "reporter": self.username,
            "imagepath": self.imagepath,
            "long": self.long,
            "lat": self.lat,
            "longitude": self.long,
            "latitude": self.lat,
            "confidencelvl": self.confidencelvl,
            "confidence": self.confidencelvl,
            "description": self.description,
            "status": self.status,
            "city": self.city,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Report":
        raw_id = data.get("id")
        parsed_id = (
            uuid.UUID(str(raw_id))
            if raw_id is not None and not isinstance(raw_id, uuid.UUID)
            else raw_id
        )
        return cls(
            username=data.get("username") or data.get("reporter", ""),
            imagepath=data.get("imagepath", ""),
            long=float(data.get("long", data.get("longitude", 0.0))),
            lat=float(data.get("lat", data.get("latitude", 0.0))),
            confidencelvl=data.get("confidencelvl", data.get("confidence")),
            description=data.get("description", ""),
            city=data.get("city", ""),
            status=data.get("status", "PENDING"),
            id=parsed_id,
        )

    def save(self) -> dict:
        """Save or update this report in the PostgreSQL reports table."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                INSERT INTO reports (id, username, imagepath, long, lat, confidencelvl, description, status, city)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (id) DO UPDATE SET
                    confidencelvl = EXCLUDED.confidencelvl,
                    description = EXCLUDED.description,
                    status = EXCLUDED.status,
                    city = EXCLUDED.city;
                """,
                (
                    str(self.id),
                    self.username,
                    self.imagepath,
                    self.long,
                    self.lat,
                    self.confidencelvl,
                    self.description,
                    self.status,
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
    def get_all_by_city(cls, city: str) -> list["Report"]:
        """Fetch all reports in a given city."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                SELECT id, username, imagepath, long, lat, confidencelvl, description, status, city
                FROM reports
                WHERE city = %s
                ORDER BY created_at DESC;
                """,
                (city,),
            )
            rows = cursor.fetchall()
            return [
                cls(
                    id=uuid.UUID(str(row[0])),
                    username=row[1],
                    imagepath=row[2],
                    long=row[3],
                    lat=row[4],
                    confidencelvl=row[5],
                    description=row[6],
                    status=row[7],
                    city=row[8],
                )
                for row in rows
            ]
        finally:
            cursor.close()

    @classmethod
    def get_summaries_by_username(cls, username: str) -> list[dict]:
        """Fetch one user's reports, newest first, for their map pins.

        Leaves out imagepath and city; adds created_at, which the Report class doesn't hold.
        """
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                SELECT id, status, description, lat, long, confidencelvl, created_at
                FROM reports
                WHERE username = %s
                ORDER BY created_at DESC;
                """,
                (username,),
            )
            return [
                {
                    "id": str(row[0]),
                    "status": row[1],
                    "description": row[2],
                    "lat": float(row[3]),
                    "long": float(row[4]),
                    "confidence": float(row[5]) if row[5] is not None else None,
                    "created_at": row[6].isoformat() if row[6] is not None else None,
                }
                for row in cursor.fetchall()
            ]
        finally:
            cursor.close()

    @classmethod
    def get_by_id(cls, report_id: str | uuid.UUID) -> "Report | None":
        """Fetch a single report by its UUID."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                SELECT id, username, imagepath, long, lat, confidencelvl, description, status, city
                FROM reports
                WHERE id = %s;
                """,
                (str(report_id),),
            )
            row = cursor.fetchone()
            if not row:
                return None
            return cls(
                id=uuid.UUID(str(row[0])),
                username=row[1],
                imagepath=row[2],
                long=row[3],
                lat=row[4],
                confidencelvl=row[5],
                description=row[6],
                status=row[7],
                city=row[8],
            )
        finally:
            cursor.close()

    @classmethod
    def update_status(cls, report_id: str | uuid.UUID, status: str, confidencelvl: float | None) -> bool:
        """Resolve a PENDING report. Returns False if it was already resolved."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                UPDATE reports
                SET status = %s, confidencelvl = %s
                WHERE id = %s AND status = 'PENDING';
                """,
                (status, confidencelvl, str(report_id)),
            )
            updated = cursor.rowcount == 1
            conn.commit()
            return updated
        except Exception:
            conn.rollback()
            raise
        finally:
            cursor.close()

    @classmethod
    def purge_expired(cls, days: int) -> list[str]:
        """Delete REJECTED (and never-resolved PENDING) reports older than `days`.

        Returns the deleted reports' image paths so their S3 objects can be removed.
        """
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                DELETE FROM reports
                WHERE status IN ('REJECTED', 'PENDING')
                  AND created_at < now() - make_interval(days => %s::int)
                RETURNING imagepath;
                """,
                (days,),
            )
            image_paths = [row[0] for row in cursor.fetchall()]
            conn.commit()
            return image_paths
        except Exception:
            conn.rollback()
            raise
        finally:
            cursor.close()

    @classmethod
    def get_stale_pending(cls, hours: int) -> list["Report"]:
        """Fetch PENDING reports created more than `hours` ago."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                SELECT id, username, imagepath, long, lat, confidencelvl, description, status, city
                FROM reports
                WHERE status = 'PENDING'
                  AND created_at < now() - make_interval(hours => %s::int)
                ORDER BY created_at;
                """,
                (hours,),
            )
            rows = cursor.fetchall()
            return [
                cls(
                    id=uuid.UUID(str(row[0])),
                    username=row[1],
                    imagepath=row[2],
                    long=row[3],
                    lat=row[4],
                    confidencelvl=row[5],
                    description=row[6],
                    status=row[7],
                    city=row[8],
                )
                for row in rows
            ]
        finally:
            cursor.close()
