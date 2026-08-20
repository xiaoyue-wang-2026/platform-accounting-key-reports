-- redash #129099
-- Database: _EDW Raw

select 
  date_trunc('month' , check_date)::date as month
, sum(gross_amount)

from bi.payrolls 
where check_date >= '2018-05-01'
and processing_state = 'paid'
and month = '{{YYYY-MM}}-01'
group by 1
order by 1 desc
