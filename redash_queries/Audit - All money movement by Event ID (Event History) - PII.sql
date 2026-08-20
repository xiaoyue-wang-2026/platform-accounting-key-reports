-- redash #128030
-- Database: _EDW Raw

SELECT
  c.name AS company_name,
  pre.on_behalf_of_id || 'x' AS company_id,
  pre.event_id || 'x' AS event_id,
  pre.transaction_category,
  pr.transaction_type,
  pr.transmission_type,
  ne.nacha_batch_id || 'x' AS nacha_batch_id,
  pr.transmission_id || 'x' AS pr_transmission_id, /* NE id, check/elec payment entries id */
  pr.bank_transaction_date,
  pr.bank_transaction_ids,
  pr.bank_account,
  SUM(
    CASE
      WHEN pre.payment_direction = 0
      THEN pre.amount
      WHEN pre.payment_direction = 1
      THEN -(
        pre.amount
      )
      ELSE 0
    END
  ) AS amount
FROM zenpayroll_production.payment_record_entries AS pre
JOIN bi.payment_records AS pr
  ON pre.payment_record_id = pr.id
LEFT JOIN zenpayroll_production.nacha_entries AS ne
  ON (
    pr.transmission_id = ne.id AND transmission_type = 'NachaEntry'
  )
LEFT JOIN bi.companies AS c
  ON c.id = pr.on_behalf_of_id
WHERE
  NOT pre.event_id IS NULL
  AND reconciled = TRUE
  AND pre.event_id IN (7757500933263435, 7757500928445977, 7757500933894253) /* update event_ids from audit selection */
  AND pre.transaction_category = 'Tax Payment'
GROUP BY
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11
ORDER BY
  9,
  8 ASC
