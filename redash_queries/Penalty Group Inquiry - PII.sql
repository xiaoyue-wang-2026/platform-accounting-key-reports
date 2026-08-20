-- redash #126731
-- Database: _EDW Raw

SELECT
  pg.id AS penalty_group_id,
  -- pg.link AS penalty_group_link,
  pg.created_at::date as created_at,
  pc.title AS penalty_case_title,
  a.name AS agent_name,
  a.agent_payment_type,
  pc.quarter,
  pc.year,
  -- pc.lsi,
  pg.pay_to AS penalty_group_pay_to,
  pe.company_id||'x' as company_id,
  pe.penalized_agent_payment_id||'x' as penalized_agent_payment_id,
  pe.penalty_amount,
  pe.interest_amount,
  -- pe.memo AS penalty_entry_memo,
  -- ap.description AS agent_payment_description,
  pc.error_type AS penalty_case_error_type,
pt.transmission_id||'x' transmission_id,
pt.transmission_type,
ne.amount as ne_amount,
nb.entry_description,
nb.id||'x' as nacha_batch_id,
nb.total_credit,
nb.total_debit,
bt.bank_account,
bt.date as bank_transaction_date

,
case
    when a.agent_payment_type like '%State tax%'            then 'no_reclass - Gusto Inc - 50030 - 2330 TaxOps'
    when a.agent_payment_type like '%Federal tax%'          then 'no_reclass - Gusto Inc - 50030 - 2330 TaxOps'
    when a.agent_payment_type like '%Benefits Payment%'     then 'requires_reclass - Gusto Inc - 71003 - 2420 Operational Excellence'
    when pc.title             like '%#ATO%'                 then 'requires_reclass - ZenPayroll - 71003 - 1520 RiskOps'
    else 'requires_reclass - default _ Gusto Inc - 71003 - 2420 Operational Excellence' end
    as accounting_mapping

FROM zenpayroll_production.penalty_groups AS pg
 LEFT JOIN zenpayroll_production.penalty_cases   AS pc ON pg.penalty_case_id = pc.id
 left JOIN zenpayroll_production.agents          AS a  ON pc.agent_id = a.id
 LEFT JOIN zenpayroll_production.penalty_entries AS pe ON pg.id = pe.penalty_group_id
 left JOIN zenpayroll_production.agent_payments  AS ap ON pe.penalized_agent_payment_id = ap.id
left join zenpayroll_production.penalty_transmissions as pt on pt.penalty_entry_id = pe.id
LEFT JOIN zenpayroll_production.nacha_entries         AS ne  ON (pt.transmission_id = ne.id AND transmission_type = 'NachaEntry')
LEFT JOIN zenpayroll_production.nacha_batches         AS nb  ON ne.nacha_batch_id = nb.id
LEFT JOIN zenpayroll_production.nacha_files           AS nf  ON nb.nacha_file_id = nf.id
LEFT JOIN zenpayroll_production.nacha_entry_returns   AS ner ON (pt.transmission_id = ner.id AND transmission_type = 'NachaEntryReturn')
-- LEFT JOIN zenpayroll_production.check_payment_entries AS cpe ON (cpe.id = pt.transmission_id AND transmission_type = 'CheckPaymentEntry') 
LEFT JOIN zenpayroll_production.check_payments        AS cp  ON (cp.id = pt.transmission_id AND transmission_type = 'CheckPayment') 
-- LEFT JOIN zenpayroll_production.wire_payments         AS wp  ON (pr.transmission_id = wp.id AND transmission_type = 'WirePayment')
-- LEFT JOIN zenpayroll_production.electronic_entries    AS ees ON (pr.transmission_id = ees.id AND transmission_type = 'ElectronicEntry')
-- LEFT JOIN zenpayroll_production.electronic_payments   AS ep  ON ep.id = ees.electronic_payment_id
LEFT JOIN zenpayroll_production.check_payment_entry_returns AS cper ON cper.id = pt.transmission_id AND transmission_type = 'CheckPaymentEntryReturn'
LEFT JOIN zenpayroll_production.check_payment_returns AS cpr ON cpr.id = cper.check_payment_return_id 
-- LEFT JOIN zenpayroll_production.wire_payment_returns AS wpr ON wpr.id = pr.transmission_id AND pr.transmission_type = 'WirePaymentReturn'
LEFT JOIN zenpayroll_production.reconciliations       AS rec ON (
                                                                (rec.record_id = nb.id AND rec.record_type = 'NachaBatch') 
                                                            OR (rec.record_id = ner.id AND rec.record_type = 'NachaEntryReturn')
                                                            OR (rec.record_id = cp.id AND rec.record_type = 'CheckPayment')
                                                            -- OR (rec.record_id = wp.id AND rec.record_type = 'WirePayment')
                                                            -- OR (rec.record_id = ep.id AND rec.record_type = 'ElectronicPayment')
                                                            OR (rec.record_id = cpr.id AND rec.record_type = 'CheckPaymentReturn')
                                                            -- OR (rec.record_id = wpr.id AND rec.record_type = 'WirePaymentReturn')
                                                                )
LEFT JOIN bi.bank_transactions     AS bt  ON bt.id = rec.transaction_id
  
where 
  bt.date >= '{{on_or_after_date}}'
  and bt.date <= '{{period_end_date}}'
  and pt.transmission_type = 'NachaEntry'


-- ORDER BY pg.id DESC
