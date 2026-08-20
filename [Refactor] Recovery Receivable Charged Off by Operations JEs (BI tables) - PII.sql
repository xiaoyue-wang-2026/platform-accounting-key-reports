-- redash #228922
-- Database: _EDW Raw

/*

    Created By: Data Engineering | Lucy Lee
    Created On: May-27-2026
    Updated By: Data Engineering | Lucy Lee
    Updated On: July-2-2026 > Known Issue #1
    
    Owner: TBD (Platform Accounting Data Analyst)

    Legacy code: https://redash.zp-int.com/queries/127731

    Change description: Replaced bi.bad_debt_transfers_snapshot with bi.fct_bad_debt_transfer_history (SCD2 history table). 
                        Point-in-time filter snapshot_date = date replaced with SCD2 equivalent:
                        history_effective_from_ts <= date AND history_effective_to_ts > date.
                        
                        *** Callout 1: bad_debt_id = 984705
                        The updated_category Credit/Product split may differ from the legacy 
                        because the refactored credit delinquency table derives `debit_event_type` from the `platform_accounting_transaction_type_mapping` seed 
                        rather than the legacy inline CASE logic. 
                        
                        Any transaction type not covered by the seed will fail to join, causing those rows to default to **Product** regardless of their actual credit loss status.
                        
    Known issues:
        (1) The bad debt amount shift between Credit <> Product: the new data mart has the updated mapping based on `debit_event`. As long as the pivot total is matching, this can be ignored. 
            BD Write Off Months: 2024-07, 2025-02, 2025-08, 2026-04
                        
                        
    Data sanity checks
        - row counts: passed
        - idempotency check: passed
        
    Change logs:
        - 2025-05-28: KL updated from PII Safe to Raw per Zhe He's guidance as long as there are any financial data mismatches between EDW Raw and EDW PII Safe
        - 2025-11-24: KL updated pivots for Snowflake
        - 2026-02-05: KL added "Summary by Category + FY" pivot visualization per Platform Accounting (Faye Culpa) request.

*/

with

    fct_bad_debt_transfer_history_snapshot as ( -- bad_debt_transfer snapshot
        
        select *
        from bi.fct_bad_debt_transfer_history
        where history_effective_from_ts <= '{{Insert Date}}'
            and history_effective_to_ts > '{{Insert Date}}'
            
    ),
    
    fct_bad_debt_history_snapshot as ( -- bad_debt_transfer.notes (PII sensitive) snapshot
    
        select *
        from bi_pii.fct_bad_debt_history
        where history_effective_from_ts <= '{{Insert Date}}'
            and 
                (
                    case 
                        when '{{Insert Date}}' > '2026-05-28' -- refactor snapshot go live date 
                            then fct_bad_debt_history.history_effective_to_ts > '{{Insert Date}}'
                        else 1 = 1 
                    end
                )
        
    ),
    
    bd as ( -- join bad_debt_transfer snapshot datasets
        
        select
            fct_bad_debt_transfer_history_snapshot.bad_debt_id,
            fct_bad_debt_transfer_history_snapshot.loss_identification_date,
            fct_bad_debt_transfer_history_snapshot.effective_date,
            fct_bad_debt_transfer_history_snapshot.transaction_category,
            fct_bad_debt_transfer_history_snapshot.event_type,
            fct_bad_debt_transfer_history_snapshot.zp_company_name,
            fct_bad_debt_transfer_history_snapshot.bad_debt_amount,
            fct_bad_debt_transfer_history_snapshot.bad_debt_reason,
            fct_bad_debt_history_snapshot.notes,
            fct_bad_debt_transfer_history_snapshot.override_status,
            fct_bad_debt_transfer_history_snapshot.payment_event_balance_id,
            fct_bad_debt_transfer_history_snapshot.payment_event_balance_amount,
            fct_bad_debt_transfer_history_snapshot.loss_event_fiscal_year,
            fct_bad_debt_transfer_history_snapshot.written_off_fiscal_year,
            fct_bad_debt_transfer_history_snapshot.event_date,
            fct_bad_debt_transfer_history_snapshot.event_id,
            fct_bad_debt_transfer_history_snapshot.event_id_transaction_category_concat,
            fct_bad_debt_transfer_history_snapshot.zp_company_id,
            fct_bad_debt_transfer_history_snapshot.bad_debt_approval_create_ts
        from fct_bad_debt_transfer_history_snapshot
        left join fct_bad_debt_history_snapshot
            on fct_bad_debt_transfer_history_snapshot.bad_debt_id = fct_bad_debt_history_snapshot.bad_debt_id
        -- removed: DISTINCT — SCD2 point-in-time filter guarantees at most one row per surrogate key
        where fct_bad_debt_transfer_history_snapshot.written_off_fiscal_year >= 'FY25'
        and fct_bad_debt_transfer_history_snapshot.effective_date <= '{{End of Period}}'
    
    ),
    
    pi_with_txn_cat as ( -- pull payment investigations and its transaction category 
        select
            fct_payment_investigation.payment_investigation_id,
            fct_payment_investigation.event_type,
            fct_payment_investigation.event_id,
            fct_payment_event_balance.transaction_category
        from bi.fct_payment_investigation as fct_payment_investigation
        left join bi_dbt.base_zenpayroll_payment_event_balance_investigations as base_zenpayroll_payment_event_balance_investigations
            on fct_payment_investigation.payment_investigation_id = base_zenpayroll_payment_event_balance_investigations.payment_investigation_id
        left join bi.fct_payment_event_balance as fct_payment_event_balance
            on base_zenpayroll_payment_event_balance_investigations.payment_event_balance_id = fct_payment_event_balance.payment_event_balance_id
    )

