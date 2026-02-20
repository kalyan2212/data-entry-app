from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
import os
import re
import psycopg2
import psycopg2.extras
from functools import wraps
from contextlib import contextmanager

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "dataentry_secret_key_2026")

# ──────────────────────────────────────────────
#  API Keys  –  loaded from environment variables
#  Set UPSTREAM_API_KEY and DOWNSTREAM_API_KEY
#  in the environment (or /etc/data-entry-app/env)
# ──────────────────────────────────────────────
API_KEYS = {
    os.environ.get("UPSTREAM_API_KEY",   "upstream-app-key-001"):   "upstream",
    os.environ.get("DOWNSTREAM_API_KEY", "downstream-app-key-002"): "downstream",
}


def require_api_key(f):
    """Decorator – rejects requests that don't carry a valid X-API-Key header."""
    @wraps(f)
    def decorated(*args, **kwargs):
        key = request.headers.get("X-API-Key", "")
        if key not in API_KEYS:
            return jsonify({"error": "Unauthorized. Provide a valid X-API-Key header."}), 401
        return f(*args, **kwargs)
    return decorated


# ──────────────────────────────────────────────
#  Database – PostgreSQL
#  Configure via environment variables:
#    DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
# ──────────────────────────────────────────────
DB_CONFIG = {
    "host":     os.environ.get("DB_HOST",     "localhost"),
    "port":     int(os.environ.get("DB_PORT", "5432")),
    "dbname":   os.environ.get("DB_NAME",     "customers"),
    "user":     os.environ.get("DB_USER",     "appuser"),
    "password": os.environ.get("DB_PASSWORD", ""),
}


def get_db():
    return psycopg2.connect(**DB_CONFIG)


@contextmanager
def db_cursor():
    """Yields a RealDictCursor, commits on success, rolls back on error,
    and always closes the connection."""
    conn = get_db()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        yield cur
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def row_to_dict(row):
    """Convert a psycopg2 RealDictRow to a plain JSON-serialisable dict."""
    if not row:
        return None
    d = dict(row)
    for key, val in d.items():
        if hasattr(val, "isoformat"):   # convert datetime → ISO string
            d[key] = val.isoformat()
    return d


def init_db():
    with db_cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS customers (
                id          SERIAL PRIMARY KEY,
                first_name  TEXT NOT NULL,
                last_name   TEXT NOT NULL,
                road        TEXT NOT NULL,
                city        TEXT NOT NULL,
                state       TEXT NOT NULL,
                zip         TEXT NOT NULL,
                country     TEXT NOT NULL,
                phone       TEXT NOT NULL,
                dob         TEXT NOT NULL,
                created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)


# ──────────────────────────────────────────────
#  Home – role selector
# ──────────────────────────────────────────────
@app.route("/")
def index():
    return render_template("index.html")


# ──────────────────────────────────────────────
#  OPERATOR  –  data entry
# ──────────────────────────────────────────────
@app.route("/operator", methods=["GET", "POST"])
def operator():
    errors = {}
    form_data = {}

    if request.method == "POST":
        form_data = request.form.to_dict()

        # --- validation ---
        first_name = form_data.get("first_name", "").strip()
        last_name  = form_data.get("last_name",  "").strip()
        road       = form_data.get("road",       "").strip()
        city       = form_data.get("city",       "").strip()
        state      = form_data.get("state",      "").strip()
        zip_code   = form_data.get("zip",        "").strip()
        country    = form_data.get("country",    "").strip()
        phone      = form_data.get("phone",      "").strip()
        dob        = form_data.get("dob",        "").strip()

        if not first_name:
            errors["first_name"] = "First name is required."
        if not last_name:
            errors["last_name"] = "Last name is required."
        if not road:
            errors["road"] = "Road / street is required."
        if not city:
            errors["city"] = "City is required."
        if not state:
            errors["state"] = "State is required."
        if not zip_code:
            errors["zip"] = "ZIP code is required."
        if not country:
            errors["country"] = "Country is required."

        # Phone: numeric only
        if not phone:
            errors["phone"] = "Phone number is required."
        elif not re.fullmatch(r"\d+", phone):
            errors["phone"] = "Phone number must contain digits only."

        # DOB: mm/dd/yyyy  –  digits + slashes only, validated format
        if not dob:
            errors["dob"] = "Date of birth is required."
        else:
            if not re.fullmatch(r"\d{2}/\d{2}/\d{4}", dob):
                errors["dob"] = "Date of birth must be in MM/DD/YYYY format (digits only)."
            else:
                mm, dd, yyyy = dob.split("/")
                mm_i, dd_i, yyyy_i = int(mm), int(dd), int(yyyy)
                if not (1 <= mm_i <= 12):
                    errors["dob"] = "Month must be between 01 and 12."
                elif not (1 <= dd_i <= 31):
                    errors["dob"] = "Day must be between 01 and 31."
                elif yyyy_i < 1900 or yyyy_i > 2026:
                    errors["dob"] = "Year must be between 1900 and 2026."

        if not errors:
            with db_cursor() as cur:
                cur.execute(
                    """INSERT INTO customers
                       (first_name, last_name, road, city, state, zip, country, phone, dob)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                       RETURNING id""",
                    (first_name, last_name, road, city, state,
                     zip_code, country, phone, dob)
                )
                new_id = cur.fetchone()["id"]
            return redirect(url_for("success", customer_id=new_id))

    return render_template("operator.html", errors=errors, form_data=form_data)


