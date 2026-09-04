# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers.

Shop: **Hill Country Portables**, Austin, Texas, Central time (`-05:00` in September). One construction account (two weekly toilets at the same site — place cache), one weekend dumpster, one driver, then invoice.

Access notes (gate code, job-box combo) stay in SQLite. They are never sent to ZenSched.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Portables Co, timezone_offset = -05:00,
    default_worker_id = NULL, default_shift_start = 07:00,
    default_shift_minutes = 15, invoice_due_days = 14, invoice_prefix = INV,
    service_proof_form_id = NULL, event_window_days = 60
```

## "My business is Hill Country Portables in Austin, Texas, Central time."

```
sqlite_execute: UPDATE settings SET value = 'Hill Country Portables' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-05:00' WHERE key = 'timezone_offset';
```

> Saved. I'll schedule everything in Central time (-05:00). You don't have a Service Proof form yet; it's free to create and every stop will come back with serviced yes/no, a unit photo, issues, and notes. No signature — this is an internal service record, not a waste manifest and not a customer ticket. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Service Proof"
  idempotency_key: "form-service-proof"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Service proof", "identifier": "sec_proof",
   "text": "Fill this in at the unit before you leave. Photo the unit. This is an internal service record, not a waste manifest and not a customer signature."},
  {"type": "select", "label": "Serviced", "identifier": "serviced", "required": true,
   "options": ["Yes", "No"]},
  {"type": "photo", "label": "Unit photo", "identifier": "unit_photo", "max_images": 2},
  {"type": "select", "label": "Issues", "identifier": "issues", "required": true,
   "options": ["None", "Tip", "Leak", "Needs pump", "Other"]},
  {"type": "textarea", "label": "Notes", "identifier": "notes"}
]
```

```
  → form_id: 501, fields: [ ...5 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '501' WHERE key = 'service_proof_form_id';
```

> Service Proof form created. I'll attach it to every place automatically. There is no signature step.

## "Add Harbor Builders, accounts@harbor.example, 512-555-0144. Two toilets T-14 and T-15 at 8800 FM 1826, Austin TX 78737, weekly $22 each starting Monday 2026-09-07 at 7:00. Gate 4410, job box on the silt fence."

```
sqlite_query:   SELECT service_id, price, default_minutes FROM services WHERE code = 'toilet_service';
  → 1, 22.00, 15

sqlite_execute:
  INSERT INTO customers (customer_name, contact_email, contact_phone)
  VALUES ('Harbor Builders', 'accounts@harbor.example', '512-555-0144');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO units (customer_id, unit_type, unit_code, site_name, address, city, state, zip,
                     normalized_address, access_notes)
  VALUES (1, 'toilet', 'T-14', 'Harbor job site', '8800 FM 1826', 'Austin', 'TX', '78737',
          '8800 fm 1826 austin',
          'Gate 4410. Job box on the silt fence.');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO service_schedule (unit_id, service_id, service_rate, frequency,
                                next_service_date, preferred_start)
  VALUES (1, 1, 22.00, 'weekly', '2026-09-07', '07:00');
  → lastInsertRowid = 1
```

Place-cache lookup for T-15 (`customer_id=1`, `normalized_address='8800 fm 1826 austin'`): no location yet. Insert T-15 locally first; both units get the same pin after the one geocode.

```
sqlite_execute:
  INSERT INTO units (customer_id, unit_type, unit_code, site_name, address, city, state, zip,
                     normalized_address, access_notes)
  VALUES (1, 'toilet', 'T-15', 'Harbor job site', '8800 FM 1826', 'Austin', 'TX', '78737',
          '8800 fm 1826 austin',
          'Gate 4410. Job box on the silt fence.');
  → lastInsertRowid = 2

sqlite_execute:
  INSERT INTO service_schedule (unit_id, service_id, service_rate, frequency,
                                next_service_date, preferred_start)
  VALUES (2, 1, 22.00, 'weekly', '2026-09-07', '07:15');
  → lastInsertRowid = 2
```

T-15 is staggered to 07:15 so Marco's shifts do not overlap. Agent (first metered call this session, rule 11):

