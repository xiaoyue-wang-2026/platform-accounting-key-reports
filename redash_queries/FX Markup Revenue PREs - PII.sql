-- redash #277886
/*

    Creator: Data Engineering | Lucy Lee
    Created: Jul-6-2026
    Owner: Xiaoyue Wang

    Legacy code: https://redash.zp-int.com/queries/72394/source?p_reporting_end_date=2025-10-31&p_reporting_start_date=2012-01-01#138125

    Change description: 
        
        - Replaced legacy bi.payment_records and zenpayroll_production_no_pii.payment_record_entries 
        with bi.fct_payment_record and bi.fct_payment_record_entry, 
        dropping the zenpayroll_production_no_pii source dependency entirely 
        
        — event_id is now available directly on fct_payment_record_entry,
        which was the only reason the query reached into the ZP table.
        
        - bi.international_contractor_payments has no refactor mapping yet and is left unchanged.

    Data sanity checks
        - row counts: passed
        - idempotency check: passed (2025-10-31 and 2026-06-30)

*/

with fx_markup_prs as (
    select
        fct_payment_record.on_behalf_of_id || 'x' as pr_comp_id,
        fct_payment_record_entry.event_id as contractor_payment_id,
        fct_payment_record.bank_transaction_date as reporting_date,
        sum(fct_payment_record_entry.payment_record_entry_signed_amount) as markup_amount
    from bi.fct_payment_record as fct_payment_record
    left join bi.fct_payment_record_entry as fct_payment_record_entry
        on fct_payment_record.payment_record_id = fct_payment_record_entry.payment_record_id
    where fct_payment_record.reconciled_flag = true
        and fct_payment_record_entry.transaction_category = 'FX Revenue'
        and fct_payment_record.bank_transaction_date between '{{ reporting_start_date }}' and '{{ reporting_end_date }}'
    group by 1, 2, 3
)

select
    fmp.pr_comp_id,
    fmp.contractor_payment_id,
    fmp.reporting_date,
    icp.credit_currency,
    icp.usd_amount as contractor_payment_usd,
    fmp.markup_amount
from fx_markup_prs fmp
left join bi.international_contractor_payments icp on fmp.contractor_payment_id = icp.id