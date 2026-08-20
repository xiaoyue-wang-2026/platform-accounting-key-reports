-- redash #164375
/*                                                                                                                                                                                                                                                   
                  
      Created By: Data Engineering | Lucy Lee
      Created On: May-7-2026
      Updated By: Data Engineering | Lucy Lee
      Updated On: Aug-17-2026 | Owner change
      
      Owner: Xiaoyue Wang                                                                                                                                                                                                 
  
      Legacy code: https://redash.zp-int.com/queries/126028/source?p_on_or_before_bank_transaction_date=2025-07-31                                                                                                                                                                                                                                     
                  
      Change description: 
        Replaced bi.bank_transactions with fct_bank_transaction.
        The join to zenpayroll_production.bank_transactions is dropped as fct_bank_transaction is based on its ZP source table.                                                                                                                                                                                                                
  
      Data sanity checks                                                                                                                                                                                                                               
          - row counts: passed
          - idempotency check: passed

  */
  
select
    fct_bank_transaction.bank_account,
    fct_bank_transaction.origination_account_id,
    fct_bank_transaction.reconcile_flag as reconciled,
    sum(fct_bank_transaction.transaction_signed_amount)

from bi.fct_bank_transaction as fct_bank_transaction

where
  fct_bank_transaction.bank_account not like '%corporate%'
  and fct_bank_transaction.bank_account not like '%health_insurance%'
  and fct_bank_transaction.bank_account not like '%flex_pay%'
  and fct_bank_transaction.origination_account_id <> 29
  and fct_bank_transaction.transaction_date <= '{{ on_or_before_bank_transaction_date }}'

group by 1,2,3
order by 1,2,3