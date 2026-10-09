-- Synthetic route-day observations for a fictional Singapore cross-border payments hub.
-- A route is one sending segment of the hub paying into one destination corridor.
-- Nothing is seeded as a prediction. Randomness is HASH-seeded, so every rebuild
-- is reproducible: per-route failure propensity, drift between nostro
-- reconciliations, missed reconciliations, segment-weighted exception types,
-- exceptions cleared without failure, and two corridor-wide clearing outages.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

CREATE TABLE RAW.ROUTES AS
WITH routes AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS ROUTE_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 40))
), draws AS (
  SELECT ROUTE_INDEX,
         MOD(ABS(HASH(ROUTE_INDEX, 'age')), 1000000) / 1e6 AS U_AGE,
         MOD(ABS(HASH(ROUTE_INDEX, 'rate')), 1000000) / 1e6 AS U_RATE,
         MOD(ABS(HASH(ROUTE_INDEX, 'recon')), 1000000) / 1e6 AS U_RECON,
         MOD(ABS(HASH(ROUTE_INDEX, 'discipline')), 1000000) / 1e6 AS U_DISCIPLINE,
         MOD(ABS(HASH(ROUTE_INDEX, 'tier')), 1000000) / 1e6 AS U_TIER
  FROM routes
)
SELECT 'RTE-' || LPAD(ROUTE_INDEX::VARCHAR, 4, '0') AS ID,
       'Synthetic route ' || LPAD(ROUTE_INDEX::VARCHAR, 4, '0') AS NAME,
       -- Deterministic spread (5 and 8 are coprime): every corridor and segment
       -- is present. All routes originate in Singapore (SGD).
       CASE MOD(ROUTE_INDEX, 5) WHEN 0 THEN 'Malaysia' WHEN 1 THEN 'Hong Kong'
            WHEN 2 THEN 'Indonesia' WHEN 3 THEN 'Thailand' ELSE 'Philippines' END AS REGION,
       CASE MOD(ROUTE_INDEX, 8) WHEN 0 THEN 'Retail remittance' WHEN 1 THEN 'Retail remittance'
            WHEN 2 THEN 'Retail remittance' WHEN 3 THEN 'SME trade' WHEN 4 THEN 'SME trade'
            WHEN 5 THEN 'Payroll batch' WHEN 6 THEN 'Corporate treasury' ELSE 'Bank-to-bank' END AS CATEGORY,
       ROUTE_INDEX,
       1 + FLOOR(U_TIER * 3) AS RISK_TIER,
       ROUND(0.2 + U_AGE * 5.8, 1) AS ROUTE_AGE_YEARS,
       -- Base daily probability of a failed payment 0.4%-3%; ~15% of routes are
       -- chronically weak (x3).
       (0.004 + U_RATE * 0.026) * IFF(U_RATE > 0.85, 3, 1) AS BASE_FAILURE_RATE,
       7 * (1 + FLOOR(U_RECON * 3)) AS RECON_INTERVAL_DAYS,
       0.55 + U_DISCIPLINE * 0.45 AS RECON_COMPLETION_PROB,
       'Active' AS STATUS
FROM draws;