> Creating Harbor's site on ZenSched costs $0.03 for geocoding. T-14 and T-15 share that pin — I will not geocode twice. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "Harbor Builders - Harbor job site"
  street_address: "8800 FM 1826, Austin, TX 78737"
  checkin_radius_m: 75
  idempotency_key: "loc-unit-1"
  → location_id: 9201, lat: 30.1921, lng: -97.9874, pin_quality: "street"
    billing: { meter: "geocode", units: 1, price: 0.03 }
```

The gate code is **not** in `notes`. It lives only in `units.access_notes`. `checkin_radius_m` on the location is informational; the enforced radius is the policy.

```
event_create:
  location_id: 9201
  title: "Portables - Harbor job site"
  start_date: "2026-09-07"
  end_date:   "2026-11-05"          ← start + 59 days (60-day cap)
  idempotency_key: "event-loc-9201-20260907"
  → event_id: 8001

form_assign:
  form_id: 501
  event_id: 8001
  idempotency_key: "assign-service-proof-8001"
  → status: "assigned", form_id: 501, event_id: 8001, policy_id: 0

sqlite_execute:
  UPDATE units SET zensched_location_id = 9201, zensched_event_id = 8001, event_valid_until = '2026-11-05'
  WHERE unit_id = 1;

sqlite_execute:
  UPDATE units SET zensched_location_id = 9201, zensched_event_id = 8001, event_valid_until = '2026-11-05'
  WHERE unit_id = 2;
```

> Added Harbor Builders, two toilets (T-14, T-15) at 8800 FM 1826. Weekly $22 each, next service Monday Sep 7 at 7:00 and 7:15. Same GPS pin for both. The gate code is saved on your computer only; give it to Marco directly. Their ZenSched event runs through Nov 5; I'll renew it automatically when scheduling gets that far.

## "Add a one-off dumpster D-3 for Lake Fest, fest@lakefest.example, 512-555-0190, at 210 Lakeside Dr, Austin TX 78746, Saturday 2026-09-12 at 8:00, $85."

Same pattern. The agent does not re-ask about the $0.03 (owner already approved geocoding this session). Frequency is `on-demand`. New place — not a cache hit.

```
sqlite_query:   SELECT service_id, default_minutes FROM services WHERE code = 'dumpster_service';
  → 2, 20

sqlite_execute:
  INSERT INTO customers (customer_name, contact_email, contact_phone)
  VALUES ('Lake Fest', 'fest@lakefest.example', '512-555-0190');
  → lastInsertRowid = 2

sqlite_execute:
  INSERT INTO units (customer_id, unit_type, unit_code, site_name, address, city, state, zip,
                     normalized_address)
  VALUES (2, 'dumpster', 'D-3', 'Lake Fest grounds', '210 Lakeside Dr', 'Austin', 'TX', '78746',
          '210 lakeside dr austin');
  → lastInsertRowid = 3

sqlite_execute:
  INSERT INTO service_schedule (unit_id, service_id, service_rate, frequency,
                                next_service_date, preferred_start)
  VALUES (3, 2, 85.00, 'on-demand', '2026-09-12', '08:00');
  → lastInsertRowid = 3

location_create:
  name: "Lake Fest - Lake Fest grounds"
  street_address: "210 Lakeside Dr, Austin, TX 78746"
  checkin_radius_m: 75
  idempotency_key: "loc-unit-3"
  → location_id: 9202

event_create:
  location_id: 9202
  title: "Portables - Lake Fest grounds"
  start_date: "2026-09-12"
  end_date:   "2026-11-10"
  idempotency_key: "event-loc-9202-20260912"
  → event_id: 8002

form_assign: form_id 501, event_id 8002, idempotency_key "assign-service-proof-8002"

sqlite_execute:
  UPDATE units SET zensched_location_id = 9202, zensched_event_id = 8002, event_valid_until = '2026-11-10'
  WHERE unit_id = 3;
