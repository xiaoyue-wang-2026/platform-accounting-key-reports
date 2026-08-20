-- redash #45467
-- Database: _EDW Raw

select
zp.id,
bi.type_description,
bi.bank_account,
bi.signed_amount,
DATE_TRUNC('day', bi.date) as bank_transaction_date,
zp.description,
zp.bank_reference


from zenpayroll_production.bank_transactions as zp
INNER JOIN bi.bank_transactions as bi on bi.id = zp.id

where zp.id in ('15161200',
'15169405',
'15248457',
'15253034',
'15257024',
'15450697',
'16149377',
'16159233',
'17089283',
'17726403',
'17734831',
'17763288',
'17779793',
'17785460',
'17793032',
'18026166',
'18037257',
'18056791',
'18242986',
'18346300',
'18494164',
'18500759')


-- bank account names as of 6.28.18
-- SVB health_insurance
-- Chase corporate
-- Chase recovery
-- SVB wire_in
-- Chase wire_in
-- Chase flex_pay
-- SVB corporate
-- SVB operations
-- Chase operations
-- Chase payroll_incoming_wires
