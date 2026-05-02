# Demo Script: Singapore Cross-Border Payments Hub

## Duration: 3.5 minutes (recorded demo)

---

## Act 1: The Problem (0:00 - 0:30)

### Voiceover:
"Singapore processes billions in cross-border payments daily through FAST, PayNow, SWIFT, and GIRO. Each payment type has different SLAs — PayNow must settle in 5 minutes, SWIFT in 4 hours. When exceptions occur — sanctions hits, AML holds, timeouts — every minute of delay costs money and risks regulatory breach. How do you monitor 500+ payments per hour and resolve exceptions before SLAs are breached?"

### Visual:
Architecture diagram showing payment flow: Kinesis/S3 → Snowflake Dynamic Tables → Bedrock → QuickSight.

---

## Act 2: Data Pipeline (0:30 - 1:00)

### Voiceover:
"Payment messages stream from clearing systems into Snowflake via Snowpipe. Dynamic Tables automatically enrich each payment with FX conversion, settlement status, and SLA deadline calculation. The exception queue prioritizes by severity and age — all refreshing every 5 minutes with zero orchestration."

### Visual:
Snowsight showing:
- RAW: 500 payments, 500 settlements, 100 FX rates, 40 exceptions
- CURATED Dynamic Tables: PAYMENT_ENRICHED (500 rows), CORRIDOR_STATS, EXCEPTION_QUEUE (26 open)
- Highlight the SLA_STATUS column: ON_TIME, AT_RISK, BREACHED

---

## Act 3: Persona 1 — Payments Ops (1:00 - 2:30)

### Scene 1: Payment Monitor (1:00 - 1:30)
**Voiceover:** "The operations dashboard shows real-time KPIs: 500 payments, $XX million volume, 90%+ success rate. Volume by corridor shows SG-MY as the highest — consistent with Singapore-Malaysia remittance flows."

**Action:** Tab 1 → Show KPIs → Corridor volume chart → Recent payments table with status badges

### Scene 2: Exception Queue (1:30 - 2:10)
**Voiceover:** "26 open exceptions need attention. Filter to CRITICAL — a sanctions hit on a SG-HK corridor payment of SGD 420,000. The beneficiary name partially matches the OFAC SDN list. One click sends this to Amazon Bedrock for analysis."

**Action:** Tab 3 → Filter to sanctions hit → Click "Analyze with Amazon Bedrock" → Show recommended action (ESCALATE), resolution steps, regulatory considerations

### Scene 3: Settlement Tracker (2:10 - 2:30)
**Voiceover:** "The settlement tracker shows SLA compliance at a glance. FAST payments averaging 8 seconds settlement. SWIFT at 2 hours — well within the 4-hour SLA. Bank reconciliation confirms DBS as the highest volume sender."

**Action:** Tab 2 → Show SLA progress bar → Performance by type table → Bank reconciliation

---

## Act 4: Analytics (2:30 - 3:15)

### Voiceover:
"The analytics tab provides corridor-level intelligence: success rates, average latency, exception distribution. FX rates update in real-time. This is the data that feeds into QuickSight for the executive view — the CFO sees revenue by corridor, the CRO sees exception rates by type."

### Visual:
Tab 4 — Corridor performance table, success rate chart, latency comparison, FX rates

---

## Act 5: Close (3:15 - 3:30)

### Voiceover:
"Real-time payments visibility from a single platform. Snowflake Dynamic Tables for zero-orchestration data pipelines. Amazon Bedrock for intelligent exception resolution. And QuickSight for executive reporting. Every payment tracked, every SLA monitored, every exception analyzed."

---

## Demo Day Checklist

- [ ] Bedrock secret populated with valid AWS credentials
- [ ] Dynamic Tables showing ACTIVE status (3 DTs)
- [ ] Exception queue showing 20+ open exceptions
- [ ] At least 1 CRITICAL and 1 HIGH severity exception visible
- [ ] Corridor stats populated with all 6 corridors

## Key Demo Questions to Anticipate

1. "How does this handle real-time vs batch?"
   → Dynamic Tables with 5-min lag for near-real-time. For sub-second, use Snowpipe Streaming.

2. "What about ISO 20022 migration?"
   → S3 can ingest any message format. RAW schema is VARIANT-ready for ISO 20022 XML.

3. "How does this scale during peak (Chinese New Year, 11.11)?"
   → Snowflake elastic scaling + multi-cluster warehouses handle 10x spikes automatically.

4. "What about the MAS payment regulations?"
   → Payment Services Act compliance built into the exception rules. AML_HOLD threshold matches MAS Notice 626.
