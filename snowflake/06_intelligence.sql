-- ============================================================================
-- 06_INTELLIGENCE.SQL - search, anomaly detection, semantic view, agent,
-- live-payment alert and on-demand refresh DAG.
-- Run with snowflake/run_intelligence.py (substitutes checked __DEMO_DB__ /
-- __DEMO_WH__ / __ALERT_EMAIL__). Requires 00-05, plus 08 (Snowflake only) or
-- aws/setup_aws.py (AWS build) for RAW.LIVE_PAYMENTS.
-- Alerts and tasks are created SUSPENDED; run them with EXECUTE ALERT / EXECUTE TASK.
-- ============================================================================
USE DATABASE __DEMO_DB__;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

-- ---------- Synthetic exception-handling knowledge base (clearly synthetic SOPs) ----------
CREATE OR REPLACE TABLE SEARCH.EXCEPTION_DOCS AS
WITH types AS (
  SELECT DISTINCT r.EXCEPTION_TYPE, a.CATEGORY
  FROM RAW.ROUTE_DAILY r JOIN RAW.ROUTES a ON a.ID = r.ENTITY_ID
  WHERE r.FAILED_COUNT > 0
)
SELECT
  'SOP-' || LPAD(ROW_NUMBER() OVER (ORDER BY CATEGORY, EXCEPTION_TYPE)::VARCHAR, 3, '0') AS DOC_ID,
  'SOP' AS DOC_TYPE,
  CATEGORY,
  EXCEPTION_TYPE,
  CATEGORY || ' - ' || EXCEPTION_TYPE || ' exception handling' AS TITLE,
  'Synthetic demo SOP. Payment segment: ' || CATEGORY || '. Exception type: ' || EXCEPTION_TYPE || '. '
  || 'Step 1: open an exception case, link the payment and hold further payments on the route above the route limit until the case is triaged. '
  || 'Step 2: ' || CASE
       WHEN EXCEPTION_TYPE = 'Sanctions screening hit' THEN 'compare the matched name, bank identifier and jurisdiction against the screening list entry, and escalate to the sanctions officer before releasing the payment.'
       WHEN EXCEPTION_TYPE = 'AML hold' THEN 'review the payer and payee profile, the purpose of payment and the last 30 days of route activity, and refer unexplained patterns to the financial crime team.'
       WHEN EXCEPTION_TYPE = 'Beneficiary name mismatch' THEN 'confirm the beneficiary name and account with the sending customer, and return the payment if it cannot be confirmed before the cut-off.'
       WHEN EXCEPTION_TYPE = 'Format error' THEN 'validate the payment message fields against the corridor format rules, correct mapping errors in the batch, and resubmit only the rejected items.'
       WHEN EXCEPTION_TYPE = 'Duplicate payment' THEN 'match the payment against the batch reference and value date, cancel the duplicate before settlement, and notify the originating corporate.'
       WHEN EXCEPTION_TYPE = 'Cut-off missed' THEN 'check the corridor cut-off and holiday calendar, agree a new value date with the customer, and record the delay against the route.'
       WHEN EXCEPTION_TYPE = 'Nostro liquidity shortfall' THEN 'check the projected nostro balance for the corridor currency, request a treasury top-up, and prioritise queued payments by value date.'
       ELSE 'review the exception against the route profile and escalate if unexplained.'
     END
  || ' Step 3: if the screening hit rate on the route exceeds 5% or average settlement time exceeds 40 minutes after triage, keep the case open and request a route review. '
  || 'Step 4: record the resolution; if the payment failed or breached its SLA, notify the customer and log the breach for the operations report.' AS CONTENT
FROM types;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.EXCEPTION_SOP_SEARCH
  ON CONTENT
  ATTRIBUTES CATEGORY, EXCEPTION_TYPE
  WAREHOUSE = __DEMO_WH__
  TARGET_LAG = '7 days'
AS (SELECT DOC_ID, TITLE, CATEGORY, EXCEPTION_TYPE, CONTENT FROM SEARCH.EXCEPTION_DOCS);

