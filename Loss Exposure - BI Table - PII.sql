-- redash #128019
-- Database: _EDW Raw

-- 2026-01-08: KL fixed some remaining visualization issues in the pivot table visualizations related to the Redshift-->Snowflake database migration more info: https://gustohq.atlassian.net/browse/FTDS-797

WITH rr AS (
  SELECT DISTINCT *  
  FROM bi.recovery_receivable_snapshot
  WHERE
    bank_transaction_date = '{{End of Period}}'
    AND snapshot_date      = '{{Insert Date}}'
    AND pi_status         IS NOT NULL
    AND company_id        IS NOT NULL
    AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880)
    AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer','NotRecovery_FalsePositive')
    AND pi_id NOT IN (579085,623771,579082)
    AND (
          (pi_status = 'recovered' AND pi_category <> 'micro variance' AND current_balance >= 0)
       OR (pi_status = 'recovered' AND pi_category IS NULL            AND current_balance >= 0)
       OR (pi_status <> 'recovered' AND pi_category <> 'micro variance')
       OR (pi_status <> 'recovered' AND pi_category IS NULL)
    )
)

SELECT DISTINCT
  REPLACE(rr.id_category_concat::varchar, '-', 'x')             AS id_category_concat,
  (rr.event_id::varchar)   || 'x'                              AS event_id,
  (rr.company_id::varchar) || 'x'                              AS company_id,
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
  pi.created_at                                                AS pi_created_at,
  TO_CHAR(pi.created_at, 'YYYY-MM')                            AS pi_mm_yyyy,
  CASE
    WHEN rr.accounting_pi_category = 'Fraud'
      THEN TO_CHAR(pi.created_at, 'YYYY-MM')
    ELSE TO_CHAR(pi.created_at + INTERVAL '90 day', 'YYYY-MM')
  END                                                          AS loss_recog_mm_yyyy,

  CASE
    WHEN rr.accounting_pi_category = 'Fraud'                   THEN 'Fraud'
    WHEN COALESCE(credit_table.is_credit_loss, FALSE) = TRUE   THEN 'Credit'
    ELSE 'Product'
  END                                                          AS updated_category,

  CASE
    WHEN rr.pi_age_in_days <= 30              THEN '0 - 30 days'
    WHEN rr.pi_age_in_days BETWEEN 31 AND 60  THEN '31 - 60 days'
    WHEN rr.pi_age_in_days BETWEEN 61 AND 90  THEN '61 - 90 days'
    WHEN rr.pi_age_in_days BETWEEN 91 AND 120 THEN '91 - 120 days'
    WHEN rr.pi_age_in_days BETWEEN 121 AND 180 THEN '121 - 180 days'
    WHEN rr.pi_age_in_days > 180             THEN '> 180 days'
    ELSE NULL
  END                                                          AS aging_bucket

FROM rr
LEFT JOIN (
  SELECT DISTINCT *
  FROM bi.recovery_receivable_credit_delinquencies_snapshot
  WHERE snapshot_date = '{{Insert Date}}'
) AS credit_table
  ON rr.id_category_concat = credit_table.id_event_concat
LEFT JOIN bi.payment_investigations pi
  ON rr.pi_id = pi.id;
  
  
-- 10/31/25: bi.table migration and id_category_concat '-' replace to 'x'  and event_id and company_id to end with 'x'

-- Original Query with DS Table --------------------------------------------------------
-- WITH rr AS (
--   SELECT DISTINCT *
--   FROM data_science.recovery_recievable_snapshot
--   WHERE 
--     (
--       bank_transaction_date = '{{End of Period}}'
--       AND insert_dt = '{{Insert Date}}'
--       AND status IS NOT NULL
--       AND status = 'recovered'
--       AND company_id IS NOT NULL
--       AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880) -- exclude corporate company IDs
--       AND pi_category <> 'micro variance' -- exclude all micro variance
--       AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
--       AND pi_id NOT IN (579085, 623771, 579082)
--       AND current_balance >= 0
--     )

