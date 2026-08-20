-- redash #127073
-- Database: _EDW Raw

-- BT and JE Reconciliation Analysis Query

-- Objective: Identify transactions present in both Bank (BT) data and GL JEs.
-- Classify each transaction as:
-- - 'Matched' (found in both datasets)
-- - 'Unmatched BT' (only in BT data)
-- 'Unmatched JE' (only in JE data)

-- Parameters:
-- - start_date: Start date for the analysis (mm-dd-yyyy format)
-- - end_date: End date for the analysis

WITH combined_payment_records AS (
    SELECT
        pr.id AS bank_transaction_id,
        pr.bank_transaction_date,
        pr.bank_account,
        pr.bank_transaction_ids,
        pr.reconciled,
        pr.transmission_type,
        pr.transaction_type,
        pr.payment_record_entries_sum,
        pre.payment_record_id,
        pre.transaction_category,
        pre.event_id,
        pre.event_type,
        pre.on_behalf_of_id,
        pre.on_behalf_of_type,
        pre.payment_direction,
        pre.amount
    FROM
        bi.payment_records pr
    LEFT JOIN
        zenpayroll_production.payment_record_entries pre
        ON pr.id = pre.payment_record_id
    WHERE pr.bank_transaction_date BETWEEN '{{ start_date }}' AND '{{ end_date }}'
),

event_balances AS (
    SELECT pre.*
    FROM combined_payment_records pre
    LEFT JOIN zenpayroll_production.historical_companies hc 
        ON hc.id = pre.event_id AND pre.event_type = 'HistoricalCompany'
    LEFT JOIN zenpayroll_production.contractor_payments cp 
        ON cp.id = pre.event_id AND pre.event_type = 'ContractorPayment'
    LEFT JOIN zenpayroll_production.payrolls pl 
        ON pl.id = pre.event_id AND pre.event_type = 'Payroll'
    WHERE pre.reconciled = TRUE
        AND pre.transaction_category NOT IN ('Balance Transfer', 'Internal Transfer', 'Invoices')
        AND pre.bank_account NOT LIKE '%corporate%'
        AND pre.bank_account NOT LIKE '%health_insurance%'
        AND pre.bank_account NOT LIKE '%flex_pay%'
        AND pre.event_id IS NOT NULL
        AND pre.bank_transaction_date BETWEEN '{{ start_date }}' AND '{{ end_date }}'
        AND pre.on_behalf_of_id NOT IN (7757616923524413, 7757616923492312, 7757616923899880, 7757616923945692, 2)
),

bt_data AS (
    SELECT 
        bt.id AS bank_transaction_id,
        bt.date,
        bt.origination_account_id,
        (DECODE(bt.transaction_type, 4, bt.amount, 0) - DECODE(bt.transaction_type, 2, bt.amount, 0)) / 100.00 AS signed_amount
    FROM event_balances eb 
    JOIN zenpayroll_production.payment_record_reconciliation_groups prrg 
        ON eb.payment_record_id = prrg.payment_record_id
    JOIN zenpayroll_production.reconciliation_groups rg 
        ON prrg.reconciliation_group_id = rg.id 
    JOIN zenpayroll_production.bank_transaction_reconciliation_groups btrg 
        ON rg.id = btrg.reconciliation_group_id
    JOIN zenpayroll_production.bank_transactions bt 
        ON btrg.bank_transaction_id = bt.id
    WHERE rg.state = 'active'
    GROUP BY 1, 2, 3, 4
),

--select * from bt_data

je_data AS (
    SELECT 
        -- CAST(REPLACE(net_usd_amount, ',', '') AS FLOAT) AS amount,
        CAST(replace(REPLACE(REPLACE(net_usd_amount, ',', ''), '(', '-'),')','') AS FLOAT) AS amount,
        je_number,
        bank_transaction_id,
        origination_account_id,
        bank_transaction_date
    FROM integrations_production.accounting_cash_je_listing
    WHERE TRY_TO_DATE(bank_transaction_date, 'MM/DD/YY') BETWEEN '{{start_date}}' AND '{{end_date}}'
)
--select * from je_data
,

