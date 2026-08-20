-- redash #128929
-- Database: _EDW Raw

-- Edit log:
-- 2025-11-24: KL adjusted the pivot tables for Snowflake
-- 2026-01-26: KL added "Recovery Receivable JEs QA" tab -- https://gustohq.atlassian.net/browse/FTDS-823 to compare to legacy logic: https://redash.zp-int.com/queries/144588/source?p_End%20of%20Period=2025-12-31&p_Insert%20Date=2026-01-05#280973
-- 2026-01-27: KL implemented logic in rr CTE to exclude `RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd` from this report. More info:  https://gustohq.atlassian.net/browse/FTDS-823
-- 2026-02-27: KL reverted to pre-2026-01-27 logic above per https://gustohq.atlassian.net/browse/FTDS-865
-- 2026-03-06: KL exposed pivot controls for visibilty of calculations and tab-level additional filters

WITH rr AS 
(
  SELECT DISTINCT * FROM bi.recovery_receivable_snapshot
  WHERE
    (
      bank_transaction_date = '{{End of Period}}'
      AND snapshot_date = '{{Insert Date}}'
      AND pi_status IS NOT NULL
      AND pi_status = 'recovered'
      AND company_id IS NOT NULL
      AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880) -- exclude corporate company IDs
      AND pi_category <> 'micro variance' -- exclude all micro variance
      AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive') -- 2026-01-26 KL: https://gustohq.atlassian.net/browse/FTDS-823
    --   AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive', 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd') -- 2026-01-26 KL: https://gustohq.atlassian.net/browse/FTDS-823
      AND pi_id NOT IN (579085, 623771, 579082)
      AND current_balance >= 0
    )
    OR (
      bank_transaction_date = '{{End of Period}}'
      AND snapshot_date = '{{Insert Date}}'
      AND pi_status IS NOT NULL
      AND pi_status = 'recovered'
      AND company_id IS NOT NULL
      AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880)
      AND pi_category IS NULL
      AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive') -- 2026-01-26 KL: https://gustohq.atlassian.net/browse/FTDS-823
    --   AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive', 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd') -- 2026-01-26 KL: https://gustohq.atlassian.net/browse/FTDS-823
      AND pi_id NOT IN (579085, 623771, 579082)
      AND current_balance >= 0
    )
    OR (
      bank_transaction_date = '{{End of Period}}'
      AND snapshot_date = '{{Insert Date}}'
      AND pi_status IS NOT NULL
      AND company_id IS NOT NULL
      AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880)
      AND pi_category <> 'micro variance'
      AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive') -- 2026-01-26 KL: https://gustohq.atlassian.net/browse/FTDS-823
    --   AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive', 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd') -- 2026-01-26 KL: https://gustohq.atlassian.net/browse/FTDS-823
      AND pi_id NOT IN (579085, 623771, 579082)
      AND pi_status <> 'recovered'
    )
    OR (
      bank_transaction_date = '{{End of Period}}'
      AND snapshot_date = '{{Insert Date}}'
      AND pi_status IS NOT NULL
      AND company_id IS NOT NULL
      AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880)
      AND pi_category IS NULL
      AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive') -- 2026-01-26 KL: https://gustohq.atlassian.net/browse/FTDS-823
    --   AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive', 'RecoveryReceivable_SuccessfullyRecoveredAfterPeriodEnd') -- 2026-01-26 KL: https://gustohq.atlassian.net/browse/FTDS-823
      AND pi_id NOT IN (579085, 623771, 579082)
      AND pi_status <> 'recovered'
    )
)

SELECT DISTINCT
  REPLACE(rr.id_category_concat, '-', 'x') AS id_category_concat,  -- Replace '-' with 'x'
  
  rr.event_id::VARCHAR || 'x' AS event_id,
  rr.company_id::VARCHAR || 'x' AS company_id,
  
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
  pi.created_at AS pi_created_at,
  EXTRACT(YEAR FROM pi.created_at) || '-' || EXTRACT(MONTH FROM pi.created_at) AS pi_month_year,
  CASE 
    WHEN rr.accounting_pi_category = 'Fraud' THEN 'Fraud'
    WHEN rr.accounting_pi_category <> 'Fraud' AND credit_table.is_credit_loss = TRUE THEN 'Credit'
    WHEN rr.accounting_pi_category <> 'Fraud' AND credit_table.is_credit_loss = FALSE THEN 'Product'
    WHEN rr.accounting_pi_category <> 'Fraud' AND credit_table.is_credit_loss IS NULL THEN 'Product'
    ELSE 'Product'
  END AS updated_category,
  CASE 
    WHEN rr.pi_age_in_days <= 30 THEN '0 - 30 days'
    WHEN rr.pi_age_in_days BETWEEN 31 AND 60 THEN '31 - 60 days'
    WHEN rr.pi_age_in_days BETWEEN 61 AND 90 THEN '61 - 90 days'
    WHEN rr.pi_age_in_days BETWEEN 91 AND 120 THEN '91 - 120 days'
    WHEN rr.pi_age_in_days BETWEEN 121 AND 180 THEN '121 - 180 days'
    WHEN rr.pi_age_in_days > 180 THEN '> 180 days'
    ELSE NULL
  END AS aging_bucket
FROM rr
LEFT JOIN (
  SELECT DISTINCT *
  FROM bi.recovery_receivable_credit_delinquencies_snapshot
  WHERE snapshot_date = '{{Insert Date}}'
) AS credit_table
  ON REPLACE(rr.id_category_concat, '-', 'x') = REPLACE(credit_table.id_event_concat, '-', 'x')  -- Normalize join key
LEFT JOIN bi.payment_investigations pi
  ON rr.pi_id = pi.id;