select distinct
    bd.bad_debt_id,
    bd.loss_identification_date,
    bd.effective_date,
    bd.transaction_category,
    bd.event_type,
    bd.zp_company_name,
    bd.bad_debt_amount,
    bd.bad_debt_reason,
    bd.notes,
    bd.override_status,
    bd.payment_event_balance_id,
    bd.payment_event_balance_amount,
    bd.loss_event_fiscal_year,
    bd.written_off_fiscal_year,
    bd.event_date,
    bd.event_id::varchar || 'x' as inv_or_event_id,
    replace(bd.event_id_transaction_category_concat, '-', 'x') as id_category_concat,
    bd.zp_company_id::varchar || 'x' as company_id,
    bd.bad_debt_approval_create_ts,
    case
        when bd.bad_debt_reason in ('Fraud loss', 'ATO concession') then 'Fraud'
        when bd.bad_debt_reason = 'Gusto Embedded Payroll (GEP) invoice' then 'GEP - Credit Invoiced'
        when bd.bad_debt_reason not in ('Fraud loss', 'ATO concession') and fct_recovery_receivable_credit_delinquency.credit_loss_flag = true then 'Credit'
        when bd.bad_debt_reason not in ('Fraud loss', 'ATO concession') and fct_recovery_receivable_credit_delinquency.credit_loss_flag = false then 'Product'
        when bd.bad_debt_reason not in ('Fraud loss', 'ATO concession') and fct_recovery_receivable_credit_delinquency.credit_loss_flag = null then 'Product'
        else 'Product'
    end as updated_category,
    extract(year from bd.effective_date) || '-' || extract(month from bd.effective_date) as bd_write_off_month_year,
    case
        when pi_with_txn_cat.payment_investigation_id::varchar is null then 'No PI'
        else pi_with_txn_cat.payment_investigation_id::varchar
    end as payment_investigation_id
from bd
left join bi.fct_recovery_receivable_credit_delinquency as fct_recovery_receivable_credit_delinquency
    on replace(bd.event_id_transaction_category_concat, '-', 'x') = replace(fct_recovery_receivable_credit_delinquency.event_id_debit_event_type_concat, '-', 'x')
left join pi_with_txn_cat as pi_with_txn_cat
    on bd.event_id = pi_with_txn_cat.event_id
    and bd.event_type = pi_with_txn_cat.event_type
    and bd.transaction_category = pi_with_txn_cat.transaction_category
;
