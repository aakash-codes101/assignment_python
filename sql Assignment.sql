-- [Q1] Find all customers from 'USA' who placed completed orders in Q1 2024.
--      Return customer_name, order_id, order_date, and order net revenue.

SELECT
    c.customer_name,
    o.order_id,
    o.order_date,
    o.net_revenue
FROM customers AS c
INNER JOIN orders AS o
    ON o.customer_id = c.customer_id
WHERE c.country = 'USA'
  AND o.status = 'Completed'
  AND o.order_date >= '2024-01-01'
  AND o.order_date < '2024-04-01'
ORDER BY o.order_date, o.order_id;


-- [Q2] Identify all sales reps (department_id = 2) who have NEVER closed an order.
--      Anti-Join pattern.

SELECT
    e.employee_id,
    e.employee_name
FROM employees AS e
LEFT JOIN orders AS o
    ON o.employee_id = e.employee_id
   AND o.status = 'Completed'
WHERE e.department_id = 2
  AND o.order_id IS NULL
ORDER BY e.employee_name;


-- [Q3] List all products that have never been ordered in the entire history.

SELECT
    p.product_id,
    p.product_name,
    p.unit_price
FROM products AS p
LEFT JOIN order_items AS oi
    ON oi.product_id = p.product_id
WHERE oi.product_id IS NULL
ORDER BY p.product_name;


-- [Q4] Employees whose salary is strictly higher than their department average.

SELECT
    e.employee_name,
    d.department_name,
    e.salary,
    AVG(e.salary) OVER (
        PARTITION BY e.department_id
    ) AS department_average_salary
FROM employees AS e
INNER JOIN departments AS d
    ON d.department_id = e.department_id
WHERE e.salary > (
    SELECT AVG(e2.salary)
    FROM employees AS e2
    WHERE e2.department_id = e.department_id
)
ORDER BY d.department_name, e.salary DESC;


-- [Q5] Customer segments where total net revenue exceeds $30,000
--      across completed orders.

SELECT
    c.segment,
    COUNT(o.order_id) AS total_orders,
    SUM(o.net_revenue) AS net_revenue
FROM customers AS c
INNER JOIN orders AS o
    ON o.customer_id = c.customer_id
WHERE o.status = 'Completed'
GROUP BY c.segment
HAVING SUM(o.net_revenue) > 30000
ORDER BY net_revenue DESC;


-- =============================================================================
-- PART B: COMMON TABLE EXPRESSIONS (CTEs) & COMPLEX LOGIC (Q6 - Q8)
-- =============================================================================

-- [Q6] Calculate total spend per customer and classify them into brackets.

WITH customer_spend AS (
    SELECT
        c.customer_id,
        c.customer_name,
        COALESCE(SUM(
            CASE
                WHEN o.status = 'Completed' THEN o.net_revenue
                ELSE 0
            END
        ), 0) AS total_spend
    FROM customers AS c
    LEFT JOIN orders AS o
        ON o.customer_id = c.customer_id
    GROUP BY
        c.customer_id,
        c.customer_name
),
spend_brackets AS (
    SELECT
        customer_id,
        customer_name,
        total_spend,
        CASE
            WHEN total_spend >= 20000 THEN 'High Spender'
            WHEN total_spend >= 5000 THEN 'Mid Spender'
            ELSE 'Low Spender'
        END AS spender_bracket
    FROM customer_spend
)
SELECT
    spender_bracket,
    COUNT(*) AS customer_count
FROM spend_brackets
GROUP BY spender_bracket
ORDER BY
    CASE spender_bracket
        WHEN 'High Spender' THEN 1
        WHEN 'Mid Spender' THEN 2
        WHEN 'Low Spender' THEN 3
    END;


-- [Q7] Customers with more than one completed order.

SELECT
    c.customer_id,
    c.customer_name,
    MIN(o.order_date) AS first_order_date,
    MAX(o.order_date) AS most_recent_order_date
FROM customers AS c
INNER JOIN orders AS o
    ON o.customer_id = c.customer_id
