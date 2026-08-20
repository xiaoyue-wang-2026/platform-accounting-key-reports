-- redash #278603
/*

    Created By: Data Engineering | Lucy Lee
    Created On: Jul-6-2026
    Updated By: Data Engineering | Lucy Lee
    Updated On: Aug-17-2026 > Owner change

    Owner: Xiaoyue Wang

    Legacy code: https://redash.zp-int.com/queries/126293/source?p_Date=2020-11-01--2021-01-29

    Change description: 
    
        - Collapsed legacy bi.payment_records + zenpayroll_production.payment_records (joined 1:1 on id) into bi.fct_payment_record 
            -- origination_account_id, transmission_type, bank_transaction_date, and the amounts all live on fct_payment_record, 
            so the zenpayroll_production raw join is dropped. 
        
        - sum(zppr.amount) reconstructed as sum(coalesce(debit_amount,0) + coalesce(credit_amount,0)). 
        
        - Swapped legacy bi.static_calendar for its refactor bi.dim_calendar (date -> calendar_date; month_name/year unchanged).

    Data sanity checks
        - row counts: passed
        - idempotency check: passed 

*/

select
  calendar.month_name || ' ' || calendar.year as time,
  case when payment_record.origination_account_id = 1  then 'SVB Ops'
       when payment_record.origination_account_id = 2  then 'SVB Corporate'
       when payment_record.origination_account_id = 10 then 'SVB Wire In'
       when payment_record.origination_account_id = 5  then 'SVB Health Insurance'
  end as bank,
  payment_record.origination_account_id,
  payment_record.transmission_type,
  sum(coalesce(payment_record.debit_amount,0) + coalesce(payment_record.credit_amount,0)) as total_volume,
  count(distinct payment_record.payment_record_id) as total_count
from bi.dim_calendar calendar
left join bi.fct_payment_record payment_record
  on calendar.calendar_date = payment_record.bank_transaction_date
where calendar.calendar_date between '{{ Date.start }}' and '{{ Date.end }}'
and payment_record.origination_account_id in (1,2,5,10)
group by 1,2,3,4
order by 1 desc
;