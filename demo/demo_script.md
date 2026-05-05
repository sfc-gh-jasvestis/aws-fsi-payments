# Demo Script: Singapore Cross-Border Payments Hub
## 3.5-Minute Recorded Walkthrough
**Format**: Screen recording with voiceover
**Target**: Customer meeting / booth loop / social share
**Pre-requisites**: Data loaded, Streamlit deployed, QuickSight dashboard published

---

## Two Personas

| Persona | Role | Tool | What they care about |
|---|---|---|---|
| **Payments Ops Analyst** | Day-to-day operations | Streamlit in Snowflake | Payment flows, SLA tracking, exception triage, Bedrock analysis |
| **CFO / Head of Payments** | Executive oversight | Amazon QuickSight + Amazon Q | Volume by corridor, settlement performance, exception rates, fee revenue |

---

## What's Built

| Layer | Component | Detail |
|---|---|---|
| **Ingest (AWS)** | Amazon S3 / Kinesis | Payment messages, settlement confirmations, FX rates |
| **RAW** | 4 tables | PAYMENTS_RAW (500), SETTLEMENTS_RAW (500), FX_RATES_RAW (100), EXCEPTIONS_RAW (40) |
| **CURATED** | 3 Dynamic Tables | PAYMENT_ENRICHED (FX + SLA calc), CORRIDOR_STATS (aggregates), EXCEPTION_QUEUE (open, prioritized) |
| **AI** | Bedrock SP | ANALYZE_EXCEPTION — intelligent exception triage and resolution |
| **Consumption** | Streamlit | 4-tab Payments Ops app |
| | QuickSight | 2-sheet dashboard (Payment Operations + Exception Management) + Q Topic |

**Current data**: 500 payments | 450 cleared | 30 pending | 20 failed | 450 on-time | 8 at-risk | 22 SLA breached | 26 open exceptions | 6 corridors

**Corridors**: SG-SG, SG-MY, SG-ID, SG-TH, SG-HK, SG-PH
**Banks**: DBS, OCBC, UOB, HSBC, Standard Chartered
**Payment Types**: FAST (15 min SLA), PayNow (5 min), SWIFT (4 hours), GIRO (24 hours)

---

## Pre-Recording Checklist

- [ ] Verify Dynamic Tables: `SHOW DYNAMIC TABLES IN DATABASE FSI_PAYMENTS` (all ACTIVE)
- [ ] Open Streamlit: `FSI_PAYMENTS.APP.PAYMENTS_HUB_APP`
- [ ] Confirm exception queue has 26 open items (Tab 3)
- [ ] Test Bedrock: Tab 3, select **EXC-0021** (AML_HOLD, CRITICAL, SGD 410K, Standard Chartered, SG-TH), click Analyze — confirm ESCALATE response
- [ ] Open QuickSight: https://us-west-2.quicksight.aws.amazon.com/sn/dashboards/payments-hub-dashboard
- [ ] Test Amazon Q: ask "What is the total volume by corridor?"
- [ ] Audio: quiet room, external mic
- [ ] Resolution: 1920x1080

---

## Script

### [0:00–0:30] THE PROBLEM (Show: Architecture Diagram)

> *"Singapore processes billions in cross-border payments daily — FAST, PayNow, SWIFT, GIRO — each with different settlement SLAs. PayNow must clear in 5 minutes. SWIFT in 4 hours. When exceptions hit — sanctions screening, AML holds, format errors — every minute of delay costs money and risks MAS regulatory breach. How do you monitor thousands of payments per hour and resolve exceptions before SLAs are breached?"*

> *"Here's the architecture. Payment messages from clearing systems land in Amazon S3 and Kinesis. Snowpipe streams them into Snowflake's RAW layer. Dynamic Tables handle enrichment — FX conversion, SLA deadline calculation, exception prioritization — all automatically, no orchestration. Amazon Bedrock provides AI-powered exception triage. And two consumption layers: Streamlit for Payments Ops, QuickSight for the CFO."*

**Screen**: Architecture diagram — walk through left to right: Kinesis/S3 → Snowpipe → RAW → Dynamic Tables → Bedrock → Streamlit/QuickSight

---

### [0:30–1:00] DATA PIPELINE (Show: Snowsight)

> *"Payments stream in via Snowpipe. Dynamic Tables do the rest — no ETL, no Airflow. PAYMENT_ENRICHED converts to SGD and calculates SLA deadlines. CORRIDOR_STATS rolls up volume and latency. EXCEPTION_QUEUE surfaces the 26 open issues. All refreshing every 5 minutes, zero orchestration."*

**Screen 1a** — Snowsight → Databases → FSI_PAYMENTS → CURATED → click **PAYMENT_ENRICHED** → **Graph** tab (shows lineage: PAYMENTS_RAW + SETTLEMENTS_RAW → PAYMENT_ENRICHED → CORRIDOR_STATS)

