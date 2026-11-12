import uuid

from database.connection import get_db_connection

# Column order shared by every SELECT that builds a full Report (see Report._from_row)
COLUMNS = (
    "id, username, imagepath, long, lat, confidencelvl, title, description, status, city, "
    "location_source, device_long, device_lat"
)


class Report:
    def __init__(
        self,
        username: str,
        imagepath: str,
        long: float,
        lat: float,
        confidencelvl: float | None,
        title: str,
        description: str,
        city: str,
        status: str = "PENDING",
        location_source: str = "ONSITE",
        device_long: float | None = None,
        device_lat: float | None = None,
        id: uuid.UUID | None = None,
    ):
        self.username: str = username
        self.imagepath: str = imagepath
        self.long: float = float(long)
        self.lat: float = float(lat)
        self.confidencelvl: float | None = (
            float(confidencelvl) if confidencelvl is not None else None
        )
        self.title: str = title
        self.description: str = description
        self.city: str = city
        self.status: str = status
        self.location_source: str = location_source
        self.device_long: float | None = float(device_long) if device_long is not None else None
        self.device_lat: float | None = float(device_lat) if device_lat is not None else None
        self.id: uuid.UUID = id if id is not None else uuid.uuid4()

    def __str__(self) -> str:
        return f"""
        Id: {self.id}
        Reporter: {self.username}
        ImagePath: {self.imagepath}
        Longitude: {self.long}
        Latitude: {self.lat}
        ConfidenceLvl: {self.confidencelvl}
        Title: {self.title}
        Description: {self.description}
        Status: {self.status}
        City: {self.city}
        LocationSource: {self.location_source}
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
            "title": self.title,
            "description": self.description,
            "status": self.status,
            "city": self.city,
            "location_source": self.location_source,
            "device_long": self.device_long,
            "device_lat": self.device_lat,
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
            title=data.get("title", ""),
            description=data.get("description", ""),
            city=data.get("city", ""),
            status=data.get("status", "PENDING"),
            location_source=data.get("location_source", "ONSITE"),
            device_long=data.get("device_long"),
            device_lat=data.get("device_lat"),
            id=parsed_id,
        )

    @classmethod
    def _from_row(cls, row) -> "Report":
        """Build a Report from a row selected with COLUMNS, in that order."""
        return cls(
            id=uuid.UUID(str(row[0])),
            username=row[1],
            imagepath=row[2],
            long=row[3],
            lat=row[4],
            confidencelvl=row[5],
            title=row[6],
            description=row[7],
            status=row[8],
            city=row[9],
            location_source=row[10],
            device_long=row[11],
            device_lat=row[12],
        )

    def save(self) -> dict:
        """Save or update this report in the PostgreSQL reports table."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                INSERT INTO reports (id, username, imagepath, long, lat, confidencelvl, title, description,
                                     status, city, location_source, device_long, device_lat)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (id) DO UPDATE SET
                    confidencelvl = EXCLUDED.confidencelvl,
                    title = EXCLUDED.title,
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
                    self.title,
                    self.description,
                    self.status,
                    self.city,
                    self.location_source,
                    self.device_long,
                    self.device_lat,
                ),
            )
            conn.commit()
            return self.to_dict()
        except Exception:
            conn.rollback()
            raise
        finally:
            cursor.close()

    def retry_rejected(self) -> str | None:
        """Reuse this user's REJECTED report (same id) for a new attempt with this report's data.

        Returns the old image path so its S3 object can be deleted,
        or None if there is no REJECTED report with this id owned by this user.
        """
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            # FOR UPDATE locks the row, so two retries at once can't both reuse it
            cursor.execute(
                """
                SELECT imagepath FROM reports
                WHERE id = %s AND username = %s AND status = 'REJECTED'
                FOR UPDATE;
                """,
                (str(self.id), self.username),
            )
            row = cursor.fetchone()
            if not row:
                conn.rollback()
                return None

            # created_at restarts so the cleanup job's 24-hour and 3-day clocks count from this attempt
            cursor.execute(
                """
                UPDATE reports
                SET imagepath = %s, long = %s, lat = %s, title = %s, description = %s, city = %s,
                    location_source = %s, device_long = %s, device_lat = %s,
                    status = 'PENDING', confidencelvl = NULL, created_at = now()
                WHERE id = %s;
                """,
                (
                    self.imagepath,
                    self.long,
                    self.lat,
                    self.title,
                    self.description,
                    self.city,
                    self.location_source,
                    self.device_long,
                    self.device_lat,
                    str(self.id),
                ),
            )
            conn.commit()
            self.status = "PENDING"
            self.confidencelvl = None
            return row[0]
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
                f"""
                SELECT {COLUMNS}
                FROM reports
                WHERE city = %s
                ORDER BY created_at DESC;
                """,
                (city,),
            )
            return [cls._from_row(row) for row in cursor.fetchall()]
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
                SELECT id, status, title, description, lat, long, confidencelvl, location_source, created_at
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
                    "title": row[2],
                    "description": row[3],
                    "lat": float(row[4]),
                    "long": float(row[5]),
                    "confidence": float(row[6]) if row[6] is not None else None,
                    "location_source": row[7],
                    "created_at": row[8].isoformat() if row[8] is not None else None,
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
                f"""
                SELECT {COLUMNS}
                FROM reports
                WHERE id = %s;
                """,
                (str(report_id),),
            )
            row = cursor.fetchone()
            return cls._from_row(row) if row else None
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
    def find_image_paths(cls, image_paths: list[str]) -> set[str]:
        """Return which of these S3 keys at least one report still points to."""
        if not image_paths:
            return set()
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "SELECT imagepath FROM reports WHERE imagepath = ANY(%s);",
                (list(image_paths),),
            )
            return {row[0] for row in cursor.fetchall()}
        finally:
            cursor.close()

    @classmethod
    def get_stale_pending(cls, hours: int) -> list["Report"]:
        """Fetch PENDING reports created more than `hours` ago."""
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                f"""
                SELECT {COLUMNS}
                FROM reports
                WHERE status = 'PENDING'
                  AND created_at < now() - make_interval(hours => %s::int)
                ORDER BY created_at;
                """,
                (hours,),
            )
            return [cls._from_row(row) for row in cursor.fetchall()]
        finally:
            cursor.close()
