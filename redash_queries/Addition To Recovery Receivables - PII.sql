-- redash #128016
-- Database: _EDW Raw

-- 11/03/2025 Migration to bi. table from ds. table
-- 11/03/2025 Normalize id_category_concat → concat ('-' → 'x')
-- 11/03/2025 Ensure event_id and company_id end with 'x'

WITH rr_prev AS (
  SELECT DISTINCT
    REPLACE(id_category_concat, '-', 'x') AS concat,
    *
  FROM bi.recovery_receivable_snapshot
  WHERE
    bank_transaction_date = '{{End of Previous Period}}'
    AND snapshot_date      = '{{Insert Date Previous Period}}'
    AND pi_status IS NOT NULL
    AND company_id IS NOT NULL
    AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880)
    AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    AND pi_id NOT IN (579085,623771,579082)
    AND (
         (pi_status = 'recovered' AND (pi_category <> 'micro variance' OR pi_category IS NULL) AND current_balance >= 0)
      OR (pi_status <> 'recovered' AND (pi_category <> 'micro variance' OR pi_category IS NULL))
    )
),
rr_curr AS (
  SELECT DISTINCT
    REPLACE(id_category_concat, '-', 'x') AS concat,
    *
  FROM bi.recovery_receivable_snapshot
  WHERE
    bank_transaction_date = '{{End of Current Period}}'
    AND snapshot_date      = '{{Insert Date Current Period}}'
    AND pi_status IS NOT NULL
    AND company_id IS NOT NULL
    AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880)
    AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    AND pi_id NOT IN (579085,623771,579082)
    AND (
         (pi_status = 'recovered' AND (pi_category <> 'micro variance' OR pi_category IS NULL) AND current_balance >= 0)
      OR (pi_status <> 'recovered' AND (pi_category <> 'micro variance' OR pi_category IS NULL))
    )
),
rr_curr_with_cat AS (
  SELECT DISTINCT
    c.concat,
    (c.event_id::varchar) || 'x' AS event_id,           -- event_id ends with 'x'
    (c.company_id::varchar) || 'x' AS company_id,        -- company_id ends with 'x'
    c.event_type,
    c.transaction_category,
    c.pi_id,
    c.pi_status,
    c.pi_category,
    c.pi_age_in_days,
    c.accounting_to_reserve,
    c.accounting_status_mapping,
    c.accounting_pi_category,
    c.balance,
    c.current_balance,
    CASE
      WHEN c.accounting_pi_category = 'Fraud' THEN 'Fraud'
      WHEN COALESCE(ct.is_credit_loss, FALSE)  THEN 'Credit'
      ELSE 'Product'
    END AS updated_category,
    CASE
      WHEN c.pi_age_in_days <= 30              THEN '0 - 30 days'
      WHEN c.pi_age_in_days BETWEEN 31 AND 60  THEN '31 - 60 days'
      WHEN c.pi_age_in_days BETWEEN 61 AND 90  THEN '61 - 90 days'
      WHEN c.pi_age_in_days BETWEEN 91 AND 120 THEN '91 - 120 days'
      WHEN c.pi_age_in_days BETWEEN 121 AND 180 THEN '121 - 180 days'
      WHEN c.pi_age_in_days > 180              THEN '> 180 days'
      ELSE NULL
    END AS aging_bucket
  FROM rr_curr c
  LEFT JOIN (
    SELECT DISTINCT
      REPLACE(id_event_concat, '-', 'x') AS concat,
      is_credit_loss
    FROM bi.recovery_receivable_credit_delinquencies_snapshot
    WHERE snapshot_date = '{{Insert Date Current Period}}'
  ) ct
    ON c.concat = ct.concat
)

