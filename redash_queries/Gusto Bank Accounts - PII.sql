-- redash #162336
-- database shown in Redash: _EDW Raw


/* 

    Created By: Data Engineering | Lucy Lee 
    Created On: May-5-2026
    
    Updated By: Data Engineering | Lucy Lee
    Updated On: May-26-2026
    
    Owner: TBD (Platform Accounting Data Analyst)
    
    Legacy code: https://redash.zp-int.com/queries/126010/source
    
    Change description: 
        Replaced direct joins to zenpayroll_production.origination_banks and zenpayroll_production.origination_accounts 
        with bi_uat.dim_origination_account,                                                                                                                                   
        which already embeds origination_bank_name — dropping both zenpayroll source table dependencies entirely.       
    
    Data sanity checks
        - row counts: passed
        - idempotency check: passed
        
    Note:
        - origination_account_id = 33, 34 (Chase & PNC test accounts) have null effective_from in the legacy; refactor has valid dates.

*/

SELECT
    dim_origination_account.origination_account_id,
    dim_origination_account.origination_bank_name AS bank,
    dim_origination_account.account_purpose AS purpose,
    dim_origination_account.origination_bank_name || ' ' || dim_origination_account.account_purpose AS combined,
    dim_origination_account.account_type,
    CAST(dim_origination_account.account_effective_from_ts AS DATE) AS effective_from,
    dim_origination_account.closed_flag,
    dim_origination_account_pii.routing_number,
    dim_origination_account_pii.account_number
FROM bi.dim_origination_account AS dim_origination_account
LEFT JOIN bi_pii.dim_origination_account AS dim_origination_account_pii
    ON dim_origination_account.origination_account_id = dim_origination_account_pii.origination_account_id
ORDER BY
    dim_origination_account.origination_account_id ASC
;

