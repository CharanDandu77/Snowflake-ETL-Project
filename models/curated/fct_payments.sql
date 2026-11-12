{{ config(materialized='table') }}

SELECT
    PAYMENT_ID,
    CUSTOMER_ID,
    PAYMENT_TYPE,
    PAYMENT_AMOUNT,
    CURRENCY,
    PAYMENT_STATUS,
    PAYMENT_DATE,
    SOURCE_SYSTEM
FROM {{ ref('stg_payments') }}