CREATE TABLE RAW.ROUTE_DAILY AS
WITH days AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS DAY_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 90))
), corridor_events AS (
  -- Two corridor-wide clearing outages; every route into the corridor raises an
  -- exception that clears once the clearing system recovers.
  SELECT * FROM VALUES (27, 'Hong Kong'), (64, 'Malaysia') AS o(DAY_INDEX, REGION)
), base AS (
  SELECT r.ID AS ENTITY_ID, r.ROUTE_INDEX, r.CATEGORY, r.REGION, r.ROUTE_AGE_YEARS,
         r.BASE_FAILURE_RATE, r.RECON_INTERVAL_DAYS, r.RECON_COMPLETION_PROB,
         d.DAY_INDEX,
         DATEADD('day', d.DAY_INDEX - 89, CURRENT_DATE()) AS EVENT_DATE,
         MOD(d.DAY_INDEX + r.ROUTE_INDEX * 5, r.RECON_INTERVAL_DAYS) AS DAYS_SINCE_RECON,
         MOD(ABS(HASH(r.ID, d.DAY_INDEX, 'fail')), 1000000) / 1e6 AS U_FAIL,
         MOD(ABS(HASH(r.ID, d.DAY_INDEX, 'detect')), 1000000) / 1e6 AS U_DETECT,
         MOD(ABS(HASH(r.ID, d.DAY_INDEX, 'clear')), 1000000) / 1e6 AS U_CLEAR,
         MOD(ABS(HASH(r.ID, d.DAY_INDEX, 'type')), 1000000) / 1e6 AS U_TYPE,
         MOD(ABS(HASH(r.ID, d.DAY_INDEX, 'done')), 1000000) / 1e6 AS U_DONE,
         MOD(ABS(HASH(r.ID, d.DAY_INDEX, 'volume')), 1000000) / 1e6 AS U_VOLUME,
         MOD(ABS(HASH(r.ID, d.DAY_INDEX, 'noise')), 1000000) / 1e6 AS U_NOISE,
         MOD(ABS(HASH(r.ID, d.DAY_INDEX, 'sla')), 1000000) / 1e6 AS U_SLA,
         e.REGION IS NOT NULL AS CORRIDOR_EVENT
  FROM RAW.ROUTES r CROSS JOIN days d
  LEFT JOIN corridor_events e ON e.DAY_INDEX = d.DAY_INDEX AND e.REGION = r.REGION
), recon AS (
  SELECT *,
         IFF(DAYS_SINCE_RECON = 0, 1, 0) AS RECON_DUE,
         IFF(DAYS_SINCE_RECON = 0 AND U_DONE < RECON_COMPLETION_PROB, 1, 0) AS RECON_COMPLETED,
         -- Data-quality drift rises between nostro reconciliations; weak
         -- reconciliation discipline carries it over.
         DAYS_SINCE_RECON / RECON_INTERVAL_DAYS + (1 - RECON_COMPLETION_PROB) AS DRIFT
  FROM base
), failures AS (
  SELECT *,
         CASE WHEN U_FAIL < LEAST(0.5, BASE_FAILURE_RATE * (0.4 + 1.6 * DRIFT) * (1 + 1 / (1 + ROUTE_AGE_YEARS))) / 4 THEN 2
              WHEN U_FAIL < LEAST(0.5, BASE_FAILURE_RATE * (0.4 + 1.6 * DRIFT) * (1 + 1 / (1 + ROUTE_AGE_YEARS))) THEN 1
              ELSE 0 END AS FAILURE_RISK_COUNT
  FROM recon
), exceptions AS (
  SELECT *,
         -- About 85% of at-risk payments are caught as exceptions and end failed
         -- or returned; the rest settle late without an exception.
         IFF(CORRIDOR_EVENT, 0, IFF(U_DETECT < 0.85, FAILURE_RISK_COUNT, 0)) AS FAILED_COUNT,
         -- Exceptions cleared without failure: higher for high-volume segments.
         IFF(CORRIDOR_EVENT, 1, IFF(U_CLEAR < CASE CATEGORY WHEN 'Payroll batch' THEN 0.20
                                                             WHEN 'Corporate treasury' THEN 0.12
                                                             WHEN 'Bank-to-bank' THEN 0.14 ELSE 0.08 END, 1, 0)) AS CLEARED_COUNT
  FROM failures
), measured AS (
  SELECT *,
         FAILED_COUNT + CLEARED_COUNT AS EXCEPTION_COUNT,
         ROUND(CASE CATEGORY WHEN 'Payroll batch' THEN 1800 WHEN 'Corporate treasury' THEN 260
                             WHEN 'Bank-to-bank' THEN 40 WHEN 'SME trade' THEN 120 ELSE 35 END
               * (0.7 + 0.6 * U_VOLUME) * (1 + 0.8 * FAILURE_RISK_COUNT)) AS PAYMENT_COUNT,
         CASE CATEGORY WHEN 'Payroll batch' THEN 2500 WHEN 'Corporate treasury' THEN 42000
                       WHEN 'Bank-to-bank' THEN 310000 WHEN 'SME trade' THEN 9500 ELSE 650 END
           * (0.8 + 0.4 * U_NOISE) AS AVG_PAYMENT_SGD
  FROM exceptions
)
SELECT ENTITY_ID || '-' || TO_CHAR(EVENT_DATE, 'YYYYMMDD') AS EVENT_ID,
       ENTITY_ID, EVENT_DATE,
       PAYMENT_COUNT,
       ROUND(PAYMENT_COUNT * AVG_PAYMENT_SGD, 2) AS VALUE_SGD,
       EXCEPTION_COUNT, FAILED_COUNT,
       IFF(FAILED_COUNT > 0 AND U_SLA < 0.6, 1, 0) AS SLA_BREACHED,
       CASE WHEN EXCEPTION_COUNT = 0 THEN 'None'
            WHEN CORRIDOR_EVENT THEN 'Clearing system outage'
            WHEN CATEGORY = 'Retail remittance' THEN IFF(U_TYPE < 0.5, 'Beneficiary name mismatch', IFF(U_TYPE < 0.8, 'AML hold', 'Sanctions screening hit'))
            WHEN CATEGORY = 'SME trade' THEN IFF(U_TYPE < 0.45, 'AML hold', IFF(U_TYPE < 0.8, 'Format error', 'Sanctions screening hit'))
            WHEN CATEGORY = 'Payroll batch' THEN IFF(U_TYPE < 0.55, 'Format error', 'Duplicate payment')
            WHEN CATEGORY = 'Corporate treasury' THEN IFF(U_TYPE < 0.45, 'Cut-off missed', IFF(U_TYPE < 0.8, 'Nostro liquidity shortfall', 'Sanctions screening hit'))
            ELSE IFF(U_TYPE < 0.5, 'Nostro liquidity shortfall', IFF(U_TYPE < 0.75, 'Sanctions screening hit', 'AML hold')) END AS EXCEPTION_TYPE,
       RECON_DUE, RECON_COMPLETED,
       ROUND(0.5 + 2.0 * DRIFT + 3.0 * FAILURE_RISK_COUNT + U_NOISE * 0.8, 2) AS SCREENING_HIT_PCT,
       ROUND(18 + 12 * DRIFT + 14 * FAILURE_RISK_COUNT + U_NOISE * 6, 1) AS AVG_SETTLE_MIN,
       CURRENT_TIMESTAMP() AS LOADED_AT
FROM measured;

-- Correspondent due-diligence document coverage per route (snapshot).
CREATE TABLE RAW.DUE_DILIGENCE_DOCUMENTS AS
SELECT ID AS ENTITY_ID,
       CASE CATEGORY WHEN 'Retail remittance' THEN 'Remittance partner licence'
                     WHEN 'SME trade' THEN 'Trade documentation policy'
                     WHEN 'Payroll batch' THEN 'Payroll mandate'
                     WHEN 'Corporate treasury' THEN 'Beneficial ownership'
                     ELSE 'Correspondent due diligence questionnaire' END AS DOC_TYPE,
       1 + MOD(ABS(HASH(ID, 'req')), 4) AS REQUIRED_QTY,
       MOD(ABS(HASH(ID, 'file')), 5) AS ON_FILE_QTY,
       IFF(MOD(ABS(HASH(ID, 'file')), 5) < 1 + MOD(ABS(HASH(ID, 'req')), 4),
           MOD(ABS(HASH(ID, 'pending')), 3), 0) AS PENDING_QTY,
       CURRENT_DATE() AS SNAPSHOT_DATE
FROM RAW.ROUTES;
