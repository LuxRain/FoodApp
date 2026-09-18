import { useEffect, useMemo, useState } from "react";
import {
  ArrowLeftIcon, ArrowRightIcon, BackpackIcon, CalendarIcon, CameraIcon,
  CheckCircledIcon, ChevronLeftIcon, Cross1Icon, DashboardIcon,
  ExclamationTriangleIcon, LightningBoltIcon, MagnifyingGlassIcon,
  Pencil2Icon, PersonIcon, ReaderIcon, SewingPinIcon,
} from "@radix-ui/react-icons";
import { BottomSheet, KeyboardInput, MobileScroll, useKeyboard, useScreenPortal } from "./mobile";
import "./prototype.css";

type Screen = "scan" | "dashboard" | "admin";
type Urgency = "expired" | "soon" | "safe";
type DonationItem = { name: string; meta: string; date: string; urgency: Urgency; calories?: string; quantity: string };

const initialItems: DonationItem[] = [
  { name: "Whole Milk", meta: "Dairy · Refrigerated", date: "Expired Sep 14", urgency: "expired", quantity: "4 cartons" },
  { name: "Greek Yogurt", meta: "Dairy · Refrigerated", date: "Sep 22 · 5 days", urgency: "soon", quantity: "18 cups", calories: "90 cal" },
  { name: "Low-Sodium Black Beans", meta: "Canned goods · Shelf stable", date: "Oct 14 · 27 days", urgency: "safe", quantity: "12 cans", calories: "110 cal" },
  { name: "Brown Rice", meta: "Grains · Shelf stable", date: "Jan 08 · 113 days", urgency: "safe", quantity: "6 bags", calories: "160 cal" },
];

export default function Prototype() {
  const keyboard = useKeyboard();
  const { screenRef } = useScreenPortal();
  const [screen, setScreen] = useState<Screen>("scan");
  const [editOpen, setEditOpen] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [flashOn, setFlashOn] = useState(false);
  const [query, setQuery] = useState("");
  const [quantity, setQuantity] = useState("12 cans");
  const [bestBy, setBestBy] = useState("Oct 14, 2026");
  const [calories, setCalories] = useState("110");
  const [location, setLocation] = useState("Main pantry · Shelf A3");
  useEffect(() => {
    keyboard.hide();
    const reset = () => { if (screenRef.current) screenRef.current.scrollTop = 0; };
    reset();
    const frame = window.requestAnimationFrame(reset);
    const settle = window.setTimeout(reset, 340);
    return () => { window.cancelAnimationFrame(frame); window.clearTimeout(settle); };
  }, [screen]);
  const items = useMemo(() => {
    const term = query.trim().toLowerCase();
    return initialItems.filter((item) => !term || `${item.name} ${item.meta}`.toLowerCase().includes(term));
  }, [query]);

  if (screen === "dashboard") {
    return <DashboardScreen items={items} query={query} submitted={submitted} onQuery={setQuery} onScan={() => { keyboard.hide(); setScreen("scan"); }} onAdmin={() => { keyboard.hide(); setScreen("admin"); }} />;
  }
  if (screen === "admin") return <AdminReview onBack={() => setScreen("dashboard")} onApprove={() => setScreen("dashboard")} />;

  return (
    <main className="scan-screen" aria-label="Scan donation intake">
      <img className="camera-image" src="/assets/donation-camera-beans.png" alt="Black beans donation item on a pantry counter" />
      <div className="camera-shade" aria-hidden="true" />
      <nav className="scan-header glass" aria-label="Scan controls">
        <button className="icon-button" aria-label="View donations" onClick={() => setScreen("dashboard")}><ChevronLeftIcon /></button>
        <strong>Scan donation</strong>
        <button className={`icon-button ${flashOn ? "active" : ""}`} aria-label="Toggle flash" onClick={() => setFlashOn((value) => !value)}><LightningBoltIcon /></button>
      </nav>
      <div className="scanner-frame" aria-label="Product recognized">
        <span className="scan-corner top-left" /><span className="scan-corner top-right" />
        <span className="scan-corner bottom-left" /><span className="scan-corner bottom-right" />
        <div className="match-pill glass"><CheckCircledIcon /> Product found</div>
      </div>
      <section className="intake-card glass-strong" aria-label="Detected item details">
        <div className="grabber" />
        <div className="item-heading">
          <div><p className="eyebrow">BARCODE MATCH · 98%</p><h1>Low-Sodium<br />Black Beans</h1></div>
          <span className="confidence-ring" aria-label="98 percent confidence">98</span>
        </div>
        <div className="detail-list">
          <DetailRow icon={<BackpackIcon />} label="Quantity" value={quantity} />
          <DetailRow icon={<CalendarIcon />} label="Best by" value={bestBy} />
          <DetailRow icon={<ReaderIcon />} label="Nutrition" value={`${calories} cal / serving`} />
        </div>
        <div className="ready-state"><span className="ready-icon"><CheckCircledIcon /></span><span><strong>Ready for automatic acceptance</strong><small>High-confidence match · shelf-life passes</small></span></div>
        <button className="primary-action" onClick={() => { keyboard.hide(); setSubmitted(true); setScreen("dashboard"); }}><span>Submit intake</span><ArrowRightIcon /></button>
        <button className="secondary-action glass" onClick={() => setEditOpen(true)}><Pencil2Icon /><span>Edit details</span></button>
      </section>
      <BottomSheet open={editOpen} onOpenChange={(open) => { if (!open) keyboard.hide(); setEditOpen(open); }} title="Edit item details" description="Correct anything the scan did not capture accurately." snap={0.73}>
        <div className="edit-form">
          <EditField label="Quantity" value={quantity} onChange={setQuantity} />
          <EditField label="Best-by date" value={bestBy} onChange={setBestBy} />
          <EditField label="Calories per serving" value={calories} onChange={setCalories} />
          <EditField label="Storage location" value={location} onChange={setLocation} />
          <button className="primary-action sheet-save" onClick={() => { keyboard.hide(); setEditOpen(false); }}>Save changes <CheckCircledIcon /></button>
        </div>
      </BottomSheet>
    </main>
  );
}

