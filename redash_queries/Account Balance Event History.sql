-- redash #42184
-- Database: _EDW BI

select * 
from bi_reporting.accounting_balance_history
where pr_on_behalf_of_id = {{ company_id }}
  and bank_transaction_date <= '{{ bank_transaction_date }}'
order by bank_transaction_date desc
