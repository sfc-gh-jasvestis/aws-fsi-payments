-- ============================================================================
-- 08_native_payments.sql - Snowflake-only build: live payment feed without AWS.
-- Creates RAW.LIVE_PAYMENTS (same columns as the Snowpipe target created by
-- aws/setup_aws.py) and APP.SIMULATE_PAYMENTS(N), which inserts synthetic
-- payment events with the same value ranges and ~10% EXCEPTION rate as
-- aws/publish_payments.py. Rows are inserted directly; this simulates a payment
-- feed and is not Snowpipe Streaming.
-- Run before 06_intelligence.sql (the alert reads RAW.LIVE_PAYMENTS).
-- Idempotent: safe to run in the AWS build too.
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS APP;

CREATE TABLE IF NOT EXISTS RAW.LIVE_PAYMENTS (
  ROUTE_ID VARCHAR, EVENT_TS TIMESTAMP_NTZ, AMOUNT_SGD FLOAT, SETTLE_SECONDS FLOAT,
  STATUS VARCHAR, SENT_TS TIMESTAMP_NTZ, SOURCE_FILE VARCHAR,
  LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());

CREATE OR REPLACE PROCEDURE APP.SIMULATE_PAYMENTS(N NUMBER)
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  IF (N < 1 OR N > 1000) THEN
    RETURN 0;
  END IF;
  INSERT INTO RAW.LIVE_PAYMENTS (ROUTE_ID, EVENT_TS, AMOUNT_SGD, SETTLE_SECONDS, STATUS, SENT_TS, SOURCE_FILE)
    WITH g AS (
      SELECT 'RTE-' || LPAD(UNIFORM(0, 39, RANDOM())::VARCHAR, 4, '0') AS ROUTE_ID,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.1 AS IS_EXCEPTION,
             SYSDATE() AS TS, SEQ4() AS I
      FROM TABLE(GENERATOR(ROWCOUNT => 1000))
    )
    -- NORMAL() needs constant arguments, so the exception offset is applied outside it.
    SELECT ROUTE_ID, TS,
           ROUND(IFF(IS_EXCEPTION, 250000, 8000) * EXP(NORMAL(0, 0.5, RANDOM())), 2),
           ROUND(IFF(IS_EXCEPTION, 1800, 20) * EXP(NORMAL(0, 0.4, RANDOM())), 0),
           IFF(IS_EXCEPTION, 'EXCEPTION', 'OK'), TS, 'APP.SIMULATE_PAYMENTS'
    FROM g
    WHERE I < :N;
  RETURN SQLROWCOUNT;
END;
$$;

-- Optional continuous feed for longer demos (suspended; RESUME to start, SUSPEND after).
CREATE OR REPLACE TASK APP.TASK_SIMULATE_PAYMENTS
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '1 MINUTE'
AS
  CALL APP.SIMULATE_PAYMENTS(5);