get_matches AS (
    SELECT 
        bt.bank_transaction_id, 
        je.bank_transaction_id AS je_bank_transaction_id,
        bt.date AS bt_date,
        je.bank_transaction_date AS je_date,
        bt.origination_account_id AS bt_account,
        je.origination_account_id AS je_account,
        bt.signed_amount AS bt_amount,
        je.amount AS je_amount,
        je.je_number,
        CASE 
            WHEN bt.bank_transaction_id IS NOT NULL AND je.bank_transaction_id IS NOT NULL THEN 'Matched'
            WHEN bt.bank_transaction_id IS NOT NULL AND je.bank_transaction_id IS NULL THEN 'Unmatched BT'
            WHEN bt.bank_transaction_id IS NULL AND je.bank_transaction_id IS NOT NULL THEN 'Unmatched JE'
        END AS scenario
    FROM bt_data bt
    FULL OUTER JOIN je_data je 
        ON bt.bank_transaction_id = je.bank_transaction_id
        
)
--Uncomment The below line to get the 3 scenarios of get_matches,unmatched JEs, and unmatched BTs
--select * from get_matches

-- Final Analysis for Unmatched JEs
--select * from unmatched_je_ids
,
unmatched_je_ids AS (
    SELECT 
    bank_transaction_id,
    je_bank_transaction_id,
    je_amount
    FROM get_matches
    WHERE scenario = 'Unmatched JE'
)

,
unmatched_bt_ids AS (
    SELECT 
    bank_transaction_id,
    je_bank_transaction_id,
    bt_amount
    FROM get_matches
    WHERE scenario = 'Unmatched BT'
),

--The below query identifies the payment records that makes up the unmatched cash JEs.
get_unmatched_jes AS(
SELECT
    pr.origination_account_id,
    pr.bank_name,
    pr.bank_account,
    pre.transaction_category,
    pr.id as payment_record_id,  
    pr.bank_transaction_ids,
    CASE
        WHEN pr.reconciled = TRUE 
            AND pre.transaction_category IS NOT NULL 
            AND pre.transaction_category NOT IN ('Balance Transfer', 'Internal Transfer', 'Invoices') 
            AND (pr.bank_account NOT LIKE '%corporate%' 
                 AND pr.bank_account NOT LIKE '%health_insurance%' 
                 AND pr.bank_account NOT LIKE '%flex_pay%')
            AND pr.bank_transaction_date IS NOT NULL 
            AND pre.on_behalf_of_id IS NOT NULL 
            AND pre.on_behalf_of_id NOT IN ('7757616923524413', '7757616923492312', '2', '7757616923899880') 
        THEN 'Should Include'
        ELSE 'Excluded'
    END AS exclusion_reason,
    COUNT(*) AS record_count,
    SUM(
        CASE
            WHEN pre.payment_direction = 0 THEN pre.amount
            WHEN pre.payment_direction = 1 THEN -pre.amount
            ELSE 0
        END
    ) AS net_sum_amount
FROM
    bi.payment_records pr
LEFT JOIN
    zenpayroll_production.payment_record_entries pre
    ON pr.id = pre.payment_record_id 
WHERE
    pr.bank_transaction_ids IN (
        SELECT je_bank_transaction_id
        FROM unmatched_je_ids
    )
GROUP BY
    pr.origination_account_id,
    pr.bank_name,
    pr.bank_account,
    pr.id, -- pull payment record level results
    pre.transaction_category,
    pr.bank_transaction_ids,
    exclusion_reason -- Use the alias here
ORDER BY pr.origination_account_id
)

select * from get_unmatched_jes