-- ---------- Screening hit rate anomaly detection (train first 75 days, detect last 15) ----------
CREATE OR REPLACE VIEW ML.SCREENING_HIT_SERIES AS
SELECT ENTITY_ID, EVENT_DATE::TIMESTAMP_NTZ AS TS, SCREENING_HIT_PCT::FLOAT AS SCREENING_HIT
FROM RAW.ROUTE_DAILY;
CREATE OR REPLACE VIEW ML.SCREENING_HIT_TRAIN AS
SELECT * FROM ML.SCREENING_HIT_SERIES WHERE TS < (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.SCREENING_HIT_SERIES);
CREATE OR REPLACE VIEW ML.SCREENING_HIT_DETECT AS
SELECT * FROM ML.SCREENING_HIT_SERIES WHERE TS >= (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.SCREENING_HIT_SERIES);

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ML.SCREENING_HIT_ANOMALY_MODEL(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.SCREENING_HIT_TRAIN'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'SCREENING_HIT',
  LABEL_COLNAME => '');

CREATE OR REPLACE TABLE ML.SCREENING_HIT_ANOMALIES AS
SELECT SERIES::VARCHAR AS ENTITY_ID, TS::DATE AS EVENT_DATE, Y AS SCREENING_HIT, FORECAST AS EXPECTED,
       LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, PERCENTILE
