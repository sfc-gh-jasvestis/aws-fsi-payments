# Cross-Border Payments Operations

**Singapore - Payments Hub**
Use case: Cross-border payment exceptions, settlement controls and operations risk

> Operations monitoring for 40 payment routes from a fictional Singapore payments hub into 5 corridors: dynamic tables, a holdout-evaluated payment-failure classifier, an exception-volume forecast and grounded AI answers.

## Why Snowflake

- **Dynamic tables** reconcile payments, exceptions, failed payments, SLA breaches and nostro reconciliation compliance from RAW route data, with checks in `run_core.py`
- **Payment-failure classification** gives a holdout-evaluated next-7-day probability per route
- **Exception forecast** projects 14 days of hub-wide exception volume with prediction intervals, for operations staffing
- **Grounded AI**: the Cortex Agent (Analyst over a semantic view, plus Search over SOPs) shows its SQL and SOP citations
- **Live payments**: a native simulator (Snowflake only) or Firehose, S3 and Snowpipe (AWS build), then an alert and email

## What is built

| | |
|---|---|
| Dimension table | `RAW.ROUTES` (40 rows) |
| Fact table | `RAW.ROUTE_DAILY` (3,600 route-days, 90 days) |
| Curated layer | `CURATED.KPI_SUMMARY`, `PERFORMANCE_SUMMARY`, `EXCEPTION_SUMMARY`, `TREND_ANALYSIS` |
| ML | `ML.FAILURE_RISK_SCORES`, `ML.FAILURE_RISK_HOLDOUT_METRICS`, `ML.EXCEPTION_FORECAST`, `ML.SCREENING_HIT_ANOMALIES` |

Origin: Singapore (SGD). Corridors: Malaysia, Hong Kong, Indonesia, Thailand, Philippines.
Segments: Retail remittance, SME trade, Payroll batch, Corporate treasury, Bank-to-bank.

## KPI cards (live from `CURATED.KPI_SUMMARY`; no fallback values)

| Card | Value from the seeded data |
|---|---|
| Straight-Through Rate | 99.96% |
| Exceptions Raised | 531 |
| Failed Payments | 160 |
| Exception Failure Rate | 30.1% |
| SLA Breaches | 80 |
| Value Processed (SGD M) | 14,133 |
| Payments Processed | 1,194,810 |
| Nostro Reconciliation Compliance | 79.9% |
| Routes Monitored | 40 |
| Due Diligence Coverage | 57.1% |
| Due Diligence Documents Pending | 21 |

Values are synthetic. A rebuild reproduces them because the data is HASH-seeded; dates are relative to the build day.

## Demo flow

1. Executive Cockpit: KPIs, daily exceptions against failed payments, exceptions and failures by exception type, route table
2. Predictive: holdout metrics, risk bands, 14-day exception forecast, screening hit rate anomalies
3. Controls: nostro reconciliation compliance, due-diligence coverage and pending documents, reconciliation compliance against failed payments, then generate the action memo
4. Live Payments: run `CALL APP.SIMULATE_PAYMENTS(20)` (Snowflake only) or `python aws/publish_payments.py --count 20` (AWS build). Then run `EXECUTE ALERT APP.LIVE_PAYMENT_ALERT` and show the alert log and email.
5. Ask AI: the Cortex Agent answers metric questions through the semantic view and cites SOPs from Cortex Search. The SQL is shown.
6. QuickSight (AWS build): the same Snowflake tables through DIRECT_QUERY
7. Architecture: both builds side by side

## Talking points

- 99.96% of payments go straight through; the 531 exceptions are where operations time goes, and about 3 in 10 of them (30.1%) end as failed or returned payments.
- AML holds produce the most failed payments (44 of 116). Clearing system outage exceptions hit every route in a corridor at once and always clear.
- The risk model is evaluated on a time-based holdout: precision 0.40 and recall 0.23 at 0.5, against a 0.21 base rate. Present it as triage, not a verdict.
- Clearing system outages are excluded from model training, because they are not route-driven.

## Business impact

Use only the sourced references in `README.md` (Business Impact).
