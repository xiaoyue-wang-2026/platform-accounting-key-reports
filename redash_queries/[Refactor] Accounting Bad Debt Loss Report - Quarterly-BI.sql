-- redash #235769
/*

    Creator: Data Engineering | Lucy Lee
    Created: May-29-2026
    Owner: TBD (Platform Accounting Data Analyst)

    Legacy code: https://redash.zp-int.com/queries/136980/source?p_effective_writeoff_date=2025-09-30 

    Change description: 
    
    1. Replaced bi.bad_debts_for_large_transfer with bi.fct_bad_debt_transfer.
        
        The refactor model pre-applies all legacy WHERE filters 
        (non-zero amount, non-Invoices transaction_category, test company exclusion via gusto_test_customers seed, non-rejected override_status) 
        — no additional filter replication needed. Fiscal year and effective date filters updated to refactor column names.
        
    2. New grain from fct_bad_debt_transfer
    
        One bad debt can have multiple approval statuses. Hence, added approval_id.

    Data sanity checks
        - row counts: passed
        - idempotency check on bad_debt_amount: passed

*/

SELECT 
    fct_bad_debt_transfer.bad_debt_id,
    fct_bad_debt_transfer.loss_identification_date,
    fct_bad_debt_transfer.loss_event_fiscal_year as year_loss_event_occurred,
    fct_bad_debt_transfer.effective_date,
    fct_bad_debt_transfer.written_off_fiscal_year as fiscal_year_written_off,
    fct_bad_debt_transfer.transaction_category,
    fct_bad_debt_transfer.event_type,
    fct_bad_debt_transfer.event_date as event_day_or_formonth,
    fct_bad_debt_transfer.event_id as inv_or_event_id,
    replace(fct_bad_debt_transfer.event_id_transaction_category_concat, '-', 'x') as concat_id_category, -- refactor delimiter: -
    fct_bad_debt_transfer.zp_company_id as company_id,
    fct_bad_debt_transfer.zp_company_name as name,
    fct_bad_debt_transfer.bad_debt_amount,
    fct_bad_debt_transfer.bad_debt_reason as reason,
    fct_bad_debt_pii.notes,
    fct_bad_debt_transfer.bad_debt_approval_create_ts::date as bad_debt_approval_created_at,
    fct_bad_debt_transfer.override_status,
    
    fct_bad_debt_transfer.approval_id, -- net new change
    fct_bad_debt_transfer.payment_event_balance_id, -- net new change
FROM bi.fct_bad_debt_transfer as fct_bad_debt_transfer
LEFT JOIN bi_pii.fct_bad_debt AS fct_bad_debt_pii
    ON fct_bad_debt_transfer.bad_debt_id = fct_bad_debt_pii.bad_debt_id
WHERE fct_bad_debt_transfer.written_off_fiscal_year >= 'FY25'  -- incl FY26
AND fct_bad_debt_transfer.effective_date <= '{{effective_writeoff_date}}'
;