-- redash #42185
-- Database: _EDW BI

with cte as (
SELECT abh.pr_on_behalf_of_id 
    ,abh.on_behalf_of_name 
    ,CASE WHEN abh.bank_transaction_date < '2020-01-01'::date THEN '2020-01-01'::date
          ELSE abh.bank_transaction_date
          END bank_transaction_date
    ,abh.investigation_status
    ,abh.investigation_created_at::date investigation_date
    ,SUM(abh.balance) balance
    ,SUM(abh.balance) 
FROM bi_reporting.accounting_balance_history abh
WHERE abh.bank_transaction_date <= '{{ bank_transaction_date }}'
GROUP BY 1,2,3,4,5
)

, cte2 as(
select cte.pr_on_behalf_of_id, cte.on_behalf_of_name, sum(cte.balance) balance, sum(cte.balance) < 0.00 has_negative_balance
from cte 
group by 1,2
having (SUM(cte.balance) > 0.01 OR SUM(cte.balance) < -0.01)

)
select cte2.pr_on_behalf_of_id, cte2.on_behalf_of_name, cte2.balance
  from cte2
WHERE cte2.has_negative_balance = {{ has_negative_balance }}
ORDER BY 3 desc
