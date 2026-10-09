-- Validate the producer contract before building downstream objects.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

EXECUTE IMMEDIATE $$
DECLARE
  violations INTEGER;
  invalid_source EXCEPTION (-20001, 'Synthetic source failed grain or measure validation');
BEGIN
  SELECT COUNT(*) INTO :violations FROM (
    SELECT ENTITY_ID, EVENT_DATE
    FROM RAW.ROUTE_DAILY
    GROUP BY ENTITY_ID, EVENT_DATE HAVING COUNT(*) <> 1
    UNION ALL
    SELECT observation.ENTITY_ID, observation.EVENT_DATE
    FROM RAW.ROUTE_DAILY observation
    LEFT JOIN RAW.ROUTES route ON route.ID = observation.ENTITY_ID
    WHERE route.ID IS NULL OR observation.PAYMENT_COUNT < 0
       OR observation.VALUE_SGD < 0
       OR observation.FAILED_COUNT < 0 OR observation.FAILED_COUNT > observation.EXCEPTION_COUNT
       OR observation.EXCEPTION_COUNT > observation.PAYMENT_COUNT
       OR observation.SLA_BREACHED > observation.FAILED_COUNT
       OR observation.RECON_COMPLETED > observation.RECON_DUE
  );
  IF (violations > 0) THEN
    RAISE invalid_source;
  END IF;
END;
$$;