WHERE o.status = 'Completed'
GROUP BY
    c.customer_id,
    c.customer_name
HAVING COUNT(o.order_id) > 1
ORDER BY most_recent_order_date DESC;


-- [Q8] Recursive CTE date series from 2024-01-01 through 2024-01-10,
--      including days with zero orders.

WITH RECURSIVE date_series AS (
    SELECT DATE('2024-01-01') AS calendar_date

    UNION ALL

    SELECT calendar_date + INTERVAL 1 DAY
    FROM date_series
    WHERE calendar_date < '2024-01-10'
)
SELECT
    ds.calendar_date,
    COUNT(o.order_id) AS order_count
FROM date_series AS ds
LEFT JOIN orders AS o
    ON DATE(o.order_date) = ds.calendar_date
GROUP BY ds.calendar_date
ORDER BY ds.calendar_date;


-- =============================================================================
-- PART C: RANKING WINDOW FUNCTIONS (Q9 - Q12)
-- =============================================================================

-- [Q9] Highest-paid employee in each department.
--      No GROUP BY and no subquery filter.

WITH ranked_employees AS (
    SELECT
        e.employee_id,
        e.employee_name,
        e.department_id,
        d.department_name,
        e.salary,
        DENSE_RANK() OVER (
            PARTITION BY e.department_id
            ORDER BY e.salary DESC
        ) AS salary_rank
    FROM employees AS e
    INNER JOIN departments AS d
        ON d.department_id = e.department_id
)
SELECT
    employee_id,
    employee_name,
    department_name,
    salary
FROM ranked_employees
WHERE salary_rank = 1
ORDER BY department_name, employee_name;


-- [Q10] Deduplication simulation:
--       earliest order per customer using ROW_NUMBER().

WITH ranked_orders AS (
    SELECT
        o.*,
        ROW_NUMBER() OVER (
            PARTITION BY o.customer_id
            ORDER BY o.order_date ASC, o.order_id ASC
        ) AS order_rank
    FROM orders AS o
)
SELECT *
FROM ranked_orders
WHERE order_rank = 1
ORDER BY customer_id;


-- [Q11] Divide products into four equal price quartiles.

SELECT
    product_name,
    unit_price,
    NTILE(4) OVER (
        ORDER BY unit_price
    ) AS price_quartile
FROM products
ORDER BY unit_price, product_name;


-- [Q12] Rank products by unit price within category using RANK()
--       and DENSE_RANK().

SELECT
    p.product_name,
    c.category_name,
    p.unit_price,
    RANK() OVER (
        PARTITION BY p.category_id
        ORDER BY p.unit_price DESC
    ) AS price_rank,
    DENSE_RANK() OVER (
        PARTITION BY p.category_id
        ORDER BY p.unit_price DESC
    ) AS dense_price_rank
FROM products AS p
INNER JOIN categories AS c
    ON c.category_id = p.category_id
ORDER BY
    c.category_name,
    p.unit_price DESC,
    p.product_name;


-- =============================================================================
-- PART D: OFFSET FUNCTIONS: LAG & LEAD (Q13 - Q15)
-- =============================================================================

-- [Q13] Monthly net revenue, previous month's revenue, and MoM dollar growth.

WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(order_date, '%Y-%m-01') AS month_start,
        SUM(net_revenue) AS monthly_revenue
    FROM orders
    WHERE status = 'Completed'
    GROUP BY DATE_FORMAT(order_date, '%Y-%m-01')
),
revenue_with_lag AS (
    SELECT
        month_start,
        monthly_revenue,
        LAG(monthly_revenue) OVER (
            ORDER BY month_start
        ) AS previous_month_revenue
    FROM monthly_revenue
)
SELECT
    month_start,
    monthly_revenue,
    previous_month_revenue,
    monthly_revenue - previous_month_revenue AS mom_dollar_growth
FROM revenue_with_lag
ORDER BY month_start;


-- [Q14] For each customer's order, calculate days since previous order.

