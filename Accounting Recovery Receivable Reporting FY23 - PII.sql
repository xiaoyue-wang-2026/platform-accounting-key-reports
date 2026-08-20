-- redash #127843
-- Database: _EDW Raw

with
neb as (
    select
        pre.event_id,
        pre.on_behalf_of_id,
        pre.event_type,
        pre.transaction_category,
        sum(
          case
            when pre.payment_direction = 0 and pr.bank_transaction_date <= '{{period_end_date}}' then pre.amount
            when pre.payment_direction = 1 and pr.bank_transaction_date <= '{{period_end_date}}' then -(pre.amount)
            else 0
          end
        ) as peb_balance_amount,
        sum(
          case
            when pre.payment_direction = 0 then pre.amount
            when pre.payment_direction = 1 then -(pre.amount)
            else 0
          end
        ) as current_balance_amount      
        
    from zenpayroll_production.payment_record_entries as pre
    inner join bi.payment_records as pr on pre.payment_record_id = pr.id      

    where pr.reconciled = true
    and pre.transaction_category not in ('Balance Transfer','Internal Transfer','Invoices')
    --and pr.bank_account in ('SVB operations', 'Chase operations','SVB wire_in','Chase wire_in','Chase recovery','Chase payroll_incoming_wires')
    and pr.bank_account not like '%corporate%' and pr.bank_account not like '%health_insurance%' and pr.bank_account not like '%flex_pay%' -- updated Jan-2021 to include new PNC bank accounts
    and pre.event_id is not null

       
        group by 1, 2,3,4      
        
        having sum(
         case
            when pre.payment_direction = 0 and pr.bank_transaction_date <= '{{period_end_date}}' then pre.amount
            when pre.payment_direction = 1 and pr.bank_transaction_date <= '{{period_end_date}}' then -(pre.amount)
            else 0
         end ) < 0 ), 
         
pi_status as (
    select
            pi.id as pi_id,
            pi.status,
            pi.company_id,
            bipi.event_id,
            bipi.event_type,
            bipi.category,
            bipi.created_at,
            round(datediff('day', bipi.created_at, '{{period_end_date}}'),0) as pi_age,
            peb.transaction_category,
            pi.created_at as pi_creation_date

    from zenpayroll_production.payment_investigations as pi
        inner join bi.payment_investigations as bipi on bipi.id = pi.id
        inner join zenpayroll_production.payment_event_balance_investigations as pebi on pi.id = pebi.payment_investigation_id
        inner join zenpayroll_production.payment_event_balances as peb on peb.id = pebi.payment_event_balance_id

)


    select distinct
    neb.event_id||'x' as event_id,
    neb.on_behalf_of_id||'x' as company_id,
    neb.event_type,
    neb.transaction_category,
    pi.pi_id,
    pi.status,
    pi.category as pi_category,
    pi.pi_age as pi_age_in_days,
    case 
        when pi_age >= 90 then 'y'
        when pi_age < 90 then 'n'
        else null end as accounting_to_reserve,
    case 
        when neb.current_balance_amount >=0 then 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd' -- negative event balances before period end, positive after period end
        when pi.status =  'awaiting_external_dependency' then 'NotRecovery_FalsePositive'  -- PIs that are not real loss (confirmed by Ops) but required eng to improve payment reporting design 
        when pi.status =  'false_positive' then 'NotRecovery_FalsePositive' --  PIs that are not real loss (confirmed by Ops) but required eng to improve payment reporting design 
        when pi.status =  'awaiting_bad_debt_approval' then 'NotRecovery_writtenoff_pendingcorptransfer' 
        when pi.status =  'awaiting_bad_debt_funds' then 'NotRecovery_writtenoff_pendingcorptransfer'
        when pi_id in (579085,623771,579082) then 'NotRecovery_FalsePositive'-- large historical PIs that are false positives after confirming with ops
        when pi.pi_age >= 90 then 'RecoveryReceivable_>90d'
        else 'RecoveryReceivable_<90d' end as accounting_status_mapping,
     case 
        when pi.category = 'expedited' then 'Credit'
        when pi.category = 'fraud' then 'Fraud'
        else 'Other' end as accounting_pi_category,
    neb.peb_balance_amount,
    neb.current_balance_amount,
    pi.pi_creation_date
    from neb
    left join pi_status as pi on   pi.event_id = neb.event_id
                                    and pi.transaction_category = neb.transaction_category
                                    and pi.event_type = neb.event_type 
    
                                    
    where 
    pi.status is not null 
    and neb.on_behalf_of_id is not null
    and neb.on_behalf_of_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