function DetailRow({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return <div className="detail-row"><span className="row-icon">{icon}</span><span className="row-label">{label}</span><strong>{value}</strong></div>;
}

function EditField({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  return <label className="edit-field"><span>{label}</span><KeyboardInput value={value} onChange={(event) => onChange(event.currentTarget.value)} /></label>;
}

function DashboardScreen({ items, query, submitted, onQuery, onScan, onAdmin }: { items: DonationItem[]; query: string; submitted: boolean; onQuery: (value: string) => void; onScan: () => void; onAdmin: () => void }) {
  return (
    <main className="dashboard-screen">
      <header className="dashboard-header"><div><p className="eyebrow">MAIN PANTRY</p><h1>Donations</h1></div><button className="avatar-button glass" aria-label="Open admin review" onClick={onAdmin}><PersonIcon /></button></header>
      <div className="search-box glass"><MagnifyingGlassIcon /><KeyboardInput aria-label="Search donations" placeholder="Search donations" value={query} onChange={(event) => onQuery(event.currentTarget.value)} />{query ? <button onClick={() => onQuery("")} aria-label="Clear search"><Cross1Icon /></button> : null}</div>
      {submitted ? <div className="success-banner"><CheckCircledIcon /><span><strong>Intake saved</strong><small>Black Beans added to inventory</small></span></div> : null}
      <div className="dashboard-summary glass"><div><strong>4</strong><span>items</span></div><div><strong className="red-text">1</strong><span>expired</span></div><div><strong className="amber-text">1</strong><span>use soon</span></div></div>
      <div className="list-heading"><span>Sorted by expiration</span><span className="legend"><i className="dot expired" /> expired <i className="dot soon" /> soon <i className="dot safe" /> safe</span></div>
      <MobileScroll className="donation-scroll"><section className="donation-list">{items.map((item) => <DonationCard item={item} key={item.name} />)}<div className="review-card glass" onClick={onAdmin} role="button" tabIndex={0}><span className="review-icon"><ExclamationTriangleIcon /></span><span><strong>1 item needs review</strong><small>Low-confidence item waiting for admin</small></span><ArrowRightIcon /></div></section></MobileScroll>
      <nav className="bottom-nav glass-strong" aria-label="Primary navigation"><button className="active"><DashboardIcon /><span>Donations</span></button><button className="scan-tab" onClick={onScan}><span><CameraIcon /></span><small>Scan</small></button><button onClick={onAdmin}><PersonIcon /><span>Admin</span></button></nav>
    </main>
  );
}

function DonationCard({ item }: { item: DonationItem }) {
  return <article className={`donation-card ${item.urgency}`}><span className={`urgency-bar ${item.urgency}`} /><div className="food-thumb"><BackpackIcon /></div><div className="donation-copy"><strong>{item.name}</strong><small>{item.meta}</small><span>{item.quantity}{item.calories ? ` · ${item.calories}` : ""}</span></div><div className="date-copy"><strong>{item.date.split(" · ")[0]}</strong><small>{item.date.split(" · ")[1] ?? "Remove now"}</small></div></article>;
}

function AdminReview({ onBack, onApprove }: { onBack: () => void; onApprove: () => void }) {
  const keyboard = useKeyboard();
  const [decision, setDecision] = useState<"pending" | "approved" | "rejected">("pending");
  useEffect(() => {
    keyboard.hide();
    const settle = window.setTimeout(() => keyboard.hide(), 120);
    return () => window.clearTimeout(settle);
  }, []);
  return (
    <main className="admin-screen">
      <header className="admin-header"><button className="icon-button glass" onClick={onBack} aria-label="Back"><ArrowLeftIcon /></button><div><p className="eyebrow">ADMIN QUEUE</p><h1>Review item</h1></div><span className="queue-badge">1</span></header>
      <MobileScroll className="admin-scroll"><div><section className="review-hero glass-strong"><img src="/assets/donation-camera-beans.png" alt="Donation item awaiting review" /><div><span className="low-confidence"><ExclamationTriangleIcon /> 62% confidence</span><h2>Organic Black Beans</h2><p>Image match · barcode unreadable</p></div></section><section className="rule-card"><h3>Why this needs review</h3><ReviewFact icon={<CalendarIcon />} title="Date detected" detail="Best by Sep 28, 2026 · 11 days remaining" status="Pass" /><ReviewFact icon={<ReaderIcon />} title="Allergens" detail="No declarable allergens detected" status="Verify" /><ReviewFact icon={<SewingPinIcon />} title="Storage" detail="Shelf stable · Main pantry" status="Pass" /></section>{decision !== "pending" ? <div className={`decision-banner ${decision}`}><CheckCircledIcon /><strong>{decision === "approved" ? "Approved for inventory" : "Item rejected"}</strong></div> : null}</div></MobileScroll>
      <div className="admin-actions glass-strong"><button className="reject-action" onClick={() => setDecision("rejected")}>Reject</button><button className="approve-action" onClick={() => { setDecision("approved"); window.setTimeout(onApprove, 700); }}>Approve item <CheckCircledIcon /></button></div>
    </main>
  );
}

function ReviewFact({ icon, title, detail, status }: { icon: React.ReactNode; title: string; detail: string; status: string }) {
  return <div className="review-fact"><span className="row-icon">{icon}</span><span><strong>{title}</strong><small>{detail}</small></span><em>{status}</em></div>;
}
