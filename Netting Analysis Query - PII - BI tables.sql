-- redash #134847
-- Database: _EDW Raw

-- Monthly Netting Analysis Query

-- 2026-03-05: Katie Lundquist updated fiscal_year_written_off filter from ('FY23', 'FY24', 'FY25') to >= 'FY25' to match "automated report" https://redash.zp-int.com/queries/131616/source?p_Current%20Period=2026-02-28&p_Insert%20Date%20Current%20Period=2026-03-03&p_Insert%20Date%20Lag%201%20Period=2025-12-02&p_Insert%20Date%20Lag%202%20Period=2025-09-03&p_Lag%201%20Period=2025-11-30&p_Lag%202%20Period=2025-08-31#264602

-- UPDATED VERSION: Migrated to use bi schema tables instead of data_science schema. See request: https://gustohq.atlassian.net/browse/FTDS-676
-- V1 with data_science schema (built by Platform Accounting contractor Duy): https://redash.zp-int.com/queries/119954/source
-- V2 with data_science schema (adjusted by a differnet contractor Neolin): https://redash.zp-int.com/queries/127898/source?p_End%20of%20Period=2025-09-30&p_End%20of%20Period%202=2025-09-30&p_Insert%20Date=2025-10-2&p_Insert%20Date%202=2025-10-2&p_bank_transaction_date=2025-09-30&p_bank_transaction_date%202=2025-09-30#248987

-- BI Migration Date: 2025-10-21
-- Changes:
--   1. data_science.bad_debt_transfers_snapshot → bi.bad_debt_transfers_snapshot
--   2. data_science.recovery_recievable_credit_delinquencies → bi.recovery_receivable_credit_delinquencies
--   3. data_science.recovery_recievable_snapshot → bi.recovery_receivable_snapshot
--   4. Column name mappings applied (see inline comments)
--   5. Added 'x' delimiters back for backward compatibility with existing workbooks

-- Objective: The following query is used to identify and classify loss events that occur month over month. In order to 
-- determine if a loss event is temporary or a true loss, negative balance events will be identified and classified into 
-- either a recovery receivable, bad debt, paid off, true loss, or excluded event. 
-- This query uses 4 prior built queries as to provide the source data.

-- Inputs: 2 months of data  would be needed for each of the following CTEs: company balances, recovery_receivable, bad_debt, and exclusion  
-- for this comparison. For example, if the user is looking to evaluate the month of April 2024, they would need to provide a lookback period inclusive
-- of 04/01/2024 (month 1) to 05/31/2024 (month 2). 

-- Parameters:
-- bank_transaction_date - cutoff date for company balances data for the first month (the last day of the month the user is analyzing)
-- End of Period - cutoff date for recovery receivable, bad debt, and exclusion data for the first month (the last day of the month the user is analyzing)
-- Insert Date - snapshot date for recovery receivable, bad debt, and exclusion data for the first month 
-- bank_transaction_date 2 - cutoff date for company balances data for the second month (the last day of the next month from the analysis period)
-- End of Period 2 - cutoff date for recovery receivable, bad debt, and exclusion data for the second month (the last day of the next month from the analysis period)
-- Insert Date 2 - snapshot date for recovery receivable, bad debt, and exclusion data for the second month 