-- FilteredData AS (
--     -- Select the data subject to your WHERE conditions, INCLUDING the date filter
--     SELECT
--         pr.id, -- Need pr.id for COUNT(DISTINCT pr.id)
--         pr.bank_account,
--         pr.bank_transaction_ids,
--         pr.reconciled,
--         pr.bank_transaction_date, -- Keep for context/ordering if needed
--         pre.payment_record_id, -- Used to check for NULL in CASE
--         pre.transaction_category,
--         pre.event_id, -- Retained for completeness
--         pre.on_behalf_of_id,
--         pre.payment_direction,
--         pre.amount
--     FROM
--         bi.payment_records pr
--     LEFT JOIN
--         zenpayroll_production.payment_record_entries pre
--         ON pr.id = pre.payment_record_id
--     WHERE pr.bank_transaction_ids IN
--         -- Filter by bank_transaction_ids list (OR LIKE chain)
--         (
--          SELECT je_bank_transaction_id
--         FROM unmatched_bt_ids
--         )
--         -- ADD THE DATE FILTER HERE TO EXCLUDE ROWS AFTER THE PERIOD END
--         AND pr.bank_transaction_date IS NOT NULL -- Also excludes records with NULL dates

-- ),
-- AggregatedData AS (
--     -- Perform your original aggregation and calculations on the FILTERED data
--     SELECT
--         bank_account,
--         bank_transaction_ids,
--         transaction_category,
--         -- Your original CASE logic for exclusion_reason (simplified as date is filtered)
--         CASE
--             -- Check if the record MEETS ALL the inclusion criteria (Date condition implicitly met by FilteredData)
--             WHEN
--                 reconciled IS TRUE
--                 AND transaction_category IS NOT NULL
--                 AND transaction_category NOT IN ('Balance Transfer','Internal Transfer','Invoices')
--                 AND (bank_account NOT LIKE '%corporate%' AND bank_account NOT LIKE '%health_insurance%' AND bank_account NOT LIKE '%flex_pay%')
--                 AND on_behalf_of_id IS NOT NULL
--                 AND on_behalf_of_id NOT IN ('7757616923524413','7757616923492312','2','7757616923899880')
--             THEN 'Should Include'

--             -- Otherwise, check the specific reasons for exclusion (Date reasons removed as they are filtered)
--             WHEN payment_record_id IS NULL THEN 'Excluded: No matching payment_record_entry'
--             WHEN transaction_category IS NULL THEN 'Excluded: transaction_category is null'
--             WHEN transaction_category IN ('Balance Transfer','Internal Transfer','Invoices') THEN 'Excluded: transaction_category in exclusion list'
--             WHEN on_behalf_of_id IS NULL THEN 'Excluded: on_behalf_of_of_id is null'
--             WHEN on_behalf_of_id IN ('7757616923524413','7757616923492312','2','7757616923899880') THEN 'Excluded: on_behalf_of_id in exclusion list'
--             WHEN reconciled IS NOT TRUE THEN 'Excluded: reconciled is not true' -- Catches FALSE or NULL
--             WHEN bank_account LIKE '%corporate%' OR bank_account LIKE '%health_insurance%' OR bank_account LIKE '%flex_pay%' THEN 'Excluded: bank_account matches exclusion pattern'

--             -- Fallback reason (should ideally not be hit if all conditions are covered and date is filtered)
--             ELSE 'Excluded: Other unspecified reason' -- Catch any remaining exclusions
--         END AS exclusion_reason,
--         COUNT(*) AS record_count,
--         COUNT(DISTINCT id) AS distinct_payment_records_count, -- Count pr.id directly from the CTE
--         SUM(
--             CASE
--                 WHEN payment_direction = 0 THEN amount
--                 WHEN payment_direction = 1 THEN -amount
--                 ELSE 0
--             END
--         ) AS net_sum_amount
--     FROM
--         FilteredData -- Aggregate from the filtered data
--     GROUP BY
--         bank_account,
--         bank_transaction_ids,
--         transaction_category,
--         exclusion_reason
-- ),
-- TotalDistinctCount AS (
--     -- Calculate the total distinct count from the *same* filtered data (after date filter)
--     SELECT
--         COUNT(DISTINCT bank_transaction_ids) AS total_distinct_bank_transactions_in_results
--     FROM
--         FilteredData
-- )
-- -- Finally, select from the aggregated data and cross join the single row from the total count CTE
-- SELECT
--     ad.bank_account,
--     ad.bank_transaction_ids,
--     ad.transaction_category,
--     ad.exclusion_reason,
--     --ad.record_count,
--     --ad.distinct_payment_records_count,
--     --tdc.total_distinct_bank_transactions_in_results, -- Add the total count from the other CTE
--     ad.net_sum_amount
-- FROM
--     AggregatedData ad
-- CROSS JOIN TotalDistinctCount tdc -- CROSS JOIN adds the single row from TotalDistinctCount to every row of AggregatedData
-- ORDER BY
--     ad.bank_account,
--     ad.bank_transaction_ids;
