# Singapore Cross-Border Payments Hub
### Snowflake + AWS | Singapore FSI Demo

> Real-time cross-border payment processing and settlement monitoring for Singapore corridors (FAST, PayNow, SWIFT, GIRO) — powered by Snowflake Dynamic Tables for zero-orchestration pipelines and Amazon Bedrock for intelligent exception resolution.

---

## Two Personas, One Platform

| Persona | Tool | What they see |
|---|---|---|
| **Payments Ops Analyst** | Streamlit in Snowflake | Payment flows, SLA tracking, exception queue, Bedrock analysis |
| **CFO / CRO** | Amazon QuickSight + Amazon Q | Volume by corridor, settlement latency, exception rates, fee revenue |

---

## Architecture

```
AWS Data Plane                     Snowflake AI Data Cloud
───────────────────                ──────────────────────────────────
Amazon S3 / Kinesis        ──────▶ RAW (Snowpipe / Streaming)
                                   ├── PAYMENTS_RAW (500 txns)
                                   ├── SETTLEMENTS_RAW
                                   ├── FX_RATES_RAW
                                   └── EXCEPTIONS_RAW
                                   CURATED (Dynamic Tables, 5 min lag)
                                   ├── PAYMENT_ENRICHED (FX + SLA calc)
                                   ├── CORRIDOR_STATS (aggregates)
                                   └── EXCEPTION_QUEUE (open, prioritized)
Amazon Bedrock (Claude)    ◀─────▶ AI (External Access, SigV4 → Converse API)
                                   └── ANALYZE_EXCEPTION SP
Amazon QuickSight          ◀─────  CURATED Views (DIRECT_QUERY)
```

| Layer | AWS | Snowflake |
|---|---|---|
| **Ingest** | S3, Kinesis | Snowpipe, Snowpipe Streaming |
| **Transform** | — | Dynamic Tables (RAW → CURATED, 5 min lag) |
| **SLA Tracking** | — | Payment-type-specific deadlines (FAST 15min, PayNow 5min, SWIFT 4h, GIRO 24h) |
| **Exception Resolution** | Amazon Bedrock (Claude Sonnet 4.5) | ANALYZE_EXCEPTION SP (SigV4 signed) |
| **Report** | Amazon QuickSight + Amazon Q | 2 datasets + Q Topic |

---

## Repository Structure

```
fsi-payments/
├── snowflake/
│   ├── 00_setup.sql              # DB, schemas, warehouse
│   ├── 01_integrations.sql       # S3 storage integration, Bedrock EAI
│   └── 02_raw_tables.sql         # 4 raw tables
├── streamlit/
│   ├── streamlit_app.py          # 4-tab Payments Ops app
│   └── snowflake.yml             # Snowflake CLI deploy config
├── quicksight/
│   └── deploy.sh                 # Datasets + Q topic deployment
├── demo/
│   └── demo_script.md            # 3.5-min video narration
└── README.md
```

---

## Quick Start

### Prerequisites
- Snowflake account with ACCOUNTADMIN
- `snow` CLI configured
- AWS CLI with Bedrock access (us-west-2)
- S3 bucket with Snowflake storage integration

### 1. Build Snowflake Platform
Run SQL files 00 → 02 against your Snowflake account. Synthetic data is generated via INSERT statements (500 payments, 500 settlements, 100 FX rates, 40 exceptions).

### 2. Update Bedrock Credentials
```sql
ALTER SECRET FSI_PAYMENTS.AI.BEDROCK_SECRET
    SET SECRET_STRING = '{"aws_access_key_id":"AKIA...","aws_secret_access_key":"..."}';
```

### 3. Deploy Streamlit App
```bash
cd streamlit && snow streamlit deploy --replace --connection <CONNECTION>
```

### 4. Deploy QuickSight
```bash
bash quicksight/deploy.sh
```

### 5. Health Check
```sql
SELECT
    (SELECT COUNT(*) FROM FSI_PAYMENTS.RAW.PAYMENTS_RAW)          AS payments,
    (SELECT COUNT(*) FROM FSI_PAYMENTS.RAW.SETTLEMENTS_RAW)       AS settlements,
    (SELECT COUNT(*) FROM FSI_PAYMENTS.CURATED.PAYMENT_ENRICHED)  AS enriched,
    (SELECT COUNT(*) FROM FSI_PAYMENTS.CURATED.EXCEPTION_QUEUE)   AS open_exceptions;
```
Expected: 500 payments, 500 settlements, 500 enriched, ~26 open exceptions.

---

## Streamlit App (4 Tabs)

| Tab | Feature | Key Capability |
|---|---|---|
| **Payment Monitor** | Real-time KPIs, volume by corridor, recent payments | Dynamic Tables |
| **Settlement Tracker** | SLA compliance (on-time/at-risk/breached), bank reconciliation | SLA deadline calculation |
| **Exception Queue** | Priority-sorted exceptions + Bedrock AI analysis | Bedrock Converse API |
| **Analytics** | Corridor performance, latency comparison, FX rates | Aggregation Dynamic Table |

---

## Payment Corridors

| Corridor | Payment Types | SLA |
|---|---|---|
| SG-SG | FAST, PayNow, GIRO | 5 min (PayNow) / 15 min (FAST) / 24h (GIRO) |
| SG-MY | SWIFT, FAST | 4 hours (SWIFT) / 15 min (FAST) |
| SG-ID | SWIFT | 4 hours |
| SG-TH | SWIFT | 4 hours |
| SG-HK | SWIFT | 4 hours |
| SG-PH | SWIFT | 4 hours |

**Banks**: DBS, OCBC, UOB, HSBC, Standard Chartered → Maybank, BCA Indonesia, Bangkok Bank, HSBC HK, BDO Philippines

---

## Synthetic Data

| Table | Rows | Content |
|---|---|---|
| PAYMENTS_RAW | 500 | 6 corridors, 4 payment types, 5 sender banks |
| SETTLEMENTS_RAW | 500 | 450 cleared, 30 pending, 20 failed |
| FX_RATES_RAW | 100 | SGD/MYR, SGD/IDR, SGD/THB, SGD/HKD, SGD/PHP |
| EXCEPTIONS_RAW | 40 | AML holds, sanctions hits, format errors, timeouts |

---

## Exception Types

| Type | Description | Typical Action |
|---|---|---|
| AML_HOLD | Amount exceeds threshold, enhanced due diligence needed | ESCALATE |
| SANCTIONS_HIT | Beneficiary partial match against OFAC SDN list | BLOCK / ESCALATE |
| INSUFFICIENT_FUNDS | Sender balance insufficient at debit time | RETRY |
| FORMAT_ERROR | SWIFT MT103 field validation failure | RETURN |
| TIMEOUT | Settlement confirmation not received within SLA | RETRY / ESCALATE |

---

## Demo Script

| Script | Duration | Use |
|---|---|---|
| `demo/demo_script.md` | 3.5 min | Recorded video walkthrough |

---

## Legal

This is a personal project and is **not an official Snowflake offering**. It comes with no support or warranty. Do not use in production without thorough review and testing.