**Screen 1b** — Click **EXCEPTION_QUEUE** → **Graph** tab (shows lineage: PAYMENTS_RAW + EXCEPTIONS_RAW → EXCEPTION_QUEUE — separate pipeline branch). Then click **Data Preview** tab to show the 26 open exceptions live.

---

### [1:00–1:30] PAYMENT MONITOR (Show: Streamlit Tab 1)

> *"Now we're the Payments Ops Analyst — this is their daily view. 500 payments processed, 90% success rate. The corridor breakdown shows volume evenly distributed across all six Singapore corridors — reflecting balanced cross-border remittance and trade settlement flows."*

**Screen**: Tab 1 → Show 4 KPI cards (Total: 500, Volume: $XXM, Success: 90%, Avg: $XXK) → Volume by corridor chart → Payment type distribution → Scroll to recent payments table

---

### [1:30–2:10] EXCEPTION QUEUE + BEDROCK (Show: Streamlit Tab 3)

> *"26 open exceptions need attention. Here's EXC-0021 — a CRITICAL AML hold. A SGD 410,000 SWIFT payment from Standard Chartered on the SG-Thailand corridor. The transaction exceeds the threshold for the corridor and the sender is flagged in the screening database. This would normally take a compliance analyst 30 minutes to research and triage. One click sends it to Amazon Bedrock."*

> *"Five seconds. Bedrock returns a full triage: recommended action, risk level, step-by-step resolution, SLA impact, and regulatory considerations. All structured, all actionable. From detection to recommended action in 5 seconds — not 30 minutes."*

**Screen**: Tab 3 → Show 26 open exceptions → Select **EXC-0021** (AML_HOLD, CRITICAL, SGD 410K, SG-TH) → Show details panel → Click "Analyze with Amazon Bedrock" → Show full response: action (ESCALATE), risk level, resolution steps, regulatory considerations

---

### [2:10–2:30] SETTLEMENT TRACKER (Show: Streamlit Tab 2)

> *"The settlement tracker shows SLA compliance: 450 out of 500 payments settled on time — 90% compliance. 22 breached SLA — spread across SWIFT, FAST, and PayNow, with GIRO's 24-hour window keeping it breach-free. Bank reconciliation shows even distribution across all five partner banks."*

**Screen**: Tab 2 → SLA progress bar (90%) → Performance by payment type table → Bank reconciliation view

---

### [2:30–3:15] EXECUTIVE VIEW — QUICKSIGHT (Show: QuickSight Dashboard)

> *"Now we shift persona — the CFO, Head of Payments. They need the big picture. QuickSight connects directly to Snowflake — live data, no ETL. Sheet 1 shows payment operations: volume by corridor, payments by type, SLA status distribution, volume by bank. Sheet 2 shows exception management: 26 open exceptions by type, severity, and corridor. And with Amazon Q: 'What is the total volume by corridor?'"*

**Screen**: QuickSight dashboard → Sheet 1 (Payment Operations): KPIs, corridor volume, payment types, SLA chart, bank volume → Sheet 2 (Exception Management): exception KPI, by type, by severity, by corridor → Amazon Q: "What is the total volume by corridor?"

---

### [3:15–3:20] TAB 4 — ANALYTICS (Brief mention)

> *"Tab 4 rounds out the picture — corridor performance, average settlement latency by payment type, live FX rates. The operational data the team needs for capacity planning."*

**Screen**: Quick flash of Tab 4 (Analytics) — corridor stats table + latency chart. No narration detail needed.

---

### [3:20–3:30] CLOSE (Show: Streamlit sidebar)

> *"Real-time payments visibility from a single platform. Snowflake Dynamic Tables for zero-orchestration data pipelines. Amazon Bedrock for intelligent exception resolution. QuickSight for executive reporting. Every payment tracked, every SLA monitored, every exception analyzed — across all Singapore corridors."*

**Screen**: Click the Streamlit sidebar to show the architecture diagram already embedded in the app — bookends with the opening.

---

## Key Demo Questions to Anticipate

1. **"How does this handle real-time vs batch?"**
   → Dynamic Tables with 5-min lag for near-real-time. For sub-second (FAST payments), use Snowpipe Streaming with 1-second latency.

2. **"What about ISO 20022 migration?"**
   → RAW schema accepts any format via S3. JSON today, ISO 20022 XML tomorrow — same pipeline, different parser.

3. **"How does this scale during peak (Chinese New Year remittances, 11.11)?"**
   → Snowflake multi-cluster warehouses auto-scale 10x. No capacity planning needed.

4. **"What about MAS payment regulations?"**
   → Payment Services Act compliance built into exception rules. AML_HOLD thresholds match MAS Notice 626. STR deadline tracking built into SLA logic.

5. **"Can this connect to SWIFT gpi Tracker?"**
   → Yes. SWIFT gpi webhooks → Amazon EventBridge → S3 → Snowpipe. Same pipeline, new data source.
