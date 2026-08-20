-- redash #120670
-- Database: _EDW Raw

  WITH cte AS (
        SELECT 
            abh.pr_on_behalf_of_id,
            event_id || 'x' || transaction_category AS concat,
            CASE 
                WHEN abh.bank_transaction_date < '2020-01-01'::date THEN bank_transaction_date::date
                ELSE abh.bank_transaction_date
            END AS bank_transaction_date,
            abh.investigation_status,
            abh.investigation_created_at::date AS investigation_date,
            abh.event_id as event_id, 
            SUM(abh.balance) AS balance
        FROM bi_reporting.accounting_balance_history abh
        WHERE abh.bank_transaction_date <= '{{ bank_transaction_date }}'
        GROUP BY 1, 2, 3, 4, 5, 6
    ),
    cte2 AS (
        SELECT 
            cte.concat AS uid,
            cte.pr_on_behalf_of_id,
              cte.event_id, 
            SUM(cte.balance) AS balance
        FROM cte 
        where event_id IS NULL
        GROUP BY 1, 2, 3
        HAVING SUM(cte.balance) < -0.01
    )
    SELECT 
        *
    FROM cte2
    -- where cte2.uid IS NOT NULL

