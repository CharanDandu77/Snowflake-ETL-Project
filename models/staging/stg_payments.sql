WITH ranked_payments AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY PAYMENT_ID
            ORDER BY PAYMENT_DATE DESC
        ) AS RN
    FROM {{ source('gpp_raw', 'PAYMENTS') }}
)

SELECT
    PAYMENT_ID,
    CUSTOMER_ID,
    PAYMENT_TYPE,
    PAYMENT_AMOUNT,
    CURRENCY,
    PAYMENT_STATUS,
    PAYMENT_DATE,
    SOURCE_SYSTEM
FROM ranked_payments
WHERE RN = 1