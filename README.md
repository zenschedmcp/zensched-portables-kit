# ZenSched Portables Reference Kit

A copy-pasteable setup for a 1–5 truck portable-toilet and dumpster shop (construction-site units, weekend events, standing commercial accounts) that wants an AI assistant to run route scheduling, GPS-verified service proof, issue flags, and contract invoicing. ZenSched handles the live schedule, the driver's phone app, GPS check-ins at the drop site, and the photo-plus-checklist Service Proof. A small local database on your computer holds your customers, units, place cache, prices, cadence, job summaries, and invoices.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("schedule this week", "add two toilets at Harbor", "which units tipped", "who owes me money?") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## What this kit is not — read this first

**What it is:** GPS-verified proof that a driver was at the drop, a Service Proof (serviced yes/no, up to 2 unit photos, issues, notes), a local extract of those records for your own files, and invoices built from completed services.

**What it is not:**

- **Not a waste manifest.** `service_log` is *your* copy of what the driver typed on the phone (date, unit, serviced, issues, notes). It is not a landfill ticket, not a hazardous-waste shipping paper, not a DOT record, and not a substitute for whatever the landfill or your state requires you to keep. This kit does not produce those forms and does not claim you are compliant because you used it.
- **Not a signed customer ticket.** The Service Proof has no signature field. On ZenSched a signature field replaces the Submit button, so adding one would make every stop look like the driver (or the customer) had signed something. Submitting the form is just submitting the form.
- **Not a tracker on the asset.** We cache the *place* the unit sits (address + one GPS pin per site). We do not GPS-track the toilet itself, and we do not replace an RFID yard system.

If any of those is a deal-breaker, this kit is not for you. If you want route cadence, door-GPS, a photo of each unit, and a local extract you can file next to your real tickets, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (drop sites with GPS coordinates; several units at the same site share one pin; the check-in radius is a **policy** setting)
- Workers (drivers with the mobile app)
- Events (one "Portables" job per place, renewed every 60 days)
- Shifts (each scheduled unit service, with push notifications to the driver)
- GPS punches (check-in/check-out with distance-from-the-pin verification)
- The Service Proof form (serviced yes/no, up to 2 unit photos, issues, notes) and every submission
- Timesheets (verified hours worked)

**Local SQLite database (`portables-ops.db`, on your computer):**

- Customer contact and billing notes
- Units (toilet or dumpster, yard stencil, current place cache) including access notes (gate code, job-box combo) that **never leave your computer**
- Service schedules (weekly / biweekly / monthly / on-demand per unit, next service date)
- Your price list (toilet service, dumpster service, extra pump, delivery, pickup)
- Drivers
- Completed jobs with a summary of each Service Proof, the service-log extract, issue flags, and invoices
- Your settings (timezone, default driver, invoice prefix, Service Proof form id)

**Never duplicated:** the live schedule, punches, timesheets, and report photos stay in ZenSched. The local database only stores *references* to them plus a short per-job summary so you can answer "did Marco service T-14" without paying to re-read reports.

### Privacy note

Gate codes, job-box combinations, site-superintendent cell numbers, and dogs are stored only in `units.access_notes` in the local database. Customer and contact names, phones, and emails stay in the `customers` table. `SKILL.md` forbids the AI from putting any of them into a ZenSched field: locations are named by street address (`8800 FM 1826, Austin`), not by customer. Give access details to your driver yourself, by whatever channel you trust. ZenSched only ever sees the street address and the GPS pin.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `form_submissions`, `shift_list`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `portables-ops.db` on your computer.

When you say "schedule this week," the AI reads who is due from the local database (`service_schedule.next_service_date` in the next 7 days), creates one shift per unit service on ZenSched, and tells you what it did. Your driver sees the stops in the app, checks in at the site (GPS-verified), services the unit, fills in the Service Proof with a photo, and checks out. Later you say "record this week's jobs" and the AI pulls the completed shifts and proofs, saves a summary locally, advances each Yes-service date (weekly +7 days, on-demand clears it; a No leaves the date put), and flags tipped or leaking units. "Which units need attention" is a local query. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

