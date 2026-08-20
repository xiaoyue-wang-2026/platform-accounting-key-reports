-- redash #125759
-- Database: _EDW Raw

-- https://gustohq.atlassian.net/browse/FTDS-512 -- surfaced during June 2025 close
-- If categories and transaction type are not needed, KL recommends using Platform Ops' report instead which compares reconciled Payment Records movement to BAI2: 
-- Payment Records Movement and Bank Balances by Account: https://redash.zp-int.com/queries/62603/source?p_PR%20Date%20Range=2025-06-01--2025-06-30#244388


-- Per Zhe on 2025-07-10, forked from her original: https://redash.zp-int.com/queries/71975/source?p_PR%20Date%20Range_end=2025-06-30&p_PR%20Date%20Range_start=2025-06-01
-- Updating report title from "YoY Funds Held By Customer - Movement by Payment Category" to "MoM - Movement by Payment Category" since the report is neither by customer nor YoY anymore

-- 7/10/25 changes:
-- [main update]: remove "and transaction_type = 'Interest Income'" filter at line 87, which is too restrictive as of FY25. confirmed that Gusto company ID is sufficient.
-- additional bank_account specificity e.g. Chase operations --> Chase operations-29 to avoid grouping Chase operations-3 and Chase operations-29 together
-- null handling and rounding to 2 decimal places for scalability
-- no change to exclude on_behalf_of_id (Company ID) which was already commented out in original report from 2023: https://redash.zp-int.com/queries/71975/source?p_PR%20Date%20Range_end=2025-06-30&p_PR%20Date%20Range_start=2025-06-01#133879
-- added brief explainations to each CTE


-- everything except for PNC Ops
select
bank_account,   
bank_account||'-'||origination_account_id as bank_account_name,
transaction_type,
payment_category,
--on_behalf_of_id,
round(sum(ifnull(credit_amount,0)),2) payout,
round(sum(ifnull(debit_amount,0)),2) payin,
round(sum(ifnull(signed_amount,0)),2) reconciled_payment_records
from bi.payment_records
where reconciled = true
and bank_account not like '%flex%'
and bank_account not like '%corp%'
and bank_account not like '%health%'
and bank_account <> 'PNC operations'
and id not in (225721474,
        232856644,
        222699167,
        232856635,
        231818189,
        231482946,
        231822150,
        230769077,
        227876433)
and bank_transaction_date between '{{PR Date Range_start}}' and '{{PR Date Range_end}}'
group by 1,2,3,4

UNION ALL

-- PNC Ops not tied to Gusto company ID, June 2025 = -$55,024,372.57
select
bank_account,   
bank_account||'-'||origination_account_id as bank_account_name,
transaction_type,
payment_category,
--on_behalf_of_id,
round(sum(ifnull(credit_amount,0)),2) payout,
round(sum(ifnull(debit_amount,0)),2) payin,
round(sum(ifnull(signed_amount,0)),2) reconciled_payment_records
from bi.payment_records
where reconciled = true
and bank_account not like '%flex%'
and bank_account not like '%corp%'
and bank_account not like '%health%'
and bank_account = 'PNC operations'
and on_behalf_of_id <> '7757616923492312'
and bank_transaction_date between '{{PR Date Range_start}}' and '{{PR Date Range_end}}'
group by 1,2,3,4

UNION ALL

-- PNC Ops, tied to Gusto company ID, June 2025 = +$95,847.55 Interest Income specifically (original logic)
-- PNC Ops, tied to Gusto company ID, June 2025 = +$55,028,935.57 Interest Income, balance transfer, treasury funding, wire sweep (relaxed/less specific logic)
select
bank_account,
bank_account||'-'||origination_account_id as bank_account_name,
transaction_type,
payment_category,
--on_behalf_of_id,
round(sum(ifnull(credit_amount,0)),2) payout,
round(sum(ifnull(debit_amount,0)),2) payin,
round(sum(ifnull(signed_amount,0)),2) reconciled_payment_records
from bi.payment_records
where reconciled = true
and bank_account not like '%flex%'
and bank_account not like '%corp%'
and bank_account not like '%health%'
and bank_account = 'PNC operations'
and on_behalf_of_id = '7757616923492312' -- Gusto/ZenPayroll company ID
-- and transaction_type = 'Interest Income' -- commenting out. this is too restrictive as of FY25. confirmed that Gusto company ID is sufficient.
-- and (transaction_type not in ('Interest Income') or transaction_type is null)
and bank_transaction_date between '{{PR Date Range_start}}' and '{{PR Date Range_end}}'
group by 1,2,3,4

UNION ALL

-- null output for June 2025 as no balance transfers for $20M occurred
select
bank_account,   
bank_account||'-'||origination_account_id as bank_account_name,
transaction_type,
payment_category ,
--on_behalf_of_id,
round(sum(ifnull(credit_amount,0)),2) payout,
round(sum(ifnull(debit_amount,0)),2) payin,
round(sum(ifnull(signed_amount,0)),2) reconciled_payment_records
from bi.payment_records
where reconciled = true
and bank_account not like '%flex%'
and bank_account not like '%corp%'
and bank_account not like '%health%'
and bank_account = 'PNC operations'
and on_behalf_of_id = '7757616923492312'
and transaction_type IN ('Credit balance transfer','Debit balance transfer')
and signed_amount between -20000000 and 20000000 -- KL commenting this out as a test on 7/10/25. decision: need to keep
and bank_transaction_date between '{{PR Date Range_start}}' and '{{PR Date Range_end}}'
-- excluding -$10M in securities investment transfers from Aug 2022 - Apr 2023
and id not in (
292269084, 
225721475, 
222703089,
231818190,
230769086,
232856637,
292269271,
227876460,
292268996,
234538572,
234538570,
225721472,
231818191,
230769099,
232856640,
227876464,
259706977)
group by 1,2,3,4

UNION ALL

-- this CTE specifically handles hard-coded BT IDs that were related to float transferred for Alert-1501 mitigation in Aug/Sept 2023
-- null output for June 2025
select
pr.bank_account,   
bank_account||'-'||pr.origination_account_id as bank_account_name,
pr.transaction_type,
pr.payment_category,
--on_behalf_of_id,
round(sum(ifnull(pr.credit_amount,0)),2) payout,
round(sum(ifnull(pr.debit_amount,0)),2) payin,
round(sum(ifnull(pr.signed_amount,0)),2) reconciled_payment_records
from bi.payment_records pr
left join zenpayroll_production.bank_transactions bt
on pr.bank_transaction_ids = bt.id
where pr.reconciled = true
and pr.bank_account = 'PNC operations'
and pr.on_behalf_of_id = '7757616923492312'
and pr.bank_transaction_date between '{{PR Date Range_start}}' and '{{PR Date Range_end}}'
and pr.bank_transaction_ids in (33504301,33504302,33606002) 
and pr.payment_category = 'Others'
--and bt.description like ('%WIRE%') description field removed from no_pii schema
group by 1,2,3,4

order by bank_account_name
