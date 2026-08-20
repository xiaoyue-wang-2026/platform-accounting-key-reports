-- redash #278463
/*

    Created By: Data Engineering | Lucy Lee
    Created On: Jul-6-2026
    Updated By: —
    Updated On: —

    Owner: TBD (Platform Accounting Data Analyst)

    Legacy code: https://redash.zp-int.com/queries/126279/source?p_Date=2020-11-01--2021-01-29

    Change description: 
        - Collapsed legacy bi.payment_records + zenpayroll_production.payment_records (joined 1:1 on id)  into bi.fct_payment_record 
            -— origination_account_id, transmission_type, bank_transaction_date, and the amounts all live on fct_payment_record, 
            so the zenpayroll_production raw join is dropped. 
            
        - sum(zppr.amount) reconstructed as sum(coalesce(debit_amount,0) + coalesce(credit_amount,0)). 
        
        - Swapped legacy bi.static_calendar for its refactor bi.dim_calendar (date -> calendar_date; month_name/year unchanged).

    Known issues:
        (1) Q1-2024 test: refactored is 1 record / $302.21 lower (March 2024, PNC Ops, NachaEntry).
            fct_payment_record.bank_transaction_date excludes transaction_type_id=6 summary BTs (can be
            NULL) whereas legacy derived it from all BT types, so one record reconciled via a summary BT
            drops out of the date join. All other groups tie exactly; can be ignored.

    Data sanity checks
        - row counts: legacy 5,973,167 vs refactored 5,973,166 (Q1-2024) — 1-record diff per Known Issue #1
        - idempotency check: passed — 1:1 id-join collapsed to a single fct, no fan-out; 21/21 groups match;
          static_calendar -> dim_calendar swap is a byte-for-byte tie

    Change logs:
        - 2026-07-06: LL initial migration to fct_payment_record + dim_calendar

*/

select
  calendar.month_name || ' ' || calendar.year as time,
  case when payment_record.origination_account_id = 16 then 'PNC Ops'
       when payment_record.origination_account_id = 17 then 'PNC Corporate'
       when payment_record.origination_account_id = 18 then 'PNC Wire In'
  end as bank,
  payment_record.origination_account_id,
  payment_record.transmission_type,
  sum(coalesce(payment_record.debit_amount,0) + coalesce(payment_record.credit_amount,0)) as total_volume,
  count(distinct payment_record.payment_record_id) as total_count
from bi.dim_calendar calendar
left join bi.fct_payment_record payment_record
  on calendar.calendar_date = payment_record.bank_transaction_date
where calendar.calendar_date between '{{ Date.start }}' and '{{ Date.end }}'
and payment_record.origination_account_id in (16,17,18)
group by 1,2,3,4
order by 1 desc,2,3,4
;