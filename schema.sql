-- ZenSched Portables Local Database Schema
-- SQLite database for CRM, unit place-cache, route cadence, service-proof
-- summaries, and contract billing for portable-toilet and dumpster routes.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my portables-ops database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 portables-ops.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- NOT A WASTE MANIFEST. service_log is the owner's local extract from the
-- Service Proof (date, unit, serviced yes/no, issues, notes). It is not a
-- landfill ticket, not a hazardous-waste shipping paper, not a DOT record,
-- and not a signed customer acceptance. Licensed haulers still keep whatever
-- their state or the landfill requires, on their own forms.
--
-- PRIVACY: units.access_notes (gate codes, job-box combos, site-super cell,
-- dogs) live ONLY in this file on your computer. They are never sent to
-- ZenSched. SKILL.md forbids the agent from putting them in any ZenSched
-- notes field.
--
-- DATA MODEL
--   customers → units (toilet | dumpster, with a place cache) →
--   service_schedule (recurring cadence per unit) → jobs (completed stops).
--   Several units at the same site reuse one ZenSched location (the place
--   cache). Look up customer_id + normalized_address before geocoding.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, default driver, business name, form id).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Portables Co');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_worker_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_start', '07:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_minutes', '15');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '14');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('service_proof_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');

-- Services: your price list. Seeded with common route items; edit prices freely.
-- jobs.service_id is what was actually done (a weekly toilet can still get
-- an extra_pump or a pickup).
CREATE TABLE IF NOT EXISTS services (
  service_id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,                        -- short handle: 'toilet_service'
  service_name TEXT NOT NULL,                       -- shown on invoices
  default_minutes INTEGER NOT NULL,                 -- shift length on ZenSched
  price REAL NOT NULL,                              -- default per-service dollars
  is_active INTEGER DEFAULT 1,
  notes TEXT
);

INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('toilet_service', 'Portable toilet service', 15, 22.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('dumpster_service', 'Dumpster service', 20, 85.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('extra_pump', 'Extra pump-out', 15, 45.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('delivery', 'Unit delivery', 30, 75.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('pickup', 'Unit pickup', 30, 75.00);

-- Customers: the contractor, event, or site that pays the contract.
-- Cadence and rate live on service_schedule (per unit), not here.
CREATE TABLE IF NOT EXISTS customers (
  customer_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_name TEXT NOT NULL,
  contact_email TEXT,
  contact_phone TEXT,
  billing_notes TEXT,                               -- 'Net 14', 'pays by check on Friday', ...
  is_active INTEGER DEFAULT 1,                      -- 0 = paused / cancelled
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Units: one portable toilet or dumpster, plus its current place cache.
-- The place cache is the drop address and the ZenSched LOCATION / EVENT for
-- that site. Several units at the same customer + normalized_address SHARE
-- zensched_location_id and the current event (do not geocode twice).
-- One ZenSched EVENT per place per rolling window of at most 60 days
-- (ZenSched caps event length). When a visit date is later than
-- event_valid_until, the agent rolls a new event and updates EVERY unit
-- that shares that location_id.
CREATE TABLE IF NOT EXISTS units (
  unit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  unit_type TEXT NOT NULL
    CHECK (unit_type IN ('toilet', 'dumpster')),
  unit_code TEXT NOT NULL,                          -- yard stencil: 'T-14', 'D-3'
  site_name TEXT,                                   -- 'Harbor job site', 'Lake Fest grounds'
  address TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT,
  state TEXT,
  zip TEXT,
  normalized_address TEXT NOT NULL,                 -- lowercase, collapsed spaces, no commas; place-cache key
  access_notes TEXT,                                -- LOCAL ONLY: gate code, job-box combo, dogs, super cell
  zensched_location_id INTEGER,                     -- from location_create (shared across units at this place)
  zensched_event_id INTEGER,                        -- from event_create (current <=60-day window for the place)
  event_valid_until TEXT,                           -- ISO date: last day the current event covers
  is_active INTEGER DEFAULT 1,                      -- 0 = picked up / in the yard
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  UNIQUE (customer_id, unit_code)
);

-- Drivers: your roster. zensched_worker_id comes from worker_invite.
CREATE TABLE IF NOT EXISTS drivers (
  driver_id INTEGER PRIMARY KEY AUTOINCREMENT,
  driver_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Service schedule: one recurring (or on-demand) cadence per unit.
-- A unit may have more than one row (weekly service + a one-off extra pump).
-- Twice-weekly service is TWO weekly rows on the same unit with different
-- next_service_date (e.g. Monday and Thursday).
-- next_service_date is advanced by trigger when a job with serviced='Yes'
-- is recorded against this schedule_id.
CREATE TABLE IF NOT EXISTS service_schedule (
  schedule_id INTEGER PRIMARY KEY AUTOINCREMENT,
  unit_id INTEGER NOT NULL,
  service_id INTEGER NOT NULL,
  service_rate REAL NOT NULL,                       -- price per service (may differ from the list)
  frequency TEXT NOT NULL
    CHECK (frequency IN ('weekly', 'biweekly', 'monthly', 'on-demand')),
  next_service_date TEXT,                           -- ISO date: '2026-09-07'
  last_service_date TEXT,                           -- set automatically when a Yes job is recorded
  preferred_start TEXT                              -- 'HH:MM' 24-hour local; NULL = settings.default_shift_start
    CHECK (preferred_start IS NULL OR preferred_start GLOB '[0-2][0-9]:[0-5][0-9]'),
  zensched_worker_id INTEGER,                       -- preferred driver; NULL = settings.default_worker_id
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (unit_id) REFERENCES units(unit_id) ON DELETE CASCADE,
  FOREIGN KEY (service_id) REFERENCES services(service_id)
);

-- Jobs: one row per COMPLETED stop, linked to the ZenSched shift and the
-- Service Proof form submission. This is the billing record plus a small
-- summary of the proof so later questions are a local query.
-- serviced / issues are CHECK-constrained to the form's option labels.
CREATE TABLE IF NOT EXISTS jobs (
  job_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  unit_id INTEGER NOT NULL,
  schedule_id INTEGER,                              -- the cadence row this stop fulfilled
  service_id INTEGER NOT NULL,
  driver_id INTEGER,                                -- local roster row (trigger fills from worker id)
  completed_date TEXT NOT NULL,                     -- ISO date: '2026-09-07'
  amount REAL NOT NULL,
  zensched_shift_id INTEGER UNIQUE,                 -- prevents recording the same shift twice
  zensched_event_id INTEGER,
  zensched_worker_id INTEGER,
  actual_in TEXT,                                   -- from shift_status / timesheet_export
  actual_out TEXT,
  duration_minutes INTEGER,
  gps_verified INTEGER,                             -- 1 if the check-in punch was on site
  report_dc_id INTEGER,                             -- Service Proof submission_id
  serviced TEXT                                     -- form option label
    CHECK (serviced IS NULL OR serviced IN ('Yes', 'No')),
  issues TEXT                                       -- form option label
    CHECK (issues IS NULL OR issues IN ('None', 'Tip', 'Leak', 'Needs pump', 'Other')),
  notes TEXT,                                       -- Service Proof notes
  photo_urls TEXT,                                  -- JSON array of media URLs from the report
  invoiced INTEGER DEFAULT 0,                       -- 1 = included in an invoice
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  FOREIGN KEY (unit_id) REFERENCES units(unit_id) ON DELETE CASCADE,
  FOREIGN KEY (schedule_id) REFERENCES service_schedule(schedule_id) ON DELETE SET NULL,
  FOREIGN KEY (service_id) REFERENCES services(service_id),
  FOREIGN KEY (driver_id) REFERENCES drivers(driver_id) ON DELETE SET NULL
);

-- Invoices: billing records.
-- invoice_number is filled in automatically by a trigger if left NULL.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- human-readable: 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,                           -- 1 = paid, 0 = unpaid
  paid_date TEXT,
  sent_date TEXT,                                   -- when you actually emailed/texted it
  line_items TEXT,                                  -- JSON array of job references
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_units_customer ON units(customer_id);
CREATE INDEX IF NOT EXISTS idx_units_place ON units(customer_id, normalized_address);
CREATE INDEX IF NOT EXISTS idx_units_zensched_location ON units(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_units_zensched_event ON units(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_schedule_unit ON service_schedule(unit_id);
CREATE INDEX IF NOT EXISTS idx_schedule_next ON service_schedule(next_service_date, is_active);
CREATE INDEX IF NOT EXISTS idx_drivers_worker ON drivers(zensched_worker_id);
CREATE INDEX IF NOT EXISTS idx_jobs_customer ON jobs(customer_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_jobs_unit ON jobs(unit_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_jobs_invoiced ON jobs(invoiced);
CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_customer_timestamp
AFTER UPDATE ON customers
BEGIN
  UPDATE customers SET updated_at = datetime('now') WHERE customer_id = NEW.customer_id;
END;

CREATE TRIGGER IF NOT EXISTS update_unit_timestamp
AFTER UPDATE ON units
BEGIN
  UPDATE units SET updated_at = datetime('now') WHERE unit_id = NEW.unit_id;
END;

CREATE TRIGGER IF NOT EXISTS update_driver_timestamp
AFTER UPDATE ON drivers
BEGIN
  UPDATE drivers SET updated_at = datetime('now') WHERE driver_id = NEW.driver_id;
END;

CREATE TRIGGER IF NOT EXISTS update_schedule_timestamp
AFTER UPDATE ON service_schedule
BEGIN
  UPDATE service_schedule SET updated_at = datetime('now') WHERE schedule_id = NEW.schedule_id;
END;

-- Fill driver_id from the roster when the agent only has the ZenSched worker id.
CREATE TRIGGER IF NOT EXISTS fill_job_driver
AFTER INSERT ON jobs
WHEN NEW.driver_id IS NULL AND NEW.zensched_worker_id IS NOT NULL
BEGIN
  UPDATE jobs
  SET driver_id = (SELECT driver_id FROM drivers WHERE zensched_worker_id = NEW.zensched_worker_id)
  WHERE job_id = NEW.job_id;
END;

-- Recording a completed Yes-service job automatically advances that
-- schedule's cadence. on-demand clears the next date. A No (could not
-- service) does NOT move the date — the stop stays due. The agent should
-- NOT hand-maintain next_service_date after a Yes job. A one-off recorded
-- against a recurring schedule also moves the cadence; if the owner wants
-- the regular stop kept, set next_service_date back explicitly.
CREATE TRIGGER IF NOT EXISTS advance_service_date_on_job
AFTER INSERT ON jobs
WHEN NEW.serviced = 'Yes' AND NEW.schedule_id IS NOT NULL
BEGIN
  UPDATE service_schedule
  SET last_service_date = NEW.completed_date,
      next_service_date = CASE frequency
        WHEN 'weekly'    THEN date(NEW.completed_date, '+7 days')
        WHEN 'biweekly'  THEN date(NEW.completed_date, '+14 days')
        WHEN 'monthly'   THEN date(NEW.completed_date, '+1 month')
        ELSE NULL                                    -- on-demand: no automatic next visit
      END
  WHERE schedule_id = NEW.schedule_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Who is due in the next 7 days (today + 6). The agent's weekly scheduling
-- query. One row = one shift_create call. Columns ending in _iso are ready
-- to pass as shift_create start/end; idempotency_key is ready too.
-- event_needs_roll = 1 means create a new ZenSched event first (see SKILL.md)
-- for the PLACE (shared location), not per unit.
-- access_notes is included so the agent can tell the owner to pass it to the
-- driver; it must never go into a ZenSched field.
CREATE VIEW IF NOT EXISTS units_due AS
SELECT
  ss.schedule_id,
  ss.frequency,
  ss.service_rate,
  ss.next_service_date,
  COALESCE(ss.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')) AS start_time,
  sv.service_id,
  sv.code                                    AS service_code,
  sv.service_name,
  COALESCE(sv.default_minutes, CAST((SELECT value FROM settings WHERE key = 'default_shift_minutes') AS INTEGER)) AS default_minutes,
  u.unit_id,
  u.unit_type,
  u.unit_code,
  u.site_name,
  u.address,
  u.city,
  u.state,
  u.zip,
  u.normalized_address,
  u.access_notes,
  u.zensched_location_id,
  u.zensched_event_id,
  u.event_valid_until,
  CASE WHEN u.event_valid_until IS NULL OR u.event_valid_until < ss.next_service_date THEN 1 ELSE 0 END AS event_needs_roll,
  c.customer_id,
  c.customer_name,
  c.contact_email,
  c.contact_phone,
  COALESCE(ss.zensched_worker_id, (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id')) AS worker_id,
  (SELECT d.driver_name FROM drivers d
    WHERE d.zensched_worker_id = COALESCE(ss.zensched_worker_id,
           (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id'))) AS driver_name,
  ss.next_service_date || 'T'
    || COALESCE(ss.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
    || ':00' || (SELECT value FROM settings WHERE key = 'timezone_offset') AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(
      ss.next_service_date || ' '
      || COALESCE(ss.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
      || ':00',
      '+' || COALESCE(sv.default_minutes, CAST((SELECT value FROM settings WHERE key = 'default_shift_minutes') AS INTEGER)) || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset') AS end_iso,
  'shift-schedule-' || ss.schedule_id || '-' || strftime('%Y%m%d', ss.next_service_date) AS idempotency_key
FROM service_schedule ss
JOIN units u ON u.unit_id = ss.unit_id AND u.is_active = 1
JOIN customers c ON c.customer_id = u.customer_id AND c.is_active = 1
LEFT JOIN services sv ON sv.service_id = ss.service_id
WHERE ss.is_active = 1
  AND ss.next_service_date IS NOT NULL
  AND ss.next_service_date <= date('now', '+7 days')
ORDER BY ss.next_service_date, COALESCE(ss.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')), c.customer_name, u.unit_code;

-- Places (unique location_id on active units) whose current ZenSched event
-- expires within 14 days (or has none) and that belong to an active customer.
-- Roll these proactively, then copy the new event onto every unit that
-- shares the location.
CREATE VIEW IF NOT EXISTS events_expiring AS
SELECT
  u.zensched_location_id,
  MIN(u.zensched_event_id) AS zensched_event_id,
  MIN(u.event_valid_until) AS event_valid_until,
  MIN(u.site_name)         AS site_name,
  MIN(u.address)           AS address,
  MIN(c.customer_name)     AS customer_name,
  COUNT(*)                 AS unit_count
FROM units u
JOIN customers c ON c.customer_id = u.customer_id AND c.is_active = 1
WHERE u.is_active = 1
  AND u.zensched_location_id IS NOT NULL
  AND (u.event_valid_until IS NULL OR u.event_valid_until <= date('now', '+14 days'))
GROUP BY u.zensched_location_id
ORDER BY event_valid_until;

-- Completed work that has not been invoiced yet, grouped by customer.
CREATE VIEW IF NOT EXISTS jobs_to_invoice AS
SELECT
  c.customer_id,
  c.customer_name,
  c.contact_email,
  c.billing_notes,
  COUNT(j.job_id)       AS job_count,
  SUM(j.amount)         AS total_amount,
  MIN(j.completed_date) AS first_job_date,
  MAX(j.completed_date) AS last_job_date
FROM jobs j
JOIN customers c ON c.customer_id = j.customer_id
WHERE j.invoiced = 0
GROUP BY c.customer_id
ORDER BY c.customer_name;

-- Unpaid invoices, oldest first.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  c.customer_name,
  c.contact_email,
  i.invoice_date,
  i.due_date,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue
FROM invoices i
JOIN customers c ON c.customer_id = i.customer_id
WHERE i.paid = 0
ORDER BY i.due_date;

-- Latest proof per unit when the driver marked not-serviced or an issue.
-- A later Yes + None job drops the unit off this list.
CREATE VIEW IF NOT EXISTS units_needing_attention AS
SELECT
  u.unit_id,
  u.unit_code,
  u.unit_type,
  u.site_name,
  u.address,
  c.customer_name,
  j.job_id,
  j.completed_date,
  j.serviced,
  j.issues,
  j.notes,
  j.photo_urls,
  j.zensched_shift_id
FROM jobs j
JOIN units u ON u.unit_id = j.unit_id AND u.is_active = 1
JOIN customers c ON c.customer_id = j.customer_id
WHERE (j.serviced = 'No' OR j.issues IN ('Tip', 'Leak', 'Needs pump', 'Other'))
  AND NOT EXISTS (
    SELECT 1 FROM jobs later
    WHERE later.unit_id = j.unit_id
      AND (later.completed_date > j.completed_date
           OR (later.completed_date = j.completed_date AND later.job_id > j.job_id))
  )
ORDER BY j.completed_date DESC, c.customer_name, u.unit_code;

-- Owner's local service extract: one row per recorded stop. This is the
-- owner's copy, not a waste manifest and not a signed customer ticket.
CREATE VIEW IF NOT EXISTS service_log AS
SELECT
  j.job_id,
  j.completed_date,
  u.unit_code,
  u.unit_type,
  u.site_name,
  u.address,
  u.city,
  u.state,
  c.customer_name,
  sv.service_name,
  j.serviced,
  j.issues,
  j.notes,
  COALESCE(d.driver_name, 'driver ' || j.zensched_worker_id) AS driver,
  j.gps_verified,
  j.amount,
  j.zensched_shift_id,
  j.report_dc_id
FROM jobs j
JOIN units u ON u.unit_id = j.unit_id
JOIN customers c ON c.customer_id = j.customer_id
LEFT JOIN services sv ON sv.service_id = j.service_id
LEFT JOIN drivers d ON d.driver_id = j.driver_id
ORDER BY j.completed_date DESC, c.customer_name, u.unit_code;
