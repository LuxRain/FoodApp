# Donation Dashboard Requirements

Status: proposed for admin sign-off
Primary view: all recorded donation items, including pending, accepted, quarantined, rejected, distributed, and disposed items

## Purpose

The donation dashboard gives users one searchable view of every recorded donation item and makes date urgency immediately visible. It combines intake and resulting inventory status, but it is not a donor report; no donor identity is collected or displayed.

## Default ordering

The dashboard sorts by the item's actionable date in ascending order:

1. Past dates (oldest first).
2. Today and the next 14 days (soonest first).
3. More than 14 days away (soonest first).
4. Unknown, unreadable, or absent dates.

Within the same actionable date, sort by `received_at` ascending and then stable `intake_item_id` ordering. This makes pagination deterministic even when an item has no inventory lot.

The **actionable date** is the stored printed date used for inventory rotation. The interface must display its actual date type—such as `Use by`, `Best if used by`, or `Sell by`—rather than relabeling every date as an expiration date.

## Urgency marks

Urgency is recalculated from the receiving location's current calendar date whenever the dashboard is queried or rendered. Do not persist a color that becomes stale overnight.

| Status | Rule | Color token | Required visible label | Default position |
|---|---|---|---|---:|
| Expired/past date | `days_remaining < 0` | Red | `Expired` for expiration/use-by dates; otherwise `Past date`, plus number of days | First |
| Close to date | `0 <= days_remaining <= 14` | Yellow/amber | `Due soon` plus days remaining | Second |
| Good | `days_remaining > 14` | Green | `Good` plus date | Third |
| No usable date | Date absent, unreadable, or not actionable | Gray | `No date` or `Date needs review` | Last |

Color is supplemental. Every row must also include text and an icon or shape so the view remains understandable for color-blind users and monochrome exports.

These colors represent **inventory urgency**, not a food-safety conclusion. For example, a past best-if-used-by date is a different condition from an expired infant-formula use-by date. The actual date type, disposition, and quarantine status remain visible.

## Desktop/table layout

| Column | Behavior |
|---|---|
| Urgency | Colored marker, text status, and days remaining/past |
| Item | Product name, brand, and optional thumbnail |
| Quantity | On-hand quantity and unit |
| Date | Date value plus exact type, for example `Best if used by · Oct 14, 2026` |
| Nutrition | Green/yellow/red nutrition tier shown separately from date urgency |
| Location | Current storage location |
| Inventory state | Available, quarantined, reserved, distributed, or disposed |
| Intake status | Automatically accepted or admin accepted |
| Received | Local date/time and regular user who submitted it |
| Actions | View evidence; admin-only adjust, quarantine, reject/dispose |

Do not use the same visual treatment for nutrition tier and date urgency. Date urgency uses a filled status mark and label; nutrition tier uses a separate `Nutrition: Green/Yellow/Red/Unclassified` label.

## iPhone layout

Use a grouped list rather than shrinking the desktop table. Each row shows:

- urgency marker and label;
- product name;
- quantity;
- actionable date and date type;
- location and inventory state.

Tapping a row opens lot details, evidence, nutrition/allergens, and movement history. Admin actions remain unavailable to a regular user.

## Filters and search

The dashboard supports:

- product name, brand, or barcode search;
- urgency: past date, due soon, good, or no date;
- inventory state;
- location;
- storage type;
- date range;
- nutrition tier;
- acceptance path: automatic or admin;
- admin-only exception/quarantine filters.

The default `All items` view includes every recorded item. Quick filters provide `Active inventory`, `Needs admin review`, `Quarantined`, and `Completed history` subsets without removing records from the dashboard.

## Role behavior

| Capability | Regular user | Admin |
|---|:---:|:---:|
| View items in authorized locations | Yes | Yes |
| Search, sort, and filter | Yes | Yes |
| Open item details and evidence | Yes | Yes |
| Export dashboard data | No by default | Yes |
| Adjust quantity/location | No | Yes |
| Quarantine, release, reject, or dispose | No | Yes |
| Change urgency threshold | No | Yes, through a new ruleset version |

## API contract

```http
GET /v1/donation-items?scope=all&sort=actionDate:asc&limit=50
```

Representative response item:

```json
{
  "intakeItemId": "item_01J...",
  "inventoryLotId": "lot_01J...",
  "product": {
    "name": "Low-Sodium Black Beans",
    "brand": "Example",
    "thumbnailUrl": "https://signed.example/..."
  },
  "onHand": { "quantity": 12, "unit": "can" },
  "date": {
    "type": "best_if_used_by",
    "value": "2026-10-14",
    "daysRemaining": 27,
    "urgency": "good"
  },
  "nutritionTier": "green",
  "location": { "id": "loc_01J...", "name": "Main Pantry · A3" },
  "inventoryState": "available",
  "acceptancePath": "auto_accepted",
  "receivedAt": "2026-09-17T18:42:00Z"
}
```

The API computes `daysRemaining` and `urgency` using the location timezone. The client may update the displayed day count at midnight, but the server remains authoritative.

## Database support

- Create a donation-dashboard read model joining every intake item to its optional inventory lot and latest decision.
- Add or expose `action_date`, `date_type`, intake/disposition status, inventory status, location ID, and received time.
- Add an index beginning with `organization_id`, followed by `action_date` and status fields used by quick filters.
- Use `NULLS LAST` for the default date sort.
- Derive urgency at query/read-model time; do not persist red/yellow/green as the source of truth.
- Keep pagination stable with `action_date`, `received_at`, and `intake_item_id` in the cursor.

## Acceptance criteria

1. On September 17, an expiration/use-by item dated September 16 appears red as `Expired` and above an item dated September 18; an older best-by date appears red as `Past date`.
2. Items dated September 17 through October 1 inclusive appear yellow/amber.
3. An item dated October 2 appears green.
4. An item without a usable date appears gray and after all dated items.
5. Each status is understandable without color.
6. `Best if used by`, `Sell by`, and `Use by` retain their exact meanings in the row.
7. A red nutrition tier never changes the date-urgency color, and vice versa.
8. Regular users cannot see or invoke admin-only actions.
9. The list order is stable across pages and refreshes.
10. The calculation uses the storage location's timezone, not the device timezone.
11. Pending, accepted, quarantined, rejected, distributed, and disposed items are all reachable from the default `All items` dashboard.
