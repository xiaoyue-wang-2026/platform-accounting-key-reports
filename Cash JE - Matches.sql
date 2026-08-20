-- redash #126982
-- Database: _EDW Raw

-- BT and JE Reconciliation Analysis Query

-- Objective: Identify transactions present in both Bank (BT) data and GL JEs.
-- Classify each transaction as:
-- - 'Matched' (found in both datasets)
-- - 'Unmatched BT' (only in BT data)
-- - 'Unmatched JE' (only in JE data)

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
select * from get_matches WHERE scenario = 'Matched'

