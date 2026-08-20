-- redash #120805
-- Database: _EDW Raw

with ORIGINATION as (
SELECT
'origination' as type
,pr.id as pr_id--as origination_pr_id
,pr.on_behalf_of_id || 'x' as on_behalf_of_id
,com.name as on_behalf_of_name
,cast(pr.date as date) as pr_date--as origination_pr_date
,pr.bank_transaction_date --as origination_bank_transaction_date
,pre.event_id
,pre.event_type
,pr.bank_account-- as origination_bank_account,
,pr.origination_account_id-- as origination_origination_account_id,
,pr.transmission_type-- as origination_transmission_type,
,SUM (pr.signed_amount) as amount -- as origination_amount
FROM zenpayroll_production.payment_record_entries AS pre
INNER JOIN bi.payment_records AS pr ON pre.payment_record_id = pr.id
LEFT JOIN bi.companies AS com ON com.id = pr.on_behalf_of_id 
WHERE 1=1
and pr.reconciled = true
and pr.on_behalf_of_id not in ('7757616923524413', '7757616923492312', '2')
and pre.transaction_category in ('Balance Transfer', 'Internal Transfer')
and pr.payment_record_entries_sum is not null
and pr.transmission_type = 'NachaEntry' -- this will filter for the originating account activity only
and pr.origination_account_id <> 29 --   and pre.event_id = 7757500969242326
and pr.bank_transaction_date = '{{ period_end_date }}'
group by all
)
, 

DESTINATION as (
SELECT
'destination' as type
,pr.id pr_id --as origination_pr_id
,pr.on_behalf_of_id || 'x' as on_behalf_of_id
,com.name as on_behalf_of_name
,cast(pr.date as date) as pr_date--as origination_pr_date
,pr.bank_transaction_date-- as destination_bank_transaction_date
,pre.event_id
,pre.event_type
,pr.bank_account --as destination_bank_account
,pr.origination_account_id --as destination_origination_account_id
,pr.transmission_type --as destination_transmission_type
,SUM (pr.signed_amount) as amount --as destination_amount
FROM zenpayroll_production.payment_record_entries AS pre
INNER JOIN bi.payment_records AS pr ON pre.payment_record_id = pr.id
LEFT JOIN bi.companies AS com ON com.id = pr.on_behalf_of_id 
WHERE 1=1
and pr.reconciled = true
and pr.on_behalf_of_id not in ('7757616923524413', '7757616923492312', '2')
and pre.transaction_category in ('Balance Transfer', 'Internal Transfer') --   and pr.bank_account in ('SVB operations', 'Chase operations','PNC operations')--Panda only originates internal transfers between our Operations accounts
and pr.payment_record_entries_sum is not null
and pr.transmission_type = 'ElectronicEntry' -- this will filter for the destination account activity only
and pr.origination_account_id <> 29 --   and pre.event_id = 7757500969242326
and pr.bank_transaction_date >= '{{ period_end_date }}'
group by all
)

select
o.on_behalf_of_id
,o.on_behalf_of_name
,o.event_id
,o.pr_date as origination_pr_date
,o.pr_id as origination_pr_id
,o.bank_transaction_date as origination_bank_transaction_date
,o.bank_account as origination_bank_account
,o.origination_account_id as origination_origination_account_id
,o.transmission_type as origination_transmission_type
,o.amount as origination_amount
,d.pr_date as destination_pr_date
,d.pr_id as destination_pr_id
,d.bank_transaction_date as destination_bank_transaction_date
,d.bank_account as destination_bank_account
,d.origination_account_id as destination_origination_account_id
,d.transmission_type as destination_transmission_type
,d.amount as destination_amount
,case when destination_bank_transaction_date is null then 'not_yet_settled'
    when destination_bank_transaction_date = '{{ period_end_date }}' then 'settled_on_period_end_date'
    when destination_bank_transaction_date > '{{ period_end_date }}' then 'settled_after_period_end_date'
    when destination_bank_transaction_date < '{{ period_end_date }}' then 'settled_before_period_end_date'
    end as settlement_timing
,coalesce(origination_amount, 0.0) + coalesce(destination_amount, 0.0) as event_balance
from origination o
left join destination d on o.event_id = d.event_id and o.event_type = d.event_type
    and o.amount = -1 * d.amount and d.pr_date >= dateadd('day',-2,'{{ period_end_date }}') --removes edge case #1, constant transfers
where 1=1
and (destination_bank_transaction_date > '{{ period_end_date }}' or destination_bank_transaction_date is null)
-- and destination_pr_id is not null --removes 22 edge cases below and in this query:  https://redash.zp-int.com/queries/122905/source?p_period_end_date=2025-05-30
--22 edge cases, ICP, untied payment_records does not tie to events, with nacha entries of ZP
-- https://gustohq.atlassian.net/browse/FDPP-303 for long term eng fix


