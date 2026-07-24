CREATE OR REPLACE PROCEDURE LOAD_ACH_PAYMENT()

RETURNS STRING

LANGUAGE SQL

EXECUTE AS OWNER

AS
$$

DECLARE

    V_RUN_ID NUMBER;
    V_COUNT NUMBER;
    V_SUCCESS NUMBER;
    V_ERROR NUMBER;
    V_DUPLICATE NUMBER;

BEGIN

    ---------------------------------------------------
    -- START AUDIT
    ---------------------------------------------------

    INSERT INTO AUDIT_SCHEMA.AUDIT_LOG
    (
        FILE_NAME,
        PROCESS_NAME,
        LOAD_TYPE,
        START_TIME,
        STATUS
    )

    VALUES
    (
        'ACH_PAYMENT_FILE',
        'LOAD_ACH_PAYMENT',
        'INCREMENTAL',
        CURRENT_TIMESTAMP(),
        'RUNNING'
    );

    SELECT MAX(RUN_ID)
    INTO V_RUN_ID
    FROM AUDIT_SCHEMA.AUDIT_LOG;

    ---------------------------------------------------
    -- CHECK STREAM
    ---------------------------------------------------

    SELECT COUNT(*)

    INTO V_COUNT

    FROM RAW_SCHEMA.RAW_ACH_PAYMENT_STREAM;

    IF (V_COUNT = 0) THEN

        UPDATE AUDIT_SCHEMA.AUDIT_LOG
        SET
            END_TIME = CURRENT_TIMESTAMP(),
            STATUS = 'NO DATA'
        WHERE RUN_ID = V_RUN_ID;

        RETURN 'NO NEW RECORDS FOUND';

    END IF;

    ---------------------------------------------------
    -- TEMP TABLE
    ---------------------------------------------------

    CREATE OR REPLACE TEMP TABLE TMP_ACH_PAYMENT AS

    SELECT

        PAYMENT_ID,

        ACCOUNT_NO,

        AMOUNT,

        CURRENCY,

        STATUS,

        PAYMENT_DATE,

        BANK_CODE,

        ROW_NUMBER()
        OVER
        (
            PARTITION BY PAYMENT_ID
            ORDER BY PAYMENT_DATE DESC
        ) RN

    FROM RAW_SCHEMA.RAW_ACH_PAYMENT_STREAM;

    ---------------------------------------------------
    -- MERGE
    ---------------------------------------------------

    MERGE INTO CURATED_SCHEMA.CURATED_ACH_PAYMENT T

    USING
    (
        SELECT *

        FROM TMP_ACH_PAYMENT

        WHERE RN = 1

        AND ACCOUNT_NO IS NOT NULL

        AND TRIM(ACCOUNT_NO) <> ''

        AND AMOUNT IS NOT NULL

        AND CURRENCY IN
        (
            'USD',
            'EUR',
            'INR'
        )

        AND STATUS IN
        (
            'SUCCESS',
            'FAILED',
            'PENDING'
        )

        AND BANK_CODE IN
        (
            'HDFC',
            'ICICI',
            'SBI',
            'AXIS',
            'BOFA',
            'CITI',
            'PNB',
            'HSBC'
        )

    ) S

    ON T.PAYMENT_ID = S.PAYMENT_ID

    WHEN MATCHED THEN

    UPDATE SET

        ACCOUNT_NO = S.ACCOUNT_NO,

        AMOUNT = S.AMOUNT,

        CURRENCY = S.CURRENCY,

        STATUS = S.STATUS,

        PAYMENT_DATE = S.PAYMENT_DATE,

        BANK_CODE = S.BANK_CODE,

        LOAD_DATE = CURRENT_TIMESTAMP()

    WHEN NOT MATCHED THEN

    INSERT
    (
        PAYMENT_ID,
        ACCOUNT_NO,
        AMOUNT,
        CURRENCY,
        STATUS,
        PAYMENT_DATE,
        BANK_CODE,
        LOAD_DATE
    )

    VALUES
    (
        S.PAYMENT_ID,
        S.ACCOUNT_NO,
        S.AMOUNT,
        S.CURRENCY,
        S.STATUS,
        S.PAYMENT_DATE,
        S.BANK_CODE,
        CURRENT_TIMESTAMP()
    );
    ---------------------------------------------------
    -- ERROR TABLE
    ---------------------------------------------------

    INSERT INTO AUDIT_SCHEMA.ERROR_PAYMENT
    (
        PAYMENT_ID,
        ACCOUNT_NO,
        AMOUNT,
        CURRENCY,
        STATUS,
        PAYMENT_DATE,
        BANK_CODE,
        ERROR_REASON,
        ERROR_DATE
    )

    SELECT

        PAYMENT_ID,
        ACCOUNT_NO,
        AMOUNT,
        CURRENCY,
        STATUS,
        PAYMENT_DATE,
        BANK_CODE,

        CASE

            WHEN ACCOUNT_NO IS NULL OR TRIM(ACCOUNT_NO) = ''
                THEN 'ACCOUNT_NO IS NULL'

            WHEN AMOUNT IS NULL
                THEN 'AMOUNT IS NULL'

            WHEN CURRENCY NOT IN ('USD','EUR','INR')
                THEN 'INVALID CURRENCY'

            WHEN STATUS NOT IN ('SUCCESS','FAILED','PENDING')
                THEN 'INVALID STATUS'

            WHEN BANK_CODE NOT IN
            (
                'HDFC',
                'ICICI',
                'SBI',
                'AXIS',
                'BOFA',
                'CITI',
                'PNB',
                'HSBC'
            )
                THEN 'INVALID BANK CODE'

        END,

        CURRENT_TIMESTAMP()

    FROM TMP_ACH_PAYMENT

    WHERE RN = 1

    AND
    (
        ACCOUNT_NO IS NULL
        OR TRIM(ACCOUNT_NO) = ''
        OR AMOUNT IS NULL
        OR CURRENCY NOT IN ('USD','EUR','INR')
        OR STATUS NOT IN ('SUCCESS','FAILED','PENDING')
        OR BANK_CODE NOT IN
        (
            'HDFC',
            'ICICI',
            'SBI',
            'AXIS',
            'BOFA',
            'CITI',
            'PNB',
            'HSBC'
        )
    );

    ---------------------------------------------------
    -- DUPLICATE TABLE
    ---------------------------------------------------

    INSERT INTO CURATED_SCHEMA.DUPLICATE_ACH_PAYMENT
    (
        PAYMENT_ID,
        ACCOUNT_NO,
        AMOUNT,
        CURRENCY,
        STATUS,
        PAYMENT_DATE,
        BANK_CODE,
        DUPLICATE_REASON,
        DUPLICATE_DATE
    )

    SELECT

        PAYMENT_ID,
        ACCOUNT_NO,
        AMOUNT,
        CURRENCY,
        STATUS,
        PAYMENT_DATE,
        BANK_CODE,

        'DUPLICATE PAYMENT_ID',

        CURRENT_TIMESTAMP()

    FROM TMP_ACH_PAYMENT

    WHERE RN > 1;

    ---------------------------------------------------
    -- COUNTS
    ---------------------------------------------------

    SELECT COUNT(*)
    INTO V_SUCCESS
    FROM TMP_ACH_PAYMENT
    WHERE RN = 1
      AND ACCOUNT_NO IS NOT NULL
      AND TRIM(ACCOUNT_NO) <> ''
      AND AMOUNT IS NOT NULL
      AND CURRENCY IN ('USD','EUR','INR')
      AND STATUS IN ('SUCCESS','FAILED','PENDING')
      AND BANK_CODE IN
      (
          'HDFC',
          'ICICI',
          'SBI',
          'AXIS',
          'BOFA',
          'CITI',
          'PNB',
          'HSBC'
      );

    SELECT COUNT(*)
    INTO V_ERROR
    FROM TMP_ACH_PAYMENT
    WHERE RN = 1
      AND
      (
          ACCOUNT_NO IS NULL
          OR TRIM(ACCOUNT_NO) = ''
          OR AMOUNT IS NULL
          OR CURRENCY NOT IN ('USD','EUR','INR')
          OR STATUS NOT IN ('SUCCESS','FAILED','PENDING')
          OR BANK_CODE NOT IN
          (
              'HDFC',
              'ICICI',
              'SBI',
              'AXIS',
              'BOFA',
              'CITI',
              'PNB',
              'HSBC'
          )
      );

    SELECT COUNT(*)
    INTO V_DUPLICATE
    FROM TMP_ACH_PAYMENT
    WHERE RN > 1;

    ---------------------------------------------------
    -- UPDATE AUDIT
    ---------------------------------------------------

    UPDATE AUDIT_SCHEMA.AUDIT_LOG

    SET

        END_TIME = CURRENT_TIMESTAMP(),

        TOTAL_RECORDS = V_COUNT,

        SUCCESS_RECORDS = V_SUCCESS,

        ERROR_RECORDS = V_ERROR,

        DUPLICATE_RECORDS = V_DUPLICATE,

        STATUS = 'SUCCESS'

    WHERE RUN_ID = V_RUN_ID;

    RETURN 'LOAD COMPLETED SUCCESSFULLY';

EXCEPTION

WHEN OTHER THEN

    UPDATE AUDIT_SCHEMA.AUDIT_LOG

    SET

        END_TIME = CURRENT_TIMESTAMP(),

        STATUS = 'FAILED',

        ERROR_MESSAGE = SQLERRM

    WHERE RUN_ID = V_RUN_ID;

    RETURN 'FAILED : ' || SQLERRM;;

END;

$$;