```

> Added Lake Fest, dumpster D-3 at 210 Lakeside Dr. One-off service at $85, Saturday Sep 12 at 8:00. Same Service Proof. This is not a waste manifest; if the landfill wants a ticket, that's still your paper.

## "Invite Marco Ruiz, marco@example.com, and make him the default."

> Inviting a driver costs $0.25. OK?

Owner: *"yes"*

```
worker_invite:
  email: "marco@example.com"
  first_name: "Marco"
  last_name: "Ruiz"
  idempotency_key: "worker-marco@example.com"
  → worker_id: 701, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute:
  INSERT INTO drivers (driver_name, email, zensched_worker_id)
  VALUES ('Marco Ruiz', 'marco@example.com', 701);
  → lastInsertRowid = 1

sqlite_execute: UPDATE settings SET value = '701' WHERE key = 'default_worker_id';
```

> Invited Marco. He'll get an email with the app link and an activation code. He's the default driver now. Remember to give him Harbor's gate 4410 and the job-box note; I keep those off ZenSched on purpose.

Optional, if the owner wants a wider circle for construction yards:

```
policy_get: policy_id 0
policy_update:
  policy_id: 0
  settings_json: '{"geofence_enabled": true, "require_on_site": true, "checkin_radius_m": 200}'
```

The radius is on the **policy**, not on either location.

## "Schedule this week for Marco."

```
sqlite_query: SELECT * FROM units_due;
  → 2026-09-07 | Harbor Builders | T-14 | weekly | $22 | toilet_service | 15 min
               | unit 1 | evt 8001 | event_needs_roll 0 | worker 701 Marco
               | start_iso 2026-09-07T07:00:00-05:00 | end_iso 2026-09-07T07:15:00-05:00
               | shift-schedule-1-20260907
    2026-09-07 | Harbor Builders | T-15 | weekly | $22 | toilet_service | 15 min
               | unit 2 | evt 8001 | event_needs_roll 0 | worker 701 Marco
               | start_iso 2026-09-07T07:15:00-05:00 | end_iso 2026-09-07T07:30:00-05:00
               | shift-schedule-2-20260907
    2026-09-12 | Lake Fest       | D-3  | on-demand | $85 | dumpster_service | 20 min
               | unit 3 | evt 8002 | event_needs_roll 0 | worker 701 Marco
               | start_iso 2026-09-12T08:00:00-05:00 | end_iso 2026-09-12T08:20:00-05:00
               | shift-schedule-3-20260912
  (3 rows)

shift_create:
  event_id: 8001
  worker_id: 701
  start: "2026-09-07T07:00:00-05:00"
  end:   "2026-09-07T07:15:00-05:00"
  idempotency_key: "shift-schedule-1-20260907"
  → shift_id: 89011, status: "scheduled", forms_installed: [501]

shift_create:
  event_id: 8001
  worker_id: 701
  start: "2026-09-07T07:15:00-05:00"
  end:   "2026-09-07T07:30:00-05:00"
  idempotency_key: "shift-schedule-2-20260907"
  → shift_id: 89012, status: "scheduled", forms_installed: [501]

shift_create:
  event_id: 8002
  worker_id: 701
  start: "2026-09-12T08:00:00-05:00"
  end:   "2026-09-12T08:20:00-05:00"
  idempotency_key: "shift-schedule-3-20260912"
  → shift_id: 89013, status: "scheduled", forms_installed: [501]
