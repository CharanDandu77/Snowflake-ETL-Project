SELECT *
FROM {{ ref('stg_payments') }}
WHERE CUSTOMER_ID IS NULL;