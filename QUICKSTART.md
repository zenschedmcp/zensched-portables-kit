# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "What this kit is not" section of `README.md`. Short version: this is GPS-verified route proof plus a local extract of the Service Proof. It is **not** a waste manifest and **not** a signed customer ticket.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\portables-ops` (Windows) or `/Users/yourname/portables-ops` (Mac). Note the full path.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\portables-ops\\portables-ops.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "Hill Country Portables". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my portables-ops database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> My business is Hill Country Portables in Austin, Texas, Central time. Save that to settings and create the Service Proof form.

The AI saves your settings and calls `form_create` once (free) to build the Service Proof your drivers fill in: serviced Yes/No, up to 2 unit photos, issues (None / Tip / Leak / Needs pump / Other), notes. No signature. It stores the form id so every stop gets it.

## 6. Add your first customer and a one-off

> Add Harbor Builders, accounts@harbor.example, 512-555-0144. Two toilets T-14 and T-15 at 8800 FM 1826, Austin TX 78737, weekly $22 each starting Monday 2026-09-07 at 7:00. Gate 4410, job box on the silt fence.

> Add a one-off dumpster D-3 for Lake Fest, fest@lakefest.example, 512-555-0190, at 210 Lakeside Dr, Austin TX 78746, Saturday 2026-09-12 at 8:00, $85.

Behind the scenes the AI inserts the customers, units, and service_schedule rows, calls `location_create` once per **place** (geocode, $0.03 — T-15 reuses T-14's pin), creates a 60-day `event_create` for each place, attaches the Service Proof with `form_assign`, and saves the IDs. Gate notes go only into the local database. You just see a confirmation.

## 7. Invite your driver

> Invite Marco Ruiz at marco@example.com as a driver and make him my default.

Marco gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)), and activates. Give him the gate code and job-box note yourself; the AI will not put them in ZenSched.

## 8. Schedule the week

> Schedule this week for Marco.

The AI reads `units_due`, creates one shift per unit service on ZenSched, and summarizes by day. Marco gets a push notification for each, with the Service Proof attached. It will confirm each stop is about $0.35 once he punches and you read the photo proof.

## 9. After the work is done

> Record this week's jobs, show me units that need attention, then draft invoices for anyone with uninvoiced work.

The AI pulls the completed, GPS-verified shifts and the Service Proofs from ZenSched (reading records is metered, so it tells you the cost first), saves a per-job summary, advances Harbor's weekly dates and clears Lake Fest's on-demand date, flags any Tip / Leak / Needs pump / missed service, creates invoice records, and writes out each invoice as text you can paste into an email.

> Harbor paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the waste-manifest boundary, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