```

> Scheduled 3 stops for Marco this week:
> - Mon 9/7  7:00–7:15  Harbor Builders T-14, 8800 FM 1826 — toilet service
> - Mon 9/7  7:15–7:30  Harbor Builders T-15, same pin
> - Sat 9/12 8:00–8:20  Lake Fest D-3, 210 Lakeside Dr — dumpster service
>
> Marco has been notified in the app and every stop has the Service Proof attached. Each stop is about $0.35 once he punches in and out and you read the photo proof ($0.10 + $0.10 + $0.15). Pass him the gate code and the job-box note yourself.

Nothing is written to SQLite here. If the owner asks "schedule this week" again, the identical idempotency keys make ZenSched return the same three shifts instead of creating duplicates.

## Marco does the work

Monday 6:58, at 8800 FM 1826, in the ZenSched app: **Check in** on T-14 (GPS: 22 m from the pin, verified, $0.10). Services the unit. Opens **Service Proof**: Serviced = Yes; one photo; Issues = Tip; Notes = "On its side by the silt fence, stood it back up, pumped." Submits (no signature). **Check out** 7:14 ($0.10).

Monday 7:16, same pin, T-15 shift: check in. Services. Service Proof: Serviced = Yes; one photo; Issues = None; Notes blank. Check out 7:28.

Saturday 7:55, 210 Lakeside Dr: check in at D-3. Swaps. Service Proof: Serviced = Yes; two photos; Issues = None; Notes = "Swap complete, empty on the pad." Check out 8:18.

## "Record this week's jobs."

```
shift_list:
  date_from: "2026-09-07"
  date_to:   "2026-09-13"
  status:    "checked_out"
  → shifts: [
      { shift_id: 89011, event_id: 8001, worker_id: 701, date: "2026-09-07", start: "07:00", end: "07:15", status: "checked_out" },
      { shift_id: 89012, event_id: 8001, worker_id: 701, date: "2026-09-07", start: "07:15", end: "07:30", status: "checked_out" },
      { shift_id: 89013, event_id: 8002, worker_id: 701, date: "2026-09-12", start: "08:00", end: "08:20", status: "checked_out" }
    ], count: 3

sqlite_query: SELECT zensched_shift_id FROM jobs WHERE zensched_shift_id IN (89011, 89012, 89013);
  → (none; not yet recorded)

sqlite_query: SELECT u.unit_id, u.customer_id, u.unit_code, ss.schedule_id, ss.service_id, ss.service_rate
              FROM units u JOIN service_schedule ss ON ss.unit_id = u.unit_id
              WHERE u.zensched_event_id = 8001
              ORDER BY ss.preferred_start;
  → 1, 1, T-14, 1, 1, 22.00
    2, 1, T-15, 2, 1, 22.00
```

Agent (metered read, rule 11):

> There are 3 service proofs to pull, all with photos, so about $0.45 ($0.15 each). I'll read them once and keep the summaries locally. That's the last piece of the ~$0.35/stop meter (punches already billed when Marco checked in and out). OK?

Owner: *"go"*

```
form_export:
  form_id: 501
  since: "2026-09-07"
  until: "2026-09-13"
  format: "json"
  → row_count: 3, rows: [
      { submission_id: 5501, worker_id: 701, event_id: 8001, submitted_at: "2026-09-07 07:12:40",
        data: { serviced: "yes", issues: "tip",
                notes: "On its side by the silt fence, stood it back up, pumped." },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../t14.jpg" } ] },
      { submission_id: 5502, worker_id: 701, event_id: 8001, submitted_at: "2026-09-07 07:26:11",
        data: { serviced: "yes", issues: "none", notes: "" },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../t15.jpg" } ] },
      { submission_id: 5503, worker_id: 701, event_id: 8002, submitted_at: "2026-09-12 08:16:02",
        data: { serviced: "yes", issues: "none",
                notes: "Swap complete, empty on the pad." },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../d3a.jpg" },
                 { cdn_url: "https://cdn.zensched.com/m/.../d3b.jpg" } ] }
    ]
    billing: { meter: "form_media", units: 3, price: 0.45 }

shift_status: shift_id 89011
  → status "checked_out", actual_in "2026-09-07T06:58:10-05:00", actual_out "2026-09-07T07:14:05-05:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 22 },
               { type: "out", gps_verified: true, distance_from_site_m: 18 } ]
(free)

sqlite_execute:
  INSERT INTO jobs (customer_id, unit_id, schedule_id, service_id, completed_date, amount,
                    zensched_shift_id, zensched_event_id, zensched_worker_id,
                    actual_in, actual_out, duration_minutes, gps_verified, report_dc_id,
                    serviced, issues, notes, photo_urls)
  VALUES (1, 1, 1, 1, '2026-09-07', 22.00,
          89011, 8001, 701,
          '2026-09-07T06:58:10-05:00', '2026-09-07T07:14:05-05:00', 16, 1, 5501,
          'Yes', 'Tip',
          'On its side by the silt fence, stood it back up, pumped.',
          '["https://cdn.zensched.com/m/.../t14.jpg"]');
  -- trigger: service_schedule.next_service_date for T-14 → 2026-09-14 (+7)
  -- trigger: jobs.driver_id → 1 (Marco)

