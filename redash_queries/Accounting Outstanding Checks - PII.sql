-- redash #126050
-- Database: _EDW Raw

select 
  case oa.id when 19 then 'Blueridge operations old' when 20 then 'Blueridge corporate old' when 26 then 'Blueridge operations new' when 27 then 'Blueridge corporate new' else ob.name || ' ' || oa.purpose end as bank_account,
  cp.id as panda_cp_id,
  cp.payment_date as check_date,
--   cp.name,
cp.description,
  cp.number as printed_check_no,
  CASE 
    WHEN cp.payment_direction = 0 then cp.amount
    WHEN cp.payment_direction= 1 then -cp.amount
    ELSE null END as cp_amount, 
  cp.deposit_date,
  cp.processing_state,
  bt.date as bt_date,
  round(bt.signed_amount,2) as bt_amount


FROM zenpayroll_production.check_payment_entries AS cpe 
INNER JOIN zenpayroll_production.check_payments AS cp ON cpe.check_payment_id = cp.id
LEFT JOIN bi.payment_records as pr ON cpe.id = pr.transmission_id AND pr.transmission_type = 'CheckPaymentEntry'
LEFT JOIN zenpayroll_production.payment_records pr2 on pr2.id = pr.id
LEFT JOIN zenpayroll_production.origination_accounts oa on oa.id = pr2.origination_account_id
LEFT JOIN zenpayroll_production.origination_banks ob on ob.id = oa.origination_bank_id
LEFT JOIN zenpayroll_production.reconciliations AS rec ON rec.record_id = cp.id AND rec.record_type = 'CheckPayment'
LEFT JOIN bi.bank_transactions AS bt ON bt.id = rec.transaction_id

WHERE
  cp.processing_state = 'sent' --excludes voided and unapproved
  and pr.bank_account not like '%corporate%' and pr.bank_account not like '%health_insurance%' and pr.bank_account not like '%flex_pay%' -- updated Jan-2021 to include new PNC bank accounts
--   and pr.bank_account in ('SVB operations','Chase operations','PNC operations')
  and cp.print_date <= '{{period_end_date}}'
  and ((bt.date > '{{period_end_date}}') OR bt.date is null )
group by 1,2,3,4,5,6,7,8,9,10