-- Company Balance CTE Month 1
-- This query is used to get the starting position of company balances events. The query will identify all events in the company balance table
-- where the balance is negative and the date is earlier than the provided bank_transaction_date
WITH 
company_balance_cte AS (
    WITH cte AS (
        SELECT 
            abh.pr_on_behalf_of_id,
            event_id || 'x' || transaction_category AS concat,
            CASE 
                WHEN abh.bank_transaction_date < '2020-01-01'::date THEN bank_transaction_date::date
                ELSE abh.bank_transaction_date
            END AS bank_transaction_date,
            abh.investigation_status,
            abh.investigation_created_at::date AS investigation_date,
            SUM(abh.balance) AS balance
        FROM bi_reporting.accounting_balance_history abh
        WHERE abh.bank_transaction_date <= '{{ bank_transaction_date }}'
        GROUP BY 1, 2, 3, 4, 5
    ),
    cte2 AS (
        SELECT 
            cte.concat AS uid,
            cte.pr_on_behalf_of_id,
            SUM(cte.balance) AS balance
        FROM cte 
        GROUP BY 1, 2
        HAVING SUM(cte.balance) < -0.01
    )
    SELECT 
        cte2.uid,
        SUM(cte2.balance) AS balance
    FROM cte2
    where cte2.uid IS NOT NULL
    GROUP BY 1
)
-- select * from
-- company_balance_cte 
,
-- Recovery Receivable CTE Month 1
-- This query is used to get all events which were determined to be recovery_receivable by the end of Month 1.
-- The output of this query will be matched with the output of Company Balances CTE Month 1 to determine which events in that population were 
-- classified as recovery_receivable.
-- This CTE is similar to the recovery receivable query and references the recovery receivable snapshot. As a result, a snapshot date that 
-- occurs after the end of period date will be needed
--WITH
recovery_receivable_cte AS (
    WITH rr AS (
        SELECT DISTINCT *
        FROM bi.recovery_receivable_snapshot -- CHANGED: was data_science.recovery_recievable_snapshot
        WHERE (
            (bank_transaction_date = '{{End of Period}}' 
            AND snapshot_date = '{{Insert Date}}' -- CHANGED: was insert_dt
            AND pi_status = 'recovered' -- CHANGED: was status
            AND company_id IS NOT NULL -- CHANGED: removed || 'x' from NULL check (type compatibility)
            AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880) -- CHANGED: removed 'x' suffix from comparison values
            AND pi_category <> 'micro variance'
            AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
            AND pi_id NOT IN (579085, 623771, 579082)
            AND current_balance >= 0)
            OR
            (bank_transaction_date = '{{End of Period}}' 
            AND snapshot_date = '{{Insert Date}}' -- CHANGED: was insert_dt
            AND pi_status = 'recovered' -- CHANGED: was status
            AND company_id IS NOT NULL -- CHANGED: removed || 'x' from NULL check (type compatibility)
            AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880) -- CHANGED: removed 'x' suffix from comparison values
            AND pi_category IS NULL
            AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
            AND pi_id NOT IN (579085, 623771, 579082)
            AND current_balance >= 0)
            OR
            (bank_transaction_date = '{{End of Period}}' 
            AND snapshot_date = '{{Insert Date}}' -- CHANGED: was insert_dt
            AND pi_status IS NOT NULL -- CHANGED: was status
            AND company_id IS NOT NULL -- CHANGED: removed || 'x' from NULL check (type compatibility)
            AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880) -- CHANGED: removed 'x' suffix from comparison values
            AND pi_category <> 'micro variance'
            AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
            AND pi_id NOT IN (579085, 623771, 579082)
            AND pi_status <> 'recovered') -- CHANGED: was status
            OR
            (bank_transaction_date = '{{End of Period}}' 
            AND snapshot_date = '{{Insert Date}}' -- CHANGED: was insert_dt
            AND pi_status IS NOT NULL -- CHANGED: was status
            AND company_id IS NOT NULL -- CHANGED: removed || 'x' from NULL check (type compatibility)
            AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880) -- CHANGED: removed 'x' suffix from comparison values
            AND pi_category IS NULL
            AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
            AND pi_id NOT IN (579085, 623771, 579082)
            AND pi_status <> 'recovered') -- CHANGED: was status
        )
    )
    SELECT 
        REPLACE(rr.id_category_concat, '-', 'x') AS concat, -- CHANGED: was concat, now id_category_concat with delimiter conversion
        rr.balance
    FROM rr
)
-- select * from
-- recovery_receivable_cte 
,
-- Bad Debt CTE Month 1
-- This query is used to get all events which were determined to be bad debts by the end of Month 1.
-- The output of this query will be matched with the output of Company Balances CTE Month 1 to determine which events in that population were 
-- classified as bad debts.
-- This CTE is similar to the recovery receivable charged by JEs query and references the recovery receivable charged by JEs snapshot. 
-- As a result, a snapshot date that  occurs after the end of period date will be needed.