sqlite_execute:
  INSERT INTO jobs (customer_id, unit_id, schedule_id, service_id, completed_date, amount,
                    zensched_shift_id, zensched_event_id, zensched_worker_id,
                    actual_in, actual_out, duration_minutes, gps_verified, report_dc_id,
                    serviced, issues, notes, photo_urls)
  VALUES (1, 2, 2, 1, '2026-09-07', 22.00,
          89012, 8001, 701,
          '2026-09-07T07:16:02-05:00', '2026-09-07T07:28:18-05:00', 12, 1, 5502,
          'Yes', 'None', '',
          '["https://cdn.zensched.com/m/.../t15.jpg"]');
  -- trigger: T-15 next → 2026-09-14

sqlite_execute:
  INSERT INTO jobs (customer_id, unit_id, schedule_id, service_id, completed_date, amount,
                    zensched_shift_id, zensched_event_id, zensched_worker_id,
                    actual_in, actual_out, duration_minutes, gps_verified, report_dc_id,
                    serviced, issues, notes, photo_urls)
  VALUES (2, 3, 3, 2, '2026-09-12', 85.00,
          89013, 8002, 701,
          '2026-09-12T07:55:02-05:00', '2026-09-12T08:18:40-05:00', 23, 1, 5503,
          'Yes', 'None',
          'Swap complete, empty on the pad.',
          '["https://cdn.zensched.com/m/.../d3a.jpg","https://cdn.zensched.com/m/.../d3b.jpg"]');
  -- trigger: Lake Fest on-demand next → NULL
```

> Recorded 3 jobs, all GPS-verified.
>
> **Attention — Monday, Harbor T-14:** Marco marked **Tip**: *"On its side by the silt fence, stood it back up, pumped."* 1 photo. Next weekly still Sep 14.
>
> Harbor T-15: serviced, no issues, next due Sep 14. Lake Fest D-3: swap complete, on-demand date cleared.

## "Which units need attention?"

```
sqlite_query: SELECT * FROM units_needing_attention;
  → T-14 | toilet | Harbor job site | Harbor Builders
    | 2026-09-07 | Yes | Tip | On its side by the silt fence...
```

T-15 and D-3 (Yes / None) are omitted.

> T-14 at Harbor is the only open issue: tipped on Sep 7, Marco stood it back up. Want me to schedule a mid-week look, or leave the weekly as-is?

## "Draft invoices for everyone with uninvoiced work."

```
sqlite_query: SELECT * FROM jobs_to_invoice;
  → Harbor Builders | 2 jobs |  44.00 | 2026-09-07 .. 2026-09-07
    Lake Fest       | 1 job  |  85.00 | 2026-09-12 .. 2026-09-12

sqlite_execute:
  INSERT INTO invoices (customer_id, invoice_date, due_date, total_amount, line_items)
  SELECT j.customer_id, date('now'),
         date('now', '+' || (SELECT value FROM settings WHERE key = 'invoice_due_days') || ' days'),
         SUM(j.amount),
         json_group_array(json_object('job_id', j.job_id, 'date', j.completed_date, 'service', s.service_name,
                                      'unit', u.unit_code, 'amount', j.amount, 'shift_id', j.zensched_shift_id,
                                      'serviced', j.serviced, 'issues', j.issues))
  FROM jobs j JOIN services s ON s.service_id = j.service_id JOIN units u ON u.unit_id = j.unit_id
  WHERE j.invoiced = 0 AND j.customer_id = 1 GROUP BY j.customer_id;

sqlite_execute: UPDATE jobs SET invoiced = 1 WHERE invoiced = 0 AND customer_id = 1;
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-12 | 2026-09-26 | 44.00     (number assigned by trigger)