SELECT
  cur.*,
  CASE WHEN prv.concat IS NULL THEN 'Yes' ELSE 'No' END                                        AS new_in_rr2,
  CASE WHEN prv.concat IS NULL THEN 'New in Current Period' ELSE prv.accounting_to_reserve END AS reserve_status_in_pp,
  CASE WHEN prv.concat IS NOT NULL THEN cur.balance - prv.balance ELSE 0 END                   AS balance_change,
  CASE WHEN 90 - cur.pi_age_in_days < 0 THEN 0 ELSE 90 - cur.pi_age_in_days END                AS days_until_90_days,
  CASE WHEN dateadd('day',
                    CASE WHEN 90 - cur.pi_age_in_days < 0 THEN 0 ELSE 90 - cur.pi_age_in_days END,
                    getdate()) <= DATE '2024-01-31'
       THEN 'Yes' ELSE 'No' END                                                                AS will_reach_90_days_aged_this_quarter
FROM rr_curr_with_cat cur
LEFT JOIN rr_prev prv
  ON cur.concat = prv.concat;






-- OG Query with DS Table
-- with rr1 as 
-- (
-- select distinct * 
-- from data_science.recovery_recievable_snapshot

--         where (bank_transaction_date = '{{End of Previous Period}}' 
--         and insert_dt = '{{Insert Date Previous Period}}'
--         and status is not null
--     and status = 'recovered'
--     and company_id is not null
--     and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
--     and pi_category <> 'micro variance' --exlcude all mircro variance
--     --and status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
--     and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
--     and pi_id not in (579085,623771,579082)
--     and current_balance >=0)
    
--     OR (bank_transaction_date = '{{End of Previous Period}}' 
--         and insert_dt = '{{Insert Date Previous Period}}'
--     and status is not null
--     and status = 'recovered'
--     and company_id is not null
--     and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
--     --and pi_category <> 'micro variance' --exlcude all mircro variance
--     and pi_category is null
--     --and status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
--     and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')    
--     and pi_id not in (579085,623771,579082)
--     and current_balance >=0)
    
--     OR (bank_transaction_date = '{{End of Previous Period}}' 
--         and insert_dt = '{{Insert Date Previous Period}}'
--     and status is not null 
--     and company_id is not null
--     and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
--     and pi_category <> 'micro variance'--exlcude all mircro variance
--     --and status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
--     and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
--     and pi_id not in (579085,623771,579082)
--     and status <> 'recovered')
    
--     or (bank_transaction_date = '{{End of Previous Period}}' 
--         and insert_dt = '{{Insert Date Previous Period}}'
--     and status is not null 
--     and company_id is not null
--     and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
--     and pi_category is null
--     -- and status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')
--     and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
--     and pi_id not in (579085,623771,579082)
--     and status <> 'recovered')
-- )
-- ,
-- rr2 as 
-- (
-- select distinct * 
-- from data_science.recovery_recievable_snapshot

--         where (bank_transaction_date = '{{End of Current Period}}' 
--         and insert_dt = '{{Insert Date Current Period}}'
--         and status is not null
--     and status = 'recovered'
--     and company_id is not null
--     and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
--     and pi_category <> 'micro variance' --exlcude all mircro variance
--     --and status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
--     and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
--     and pi_id not in (579085,623771,579082)
--     and current_balance >=0)
    
--     OR (bank_transaction_date = '{{End of Current Period}}' 
--         and insert_dt = '{{Insert Date Current Period}}'
--     and status is not null
--     and status = 'recovered'
--     and company_id is not null
--     and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
--     --and pi_category <> 'micro variance' --exlcude all mircro variance
--     and pi_category is null
--     --and status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
--     and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')    
--     and pi_id not in (579085,623771,579082)
--     and current_balance >=0)
    
--     OR (bank_transaction_date = '{{End of Current Period}}' 
--         and insert_dt = '{{Insert Date Current Period}}'
--     and status is not null 
--     and company_id is not null
--     and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
--     and pi_category <> 'micro variance'--exlcude all mircro variance
--     --and status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')-- exclude bad debt written off pending transfer and also false positives
--     and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
--     and pi_id not in (579085,623771,579082)
--     and status <> 'recovered')
    
--     or (bank_transaction_date = '{{End of Current Period}}' 
--         and insert_dt = '{{Insert Date Current Period}}'
--     and status is not null 
--     and company_id is not null
--     and company_id not in (7757616923492312, 7757616923524413, 2,7757616923899880) -- exclude corporate company IDs
--     and pi_category is null
--     -- and status not in ('awaiting_external_dependency','false_positive','awaiting_bad_debt_approval','awaiting_bad_debt_funds')
--     and accounting_status_mapping not in ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
--     and pi_id not in (579085,623771,579082)
--     and status <> 'recovered')
-- )
-- , 
-- rr2_and_categories as 
-- (
-- SELECT distinct
-- rr2.concat,
-- rr2.event_id,
-- rr2.company_id,
-- rr2.event_type,
-- rr2.transaction_category,
-- rr2.pi_id,
-- rr2.status,
-- rr2.pi_category,
-- rr2.pi_age_in_days,
-- rr2.accounting_to_reserve,
-- rr2.accounting_status_mapping,
-- rr2.accounting_pi_category,
-- rr2.balance,
-- rr2.current_balance,
-- -- rr2.pi_creation_date,
-- -- EXTRACT(YEAR FROM rr2.pi_creation_date) || '-' || EXTRACT(MONTH FROM rr2.pi_creation_date) AS pi_month_year,
-- case 
--     when rr2.accounting_pi_category = 'Fraud' then 'Fraud'
--     when rr2.accounting_pi_category <> 'Fraud' and credit_table.is_credit_loss = TRUE then 'Credit'
--     when rr2.accounting_pi_category <> 'Fraud' and credit_table.is_credit_loss = FALSE then 'Product'
--     when rr2.accounting_pi_category <> 'Fraud' and credit_table.is_credit_loss = null then 'Product'
--     else 'Product' end as updated_category,
-- case 
--     when rr2.pi_age_in_days <=30 then '0 - 30 days'
--     when rr2.pi_age_in_days between 31 and 60 then '31 - 60 days'
--     when rr2.pi_age_in_days between 61 and 90 then '61 - 90 days'
--     when rr2.pi_age_in_days between 91 and 120 then '91 - 120 days'
--     when rr2.pi_age_in_days between 121 and 180 then '121 - 180 days'
--     when rr2.pi_age_in_days > 180 then '> 180 days'
--     else null end as aging_bucket

-- FROM rr2 
-- LEFT JOIN (select distinct * from data_science.recovery_recievable_credit_delinquencies_snapshot where insert_dt = '{{Insert Date Current Period}}')
-- as credit_table on rr2.concat = credit_table.combo
-- )


-- select
-- rr2.*,
-- case when rr1.concat is null then 'Yes'::varchar
-- else 'No' end as new_in_rr2,
-- case when rr1.concat is null then 'New in Current Period'::varchar 
-- else rr1.accounting_to_reserve end as reserve_status_in_pp,
-- case when rr1.concat is not null then rr2.balance - rr1.balance else 0 end as balance_change,
-- case when 90 - rr2.pi_age_in_days < 0 then 0 else 90 - rr2.pi_age_in_days end as days_until_90_days,
-- case when dateadd('days', days_until_90_days, getdate()) <= '01-31-2024' then 'Yes' else 'No' end as will_reach_90_days_aged_this_quarter
-- from rr2_and_categories rr2
-- left join rr1 on rr2.concat = rr1.concat
-- -- where new_in_rr2 = 'Yes'
-- -- and rr2.updated_category = 'Product'
-- -- and rr2.accounting_to_reserve = 'y'

-- -- compare the october concat to the july concat 
-- -- see if anything new and see balance change 
-- -- then grab the PI IDs and doing a deep dive into the comments 