-- Uncomment WITH clause to run with Select statement 
--WITH
bad_debt_cte AS (
    WITH bd AS (
        SELECT DISTINCT *
        FROM bi.bad_debt_transfers_snapshot -- CHANGED: was data_science.bad_debt_transfers_snapshot
        -- WHERE fiscal_year_written_off IN ('FY23', 'FY24', 'FY25')
        WHERE fiscal_year_written_off >= 'FY25' -- KL updated 2026-03-05 to match automated report
        AND effective_date <= '{{End of Period}}'
        AND snapshot_date = '{{Insert Date}}' -- CHANGED: was insert_dt
    ),
    pi_with_txn_cat AS (
        SELECT 
            pi.id AS payment_investigation_id,
            pi.event_type,
            pi.event_id,
            peb.transaction_category
        FROM bi.payment_investigations pi
        LEFT JOIN zenpayroll_production.payment_event_balance_investigations pebi 
            ON pi.id = pebi.payment_investigation_id
        LEFT JOIN zenpayroll_production.payment_event_balances peb 
            ON pebi.payment_event_balance_id = peb.id
    )
    SELECT DISTINCT
        MAX(bd.bad_debt_id) AS bad_debt_id,
        MAX(bd.bad_debt_amount) AS bad_debt_amount,
        MAX(bd.payment_event_balance_amount) AS p_e_amount,
        REPLACE(bd.id_category_concat, '-', 'x') AS concatenante -- CHANGED: was concatenante, now id_category_concat with delimiter conversion
    FROM bd
    LEFT JOIN bi.recovery_receivable_credit_delinquencies AS credit_table -- CHANGED: was data_science.recovery_recievable_credit_delinquencies
        ON REPLACE(bd.id_category_concat, '-', 'x') = REPLACE(credit_table.id_event_concat, '-', 'x') -- CHANGED: was combo, now id_event_concat with delimiter conversion
    LEFT JOIN pi_with_txn_cat pi 
        ON bd.inv_or_event_id || 'x' = pi.event_id || 'x' -- CHANGED: added || 'x' for backward compatibility
        AND bd.event_type = pi.event_type 
        AND bd.transaction_category = pi.transaction_category
    WHERE override_status = 'pending'
    GROUP BY REPLACE(bd.id_category_concat, '-', 'x') -- CHANGED: was bd.concatenante
)
-- select * from
-- bad_debt_cte 

,

-- Exclusion CTE Month 1
-- This query is used to find out if any event_id+transaction_category should be
-- part of any of the false positives or duplicates of bad debt that's were excluded from RR Report.
-- The output of this query will be matched with the output of Company Balances CTE Month 1 to determine which events in that population should 
-- be excluded 

