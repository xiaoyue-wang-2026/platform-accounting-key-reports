-- redash #4833
-- Database: _EDW Raw

select
bi.bank_account,
zp.id,
bi.date,
zp.description,
zp.type_description,
zp.bank_reference,
bi.signed_amount

from zenpayroll_production.bank_transactions as zp
INNER JOIN bi.bank_transactions as bi on bi.id = zp.id

where 
bi.bank_account = 'Chase operations'
and zp.bank_reference in 
('1190282511TC',
'1211182066TC',
'1211182066TC',
'1262445773TC',
'1338202662TC',
'1404604013TC',
'1486903659TC',
'1540189174TC',
'1625407522TC',
'1688578613TC',
'1755227014TC',
'1823291677TC',
'1895784674TC',
'1966603450TC',
'2034328737TC',
'2100263841TC',
'2173026060TC',
'2244041619TC',
'2314009216TC',
'2389884531TC',
'2421688183TC',
'2524066972TC',
'2599344884TC',
'2666856952TC',
'2734410031TC',
'2805555621TC',
'2848178374TC',
'2940328076TC',
'3014348013TC')
group by 1,2,3,4,5,6,7
