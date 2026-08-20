-- redash #131616
-- Database: _EDW Raw

-- Recovery Receivable & Transactional Loss w/180 Day Calculation - PII
-- "Automated Report"
--
-- Edit log:
-- 2025-11-24: KL adjusted pivot visualization for Snowflake
-- 2026-02-27: KL updated recovery_reserve_identified to include 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd'
--             ONLY when pi_age_in_days >= 90 (to match reserve criteria) in rr0, rr1, rr2 CTEs.
--             This aligns with JEs Report treatment. More info: https://gustohq.atlassian.net/browse/FTDS-823

with dccb0 as
(
select *
from bi.daily_customer_cash_balances_snapshot dccb
where snapshot_date = '{{Insert Date Lag 2 Period}}'
and '{{Lag 2 Period}}' between effective_from_date and effective_to_date
--and company_id = '7757616923743576x'
)
,
dccb1 as
(
select *
from bi.daily_customer_cash_balances_snapshot dccb
where snapshot_date = '{{Insert Date Lag 1 Period}}'
and '{{Lag 1 Period}}' between effective_from_date and effective_to_date
)
,
dccb2 as
(
select *
from bi.daily_customer_cash_balances_snapshot dccb
where snapshot_date = '{{Insert Date Current Period}}'
and '{{Current Period}}' between effective_from_date and effective_to_date
-- and bank_transaction_date = date_trunc('day', dateadd('day',-1, getdate())) -- should think about the best way to do this.
)
,
bdt0 as
(
SELECT company_id,
sum(bad_debt_amount)
loss_due_to_transfer
FROM bi.bad_debt_transfers_snapshot
where snapshot_date = '{{Insert Date Lag 2 Period}}'
and effective_date <= '{{Lag 2 Period}}'
and override_status = 'pending'
--and fiscal_year_written_off in ('FY23', 'FY24', 'FY25') -- these should be updated to parameters
and fiscal_year_written_off >= 'FY25'
group by 1
)
,
bdt1 as
(
SELECT company_id,
sum(bad_debt_amount)
loss_due_to_transfer
FROM bi.bad_debt_transfers_snapshot
where snapshot_date = '{{Insert Date Lag 1 Period}}'
and effective_date <= '{{Lag 1 Period}}'
and override_status = 'pending'
--and fiscal_year_written_off in ('FY23', 'FY24', 'FY25') -- these should be updated to parameters
and fiscal_year_written_off >= 'FY25'
group by 1
)
,
bdt2 as
(
SELECT company_id,
sum(bad_debt_amount)
loss_due_to_transfer
FROM bi.bad_debt_transfers_snapshot
where snapshot_date = '{{Insert Date Current Period}}'
and effective_date <= '{{Current Period}}'
and override_status = 'pending'
--nd fiscal_year_written_off in ('FY23', 'FY24', 'FY25') -- these should be updated to parameters
and fiscal_year_written_off >= 'FY25'
group by 1
)
,
rr0 as
(
select
company_id
, abs(sum(ifnull(balance,0))) recovery_identified
, abs(sum(case when aging_bucket = '> 180 days' then balance else 0 end)) as pis_older_than_180_days
, abs(sum(case when (accounting_pi_category = 'Fraud') then balance else 0 end)) fraud_pis
-- 2026-02-26: Updated to include 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd' (only if pi_age >= 90) to align with JEs Report
, ifnull(sum(case when (
    (accounting_status_mapping = 'RecoveryReceivable_>90d' 
     OR (accounting_status_mapping = 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd' AND pi_age_in_days >= 90))
    and accounting_pi_category <> 'Fraud'
) then ifnull(balance, 0) else 0 end), 0) as recovery_reserve_identified
from
(
select distinct rr.id_category_concat,
rr.event_id,
rr.company_id,
rr.event_type,
rr.transaction_category,
rr.pi_id,
rr.pi_status,
rr.pi_category,
rr.pi_age_in_days,
rr.accounting_to_reserve,
rr.accounting_status_mapping,
rr.accounting_pi_category,
rr.balance,
rr.current_balance,
case
    when rr.pi_age_in_days <=30 then '0 - 30 days'
    when rr.pi_age_in_days between 31 and 60 then '31 - 60 days'
    when rr.pi_age_in_days between 61 and 90 then '61 - 90 days'
    when rr.pi_age_in_days between 91 and 120 then '91 - 120 days'
    when rr.pi_age_in_days between 121 and 180 then '121 - 180 days'
    when rr.pi_age_in_days > 180 then '> 180 days'
    else null end as aging_bucket
from bi.recovery_receivable_snapshot rr

    where (bank_transaction_date = '{{Lag 2 Period}}'
    and snapshot_date = '{{Insert Date Lag 2 Period}}'
    and pi_status is not null
    and pi_status = 'recovered'
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    and pi_category <> 'micro variance' --exlcude all mircro variance
    --and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and current_balance >=0)

    or (bank_transaction_date = '{{Lag 2 Period}}'
    and snapshot_date = '{{Insert Date Lag 2 Period}}'
    and pi_status is not null
    and pi_status = 'recovered'
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    --and pi_category <> 'micro variance' --exlcude all mircro variance
    and pi_category is null
    --and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and current_balance >=0)

    or (bank_transaction_date = '{{Lag 2 Period}}'
    and snapshot_date = '{{Insert Date Lag 2 Period}}'
    and pi_status is not null
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    and pi_category <> 'micro variance'--exlcude all mircro variance
    --and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and pi_status <> 'recovered')

    or (bank_transaction_date = '{{Lag 2 Period}}'
    and snapshot_date = '{{Insert Date Lag 2 Period}}'
    and pi_status is not null
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    and pi_category is null
    -- and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and pi_status <> 'recovered')
)
group by 1
)
,
rr1 as
(
select
company_id
, abs(sum(ifnull(balance,0))) recovery_identified
, abs(sum(case when aging_bucket = '> 180 days' then balance else 0 end)) as pis_older_than_180_days
, abs(sum(case when (accounting_pi_category = 'Fraud') then balance else 0 end)) fraud_pis
-- 2026-02-26: Updated to include 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd' (only if pi_age >= 90) to align with JEs Report
, ifnull(sum(case when (
    (accounting_status_mapping = 'RecoveryReceivable_>90d' 
     OR (accounting_status_mapping = 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd' AND pi_age_in_days >= 90))
    and accounting_pi_category <> 'Fraud'
) then ifnull(balance, 0) else 0 end), 0) as recovery_reserve_identified
from
(
select distinct rr.id_category_concat,
rr.event_id,
rr.company_id,
rr.event_type,
rr.transaction_category,
rr.pi_id,
rr.pi_status,
rr.pi_category,
rr.pi_age_in_days,
rr.accounting_to_reserve,
rr.accounting_status_mapping,
rr.accounting_pi_category,
rr.balance,
rr.current_balance,
case
    when rr.pi_age_in_days <=30 then '0 - 30 days'
    when rr.pi_age_in_days between 31 and 60 then '31 - 60 days'
    when rr.pi_age_in_days between 61 and 90 then '61 - 90 days'
    when rr.pi_age_in_days between 91 and 120 then '91 - 120 days'
    when rr.pi_age_in_days between 121 and 180 then '121 - 180 days'
    when rr.pi_age_in_days > 180 then '> 180 days'
    else null end as aging_bucket
from bi.recovery_receivable_snapshot rr

    where (bank_transaction_date = '{{Lag 1 Period}}'
    and snapshot_date = '{{Insert Date Lag 1 Period}}'
    and pi_status is not null
    and pi_status = 'recovered'
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    and pi_category <> 'micro variance' --exlcude all mircro variance
    --and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and current_balance >=0)

    or (bank_transaction_date = '{{Lag 1 Period}}'
    and snapshot_date = '{{Insert Date Lag 1 Period}}'
    and pi_status is not null
    and pi_status = 'recovered'
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    --and pi_category <> 'micro variance' --exlcude all mircro variance
    and pi_category is null
    --and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and current_balance >=0)

    or (bank_transaction_date = '{{Lag 1 Period}}'
    and snapshot_date = '{{Insert Date Lag 1 Period}}'
    and pi_status is not null
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    and pi_category <> 'micro variance'--exlcude all mircro variance
    --and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and pi_status <> 'recovered')

    or (bank_transaction_date = '{{Lag 1 Period}}'
    and snapshot_date = '{{Insert Date Lag 1 Period}}'
    and pi_status is not null
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    and pi_category is null
    -- and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and pi_status <> 'recovered')
)
group by 1
)
,
rr2 as
(
select
company_id
, abs(sum(ifnull(balance,0))) recovery_identified
, abs(sum(case when aging_bucket = '> 180 days' then balance else 0 end)) as pis_older_than_180_days
, abs(sum(case when (accounting_pi_category = 'Fraud') then balance else 0 end)) fraud_pis
-- 2026-02-26: Updated to include 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd' (only if pi_age >= 90) to align with JEs Report
, ifnull(sum(case when (
    (accounting_status_mapping = 'RecoveryReceivable_>90d' 
     OR (accounting_status_mapping = 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd' AND pi_age_in_days >= 90))
    and accounting_pi_category <> 'Fraud'
) then ifnull(balance, 0) else 0 end), 0) as recovery_reserve_identified
from
(
select distinct rr.id_category_concat,
rr.event_id,
rr.company_id,
rr.event_type,
rr.transaction_category,
rr.pi_id,
rr.pi_status,
rr.pi_category,
rr.pi_age_in_days,
rr.accounting_to_reserve,
rr.accounting_status_mapping,
rr.accounting_pi_category,
rr.balance,
rr.current_balance,
case
    when rr.pi_age_in_days <=30 then '0 - 30 days'
    when rr.pi_age_in_days between 31 and 60 then '31 - 60 days'
    when rr.pi_age_in_days between 61 and 90 then '61 - 90 days'
    when rr.pi_age_in_days between 91 and 120 then '91 - 120 days'
    when rr.pi_age_in_days between 121 and 180 then '121 - 180 days'
    when rr.pi_age_in_days > 180 then '> 180 days'
    else null end as aging_bucket
from bi.recovery_receivable_snapshot rr

    where (bank_transaction_date = '{{Current Period}}'
    and snapshot_date = '{{Insert Date Current Period}}'
    and pi_status is not null
    and pi_status = 'recovered'
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    and pi_category <> 'micro variance' --exlcude all mircro variance
    --and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and current_balance >=0)

    OR (bank_transaction_date = '{{Current Period}}'
    and snapshot_date = '{{Insert Date Current Period}}'
    and pi_status is not null
    and pi_status = 'recovered'
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    --and pi_category <> 'micro variance' --exlcude all mircro variance
    and pi_category is null
    --and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and current_balance >=0)

    OR (bank_transaction_date = '{{Current Period}}'
    and snapshot_date = '{{Insert Date Current Period}}'
    and pi_status is not null
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    and pi_category <> 'micro variance'--exlcude all mircro variance
    --and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and pi_status <> 'recovered')

    or (bank_transaction_date = '{{Current Period}}'
    and snapshot_date = '{{Insert Date Current Period}}'
    and pi_status is not null
    and company_id is not null
    and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
    and pi_category is null
    -- and pi_status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')
    and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    and pi_id not in (579085,623771,579082)
    and pi_status <> 'recovered')
)
group by 1
)
,
-- joins all of the date 1 ctes
final_report_date_0 as
(
select
  dccb0.company_id
, dccb0.balance
, ifnull(bdt0.loss_due_to_transfer, 0) loss_due_to_transfer
, ifnull(rr0.pis_older_than_180_days, 0) pis_older_than_180_days
, dccb0.balance + ifnull(bdt0.loss_due_to_transfer, 0) + ifnull(rr0.pis_older_than_180_days, 0) as adjusted_cash
, ifnull(rr0.recovery_identified, 0) recovery_identified
, case when (adjusted_cash + ifnull(rr0.recovery_identified, 0)) <0 then -1*(adjusted_cash + ifnull(rr0.recovery_identified, 0)) else 0 end as recovery_manual
, -1*(ifnull(rr0.pis_older_than_180_days, 0)) as pis_older_than_180_days_negative
, pis_older_than_180_days_negative + ifnull(rr0.recovery_identified, 0) + ifnull(recovery_manual,0) recovery_total
, ifnull(rr0.recovery_reserve_identified, 0) recovery_reserve_identified
, ifnull(rr0.fraud_pis, 0) fraud_pis
, -1*(ifnull(rr0.pis_older_than_180_days, 0)) as pis_older_than_180_days_accounting_charge_off
, adjusted_cash + recovery_total as liability_by_customer
from dccb0
left join bdt0 on dccb0.company_id = bdt0.company_id
left join rr0 on dccb0.company_id = rr0.company_id
)
,
-- joins all of the date 1 ctes
final_report_date_1 as
(
select
  dccb1.company_id
, dccb1.balance
, ifnull(bdt1.loss_due_to_transfer, 0) loss_due_to_transfer
, ifnull(rr1.pis_older_than_180_days, 0) pis_older_than_180_days
, dccb1.balance + ifnull(bdt1.loss_due_to_transfer, 0) + ifnull(rr1.pis_older_than_180_days, 0) as adjusted_cash
, ifnull(rr1.recovery_identified, 0) recovery_identified
, case when (adjusted_cash + ifnull(rr1.recovery_identified, 0)) <0 then -1*(adjusted_cash + ifnull(rr1.recovery_identified, 0)) else 0 end as recovery_manual
, -1*(ifnull(rr1.pis_older_than_180_days, 0)) as pis_older_than_180_days_negative
, pis_older_than_180_days_negative + ifnull(rr1.recovery_identified, 0) + ifnull(recovery_manual,0) recovery_total
, ifnull(rr1.recovery_reserve_identified, 0) recovery_reserve_identified
, ifnull(rr1.fraud_pis, 0) fraud_pis
, -1*(ifnull(rr1.pis_older_than_180_days, 0)) as pis_older_than_180_days_accounting_charge_off
, adjusted_cash + recovery_total as liability_by_customer
from dccb1
left join bdt1 on dccb1.company_id = bdt1.company_id
left join rr1 on dccb1.company_id = rr1.company_id
)
,
-- joins all of the date 2 ctes
final_report_date_2 as
(
select
  dccb2.company_id
, dccb2.balance
, ifnull(bdt2.loss_due_to_transfer, 0) loss_due_to_transfer
, ifnull(rr2.pis_older_than_180_days, 0) pis_older_than_180_days
, dccb2.balance + ifnull(bdt2.loss_due_to_transfer, 0) + ifnull(rr2.pis_older_than_180_days, 0) as adjusted_cash
, ifnull(rr2.recovery_identified, 0) recovery_identified
, case when (adjusted_cash + ifnull(rr2.recovery_identified, 0)) <0 then -1*(adjusted_cash + ifnull(rr2.recovery_identified, 0)) else 0 end as recovery_manual
, -1*(ifnull(rr2.pis_older_than_180_days, 0)) as pis_older_than_180_days_negative
, pis_older_than_180_days_negative + ifnull(rr2.recovery_identified, 0) + ifnull(recovery_manual,0) recovery_total
, ifnull(rr2.recovery_reserve_identified, 0) recovery_reserve_identified
, ifnull(rr2.fraud_pis, 0) fraud_pis
, -1*(ifnull(rr2.pis_older_than_180_days, 0)) as pis_older_than_180_days_accounting_charge_off
, adjusted_cash + recovery_total as liability_by_customer
from dccb2
left join bdt2 on dccb2.company_id = bdt2.company_id
left join rr2 on dccb2.company_id = rr2.company_id
)
-- performs final join and gathers all necessary base columns
,
final_join as
(
select
  frd2.company_id||'x' as company_id,
  frd2.balance,
  frd2.loss_due_to_transfer,
  frd2.pis_older_than_180_days,
  frd2.recovery_identified,
  frd2.pis_older_than_180_days_negative,
  abs(frd2.recovery_reserve_identified) as recovery_reserve_identified,
  frd2.fraud_pis,
  frd2.pis_older_than_180_days_accounting_charge_off,

  -- Pre-calculate values from original logic that are needed for new calculations
  case when ifnull(frd2.recovery_manual::float, 0) <> 0 and  ifnull(frd1.recovery_manual::float, 0) = ifnull(frd2.recovery_manual::float,0) then ifnull(frd2.recovery_manual::float, 0) else 0 end as recovery_reserve_manual,
  -1*(case when ifnull(frd2.recovery_manual::float, 0) <> 0 and  ifnull(frd0.recovery_manual::float, 0) = ifnull(frd2.recovery_manual::float,0) then ifnull(frd2.recovery_manual::float, 0) else 0 end) as recovery_reserve_manual_180_days,

  -- 1. Calculate new intermediate value: Cash before Accounting Charge off
  (frd2.balance + frd2.loss_due_to_transfer) as cash_before_accounting_charge_off

from final_report_date_2 frd2
left join final_report_date_1 frd1 on frd2.company_id = frd1.company_id
left join final_report_date_0 frd0 on frd2.company_id = frd0.company_id
)
,
-- Step 1 of calculations, handling first-level dependencies
calculations_step_1 as
(
select
    *,
    -- 2. Calculate recovery_reserve_manual_180_days_negative
    -1 * recovery_reserve_manual_180_days as recovery_reserve_manual_180_days_negative,
    -- 4. Calculate new recovery_manual
    case when (cash_before_accounting_charge_off + recovery_identified) < 0 then -1 * (cash_before_accounting_charge_off + recovery_identified) else 0 end as recovery_manual
from final_join
where balance <> 0
or loss_due_to_transfer <> 0
or pis_older_than_180_days <> 0
or recovery_identified <> 0
or pis_older_than_180_days_negative <> 0
or recovery_reserve_identified <> 0
or fraud_pis <> 0
or pis_older_than_180_days_accounting_charge_off <> 0
or recovery_reserve_manual <> 0
or recovery_reserve_manual_180_days <> 0
or cash_before_accounting_charge_off <> 0
or recovery_reserve_manual_180_days_negative <> 0
or recovery_manual <> 0
)
,
-- Step 2 of calculations, handling second-level dependencies
calculations_step_2 as
(
select
    *,
    -- 3. Calculate corrected adjusted_cash
    (cash_before_accounting_charge_off + pis_older_than_180_days + recovery_reserve_manual_180_days_negative) as adjusted_cash
from calculations_step_1
)
-- Final SELECT with all the new calculations applied in order
select
  company_id,
  balance,
  loss_due_to_transfer,
  cash_before_accounting_charge_off,
  pis_older_than_180_days,
  recovery_reserve_manual_180_days_negative,
  adjusted_cash,
  recovery_identified,
  recovery_manual,
  pis_older_than_180_days_negative,
  recovery_reserve_manual_180_days,
  (recovery_identified + recovery_manual + pis_older_than_180_days_negative + recovery_reserve_manual_180_days) as recovery_total,
  recovery_reserve_identified,
  fraud_pis,
  pis_older_than_180_days_accounting_charge_off,
  recovery_reserve_manual,
  recovery_reserve_manual_180_days as recovery_reserve_manual_180_days_for_reserve,
  -- The 'reserve_total' calculation, with components in the requested order.
  recovery_reserve_identified + fraud_pis + pis_older_than_180_days_accounting_charge_off + recovery_reserve_manual + recovery_reserve_manual_180_days as reserve_total,
  -- 7. Calculate new liability_by_customer
  (adjusted_cash + (recovery_identified + recovery_manual + pis_older_than_180_days_negative + recovery_reserve_manual_180_days)) as liability_by_customer
from calculations_step_2