-- Uncomment WITH clause to run with Select statement 
--WITH
exclusion_cte AS (
    SELECT 
        REPLACE(id_category_concat, '-', 'x') AS uid, -- CHANGED: delimiter conversion from '-' to 'x'
        pi_status, -- CHANGED: was pi_status (column now consistently named)
        pi_category,
        pi_id,
        SUM(balance) as balance
    FROM bi.recovery_receivable_snapshot -- CHANGED: was bi.recovery_receivable_snapshot (schema unchanged, but spelling corrected in upstream)
    WHERE 
        pi_status IN ('recovered', 'awaiting_bad_debt_funds', 'awaiting_external_dependency', 'awaiting_bad_debt_approval', 'false_positive') -- CHANGED: was pi_status
        AND bank_transaction_date = '{{End of Period}}'
        AND snapshot_date = '{{Insert Date}}' -- CHANGED: was snapshot_date (keeping new name)
    GROUP BY 1,2,3,4

    UNION ALL

    SELECT  
        REPLACE(id_category_concat, '-', 'x') AS uid, -- CHANGED: delimiter conversion from '-' to 'x'
        pi_status, -- CHANGED: was pi_status (column now consistently named)
        pi_category,
        pi_id,
        SUM(balance)
    FROM bi.recovery_receivable_snapshot -- CHANGED: was bi.recovery_receivable_snapshot (schema unchanged, but spelling corrected in upstream)
    WHERE 
        pi_category = 'micro variance'
        AND pi_status NOT IN ('recovered', 'awaiting_bad_debt_funds', 'awaiting_external_dependency', 'awaiting_bad_debt_approval', 'false_positive') -- CHANGED: was pi_status
        AND bank_transaction_date = '{{End of Period}}'
        AND snapshot_date = '{{Insert Date}}' -- CHANGED: was snapshot_date (keeping new name)
    GROUP BY 1,2,3,4
)
-- select * from
-- exclusion_cte 
,
grouped_by_exclusion as(
select 
uid,
sum(balance)
from exclusion_cte
group by 1
)
,
-- Company Balances with Matches CTE Month 1
-- This CTE idenfies the negative company balances where the unique identifier matches to either a bad_debt, recovery_receivable or exclusion event
-- If there is a match, the query will assign a corresponding match value to a new match column on that event.
-- Unmatched events are events that have not been identified by the end of month close period and are unidentified loss events
-- These events will be determined to be temporary loss exposure or true loss upon review with next month's CTEs.
cb_with_matches_cte AS (
    SELECT
        cb.*,
        CASE
            WHEN rr.concat IS NOT NULL THEN 'recovery receivable matched'
            WHEN bd.concatenante IS NOT NULL THEN 'bad debt matched'
            WHEN ex.uid IS NOT NULL THEN 'excluded'
            ELSE 'unmatched'
        END AS match,
        CASE
            WHEN rr.concat IS NOT NULL THEN 1
            WHEN bd.concatenante IS NOT NULL THEN 2
            WHEN ex.uid IS NOT NULL THEN 3
            ELSE 4
        END AS match_priority
    FROM 
        company_balance_cte cb
    LEFT JOIN 
        recovery_receivable_cte rr
        ON cb.uid = rr.concat 
    LEFT JOIN 
        bad_debt_cte bd
        ON cb.uid = bd.concatenante
    LEFT JOIN 
        grouped_by_exclusion ex
        ON cb.uid = ex.uid
)
,
-- Company Balance CTE Month 2
-- This query is used to get the starting position of company balances events for the 2nd month. 
-- The query will identify all events in the company balance table
-- where the balance is negative and the date is earlier than the provided bank_transaction_date.
-- Uncomment WITH clause to run with Select statement 
--WITH
fresh_company_balance_cte AS (
  WITH cte AS (
        SELECT 
            abh.pr_on_behalf_of_id,
            event_id || 'x' || transaction_category AS concat,
            CASE 
                WHEN abh.bank_transaction_date < '2020-01-01'::date THEN bank_transaction_date::date
                ELSE abh.bank_transaction_date
            END AS bank_transaction_date,
            abh.investigation_status,
            abh.investigation_created_at::date AS investigation_date,
            SUM(abh.balance) AS balance
        FROM bi_reporting.accounting_balance_history abh
        WHERE abh.bank_transaction_date <= '{{ bank_transaction_date 2 }}'
        GROUP BY 1, 2, 3, 4, 5
    ),
    cte2 AS (
        SELECT 
            cte.concat AS uid,
            cte.pr_on_behalf_of_id,
            SUM(cte.balance) AS balance
        FROM cte 
        GROUP BY 1, 2
        HAVING SUM(cte.balance) < -0.01
    )
    SELECT 
        cte2.uid,
        SUM(cte2.balance) AS balance
    FROM cte2
    where cte2.uid IS NOT NULL
    GROUP BY 1
)
-- select * from
-- fresh_company_balance_cte
,
-- Recovery Receivable CTE Month 2
-- This query is used to get all events which were determined to be recovery_receivable by the end of Month 2.
-- The output of this query will be matched with the output of Company Balances with Matches CTE Month 1 to determine which unmatched events 
-- in that population were classified as recovery_receivable.
-- This CTE is similar to the recovery receivable query and references the recovery receivable snapshot. As a result, a snapshot date that 
-- occurs after the end of period date will be needed