(same three statements for customer 2 → INV-2026-0002, 85.00)
```

The agent then writes the invoices out as text:

> Here are your two invoices. Paste each into an email or text.
>
> ```
> Hill Country Portables
> Invoice INV-2026-0001
> To: Harbor Builders (accounts@harbor.example)
> Date: Sep 12, 2026    Due: Sep 26, 2026
>
>   Sep 7    Portable toilet service, T-14, Harbor job site    $22.00
>   Sep 7    Portable toilet service, T-15, Harbor job site    $22.00
>
> Total due: $44.00
> Visits GPS-verified at the site.
> ```
>
> ```
> Hill Country Portables
> Invoice INV-2026-0002
> To: Lake Fest (fest@lakefest.example)
> Date: Sep 12, 2026    Due: Sep 26, 2026
>
>   Sep 12   Dumpster service, D-3, Lake Fest grounds          $85.00
>
> Total due: $85.00
> Visit GPS-verified at the site.
> ```
>
> Say "sent" when they're out and I'll note the date.

## "Sent. Harbor already paid."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now') WHERE invoice_number IN ('INV-2026-0001', 'INV-2026-0002');
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now') WHERE invoice_number = 'INV-2026-0001';
```

> Marked both sent and INV-2026-0001 paid. Lake Fest's $85 (INV-2026-0002) is outstanding, due Sep 26.

## Eight weeks later: "Schedule this week."

```
sqlite_query: SELECT * FROM units_due;
  → 2026-11-09 | Harbor T-14 | weekly | evt 8001 | event_valid_until 2026-11-05 | event_needs_roll 1 | loc 9201
    2026-11-09 | Harbor T-15 | weekly | evt 8001 | event_valid_until 2026-11-05 | event_needs_roll 1 | loc 9201

event_create:
  location_id: 9201
  title: "Portables - Harbor job site"
  start_date: "2026-11-09"
  end_date:   "2027-01-07"
  idempotency_key: "event-loc-9201-20261109"
  → event_id: 8101

form_assign: form_id 501, event_id 8101, idempotency_key "assign-service-proof-8101"
sqlite_execute: UPDATE units SET zensched_event_id = 8101, event_valid_until = '2027-01-07'
                WHERE zensched_location_id = 9201 AND is_active = 1;

shift_create: event_id 8101, worker_id 701, start "2026-11-09T07:00:00-06:00",
              end "2026-11-09T07:15:00-06:00", idempotency_key "shift-schedule-1-20261109"
shift_create: event_id 8101, worker_id 701, start "2026-11-09T07:15:00-06:00",
              end "2026-11-09T07:30:00-06:00", idempotency_key "shift-schedule-2-20261109"
```

> Scheduled Harbor T-14 and T-15 for Mon Nov 9 7:00 and 7:15. Their ZenSched event was about to expire (Nov 5), so I renewed the **place** once through Jan 7 and copied it onto both toilets. Lake Fest has no next date (on-demand) so it is not on this week's list.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Harbor contact, Lake Fest one-off, prices, weekly cadence | SQLite | CRM; ZenSched does not model rates or recurrence |
| Gate code, job-box combo | SQLite **only** | Privacy; never sent to ZenSched |
| Each **place's** GPS location (shared by T-14 and T-15) | ZenSched (integer ID on both `units` rows) | Needed for geofenced check-in; geocoded once |
| Each place's current ≤60-day event and its end date | ZenSched (integer ID + `event_valid_until` on every unit at the place) | Shifts hang off events; renewed by the agent once per location |
| The Service Proof form | ZenSched (ID in `settings`) | Installed on the driver's phone per shift |
| Marco, his invite, his app | ZenSched (integer ID in `drivers`) | Workforce and notifications |
| The week's three shifts | ZenSched only | Live schedule; never copied |
| GPS punches, actual times | ZenSched only | Verified record; queried via `shift_status` / `timesheet_export` |
| Three service proofs with photos | ZenSched (originals); summary + photo URLs in `jobs` | Read once (metered), then issues / invoices from SQLite |
| Three `jobs` rows referencing shift and submission IDs | SQLite | Billing + service-log extract + attention list |
| Two invoices, one paid | SQLite | Billing |