SELECT
    customer_id,
    order_id,
    order_date,
    DATEDIFF(
        order_date,
        LAG(order_date) OVER (
            PARTITION BY customer_id
            ORDER BY order_date, order_id
        )
    ) AS days_since_previous_order
FROM orders
ORDER BY customer_id, order_date, order_id;


-- [Q15] For each order, show the customer's next upcoming order date.

SELECT
    order_id,
    customer_id,
    order_date,
    LEAD(order_date) OVER (
        PARTITION BY customer_id
        ORDER BY order_date, order_id
    ) AS next_order_date
FROM orders
ORDER BY customer_id, order_date, order_id;


-- =============================================================================
-- PART E: AGGREGATE WINDOW FUNCTIONS & FRAMES (Q16 - Q20)
-- =============================================================================

-- [Q16] Running cumulative total of completed-order net revenue.

SELECT
    order_id,
    order_date,
    customer_id,
    net_revenue,
    SUM(net_revenue) OVER (
        ORDER BY order_date, order_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total_revenue
FROM orders
WHERE status = 'Completed'
ORDER BY order_date, order_id;


-- [Q17] Daily revenue and 3-day moving average.
--      The requested ROWS frame operates on rows, so first aggregate
--      revenue to one row per calendar day.

WITH daily_revenue AS (
    SELECT
        DATE(order_date) AS order_date,
        SUM(net_revenue) AS daily_revenue
    FROM orders
    WHERE status = 'Completed'
    GROUP BY DATE(order_date)
)
SELECT
    order_date,
    daily_revenue,
    AVG(daily_revenue) OVER (
        ORDER BY order_date
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS three_day_moving_average
FROM daily_revenue
ORDER BY order_date;


-- [Q18] Product revenue and percentage contribution to category revenue.

WITH product_revenue AS (
    SELECT
        p.product_id,
        p.product_name,
        p.category_id,
        c.category_name,
        SUM(oi.quantity * oi.unit_price) AS product_revenue
    FROM products AS p
    INNER JOIN categories AS c
        ON c.category_id = p.category_id
    INNER JOIN order_items AS oi
        ON oi.product_id = p.product_id
    INNER JOIN orders AS o
        ON o.order_id = oi.order_id
    WHERE o.status = 'Completed'
    GROUP BY
        p.product_id,
        p.product_name,
        p.category_id,
        c.category_name
)
SELECT
    product_name,
    category_name,
    product_revenue,
    ROUND(
        100.0 * product_revenue
        / SUM(product_revenue) OVER (
            PARTITION BY category_id
        ),
        2
    ) AS category_revenue_percentage
FROM product_revenue
ORDER BY category_name, product_revenue DESC;


-- [Q19] Difference between each employee's salary and the highest salary
--       in their department.

SELECT
    e.employee_name,
    d.department_name,
    e.salary,
    MAX(e.salary) OVER (
        PARTITION BY e.department_id
    ) AS department_highest_salary,
    e.salary - MAX(e.salary) OVER (
        PARTITION BY e.department_id
    ) AS difference_from_department_max
FROM employees AS e
INNER JOIN departments AS d
    ON d.department_id = e.department_id
ORDER BY
    d.department_name,
    e.salary DESC;


-- [Q20] Customers who placed completed orders in two consecutive months
--       during 2024.

WITH customer_months AS (
    SELECT DISTINCT
        customer_id,
        DATE_FORMAT(order_date, '%Y-%m-01') AS order_month
    FROM orders
    WHERE status = 'Completed'
      AND order_date >= '2024-01-01'
      AND order_date < '2025-01-01'
),
months_with_next AS (
    SELECT
        customer_id,
        order_month,
        LEAD(order_month) OVER (
            PARTITION BY customer_id
            ORDER BY order_month
        ) AS next_order_month
    FROM customer_months
)
SELECT DISTINCT
    cm.customer_id,
    c.customer_name
FROM months_with_next AS cm
INNER JOIN customers AS c
    ON c.customer_id = cm.customer_id
WHERE cm.next_order_month = cm.order_month + INTERVAL 1 MONTH
ORDER BY cm.customer_id;
```
