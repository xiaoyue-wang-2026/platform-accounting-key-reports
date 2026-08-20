-- redash #11570
-- Database: _EDW PII

select
bi.bank_account,
bt.origination_account_id,
bi.payment_method,
bt.id as panda_bank_transaction_id,
bi.type_description,
bi.date,
bi.debit_amount,
bi.credit_amount,
bi.signed_amount,
bt.bank_reference,
bt.customer_reference,
bt.type_code as bai_type_code,
bt.description

from zenpayroll_production.bank_transactions as bt
inner join bi.bank_transactions as bi on bt.id = bi.id

where 
bi.bank_account in ({{ bank_account_name }}) 
and bt.origination_account_id in ({{ origination_account_id }})
and bi.date >= '{{ start_date }}'
and bi.date <= '{{ end_date }}'

order by bi.bank_account asc, date asc, bt.bank_reference asc