--     OR (
--       bank_transaction_date = '{{End of Period}}'
--       AND insert_dt = '{{Insert Date}}'
--       AND status IS NOT NULL
--       AND status = 'recovered'
--       AND company_id IS NOT NULL
--       AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880)
--       AND pi_category IS NULL
--       AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
--       AND pi_id NOT IN (579085, 623771, 579082)
--       AND current_balance >= 0
--     )

--     OR (
--       bank_transaction_date = '{{End of Period}}'
--       AND insert_dt = '{{Insert Date}}'
--       AND status IS NOT NULL
--       AND company_id IS NOT NULL
--       AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880) -- exclude corporate company IDs
--       AND pi_category <> 'micro variance' -- exclude all micro variance
--       AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
--       AND pi_id NOT IN (579085, 623771, 579082)
--       AND status <> 'recovered'
--     )

--     OR (
--       bank_transaction_date = '{{End of Period}}'
--       AND insert_dt = '{{Insert Date}}'
--       AND status IS NOT NULL
--       AND company_id IS NOT NULL
--       AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880)
--       AND pi_category IS NULL
--       AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
--       AND pi_id NOT IN (579085, 623771, 579082)
--       AND status <> 'recovered'
--     )
-- )

-- SELECT DISTINCT
--   rr.concat,
--   rr.event_id::VARCHAR || 'x' AS event_id,
--   rr.company_id,
--   rr.event_type,
--   rr.transaction_category,
--   rr.pi_id,
--   rr.status,
--   rr.pi_category,
--   rr.pi_age_in_days,
--   rr.accounting_to_reserve,
--   rr.accounting_status_mapping,
--   rr.accounting_pi_category,
--   rr.balance,
--   rr.current_balance,

--   CASE
--     WHEN rr.accounting_pi_category = 'Fraud' THEN 'Fraud'
--     WHEN rr.accounting_pi_category <> 'Fraud' AND credit_table.is_credit_loss = TRUE THEN 'Credit'
--     WHEN rr.accounting_pi_category <> 'Fraud' AND credit_table.is_credit_loss = FALSE THEN 'Product'
--     WHEN rr.accounting_pi_category <> 'Fraud' AND credit_table.is_credit_loss = NULL THEN 'Product'
--     ELSE 'Product'
--   END AS updated_category,

--   CASE
--     WHEN rr.pi_age_in_days <= 30 THEN '0 - 30 days'
--     WHEN rr.pi_age_in_days BETWEEN 31 AND 60 THEN '31 - 60 days'
--     WHEN rr.pi_age_in_days BETWEEN 61 AND 90 THEN '61 - 90 days'
--     WHEN rr.pi_age_in_days BETWEEN 91 AND 120 THEN '91 - 120 days'
--     WHEN rr.pi_age_in_days BETWEEN 121 AND 180 THEN '121 - 180 days'
--     WHEN rr.pi_age_in_days > 180 THEN '> 180 days'
--     ELSE NULL
--   END AS aging_bucket,

--   bi_pi.created_at,
--   EXTRACT(YEAR FROM bi_pi.created_at) || '-' || EXTRACT(MONTH FROM bi_pi.created_at) AS pi_mm_yyyy,

--   CASE
--     WHEN rr.accounting_pi_category = 'Fraud'
--       THEN EXTRACT(YEAR FROM (bi_pi.created_at)) || '-' || EXTRACT(MONTH FROM (bi_pi.created_at))
--     ELSE
--       EXTRACT(YEAR FROM (bi_pi.created_at + 90)) || '-' || EXTRACT(MONTH FROM (bi_pi.created_at + 90))
--   END AS loss_recog_mm_yyyy

-- FROM rr
-- LEFT JOIN (
--   SELECT DISTINCT *
--   FROM data_science.recovery_recievable_credit_delinquencies_snapshot
--   WHERE insert_dt = '{{Insert Date}}'
-- ) AS credit_table
--   ON rr.concat = credit_table.combo
-- LEFT JOIN bi.payment_investigations bi_pi
--   ON rr.pi_id = bi_pi.id;