# ──────────────────────────────────────────────
#  Success page
# ──────────────────────────────────────────────
@app.route("/success/<int:customer_id>")
def success(customer_id):
    with db_cursor() as cur:
        cur.execute("SELECT * FROM customers WHERE id = %s", (customer_id,))
        row = cur.fetchone()
    return render_template("success.html", customer=row)


# ──────────────────────────────────────────────
#  MANAGER  –  search
# ──────────────────────────────────────────────
@app.route("/manager", methods=["GET", "POST"])
def manager():
    results = None
    search_performed = False
    search_term = ""
    search_type = ""
    error = ""

    if request.method == "POST":
        search_type = request.form.get("search_type", "")
        search_term = request.form.get("search_term", "").strip()
        search_performed = True

        if not search_term:
            error = "Please enter a search term."
        else:
            with db_cursor() as cur:
                if search_type == "id":
                    if not re.fullmatch(r"\d+", search_term):
                        error = "Customer ID must be numeric."
                    else:
                        cur.execute(
                            "SELECT * FROM customers WHERE id = %s",
                            (int(search_term),)
                        )
                        results = cur.fetchall()

                elif search_type == "city":
                    cur.execute(
                        "SELECT * FROM customers WHERE city ILIKE %s",
                        (f"%{search_term}%",)
                    )
                    results = cur.fetchall()

                elif search_type == "last_name":
                    cur.execute(
                        "SELECT * FROM customers WHERE last_name ILIKE %s",
                        (f"%{search_term}%",)
                    )
                    results = cur.fetchall()

                elif search_type == "phone":
                    if not re.fullmatch(r"\d+", search_term):
                        error = "Phone number must contain digits only."
                    else:
                        cur.execute(
                            "SELECT * FROM customers WHERE phone LIKE %s",
                            (f"%{search_term}%",)
                        )
                        results = cur.fetchall()
                else:
                    error = "Please select a valid search type."

    return render_template(
        "manager.html",
        results=results,
        search_performed=search_performed,
        search_term=search_term,
        search_type=search_type,
        error=error,
    )


# ──────────────────────────────────────────────
#  REST API  –  for external applications
# ──────────────────────────────────────────────

@app.route("/api/customers", methods=["GET"])
@require_api_key
def api_list_customers():
    """
    GET /api/customers
    Headers : X-API-Key: <key>
    Query params:
        id, last_name, city, phone  – filter fields
        since   – ISO datetime (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)
                  returns only records created after this timestamp
                  (useful for downstream incremental polling)
        limit   – max rows to return (default 100, max 1000)
        offset  – skip N rows for pagination (default 0)
    Example:
        /api/customers?city=Boston&since=2026-02-01&limit=50&offset=0
    """
    id_        = request.args.get("id",        "").strip()
    last_name  = request.args.get("last_name",  "").strip()
    city       = request.args.get("city",       "").strip()
    phone      = request.args.get("phone",      "").strip()
    since      = request.args.get("since",      "").strip()

    try:
        limit  = min(int(request.args.get("limit",  100)), 1000)
        offset = max(int(request.args.get("offset", 0)),   0)
    except ValueError:
        return jsonify({"error": "limit and offset must be integers."}), 400

    where  = "WHERE 1=1"
    params = []

    if id_:
        if not re.fullmatch(r"\d+", id_):
            return jsonify({"error": "id must be numeric."}), 400
        where += " AND id = %s"
        params.append(int(id_))
    if last_name:
        where += " AND last_name ILIKE %s"
        params.append(f"%{last_name}%")
    if city:
        where += " AND city ILIKE %s"
        params.append(f"%{city}%")
    if phone:
        if not re.fullmatch(r"\d+", phone):
            return jsonify({"error": "phone must contain digits only."}), 400
        where += " AND phone LIKE %s"
        params.append(f"%{phone}%")
    if since:
        where += " AND created_at > %s"
        params.append(since)

    with db_cursor() as cur:
        cur.execute(f"SELECT COUNT(*) AS cnt FROM customers {where}", params)
        total = cur.fetchone()["cnt"]
        cur.execute(
            f"SELECT * FROM customers {where} ORDER BY created_at ASC LIMIT %s OFFSET %s",
            params + [limit, offset]
        )
        rows = cur.fetchall()

    return jsonify({
        "total":   total,
        "limit":   limit,
        "offset":  offset,
        "count":   len(rows),
        "data":    [row_to_dict(r) for r in rows],
    }), 200


