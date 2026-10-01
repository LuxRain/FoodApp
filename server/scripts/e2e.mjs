import { randomUUID } from "node:crypto";

const baseURL = process.env.API_URL ?? "http://127.0.0.1:3000/v1";
const organizationID = "00000000-0000-4000-8000-000000000001";
const locationID = "00000000-0000-4000-8000-000000000101";
const productID = "00000000-0000-4000-8000-000000000201";
const runID = randomUUID();
const regularHeaders = {
  "content-type": "application/json",
  "x-user-id": "regular-demo",
  "x-organization-id": organizationID,
  "x-role": "regular_user",
};

async function request(path, options = {}, expectedStatus = 200) {
  const response = await fetch(`${baseURL}${path}`, { ...options, headers: { ...regularHeaders, ...options.headers } });
  const body = await response.json();
  if (response.status !== expectedStatus) throw new Error(`${path}: expected ${expectedStatus}, received ${response.status}: ${JSON.stringify(body)}`);
  return body;
}

const lookup = await request("/product-lookups", { method: "POST", body: JSON.stringify({ rawCode: "012345678905", scheme: "upc_a" }) }, 201);
if (lookup.candidates[0]?.productId !== productID) throw new Error("Internal catalog product lookup failed");

const session = await request("/intake-sessions", {
  method: "POST",
  body: JSON.stringify({ receivingLocationId: locationID, receivedAt: new Date().toISOString(), sourceChannel: "walk_in", clientMutationId: `e2e-session-${runID}` }),
}, 201);

const item = await request(`/intake-sessions/${session.id}/items`, {
  method: "POST",
  body: JSON.stringify({
    productId: productID, productName: "Low-Sodium Black Beans", brand: "Community Pantry", identitySource: "barcode",
    quantity: 12, quantityUnit: "can", dateType: "best_if_used_by", dateValue: new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10),
    dateLabelRaw: "BEST IF USED BY — verified in end-to-end test", storageType: "shelf_stable", storageLocationId: locationID,
    packageCondition: "acceptable", temperatureStatus: "not_applicable", calorieStatus: "recorded", calories: 110,
    calorieBasis: "per_serving", allergens: [], requiredFieldConfidence: [0.99, 0.96, 0.94],
  }),
}, 201);

const onePixelPNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==", "base64");
const evidenceForm = new FormData();
evidenceForm.append("capturedAt", new Date().toISOString());
evidenceForm.append("photo", new Blob([onePixelPNG], { type: "image/png" }), "date-label.png");
const { "content-type": _jsonContentType, ...multipartHeaders } = regularHeaders;
const uploadResponse = await fetch(`${baseURL}/intake-items/${item.id}/evidence`, {
  method: "POST", headers: multipartHeaders, body: evidenceForm,
});
const uploaded = await uploadResponse.json();
if (uploadResponse.status !== 201 || uploaded.evidenceType !== "date_label") throw new Error(`Evidence upload failed: ${JSON.stringify(uploaded)}`);
const duplicateResponse = await fetch(`${baseURL}/intake-items/${item.id}/evidence`, {
  method: "POST", headers: multipartHeaders, body: evidenceForm,
});
const duplicate = await duplicateResponse.json();
if (duplicateResponse.status !== 201 || duplicate.id !== uploaded.id) throw new Error("Duplicate upload created another asset");
const evidence = await request(`/intake-items/${item.id}/evidence`);
if (!evidence.items.some((asset) => asset.id === uploaded.id)) throw new Error("Uploaded evidence missing from item");
const imageResponse = await fetch(`${baseURL}/intake-items/${item.id}/evidence/${uploaded.id}`, { headers: multipartHeaders });
if (imageResponse.status !== 200 || imageResponse.headers.get("content-type") !== "image/png") throw new Error("Evidence download failed");
if (!Buffer.from(await imageResponse.arrayBuffer()).equals(onePixelPNG)) throw new Error("Evidence image bytes changed");
await request(`/intake-items/${item.id}/evidence`, { headers: { "x-organization-id": "00000000-0000-4000-8000-000000000999" } }, 404);
const crossOrgImage = await fetch(`${baseURL}/intake-items/${item.id}/evidence/${uploaded.id}`, {
  headers: { ...multipartHeaders, "x-organization-id": "00000000-0000-4000-8000-000000000999" },
});
if (crossOrgImage.status !== 404) throw new Error("Cross-organization evidence download was allowed");
const invalidForm = new FormData();
invalidForm.append("photo", new Blob([Buffer.from("not an image")], { type: "image/jpeg" }), "fake.jpg");
const invalidResponse = await fetch(`${baseURL}/intake-items/${item.id}/evidence`, {
  method: "POST", headers: multipartHeaders, body: invalidForm,
});
if (invalidResponse.status !== 400) throw new Error("Invalid image bytes were accepted");

const submitOptions = {
  method: "POST",
  headers: { "idempotency-key": `e2e-submit-${runID}` },
  body: JSON.stringify({ userReviewedAt: new Date().toISOString() }),
};
const submitted = await request(`/intake-items/${item.id}/submit`, submitOptions, 201);
const replayed = await request(`/intake-items/${item.id}/submit`, submitOptions, 201);
if (submitted.status !== "auto_accepted" || !submitted.inventoryLotId) throw new Error("Expected accepted inventory lot");
if (JSON.stringify(Object.entries(submitted).sort()) !== JSON.stringify(Object.entries(replayed).sort())) throw new Error("Idempotent response changed");

const dashboard = await request("/donation-items");
if (!dashboard.items.some((entry) => entry.intakeItemId === item.id)) throw new Error("Submitted item missing from dashboard");
await request("/admin/review-queue", {}, 403);
await request("/admin/review-queue", { headers: { "x-user-id": "admin-demo", "x-role": "admin" } });

console.log(JSON.stringify({ productLookup: "passed", intakeItemId: item.id, inventoryLotId: submitted.inventoryLotId, evidence: "passed", idempotency: "passed", roleEnforcement: "passed", dashboard: "passed" }, null, 2));