-- Uncomment WITH clause to run with Select statement 
--WITH
second_recovery_receivable_cte AS (
    WITH rr AS (
        SELECT DISTINCT *
        FROM bi.recovery_receivable_snapshot -- CHANGED: was data_science.recovery_recievable_snapshot
        WHERE (
            (bank_transaction_date = '{{End of Period 2}}' 
            AND snapshot_date = '{{Insert Date 2}}' -- CHANGED: was insert_dt
            AND pi_status = 'recovered' -- CHANGED: was status
            AND company_id IS NOT NULL -- CHANGED: removed || 'x' from NULL check (type compatibility)
            AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880) -- CHANGED: removed 'x' suffix from comparison values
            AND pi_category <> 'micro variance'
            AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
            AND pi_id NOT IN (579085, 623771, 579082)
            AND current_balance >= 0)
            OR
            (bank_transaction_date = '{{End of Period 2}}' 
            AND snapshot_date = '{{Insert Date 2}}' -- CHANGED: was insert_dt
            AND pi_status = 'recovered' -- CHANGED: was status
            AND company_id IS NOT NULL -- CHANGED: removed || 'x' from NULL check (type compatibility)
            AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880) -- CHANGED: removed 'x' suffix from comparison values
            AND pi_category IS NULL
            AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
            AND pi_id NOT IN (579085, 623771, 579082)
            AND current_balance >= 0)
            OR
            (bank_transaction_date = '{{End of Period 2}}' 
            AND snapshot_date = '{{Insert Date 2}}' -- CHANGED: was insert_dt
            AND pi_status IS NOT NULL -- CHANGED: was status
            AND company_id IS NOT NULL -- CHANGED: removed || 'x' from NULL check (type compatibility)
            AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880) -- CHANGED: removed 'x' suffix from comparison values
            AND pi_category <> 'micro variance'
            AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
            AND pi_id NOT IN (579085, 623771, 579082)
            AND pi_status <> 'recovered') -- CHANGED: was status
            OR
            (bank_transaction_date = '{{End of Period 2}}' 
            AND snapshot_date = '{{Insert Date 2}}' -- CHANGED: was insert_dt
            AND pi_status IS NOT NULL -- CHANGED: was status
            AND company_id IS NOT NULL -- CHANGED: removed || 'x' from NULL check (type compatibility)
            AND company_id NOT IN (7757616923492312, 7757616923524413, 2, 7757616923899880) -- CHANGED: removed 'x' suffix from comparison values
            AND pi_category IS NULL
            AND accounting_status_mapping NOT IN ('NotRecovery_writtenoff_pendingcorptransfer', 'NotRecovery_FalsePositive')
            AND pi_id NOT IN (579085, 623771, 579082)
            AND pi_status <> 'recovered') -- CHANGED: was status
        )
    )
    SELECT 
        REPLACE(rr.id_category_concat, '-', 'x') AS concat -- CHANGED: was concat, now id_category_concat with delimiter conversion
    FROM rr
)
-- select * from
-- second_recovery_receivable_cte
,
-- Bad Debt CTE Month 2
-- This query is used to get all events which were determined to be bad debts by the end of Month 2.
-- The output of this query will be matched with the output of Company Balances with Matches CTE Month 1 to determine which events in that unmatched population were 
-- classified as bad debts.
-- This CTE is similar to the recovery receivable charged by JEs query and references the recovery receivable charged by JEs snapshot. 
-- As a result, a snapshot date that  occurs after the end of period date will be needed.

-- Uncomment WITH clause to run with Select statement 
--WITH
second_bad_debt_cte AS (
    WITH bd AS (
        SELECT DISTINCT *
        FROM bi.bad_debt_transfers_snapshot -- CHANGED: was data_science.bad_debt_transfers_snapshot
        -- WHERE fiscal_year_written_off IN ('FY23', 'FY24', 'FY25')
        WHERE fiscal_year_written_off >= 'FY25' -- KL updated 2026-03-05 to match automated report
        AND effective_date <= '{{End of Period 2}}'
        AND snapshot_date = '{{Insert Date 2}}' -- CHANGED: was insert_dt
    ),
    pi_with_txn_cat AS (
        SELECT 
            pi.id AS payment_investigation_id,
            pi.event_type,
            pi.event_id,
            peb.transaction_category
        FROM bi.payment_investigations pi
        LEFT JOIN zenpayroll_production.payment_event_balance_investigations pebi 
            ON pi.id = pebi.payment_investigation_id
        LEFT JOIN zenpayroll_production.payment_event_balances peb 
            ON pebi.payment_event_balance_id = peb.id
    )
    SELECT DISTINCT
        MAX(bd.bad_debt_id) AS bad_debt_id,
        MAX(bd.bad_debt_amount) AS bad_debt_amount,
        MAX(bd.payment_event_balance_amount) AS p_e_amount,
        REPLACE(bd.id_category_concat, '-', 'x') AS concatenante -- CHANGED: was concatenante, now id_category_concat with delimiter conversion
    FROM bd
    LEFT JOIN bi.recovery_receivable_credit_delinquencies AS credit_table -- CHANGED: was data_science.recovery_recievable_credit_delinquencies
        ON REPLACE(bd.id_category_concat, '-', 'x') = REPLACE(credit_table.id_event_concat, '-', 'x') -- CHANGED: was combo, now id_event_concat with delimiter conversion
    LEFT JOIN pi_with_txn_cat pi 
        ON bd.inv_or_event_id || 'x' = pi.event_id || 'x' -- CHANGED: added || 'x' for backward compatibility
        AND bd.event_type = pi.event_type 
        AND bd.transaction_category = pi.transaction_category
    WHERE override_status = 'pending'
    GROUP BY REPLACE(bd.id_category_concat, '-', 'x') -- CHANGED: was bd.concatenante
)
,

