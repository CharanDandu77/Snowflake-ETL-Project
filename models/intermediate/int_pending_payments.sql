{{ config(materialized='view') }}

SELECT
    PAYMENT_ID,
    CUSTOMER_ID,
    PAYMENT_AMOUNT,
    CURRENCY,
    PAYMENT_DATE,
    PAYMENT_STATUS
FROM {{ ref('stg_payments') }}
WHERE PAYMENT_STATUS = 'PENDING';