FROM TABLE(ML.SCREENING_HIT_ANOMALY_MODEL!DETECT_ANOMALIES(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.SCREENING_HIT_DETECT'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'SCREENING_HIT'));

-- ---------- Semantic view ----------
CREATE OR REPLACE SEMANTIC VIEW APP.PAYMENTS_ANALYTICS
  TABLES (
    routes AS CURATED.PERFORMANCE_SUMMARY PRIMARY KEY (ENTITY_ID)
      COMMENT = 'One row per payment route (Singapore sending segment into a corridor), 90-day totals',
    risk AS ML.FAILURE_RISK_SCORES PRIMARY KEY (ENTITY_ID)
      COMMENT = 'Latest next-7-day payment-failure probability per route',
    exceptions AS CURATED.EXCEPTION_SUMMARY PRIMARY KEY (EXCEPTION_TYPE)
      COMMENT = 'Exceptions, failed payments and SLA breaches by exception type, 90 days',
    daily AS CURATED.TREND_ANALYSIS PRIMARY KEY (METRIC_DATE)
      COMMENT = 'Hub-wide totals per day'
  )
  RELATIONSHIPS (risk_route AS risk (ENTITY_ID) REFERENCES routes)
  FACTS (
    routes.exceptions_f AS EXCEPTION_COUNT,
    routes.failed_f AS FAILED_COUNT,
    routes.breaches_f AS SLA_BREACH_COUNT,
    routes.payments_f AS PAYMENT_COUNT,
    routes.value_f AS VALUE_SGD,
    routes.recon_due_f AS RECON_DUE,
    routes.recon_done_f AS RECON_COMPLETED,
    risk.failure_prob_f AS FAILURE_PROB_7D,
    exceptions.type_exceptions_f AS EXCEPTION_COUNT,
    exceptions.type_failed_f AS FAILED_COUNT,
    exceptions.type_breaches_f AS SLA_BREACH_COUNT,
    exceptions.type_value_f AS EXPOSED_VALUE_SGD,
    daily.day_exceptions_f AS EXCEPTION_COUNT,
    daily.day_failed_f AS FAILED_COUNT,
    daily.day_value_f AS VALUE_SGD
  )
  DIMENSIONS (
    routes.route_id AS ENTITY_ID WITH SYNONYMS = ('route', 'payment route'),
    routes.route_name AS ENTITY_NAME,
    routes.corridor AS REGION WITH SYNONYMS = ('corridor', 'destination', 'country')
      COMMENT = 'Destination corridor; every route originates in Singapore',
    routes.segment AS CATEGORY WITH SYNONYMS = ('segment', 'payment type', 'business line'),
    routes.risk_tier AS RISK_TIER COMMENT = 'Correspondent risk tier 1 (low) to 3 (high)',
    risk.risk_band AS RISK_BAND COMMENT = 'High >= 0.5, Medium >= 0.25, else Low',
    risk.scored_as_of AS SCORED_AS_OF,
    exceptions.exception_type AS EXCEPTION_TYPE WITH SYNONYMS = ('exception', 'exception reason', 'hold reason'),
    daily.metric_date AS METRIC_DATE
  )
  METRICS (
    routes.straight_through_pct AS 100 * (SUM(routes.payments_f) - SUM(routes.exceptions_f)) / NULLIF(SUM(routes.payments_f), 0)
      WITH SYNONYMS = ('straight-through rate', 'STP rate')
      COMMENT = 'Payments without an exception / payments processed',
    routes.failure_share_pct AS 100 * SUM(routes.failed_f) / NULLIF(SUM(routes.exceptions_f), 0)
      COMMENT = 'Failed payments / exceptions raised',
    routes.exceptions_raised AS SUM(routes.exceptions_f) WITH SYNONYMS = ('exceptions', 'exception volume'),
    routes.failed_payments AS SUM(routes.failed_f) WITH SYNONYMS = ('failures', 'returned payments'),
    routes.sla_breaches AS SUM(routes.breaches_f) WITH SYNONYMS = ('late payments', 'SLA misses'),
    routes.payments_processed AS SUM(routes.payments_f),
    routes.total_value_sgd AS SUM(routes.value_f) WITH SYNONYMS = ('value', 'volume in SGD'),
    routes.reconciliation_pct AS 100 * SUM(routes.recon_done_f) / NULLIF(SUM(routes.recon_due_f), 0)
      COMMENT = 'Nostro reconciliations completed / reconciliations due',
    risk.avg_failure_prob AS AVG(risk.failure_prob_f),
    exceptions.type_exceptions AS SUM(exceptions.type_exceptions_f),
    exceptions.type_failed AS SUM(exceptions.type_failed_f),
    exceptions.type_breaches AS SUM(exceptions.type_breaches_f),
    exceptions.type_failure_share_pct AS 100 * SUM(exceptions.type_failed_f) / NULLIF(SUM(exceptions.type_exceptions_f), 0),
    daily.daily_exceptions AS SUM(daily.day_exceptions_f),
    daily.daily_failed AS SUM(daily.day_failed_f),
    daily.daily_value_sgd AS SUM(daily.day_value_f)
  )
  COMMENT = 'Synthetic Singapore cross-border payments operations analytics (demo)';

-- ---------- Cortex Agent ----------
CREATE OR REPLACE AGENT APP.PAYMENTS_AGENT
  COMMENT = 'Payments operations assistant over a synthetic Singapore cross-border payments hub'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5
instructions:
  response: "Answer only from tool results. State that data is synthetic. Give route IDs and numbers with units (SGD, %)."
  orchestration: "Use payments_analyst for payments, exceptions, failed payments, SLA breaches, straight-through rate, routes, corridors, segments, exception types and failure risk. Use sop_search for exception-handling procedures."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: payments_analyst
      description: "Payments processed, value in SGD, exceptions, failed payments, SLA breaches, straight-through rate, nostro reconciliation compliance, exception types and payment-failure risk scores by route and corridor"
  - tool_spec:
      type: cortex_search
      name: sop_search
      description: "Synthetic payment exception-handling SOPs by payment segment and exception type"
tool_resources:
  payments_analyst:
    semantic_view: __DEMO_DB__.APP.PAYMENTS_ANALYTICS
    execution_environment:
      type: warehouse
      warehouse: __DEMO_WH__
  sop_search:
    name: __DEMO_DB__.SEARCH.EXCEPTION_SOP_SEARCH
    max_results: 3
    id_column: DOC_ID
    title_column: TITLE
$$;

-- ---------- Live-payment alert ----------
CREATE TABLE IF NOT EXISTS APP.ALERT_LOG (
  ALERTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), ROUTE_ID VARCHAR,
  EVENT_TS TIMESTAMP_NTZ, AMOUNT_SGD FLOAT, SETTLE_SECONDS FLOAT, SOP_HINT VARCHAR);

CREATE OR REPLACE NOTIFICATION INTEGRATION SG_PAY_EMAIL_INT
  TYPE = EMAIL ENABLED = TRUE ALLOWED_RECIPIENTS = ('__ALERT_EMAIL__');

CREATE OR REPLACE PROCEDURE APP.LOG_LIVE_ALERTS()
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  n NUMBER;
BEGIN
  INSERT INTO APP.ALERT_LOG (ROUTE_ID, EVENT_TS, AMOUNT_SGD, SETTLE_SECONDS, SOP_HINT)
    SELECT p.ROUTE_ID, p.EVENT_TS, p.AMOUNT_SGD, p.SETTLE_SECONDS,
           'Check ' || r.CATEGORY || ' exception SOPs; current risk band ' || COALESCE(s.RISK_BAND, 'n/a')
    FROM RAW.LIVE_PAYMENTS p
    JOIN RAW.ROUTES r ON r.ID = p.ROUTE_ID
    LEFT JOIN ML.FAILURE_RISK_SCORES s ON s.ENTITY_ID = p.ROUTE_ID
    WHERE p.STATUS = 'EXCEPTION'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.ROUTE_ID = p.ROUTE_ID AND l.EVENT_TS = p.EVENT_TS);
  n := SQLROWCOUNT;
  IF (n > 0) THEN
    CALL SYSTEM$SEND_EMAIL('SG_PAY_EMAIL_INT', '__ALERT_EMAIL__',
      '[Demo] Payment exception alert',
      'New live payment exceptions logged in APP.ALERT_LOG: ' || :n || '. Data is synthetic.');
  END IF;
  RETURN n;
