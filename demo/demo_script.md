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

**Current data**: 500 payments | 450 cleared | 30 pending | 20 failed | 450 on-time | 22 SLA breached | 26 open exceptions | 6 corridors

**Corridors**: SG-SG, SG-MY, SG-ID, SG-TH, SG-HK, SG-PH
**Banks**: DBS, OCBC, UOB, HSBC, Standard Chartered
**Payment Types**: FAST (15 min SLA), PayNow (5 min), SWIFT (4 hours), GIRO (24 hours)

---

## Pre-Recording Checklist

- [ ] Verify Dynamic Tables: `SHOW DYNAMIC TABLES IN DATABASE FSI_PAYMENTS` (all ACTIVE)
- [ ] Open Streamlit: `FSI_PAYMENTS.APP.PAYMENTS_HUB_APP`
- [ ] Confirm exception queue has 26 open items (Tab 3)
- [ ] Test Bedrock: Select an AML_HOLD exception, click Analyze — confirm response
- [ ] Open QuickSight: https://us-west-2.quicksight.aws.amazon.com/sn/dashboards/payments-hub-dashboard
- [ ] Test Amazon Q: ask "What is the total volume by corridor?"
- [ ] Audio: quiet room, external mic
- [ ] Resolution: 1920x1080

---

## Script

### [0:00–0:30] THE PROBLEM (Show: Architecture Diagram)

> *"Singapore processes billions in cross-border payments daily — FAST, PayNow, SWIFT, GIRO — each with different settlement SLAs. PayNow must clear in 5 minutes. SWIFT in 4 hours. When exceptions hit — sanctions screening, AML holds, format errors — every minute of delay costs money and risks MAS regulatory breach. How do you monitor thousands of payments per hour and resolve exceptions before SLAs are breached?"*

**Screen**: Architecture diagram (Kinesis/S3 → Snowpipe → RAW → Dynamic Tables → Bedrock → Streamlit/QuickSight)

---

### [0:30–1:00] DATA PIPELINE (Show: Snowsight)

> *"Payment messages stream from clearing systems — MEPS+, FAST, SWIFT GPI — into Snowflake via Snowpipe. Dynamic Tables automatically enrich each payment: convert to SGD, calculate the SLA deadline based on payment type, and track settlement status. The exception queue surfaces 26 open issues prioritized by severity and age. All refreshing every 5 minutes. Zero orchestration."*

**Screen**: Run in Snowsight:
```sql
SELECT 'PAYMENTS' AS SOURCE, COUNT(*) FROM FSI_PAYMENTS.RAW.PAYMENTS_RAW
UNION ALL SELECT 'ENRICHED (DT)', COUNT(*) FROM FSI_PAYMENTS.CURATED.PAYMENT_ENRICHED
UNION ALL SELECT 'OPEN EXCEPTIONS', COUNT(*) FROM FSI_PAYMENTS.CURATED.EXCEPTION_QUEUE;
```
Expected output: 500 payments, 500 enriched, 26 open exceptions.

Then show PAYMENT_ENRICHED columns — highlight SLA_DEADLINE, SLA_STATUS (ON_TIME / AT_RISK / BREACHED).

---

### [1:00–1:30] PAYMENT MONITOR (Show: Streamlit Tab 1)

> *"The Payments Ops dashboard shows real-time KPIs. 500 payments processed, 90% success rate. The corridor breakdown shows SG-MY and SG-HK as highest volume — consistent with Singapore's cross-border remittance and trade settlement flows."*

**Screen**: Tab 1 → Show 4 KPI cards (Total: 500, Volume: $XXM, Success: 90%, Avg: $XXK) → Volume by corridor chart → Payment type distribution → Scroll to recent payments table

---

### [1:30–2:10] EXCEPTION QUEUE + BEDROCK (Show: Streamlit Tab 3)

> *"26 open exceptions need attention. Here's a CRITICAL one — an AML hold on a cross-border payment. The transaction amount exceeds the threshold for the corridor and the sender is flagged in the screening database. One click sends this to Amazon Bedrock for intelligent triage."*

> *"Bedrock recommends: ESCALATE. Risk level CRITICAL. Resolution steps: engage the MLRO, request enhanced due diligence documentation, run full name screening. Regulatory note: MAS Notice 626 applies — report to STRO if suspicion confirmed."*

**Screen**: Tab 3 → Show 26 open exceptions → Select AML_HOLD or SANCTIONS_HIT (CRITICAL) → Show details panel → Click "Analyze with Amazon Bedrock" → Show full response: action (ESCALATE), risk level, resolution steps, regulatory considerations

---

### [2:10–2:30] SETTLEMENT TRACKER (Show: Streamlit Tab 2)

> *"The settlement tracker shows SLA compliance: 450 out of 500 payments settled on time — 90% compliance. 22 breached SLA, mostly SWIFT cross-border payments that hit sanctions screening delays. Bank reconciliation confirms DBS as the highest volume sender."*

**Screen**: Tab 2 → SLA progress bar (90%) → Performance by payment type table → Bank reconciliation view

---

### [2:30–3:15] EXECUTIVE VIEW — QUICKSIGHT (Show: QuickSight Dashboard)

> *"The CFO needs the big picture. QuickSight connects directly to Snowflake — live data, no ETL. Sheet 1 shows payment operations: volume by corridor, payments by type, SLA status distribution, volume by bank. Sheet 2 shows exception management: 26 open exceptions by type, severity, and corridor. And with Amazon Q: 'What is the total volume by corridor?'"*

**Screen**: QuickSight dashboard → Sheet 1 (Payment Operations): KPIs, corridor volume, payment types, SLA chart, bank volume → Sheet 2 (Exception Management): exception KPI, by type, by severity, by corridor → Amazon Q: "What is the total volume by corridor?"

---

### [3:15–3:30] CLOSE

> *"Real-time payments visibility from a single platform. Snowflake Dynamic Tables for zero-orchestration data pipelines. Amazon Bedrock for intelligent exception resolution. QuickSight for executive reporting. Every payment tracked, every SLA monitored, every exception analyzed — across all Singapore corridors."*

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
