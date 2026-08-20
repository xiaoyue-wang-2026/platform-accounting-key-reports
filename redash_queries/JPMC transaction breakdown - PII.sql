-- redash #126406
-- Database: _EDW Raw

select 
sc.month_name || ' ' || sc.year as time,
-- date_trunc('month', sc.date - interval '2 days'),
-- date_trunc('month', sc.date - interval '34 days'),
-- sc.month_start,
-- sc.date,
-- sc.business_day,
-- sc_lagg.date as plus_1, 
-- sc_lagg.business_day as plus_1_,
-- sc_lead.date as minus_1, 
-- sc_lead.business_day as minus_1_,
-- date_trunc('month', nearest_business_day_gte),
case when zppr.origination_account_id = 3 then 'JPMC Ops'
when zppr.origination_account_id = 4 then 'JPMC Corporate'
when zppr.origination_account_id = 9 then 'JPMC Wire In'
when zppr.origination_account_id = 6 then 'JPMC Payroll Incoming Wires'
when zppr.origination_account_id=7 then 'JPMC Recovery'
when zppr.origination_account_id=12 then 'JPMC Flex Pay Repayment'
when zppr.origination_account_id=8 then 'JPMC Flex Pay'
end as bank,
zppr.origination_account_id,
-- TO_CHAR(payment_records.bank_transaction_date, 'MM/YYYY') as month_1,
-- date_trunc('week', payment_records.bank_transaction_date + interval '1 day' )::date as reconciled_week,
-- count(distinct case when zppr.payment_direction = 1 then payment_records.id end) as credits_count,
-- count(distinct case when zppr.payment_direction = 0 then payment_records.id end) as debits_count,
-- sum(case when zppr.payment_direction = 1 then zppr.amount end) as credits_volume,
-- sum(case when zppr.payment_direction = 0 then zppr.amount end) as debits_volume,
zppr.transmission_type,
sum(zppr.amount) as total_volume, 
count(distinct payment_records.id) as total_count
from bi.static_calendar sc
left join bi.payment_records payment_records on sc.date = payment_records.bank_transaction_date
left join zenpayroll_production.payment_records zppr on payment_records.id = zppr.id
-- left join bi.static_calendar sc_lagg on sc_lagg.date = sc.date + interval '1 day'
-- left join bi.static_calendar sc_lead on sc_lead.date = sc.date - interval '1 day'
-- -- looking at one state in particular 
-- inner join zenpayroll_production.companies c
--   on payment_records.on_behalf_of_type = 'Company' and payment_records.on_behalf_of_id = c.id
-- inner join zenpayroll_production.addresses a 
--   on a.id = c.filing_address_id and a.state = 'FL'
where 
-- payment_records.transaction_type not in (
-- 'Credit internal transfer contractor pay',
-- 'Credit internal transfer employee pay',
-- 'Credit internal transfer child support garnishment',
-- 'Credit internal transfer overpayment',
-- 'Credit internal transfer tax payment',
-- 'Credit internal transfer fees & penalty',
-- 'Credit internal transfer verification',
-- 'Credit internal transfer invoices',
-- 'Credit internal transfer others', 
-- 'Debit balance transfer',
-- -- added
-- 'Credit balance transfer',
-- 'Debit payroll fee',
-- 'Credit payroll fee',
-- 'Partner rev share payout',
-- 'Debit Partner Commission',
-- 'Debit HI Commission',
-- 'Debit bank verification',
-- 'Wire payment fee',
-- 'Credit test transaction',
-- 'Credit internal error expense',
-- 'Credit bank verification',
-- 'Credit internal transfer verification'
-- ) 
sc.date between '{{ Date.start }}' and '{{ Date.end }}' 
and zppr.origination_account_id in (3,4,6,7,8,9,12) 
-- and date_trunc('month',sc.date + interval '1 day') <  date_trunc('month',convert_timezone('America/Los_Angeles', current_date))
-- reconciliations timing logic
-- and (
--     (sc.date = convert_timezone('America/Los_Angeles', current_date) and sc_lagg.business_day = 'f' and sc.business_day = 't'
--     and date_trunc('month', sc.date - interval '34 days') < date_trunc('month', convert_timezone('America/Los_Angeles', current_date)))
--     -- or (sc.business_day = 'f' and sc_lead.business_day = 't' and sc_lead.date + interval '1 day' < convert_timezone('America/Los_Angeles', current_date))
--     -- or (sc.business_day = 'f' and sc_lead.business_day = 'f' and sc_lead.date + interval '2 day' < convert_timezone('America/Los_Angeles', current_date))
    -- or  date_trunc('month',sc.date + interval '1 day') <  date_trunc('month',convert_timezone('America/Los_Angeles', current_date))
-- )
group by 1,2,3,4
order by 1 desc
