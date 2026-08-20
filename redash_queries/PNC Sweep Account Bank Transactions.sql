-- redash #49788
-- Database: _EDW Raw

SELECT
id,
date,
description,
sum( 
    case
        when transaction_type = 2 then amount
        when transaction_type = 4 then -amount
        else 0
    end
    ) as amount_cents,
 case
        when transaction_type = 2 then 'DEBIT'
        when transaction_type = 4 then 'CREDIT'
        else null
    end as debit_credit_accgt
FROM zenpayroll_production.bank_transactions -- change to zenpayroll_production.bank_transactions 
WHERE date between '{{period_start_date}}' and '{{period_end_date}}'
AND origination_account_id = 16
AND description LIKE '%SWEEP%1077770497%'
GROUP BY 1,2,3,5
ORDER BY id, date

/*SELECT*
FROM bi.bank_transactions
WHERE id = 21249581
*/
