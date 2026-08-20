-- redash #128039
-- Database: _EDW Raw

select
--com.name AS company_name,
pr.on_behalf_of_id||'x' AS company_id,
pre.event_id||'x' AS event_id,
pr.transaction_type,
pr.transmission_type,
-- nb.id||'x' AS nacha_batch_id,
pr.transmission_id||'x' as pr_transmission_id, -- NE id, check/elec payment entries id
-- CASE 
--   WHEN pr.transmission_type = 'CheckPaymentEntry' then cp.id||'x' else '-' end AS panda_check_payment_id_if_applicable,
-- CASE 
--   WHEN pr.transmission_type = 'ElectronicEntry' then ep.id||'x' else '-' end AS panda_electronic_payment_id_if_applicable,
-- CASE 
--   WHEN pr.transmission_type = 'NachaEntry' then '-' else pr.id||'x' end AS payment_record_id,
pre.transaction_category,
pre.event_id||'x'||pre.transaction_category as concatenate,
pr.bank_transaction_date,
-- CASE 
--   WHEN pr.transmission_type = 'CheckPaymentEntry' then bt.customer_reference||'x' else '-' end AS printed_check_number_if_applicable,
pr.bank_transaction_ids, 
pr.bank_account,
SUM(CASE
    WHEN pre.payment_direction = 0 THEN pre.amount
    WHEN pre.payment_direction = 1 THEN -(pre.amount)
    else 0
  END) AS amount
  
  
FROM zenpayroll_production.payment_record_entries     AS pre
INNER JOIN bi.payment_records                         AS pr  ON pre.payment_record_id = pr.id 
-- LEFT JOIN zenpayroll_production_no_pii.nacha_entries         AS ne  ON (pr.transmission_id = ne.id AND transmission_type = 'NachaEntry')
-- LEFT JOIN zenpayroll_production_no_pii.nacha_batches         AS nb  ON ne.nacha_batch_id = nb.id
-- LEFT JOIN zenpayroll_production_no_pii.nacha_files           AS nf  ON nb.nacha_file_id = nf.id
-- LEFT JOIN zenpayroll_production_no_pii.nacha_entry_returns   AS ner ON (pr.transmission_id = ner.id AND transmission_type = 'NachaEntryReturn')
-- LEFT JOIN zenpayroll_production_no_pii.check_payment_entries AS cpe ON (cpe.id = pr.transmission_id AND transmission_type = 'CheckPaymentEntry') 
-- LEFT JOIN zenpayroll_production_no_pii.check_payments        AS cp  ON cpe.check_payment_id = cp.id
-- LEFT JOIN zenpayroll_production_no_pii.wire_payments         AS wp  ON (pr.transmission_id = wp.id AND transmission_type = 'WirePayment')
-- LEFT JOIN zenpayroll_production_no_pii.electronic_entries    AS ees ON (pr.transmission_id = ees.id AND transmission_type = 'ElectronicEntry')
-- LEFT JOIN zenpayroll_production_no_pii.electronic_payments   AS ep  ON ep.id = ees.electronic_payment_id
-- LEFT JOIN zenpayroll_production_no_pii.check_payment_entry_returns AS cper ON cper.id = pr.transmission_id AND transmission_type = 'CheckPaymentEntryReturn'
-- LEFT JOIN zenpayroll_production_no_pii.check_payment_returns AS cpr ON cpr.id = cper.check_payment_return_id 
-- LEFT JOIN zenpayroll_production_no_pii.wire_payment_returns AS wpr ON wpr.id = pr.transmission_id AND pr.transmission_type = 'WirePaymentReturn'
-- left join zenpayroll_production_no_pii.international_wire_payments as iwp on iwp.id = rec.record_id and record_type = 	'InternationalContractorPayments::Db::InternationalWirePayment'
-- LEFT JOIN zenpayroll_production_no_pii.reconciliations       AS rec ON (
--                                                                 (rec.record_id = nb.id AND rec.record_type = 'NachaBatch') 
--                                                             OR (rec.record_id = ner.id AND rec.record_type = 'NachaEntryReturn')
--                                                             OR (rec.record_id = cp.id AND rec.record_type = 'CheckPayment')
--                                                             OR (rec.record_id = wp.id AND rec.record_type = 'WirePayment')
--                                                             OR (rec.record_id = ep.id AND rec.record_type = 'ElectronicPayment')
--                                                             OR (rec.record_id = cpr.id AND rec.record_type = 'CheckPaymentReturn')
--                                                             OR (rec.record_id = wpr.id AND rec.record_type = 'WirePaymentReturn')
--                                                                 )
-- LEFT JOIN zenpayroll_production_no_pii.bank_transactions     AS bt  ON bt.id = rec.transaction_id
LEFT JOIN bi.companies                                AS com ON com.id = pr.on_behalf_of_id 
WHERE 
  --     pre.event_id IS NOT NULL 
  -- AND pre.event_type IS NOT NULL 
  -- AND pr.on_behalf_of_type = 'Company'
  -- AND pr.bank_transaction_date => {on_or_after_date}
  -- AND pre.event_id = {eventid}
  -- AND pre.transaction_category = {trxn_category}
pr.bank_transaction_ids = '{{bt_id}}'


GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10--, 11--,12,13,14--,15