@app.route("/api/customers/<int:customer_id>", methods=["GET"])
@require_api_key
def api_get_customer(customer_id):
    """
    GET /api/customers/<id>
    Returns a single customer record.
    """
    with db_cursor() as cur:
        cur.execute("SELECT * FROM customers WHERE id = %s", (customer_id,))
        row = cur.fetchone()

    if row is None:
        return jsonify({"error": f"Customer {customer_id} not found."}), 404

    return jsonify(row_to_dict(row)), 200


@app.route("/api/customers", methods=["POST"])
@require_api_key
def api_create_customer():
    """
    POST /api/customers
    Accepts JSON body with customer fields.
    Returns the created customer record.

    Required fields:
        first_name, last_name, road, city, state,
        zip, country, phone, dob (MM/DD/YYYY)
    """
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Request body must be JSON."}), 400

    errors = {}

    first_name = str(data.get("first_name", "")).strip()
    last_name  = str(data.get("last_name",  "")).strip()
    road       = str(data.get("road",       "")).strip()
    city       = str(data.get("city",       "")).strip()
    state      = str(data.get("state",      "")).strip()
    zip_code   = str(data.get("zip",        "")).strip()
    country    = str(data.get("country",    "")).strip()
    phone      = str(data.get("phone",      "")).strip()
    dob        = str(data.get("dob",        "")).strip()

    if not first_name: errors["first_name"] = "First name is required."
    if not last_name:  errors["last_name"]  = "Last name is required."
    if not road:       errors["road"]       = "Road / street is required."
    if not city:       errors["city"]       = "City is required."
    if not state:      errors["state"]      = "State is required."
    if not zip_code:   errors["zip"]        = "ZIP code is required."
    if not country:    errors["country"]    = "Country is required."

    if not phone:
        errors["phone"] = "Phone number is required."
    elif not re.fullmatch(r"\d+", phone):
        errors["phone"] = "Phone number must contain digits only."

    if not dob:
        errors["dob"] = "Date of birth is required."
    elif not re.fullmatch(r"\d{2}/\d{2}/\d{4}", dob):
        errors["dob"] = "Date of birth must be in MM/DD/YYYY format."
    else:
        mm, dd, yyyy = dob.split("/")
        mm_i, dd_i, yyyy_i = int(mm), int(dd), int(yyyy)
        if not (1 <= mm_i <= 12):
            errors["dob"] = "Month must be between 01 and 12."
        elif not (1 <= dd_i <= 31):
            errors["dob"] = "Day must be between 01 and 31."
        elif yyyy_i < 1900 or yyyy_i > 2026:
            errors["dob"] = "Year must be between 1900 and 2026."

    if errors:
        return jsonify({"errors": errors}), 422

    with db_cursor() as cur:
        cur.execute(
            """INSERT INTO customers
               (first_name, last_name, road, city, state, zip, country, phone, dob)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
               RETURNING id""",
            (first_name, last_name, road, city, state, zip_code, country, phone, dob)
        )
        new_id = cur.fetchone()["id"]
        cur.execute("SELECT * FROM customers WHERE id = %s", (new_id,))
        row = cur.fetchone()

    return jsonify(row_to_dict(row)), 201


if __name__ == "__main__":
    init_db()
    app.run(debug=False, host="0.0.0.0", port=5000)
