USE project1;

SELECT DISTINCT is_churned
FROM customers;

DESC subscriptions;

SELECT DISTINCT payment_status
FROM subscriptions;

-- Q1
SELECT
    c.plan_type,
    COUNT(c.customer_id) AS active_customers,
    ROUND(
        SUM(COALESCE(r.total_revenue, 0))
        / COUNT(c.customer_id),
        2
    ) AS avg_revenue_per_active_customer

FROM customers c

LEFT JOIN (
    SELECT
        customer_id,
        SUM(amount) AS total_revenue
    FROM subscriptions
    WHERE payment_status = 'Paid'
    GROUP BY customer_id
) r
ON c.customer_id = r.customer_id
WHERE c.is_churned = 'FALSE'
GROUP BY c.plan_type
ORDER BY avg_revenue_per_active_customer DESC;

-- Q2

SELECT
    customer_id,
    ROUND(SUM(total_minutes), 2) AS total_time_spent
FROM product_usage
GROUP BY customer_id
ORDER BY total_time_spent DESC
LIMIT 5;

-- Q3


SELECT
    industry,
    COUNT(*) AS total_customers,
    SUM(
        CASE
            WHEN is_churned = 'TRUE' THEN 1
            ELSE 0
        END
    ) AS churned_customers,
    ROUND(
        SUM(
            CASE
                WHEN is_churned = 'TRUE' THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(*),
        2
    ) AS churn_rate_percentage
FROM customers
GROUP BY industry
ORDER BY churn_rate_percentage DESC;

-- Q4


WITH monthly_events AS (

    -- Monthly new customer signups
    SELECT
        DATE_FORMAT(
            STR_TO_DATE(signup_date, '%d-%m-%Y'),
            '%Y-%m'
        ) AS month,
        COUNT(*) AS new_signups,
        0 AS churned_customers
    FROM customers
    WHERE signup_date IS NOT NULL
    GROUP BY month

    UNION ALL

    -- Monthly customer churn
    SELECT
        DATE_FORMAT(
            STR_TO_DATE(churn_date, '%Y-%m-%d %H:%i:%s'),
            '%Y-%m'
        ) AS month,
        0 AS new_signups,
        COUNT(*) AS churned_customers
    FROM customers
    WHERE churn_date IS NOT NULL
      AND TRIM(churn_date) <> ''
    GROUP BY month
)

SELECT
    month,
    SUM(new_signups) AS new_signups,
    SUM(churned_customers) AS churned_customers
FROM monthly_events
WHERE month IS NOT NULL
GROUP BY month
ORDER BY month;

-- Q5
DESC product_usage;

SELECT customer_id, date, logins
FROM product_usage
LIMIT 5;


SELECT
    c.customer_id,
    c.churn_date,
    COALESCE(SUM(p.logins), 0) AS previous_month_logins

FROM customers c

LEFT JOIN product_usage p
    ON c.customer_id = p.customer_id
    AND STR_TO_DATE(p.date, '%d-%m-%Y')
        >= DATE_SUB(
            DATE_FORMAT(
                STR_TO_DATE(c.churn_date, '%Y-%m-%d %H:%i:%s'),
                '%Y-%m-01'
            ),
            INTERVAL 1 MONTH
        )
    AND STR_TO_DATE(p.date, '%d-%m-%Y')
        < DATE_FORMAT(
            STR_TO_DATE(c.churn_date, '%Y-%m-%d %H:%i:%s'),
            '%Y-%m-01'
        )
WHERE c.is_churned = 'TRUE'
  AND c.churn_date IS NOT NULL
  AND TRIM(c.churn_date) <> ''
GROUP BY c.customer_id, c.churn_date
HAVING COALESCE(SUM(p.logins), 0) = 0;

-- Q6

SELECT
    s.ticket_type,
    COUNT(*) AS total_tickets
FROM support_tickets s
JOIN customers c
    ON s.customer_id = c.customer_id
WHERE c.is_churned = 'TRUE'
GROUP BY s.ticket_type
ORDER BY total_tickets DESC;

-- Q7

WITH daily_logins AS (
    SELECT
        customer_id,
        STR_TO_DATE(date, '%d-%m-%Y') AS usage_date,
        SUM(logins) AS daily_logins
    FROM product_usage
    GROUP BY customer_id, usage_date
)

SELECT
    customer_id,
    usage_date,
    daily_logins,
    ROUND(
        AVG(daily_logins) OVER (
            PARTITION BY customer_id
            ORDER BY usage_date
            RANGE BETWEEN INTERVAL 29 DAY PRECEDING
            AND CURRENT ROW
        ),
        2
    ) AS rolling_30_day_avg_logins
FROM daily_logins
ORDER BY customer_id, usage_date;

-- Q8

WITH monthly_usage AS (
    SELECT
        customer_id,
        DATE_FORMAT(
            STR_TO_DATE(date, '%d-%m-%Y'),
            '%Y-%m'
        ) AS usage_month,
        AVG(total_minutes) AS avg_usage_minutes
    FROM product_usage
    GROUP BY
        customer_id,
        DATE_FORMAT(
            STR_TO_DATE(date, '%d-%m-%Y'),
            '%Y-%m'
        )
),

usage_comparison AS (
    SELECT
        customer_id,
        usage_month,
        avg_usage_minutes,

        LAG(avg_usage_minutes) OVER (
            PARTITION BY customer_id
            ORDER BY usage_month
        ) AS previous_month_avg

    FROM monthly_usage
)

SELECT
    customer_id,
    usage_month,
    ROUND(previous_month_avg, 2) AS previous_month_avg,
    ROUND(avg_usage_minutes, 2) AS current_month_avg,
    ROUND(previous_month_avg - avg_usage_minutes, 2)
        AS usage_drop
FROM usage_comparison
WHERE previous_month_avg IS NOT NULL
  AND avg_usage_minutes < previous_month_avg
ORDER BY usage_drop DESC
LIMIT 1;

-- Q9

SELECT
    s.customer_id,
    SUM(s.amount) AS total_paid_amount
FROM subscriptions s
WHERE s.payment_status = 'Paid'
  AND NOT EXISTS (
      SELECT 1
      FROM product_usage p
      WHERE p.customer_id = s.customer_id
  )
GROUP BY s.customer_id
ORDER BY total_paid_amount DESC;

-- Q10

SELECT
    customer_id,
    ROUND(SUM(total_minutes), 2) AS total_usage_minutes
FROM product_usage
GROUP BY customer_id
HAVING SUM(total_minutes) > (
    SELECT AVG(user_total_minutes)
    FROM (
        SELECT
            customer_id,
            SUM(total_minutes) AS user_total_minutes
        FROM product_usage
        GROUP BY customer_id
    ) AS user_usage
)
ORDER BY total_usage_minutes DESC;

-- Q11

SELECT
    c.customer_id,
    c.churn_date
FROM customers c
WHERE c.is_churned = 'TRUE'
  AND c.churn_date IS NOT NULL
  AND TRIM(c.churn_date) <> ''
  AND NOT EXISTS (
      SELECT 1
      FROM support_tickets s
      WHERE s.customer_id = c.customer_id
        AND STR_TO_DATE(s.ticket_date, '%d-%m-%Y')
            < STR_TO_DATE(
                c.churn_date,
                '%Y-%m-%d %H:%i:%s'
            )
  )
ORDER BY c.churn_date;

-- Q12

SELECT DISTINCT
    p.customer_id,
    STR_TO_DATE(p.date, '%d-%m-%Y') AS activity_date
FROM product_usage p
JOIN support_tickets s
    ON p.customer_id = s.customer_id
    AND STR_TO_DATE(p.date, '%d-%m-%Y')
        = STR_TO_DATE(s.ticket_date, '%d-%m-%Y')
ORDER BY activity_date, p.customer_id;

SELECT
    ticket_id,
    customer_id,
    ticket_date
FROM support_tickets
LIMIT 10;

SELECT
    customer_id,
    date
FROM product_usage
LIMIT 10;



SELECT DISTINCT
    p.customer_id,
    STR_TO_DATE(p.date, '%d-%m-%Y') AS activity_date

FROM product_usage p

JOIN support_tickets s
    ON p.customer_id = s.customer_id

    AND STR_TO_DATE(p.date, '%d-%m-%Y')
        = STR_TO_DATE(
            s.ticket_date,
            '%Y-%m-%d %H:%i:%s'
        )

ORDER BY activity_date, p.customer_id;

-- Q13

SELECT
    ROUND(
        SUM(
            CASE
                WHEN c.is_churned = 'TRUE'
                THEN s.amount
                ELSE 0
            END
        ),
        2
    ) AS churned_customer_revenue,

    ROUND(SUM(s.amount), 2) AS total_subscription_revenue,

    ROUND(
        SUM(
            CASE
                WHEN c.is_churned = 'TRUE'
                THEN s.amount
                ELSE 0
            END
        ) * 100.0 / SUM(s.amount),
        2
    ) AS churned_revenue_percentage

FROM subscriptions s

JOIN customers c
    ON s.customer_id = c.customer_id

WHERE s.payment_status = 'Paid';

-- Q14

SELECT
    s.ticket_type,
    COUNT(*) AS total_tickets,
    COUNT(DISTINCT s.customer_id) AS churned_customers

FROM support_tickets s

JOIN customers c
    ON s.customer_id = c.customer_id

WHERE c.is_churned = 'TRUE'

GROUP BY s.ticket_type
ORDER BY total_tickets DESC;

-- Q15
DESC support_tickets;
SELECT DISTINCT ticket_status
FROM support_tickets;


SELECT
    product_name,
    COUNT(*) AS total_tickets,

    SUM(
        CASE
            WHEN ticket_status = 'Escalated'
            THEN 1
            ELSE 0
        END
    ) AS escalated_tickets,

    ROUND(
        SUM(
            CASE
                WHEN ticket_status = 'Escalated'
                THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(*),
        2
    ) AS escalation_percentage

FROM support_tickets

GROUP BY product_name
ORDER BY escalation_percentage DESC;

-- Q16

WITH customer_tenure AS (
    SELECT
        customer_id,
        is_churned,

        TIMESTAMPDIFF(
            MONTH,
            STR_TO_DATE(signup_date, '%d-%m-%Y'),
            CASE
                WHEN is_churned = 'TRUE'
                THEN STR_TO_DATE(
                    churn_date,
                    '%Y-%m-%d %H:%i:%s'
                )
                ELSE CURDATE()
            END
        ) AS tenure_months

    FROM customers
)

SELECT
    CASE
        WHEN tenure_months <= 3 THEN '0-3 Months'
        WHEN tenure_months <= 6 THEN '4-6 Months'
        WHEN tenure_months <= 12 THEN '7-12 Months'
        ELSE 'More than 12 Months'
    END AS tenure_period,

    COUNT(*) AS total_customers,

    SUM(
        CASE WHEN is_churned = 'TRUE'
        THEN 1 ELSE 0 END
    ) AS churned_customers,

    ROUND(
        SUM(
            CASE WHEN is_churned = 'TRUE'
            THEN 1 ELSE 0 END
        ) * 100.0 / COUNT(*),
        2
    ) AS churn_rate_percentage

FROM customer_tenure
WHERE tenure_months IS NOT NULL
  AND tenure_months >= 0

GROUP BY tenure_period
ORDER BY churn_rate_percentage DESC;

-- Q17

SELECT
    customer_id,
    COUNT(subscription_id) AS subscription_count
FROM subscriptions
GROUP BY customer_id
HAVING COUNT(subscription_id) > 1
ORDER BY subscription_count DESC;


SELECT COUNT(*) AS customers_with_multiple_subscriptions
FROM (
    SELECT customer_id
    FROM subscriptions
    GROUP BY customer_id
    HAVING COUNT(subscription_id) > 1
) AS multiple_subscriptions;


SELECT 'customers' AS table_name,
       COUNT(*) AS total_rows,
       COUNT(DISTINCT customer_id) AS unique_customers
FROM customers

UNION ALL

SELECT 'product_usage',
       COUNT(*),
       COUNT(DISTINCT customer_id)
FROM product_usage

UNION ALL

SELECT 'subscriptions',
       COUNT(*),
       COUNT(DISTINCT customer_id)
FROM subscriptions

UNION ALL

SELECT 'support_tickets',
       COUNT(*),
       COUNT(DISTINCT customer_id)
FROM support_tickets;

