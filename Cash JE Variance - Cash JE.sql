-- redash #126976
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

--select * from bt_data
WITH convert_date as (
   SELECT *,
        case 
             when bank_transaction_date != '' and bank_transaction_date like '%/%' 
                 and length(split_part(bank_transaction_date,'/',3)) = 4              
                 then to_date(bank_transaction_date,'MM/DD/YYYY')
             when bank_transaction_date != '' and bank_transaction_date like '%/%' 
                 and length(split_part(bank_transaction_date,'/',3)) = 2 
                 then to_date(bank_transaction_date,'MM/DD/YY')
             when bank_transaction_date != '' and bank_transaction_date like '%/%' 
                 then to_date(bank_transaction_date,'MM/DD/YY')
             when bank_transaction_date != '' and bank_transaction_date not like '%/%' 
                 then dateadd(day, bank_transaction_date:: integer, '1899-12-30'):: date
          else null 
          end as bank_transaction_date1
    FROM integrations_production.accounting_cash_je_listing
)

, je_data AS (
    SELECT 
        CAST(replace(REPLACE(REPLACE(net_usd_amount, ',', ''), '(', '-'),')','') AS FLOAT) AS amount,
        je_number,
        bank_transaction_id,
        origination_account_id,
        bank_transaction_date1 as bank_transaction_date
    FROM convert_date
    WHERE bank_transaction_date1 BETWEEN '{{start_date}}' AND '{{end_date}}'
)

select * from je_data

