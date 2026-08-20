-- redash #128017
-- Database: _EDW Raw

SELECT
  bank_account,
  transmission_id,
  transmission_type,
  SUM(CASE WHEN pre.payment_direction = 0 THEN pre.amount ELSE -1 * pre.amount END) AS signed_amount
FROM zenpayroll_production.payment_record_entries AS pre
LEFT JOIN bi.payment_records AS pr
  ON pre.payment_record_id = pr.id
WHERE
  pre.transaction_category IN ('Invoices')
  AND pr.reconciled = TRUE
  AND NOT pr.bank_account LIKE '%corporate%'
  AND NOT pr.bank_account LIKE 'SVB%'
GROUP BY
  1,
  2,
  3