-- Second Exclusion CTE Month 2
-- This query is used to find out if any event_id+transaction_category should be
-- part of any of the false positives or duplicates of bad debt that's were excluded from RR Report for Month 2.
-- The output of this query will be matched with the output of Company Balances with Matches CTE Month 1 to determine which
-- unmatched events in that population should be excluded 
-- Uncomment WITH clause to run with Select statement 
--WITH
second_exclusion_cte AS (
    SELECT 
        REPLACE(id_category_concat, '-', 'x') AS uid, -- CHANGED: delimiter conversion from '-' to 'x'
        pi_status, -- CHANGED: was pi_status (column now consistently named)
        pi_category,
        pi_id,
        SUM(balance) as balance
    FROM bi.recovery_receivable_snapshot -- CHANGED: was bi.recovery_receivable_snapshot (schema unchanged, but spelling corrected in upstream)
    WHERE 
        pi_status IN ('recovered', 'awaiting_bad_debt_funds', 'awaiting_external_dependency', 'awaiting_bad_debt_approval', 'false_positive') -- CHANGED: was pi_status
        AND bank_transaction_date = '{{End of Period 2}}'
        AND snapshot_date = '{{Insert Date 2}}' -- CHANGED: was snapshot_date (keeping new name)
    GROUP BY 1,2,3,4

    UNION ALL

    SELECT  
        REPLACE(id_category_concat, '-', 'x') AS uid, -- CHANGED: delimiter conversion from '-' to 'x'
        pi_status, -- CHANGED: was pi_status (column now consistently named)
        pi_category,
        pi_id,
        SUM(balance)
    FROM bi.recovery_receivable_snapshot -- CHANGED: was bi.recovery_receivable_snapshot (schema unchanged, but spelling corrected in upstream)
    WHERE 
        pi_category = 'micro variance'
        AND pi_status NOT IN ('recovered', 'awaiting_bad_debt_funds', 'awaiting_external_dependency', 'awaiting_bad_debt_approval', 'false_positive') -- CHANGED: was pi_status
        AND bank_transaction_date = '{{End of Period 2}}'
        AND snapshot_date = '{{Insert Date 2}}' -- CHANGED: was snapshot_date (keeping new name)
    GROUP BY 1,2,3,4
)
,
grouped_by_exclusion_2 as(
select 
uid,
sum(balance)
from second_exclusion_cte
group by 1
)
-- FINAL SELECT
-- This select statement classifies the unmatched population from Month 1 into different categories.
-- If the previous month's events are found in the recovery receivable, bad debt, or excluded reports in Month 2, they will be assigned their respective 
-- categories in the column second matched.
-- The recovery receivable and bad debt population are temporary loss exposures, driven by delayed payment investigation.
-- If an unmatched event still remains with the same negative balance, it will be in the unchanged population and is a true loss.
-- If an unmatched event still remains but has a different balance, it will be in the changed population and is a true loss.
-- If an unmatched event no longer appears in the Month 2 company balances, it indicates that the event was paid off between the cutover date for Month 1 and Month 2 and was a temporary loss exposure.

SELECT
    cbm.uid,
    cbm.balance,
    cbm.match,
    cbm.match_priority,
    CASE
        WHEN rr2.concat IS NOT NULL THEN 'Recovery Receivable'
        WHEN bd2.concatenante IS NOT NULL THEN 'Bad Debts'
        WHEN ex2.uid IS NOT NULL THEN 'Unchanged- matched to Exclusion'
        WHEN fcb.uid IS NOT NULL AND fcb.balance = cbm.balance THEN 'Unchanged'
        WHEN fcb.uid IS NOT NULL AND fcb.balance <> cbm.balance THEN 'Unidentified Loss'
        ELSE 'Paid Off'
    END AS second_match,
    CASE
        WHEN rr2.concat IS NOT NULL THEN 1
        WHEN bd2.concatenante IS NOT NULL THEN 2
        WHEN ex2.uid IS NOT NULL THEN 3
        WHEN fcb.uid IS NOT NULL AND fcb.balance = cbm.balance THEN 4
        WHEN fcb.uid IS NOT NULL AND fcb.balance <> cbm.balance THEN 5
        ELSE 6
    END AS second_match_priority
FROM cb_with_matches_cte cbm
LEFT JOIN fresh_company_balance_cte fcb ON cbm.uid = fcb.uid
LEFT JOIN second_recovery_receivable_cte rr2 ON cbm.uid = rr2.concat
LEFT JOIN second_bad_debt_cte bd2 ON cbm.uid = bd2.concatenante
LEFT JOIN grouped_by_exclusion_2 ex2 ON cbm.uid = ex2.uid
where cbm.match = 'unmatched';