A typical stop costs about **$0.35** on ZenSched: GPS in $0.10 + GPS out $0.10 + reading a Service Proof that has photos $0.15. Geocoding a new **place** is $0.03 once — two toilets at the same address share the pin and are not geocoded twice. The AI states the cost before it spends.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\portables-ops`
- Mac: `/Users/yourname/portables-ops`

The database file will be created automatically inside this folder the first time the AI uses it.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\portables-ops.db` (Windows) or `/portables-ops.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "portables-ops-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/portables-ops/portables-ops.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\portables-ops\\portables-ops.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Portables Co" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my portables-ops database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run the statements one at a time and confirm the tables exist. The `portables-ops.db` file now exists in your folder, pre-loaded with a starter price list you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 portables-ops.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> My business is Hill Country Portables in Austin, Texas (Central time). Save that in settings, and set up the Service Proof form.

It writes those to the `settings` table, creates the Service Proof form on ZenSched (free), and saves the form id so every stop gets it automatically.

**Check-in radius.** The default pin uses `checkin_radius_m=75` on `location_create`, but ZenSched **enforces** the radius through the account's policy, not per place. With geofencing on it raises anything under 100 m to about 91 m (300 ft), so 75 behaves as roughly a driveway circle. For a construction yard, a festival field, or a pin that lands on the road, ask the AI to "set the check-in radius to 200 m" (`policy_update`) or to move the pin onto the pad (`location_update`, free). Do not ask it to widen the radius "on that location" — that field is informational only.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a location (geocoding, $0.03), inviting a driver ($0.25), each GPS-verified check-in or check-out ($0.10), and reading a Service Proof ($0.05, or $0.15 when it has photos). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

A typical stop is about $0.35 (in + out + photo proof). A driver doing 25 stops a day is about $8.75 in meters that day, plus $0.03 the first time you add each **site** (not each unit). The AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "Add Harbor Builders, accounts@harbor.example, 512-555-0144. Two toilets T-14 and T-15 at 8800 FM 1826, Austin TX 78737, weekly $22 each starting Monday 7:00. Gate 4410, job box on the silt fence."
- "Add a one-off dumpster D-3 for Lake Fest at 210 Lakeside Dr, Austin TX 78746, Saturday 8:00, $85."
- "Invite Marco Ruiz, marco@example.com, and make him the default driver."
- "Schedule this week for Marco."
- "Record this week's jobs."
- "Which units need attention?"
- "Draft invoices for everyone with uninvoiced work."
- "Who still owes me money?"
- "Harbor paid INV-2026-0001."
- "Pick up T-15, the Harbor job is down to one toilet."
- "Extra pump Thursday at T-14."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Draft an invoice" records the invoice in your database (number, date, due date, amount, which jobs) and the AI writes out a plain-text invoice you can paste into an email or text message, with a line per unit service and a note that the visit was GPS-verified. It does **not** generate a PDF, email it for you, or collect payment. When the customer pays, tell the AI ("Harbor paid INV-2026-0001") and it marks it paid. If you outgrow this, the invoice records are simple enough to import into any accounting tool.

## Mobile app for drivers

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

When you invite a driver, they get an email, install the app, and can immediately see their stops, check in and out with GPS verification, and fill in the Service Proof with photos. The form is attached to each stop automatically. There is no signature step — they tap Submit.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `portables-ops-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set, or the clocks changed (DST) | "Set my timezone offset to -05:00 in settings" (use your own offset; Central is `-05:00` in summer and `-06:00` in winter) |
| Shift creation fails for dates a couple of months out | The place's 60-day ZenSched event has expired | Say "renew the events"; the AI runs the roll-over in `SKILL.md` and retries |
| Driver's check-in not GPS-verified at a yard | Geocoded pin is at the road, driver parked far in, or a large site | Ask the AI to widen `checkin_radius_m` with `policy_update` (not on the location), or run `location_update` / `location_refine` ($0.10) |
| Driver does not see the Service Proof | Form not assigned to that place's event | "Attach the Service Proof to Harbor's event" (`form_assign`) |
| "Units needing attention" comes back empty | Jobs not recorded yet, or the driver marked Yes / None | "Record this week's jobs" first |
| Two toilets got two GPS pins at the same address | Place cache missed | "Reuse Harbor's existing pin on T-15"; the AI copies `zensched_location_id` from the cached place |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |
| AI refuses to put a gate code in ZenSched | Working as intended | Give it to the driver directly |
| AI offers a waste manifest or a customer signature | It shouldn't | This kit does not produce those; use your landfill ticket / paper ticket |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, forms); SQLite is authoritative for CRM, the unit place-cache, cadence, proof summaries, and billing; each side stores only the other's **integer** IDs, plus a per-job report summary cached locally because submission reads are metered.

**Data model decisions.**