END;
$$;

CREATE OR REPLACE ALERT APP.LIVE_PAYMENT_ALERT
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM RAW.LIVE_PAYMENTS p
    WHERE p.STATUS = 'EXCEPTION'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.ROUTE_ID = p.ROUTE_ID AND l.EVENT_TS = p.EVENT_TS)))
  THEN CALL APP.LOG_LIVE_ALERTS();

-- ---------- On-demand refresh DAG (suspended; run with EXECUTE TASK APP.TASK_REFRESH_CURATED) ----------
CREATE OR REPLACE PROCEDURE APP.REFRESH_CURATED()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  ALTER DYNAMIC TABLE CURATED.PERFORMANCE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.TREND_ANALYSIS REFRESH;
  ALTER DYNAMIC TABLE CURATED.EXCEPTION_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.KPI_SUMMARY REFRESH;
  RETURN 'refreshed';
END;
$$;

CREATE OR REPLACE TASK APP.TASK_REFRESH_CURATED
  WAREHOUSE = __DEMO_WH__
AS
  CALL APP.REFRESH_CURATED();

CREATE OR REPLACE TASK APP.TASK_RESCORE_RISK
  WAREHOUSE = __DEMO_WH__
  AFTER APP.TASK_REFRESH_CURATED
AS
  CREATE OR REPLACE TABLE ML.FAILURE_RISK_SCORES COPY GRANTS AS
  WITH latest AS (
    SELECT * FROM ML.FAILURE_FEATURES QUALIFY ROW_NUMBER() OVER (PARTITION BY ENTITY_ID ORDER BY EVENT_DATE DESC) = 1
  ), p AS (
    SELECT ENTITY_ID, EVENT_DATE,
           ML.FAILURE_RISK_MODEL!PREDICT(INPUT_DATA => OBJECT_CONSTRUCT(
             'CATEGORY', CATEGORY, 'RISK_TIER', RISK_TIER, 'ROUTE_AGE_YEARS', ROUTE_AGE_YEARS,
             'SCREENING_HIT_PCT', SCREENING_HIT_PCT, 'AVG_SETTLE_MIN', AVG_SETTLE_MIN,
             'SCREENING_HIT_7D', SCREENING_HIT_7D, 'FAILED_30D', FAILED_30D)) AS PRED
    FROM latest
  )
  SELECT ENTITY_ID, EVENT_DATE AS SCORED_AS_OF, ROUND(PRED:probability:FAILURE::FLOAT, 4) AS FAILURE_PROB_7D,
         CASE WHEN PRED:probability:FAILURE::FLOAT >= 0.5 THEN 'High'
              WHEN PRED:probability:FAILURE::FLOAT >= 0.25 THEN 'Medium' ELSE 'Low' END AS RISK_BAND,
         CURRENT_TIMESTAMP() AS SCORED_AT
  FROM p;