- **`customers` → `units` → `service_schedule` → `jobs`.** Rate and cadence live on the schedule, not the customer: one contractor can have twenty toilets on weekly service and one dumpster on-demand.
- **Units are the place cache.** `units.normalized_address` plus `customer_id` is the cache key. The first unit at a site calls `location_create(name="<street>, <city>", street_address=..., checkin_radius_m=75, idempotency_key="loc-unit-{unit_id}")` — the label is the address, never the customer name (see Privacy note). Later units at the same customer + normalized address copy `zensched_location_id` / `zensched_event_id` / `event_valid_until` and do **not** geocode again. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft.
- **Events are capped at 60 days by ZenSched**, so an event cannot be a permanent job template. The event belongs to the **place** (`zensched_location_id`), not to a single unit. Each unit holds the current event in `zensched_event_id` and its last covered date in `event_valid_until`. The agent creates a new event (`event_create(location_id, title="Portables - <street>", start_date, end_date=start+59 days, idempotency_key="event-loc-{location_id}-{YYYYMMDD}")`) whenever a shift date is later than `event_valid_until`, calls `form_assign` on it, and `UPDATE`s **every** active unit that shares that location. `units_due` exposes `event_needs_roll` per row and `events_expiring` lists places (grouped by location_id) due for renewal within 14 days. Shifts already created on the old event remain valid. When recording a completed job whose `event_id` no longer matches a unit, the agent falls back to `event_get(event_id).location_id` against `units.zensched_location_id`, then matches the unit by date/start among units at that place.
- **Cadence is next-service-date on `service_schedule`.** `frequency` is `weekly | biweekly | monthly | on-demand`. Twice-weekly is two weekly rows on the same unit. `units_due` is every active schedule with `next_service_date <= today+7` joined to its active unit and customer, emitting `start_iso` / `end_iso` (preferred start or `settings.default_shift_start`, duration from the service or `default_shift_minutes`) and the shift `idempotency_key`.
- **The `advance_service_date_on_job` trigger** fires only when `serviced = 'Yes'` and `schedule_id` is set. It writes `last_service_date` and `next_service_date`: +7 / +14 / +1 month / NULL. A `No` (could not service) leaves the date put. Recording a one-off against a recurring schedule also moves that row; `SKILL.md` tells the agent to set the date back if the owner says so.
- Rate lives on the **schedule** (`service_rate`) so a shop can charge off-list. `jobs.service_id` is what was actually done (a weekly toilet can still get an `extra_pump` job).
- `jobs.zensched_shift_id` and `drivers.zensched_worker_id` are integer `UNIQUE`. `jobs.report_dc_id` holds the form `submission_id`. `serviced` and `issues` are `CHECK`-constrained to the form's option labels.
- `fill_job_driver` sets `driver_id` from `zensched_worker_id` when the agent leaves it NULL.
- `invoices.invoice_number` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}`.
- **`units_needing_attention`** is the latest job per unit when that job is `serviced = 'No'` or `issues` in Tip / Leak / Needs pump / Other. A later Yes + None job drops the unit off the list.
- **`service_log`** is a view over recorded jobs. It does not transmit anything and is not a waste manifest.
- `units.access_notes` is the column that must never be sent to ZenSched; `SKILL.md` rule 6 enforces it. `units_due` still *selects* `access_notes` so the agent can tell the owner to pass them to the driver.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it.

**Service Proof form.** Created once with `form_create(title, fields_json, idempotency_key="form-service-proof")`; the exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's `_validate_fields`. Every field carries an explicit `identifier` so submission `data` keys are stable (`serviced`, `unit_photo`, `issues`, `notes`; section `sec_proof`). Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`, truncated at 30 characters); every option here is well under 30 characters, so nothing truncates. **No `signature` field** — the phone keeps a Submit button, and submitting is not a legal attestation. Attaching is `form_assign(form_id, event_id=...)`.

**Idempotency keys.** Deterministic, derived from local IDs:

- location: `loc-unit-{unit_id}` (first unit at a place only)
- event: `event-loc-{zensched_location_id}-{YYYYMMDD window start}`
- shift: `shift-schedule-{schedule_id}-{YYYYMMDD}`
- worker: `worker-{email}`
- form: `form-service-proof`; assignment: `assign-service-proof-{event_id}`

ZenSched caches idempotent responses for 24 hours.

**Timestamps.** `shift_create` takes `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-07T07:00:00-05:00`), never `Z`. The view builds these strings so the agent does not have to. The offset is a single stored value, so `SKILL.md` has the agent update it when DST starts or ends (Central: `-05:00` → `-06:00` in November); otherwise every shift after the change is an hour off.

**Metered reads.** `form_submissions` and `form_export` bill $0.05 per submission read ($0.15 with media); `form_export` is preferred for a week at a time. The kit stores the summary and media URLs on `jobs` on first read so later issue questions are answered from SQLite. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its **48** statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) **twice** for idempotency (seed rows not duplicated), then exercising: all **8** tables, **6** views, and **7** triggers present; every view on an empty database; the `advance_service_date_on_job` trigger for weekly (+7), biweekly (+14), monthly (+1 month), and on-demand (NULL); a `serviced='No'` job leaving `next_service_date` put; `fill_job_driver` from `zensched_worker_id`; `UNIQUE` on `zensched_shift_id` and `(customer_id, unit_code)`; every `CHECK` (`unit_type`, frequency, `preferred_start`, serviced, issues); `units_due` `start_iso` / `end_iso` / `idempotency_key` / worker / minutes; `event_needs_roll` flipping exactly when `event_valid_until < next_service_date`; inactive and +20-day rows excluded; `events_expiring` grouped by location; place-cache reuse of `zensched_location_id`; invoice numbering (auto `INV-2026-0001`, explicit number kept); `jobs_to_invoice` / `invoices_outstanding` filters; `units_needing_attention` showing Tip / No / Needs pump and clearing on a later Yes+None; cascade delete and driver set-null; `updated_at`; integer types on ZenSched ID columns. Form payload validated against `_validate_fields` (5 fields, no signature, SKILL.md byte-identical to example-workflow.md, every option key ≤ 30 characters). **217/217** checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
