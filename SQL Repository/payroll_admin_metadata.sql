WITH 

-- Get pay (1) minimum pay schedule, # of pay schedules, and autopilot flag 
pay_periods AS (
    SELECT 
        company_id,
        CASE MIN(pp.pay_period_num) 
            WHEN 1 THEN 'Every week' 
            WHEN 2 THEN 'Every other week' 
            WHEN 3 THEN 'Twice per month' 
            WHEN 4 THEN 'Monthly' 
            WHEN 5 THEN 'Quarterly'
            WHEN 6 THEN 'Annually' 
        END AS shortest_pay_period,
        COUNT(DISTINCT ps.pay_period) AS pay_period_ct,
        CASE 
            WHEN SUM(CASE WHEN is_auto_pilot = TRUE THEN 1 ELSE 0 END) > 0 THEN 'Y' 
            ELSE 'N' 
        END AS has_auto_pilot
    FROM bi.pay_schedules ps
    INNER JOIN scratch.mz_pay_periods pp
        ON ps.pay_period = pp.pay_period
    WHERE is_active = TRUE AND current_flag = TRUE
    GROUP BY ps.company_id
),

-- Get flag for Gusto Wallet users
wallet_users AS (
    SELECT DISTINCT user_id, wallet_user 
    FROM bi.monthly_employees 
    WHERE for_month = (SELECT MAX(for_month) FROM bi.monthly_employees)
        AND wallet_user = TRUE
),

-- Get events for finishing payroll by device
events_base AS (
    SELECT DISTINCT
        gat.event_id,
        gat.user_id,
        comp.id AS company_id,
        gat.os_name,
        gat.device_type
    FROM snowplow_facts.ga_track_90_days gat
    INNER JOIN bi.payroll_admins pa
        ON gat.user_id = pa.user_id
    INNER JOIN bi.companies comp
        ON pa.company_id = comp.id
    WHERE gat.action = 'FinishedRunningPayroll'
        AND comp.is_active = TRUE
        AND pa.current_flag = TRUE
        AND pa.primary_payroll_admin = TRUE
),

-- Consolidate user profile for payroll completion by device
user_devices AS (
    SELECT
        user_id,
        company_id,
        COUNT(DISTINCT device_type) AS device_ct,
        COUNT(DISTINCT CASE WHEN os_name = 'iOS' THEN 'iOS' END) AS has_ios,
        COUNT(DISTINCT CASE WHEN os_name = 'Android' THEN 'Android' END) AS has_android,
        COUNT(DISTINCT event_id) AS payroll_ct,
        COUNT(DISTINCT CASE WHEN device_type = 'Computer' THEN event_id END) AS computer_ct,
        COUNT(DISTINCT CASE WHEN device_type IN ('Mobile', 'Tablet') THEN event_id END) AS mobile_ct
    FROM events_base
    GROUP BY user_id, company_id
),

-- Get events for logging in by device
login_base AS (
    SELECT DISTINCT
        gat.user_id,
        comp.id AS company_id,
        gat.device_type
    FROM snowplow_facts.ga_track_90_days gat
    INNER JOIN bi.payroll_admins pa
        ON gat.user_id = pa.user_id
    INNER JOIN bi.companies comp
        ON pa.company_id = comp.id
    WHERE gat.has_signed_in = TRUE
        AND comp.is_active = TRUE
        AND pa.current_flag = TRUE
        AND pa.primary_payroll_admin = TRUE
),

-- Consolidate user profile for logging in by device
login_devices AS (
    SELECT
        user_id,
        company_id,
        COUNT(CASE WHEN device_type = 'Computer' THEN 1 END) AS computer_login_flg,
        COUNT(CASE WHEN device_type IN ('Mobile', 'Tablet') THEN 1 END) AS mobile_login_flg
    FROM events_base
    GROUP BY user_id, company_id
),

-- Get time tracking flag 
time_tracking AS (
    SELECT DISTINCT
        company_id
    FROM bi.integrated_journey_monthly_features_companies fmc
    WHERE fmc.for_month BETWEEN '2024-09-01' AND '2024-11-01'
        AND won_indicator = 1
        AND feature_key IN (2, 17)
),

-- Get current onboarding and risk payroll blockers
payroll_blockers AS (
    SELECT company_id, 
        COUNT(DISTINCT CASE WHEN payroll_blocker_type = 'onboarding' THEN reason END) AS payroll_onboarding_blocker_ct,
        COUNT(DISTINCT CASE WHEN payroll_blocker_type = 'risk' THEN reason END) AS payroll_risk_blocker_ct
    FROM zenpayroll_production_no_pii.cached_payroll_blockers pb 
    INNER JOIN scratch.mz_payroll_blockers pbt
        ON pb.reason = pbt.payroll_blocker_desc
    WHERE tx_end > CURRENT_TIMESTAMP
    GROUP BY company_id
),

-- Get number of active EEs/contractors/salary/hourly
gusto_company_data AS (
    SELECT 
        company_id,
        payroll_admins_type,
        MAX(gcd.number_of_payroll_employees) AS number_active_employees,
        MAX(gcd.number_of_payroll_contractors) AS number_active_contractors,
        MAX(gcd.hourly_employees) AS number_hourly_employees,
        MAX(gcd.salary_employees) AS number_salary_employees
    FROM bi_reporting.gusto_company_data gcd
    WHERE for_month IN ('2024-11-01')
        AND joined_at IS NOT NULL
    GROUP BY company_id, payroll_admins_type
),

-- Get current product plan for customer
product_plans AS (
    SELECT DISTINCT company_id,
        plan_name
    FROM bi.company_product_tiers
    WHERE current_flag = TRUE 
        AND effect_end_dt > CURRENT_TIMESTAMP
),

-- Get 3M avg number of regular payrolls, 3M sum of irregular payrolls, and flag if regular payroll is consistent across last 3 months
payroll_history AS (
    SELECT 
        company_id,
        AVG(number_of_regular_payrolls) AS regular_payrolls_3m_avg,
        CASE WHEN COUNT(DISTINCT number_of_regular_payrolls) = 1 THEN 'Y' ELSE 'N' END AS payroll_schedule_is_consistent,
        SUM(number_of_irregular_payrolls) AS irregular_payroll_ct_3m
    FROM bi.monthly_company_payrolls 
    WHERE created_month IN ('2024-09-01', '2024-10-01', '2024-11-01')
    GROUP BY company_id
),

--Get users who use third party logins (google, xero, intuit)
third_party_logins as (
    SELECT DISTINCT user_id
    FROM snowplow_facts.ga_track_7_days 
    WHERE
      ((ACTION = 'GoogleOAuth')
      OR 
      (ACTION IN ('VisitedLoginPage','LoginClicked') AND referral_url IN ('https//go.xero.com/','https://appcenter.intuit.com/')))
      AND has_signed_in = TRUE
)      

-- FINAL QUERY
SELECT DISTINCT
    pa.user_id,
    --zur.first_name,
    zu.email,
    comp.id AS company_id,
    comp.name AS company_name,
    comp.accounting_firm_id,
    comp.industry_classification,
    comp.industry_title,
    pp.shortest_pay_period,
    pp.pay_period_ct,
    comp.filing_state AS company_state,
    DATEDIFF('month', comp.joined_at, CURRENT_DATE) AS company_age_months,
    comp.median_payroll_net_pay,
    CASE WHEN pa.primary_payroll_admin = TRUE THEN 'Y' ELSE 'N' END AS is_primary_payroll_admin,
    CASE WHEN pa.is_employee = TRUE THEN 'Y' ELSE 'N' END AS is_employee,
    CASE WHEN pa.is_contractor = TRUE THEN 'Y' ELSE 'N' END AS is_contractor,
    CASE WHEN pa.is_accountant = TRUE THEN 'Y' ELSE 'N' END AS is_accountant,
    CASE WHEN wu.wallet_user = TRUE THEN 'Y' ELSE 'N' END AS is_wallet_user,
    device_ct,
    CASE WHEN has_ios > 0 THEN 'Y' ELSE 'N' END AS has_ios,
    CASE WHEN has_android > 0 THEN 'Y' ELSE 'N' END AS has_android,
    payroll_ct,
    computer_ct,
    mobile_ct,
    payroll_onboarding_blocker_ct,
    payroll_risk_blocker_ct,
    gcd.payroll_admins_type,
    pp.has_auto_pilot,
    mobile_login_flg,
    computer_login_flg,
    CASE WHEN tt.company_id IS NOT NULL THEN 'Y' ELSE 'N' END AS has_time_tracking,
    gcd.number_active_employees,
    gcd.number_active_contractors,
    gcd.number_hourly_employees,
    gcd.number_salary_employees,
    prp.plan_name AS product_plan,
    regular_payrolls_3m_avg,
    payroll_schedule_is_consistent,
    irregular_payroll_ct_3m,
    CASE WHEN tpl.user_id IS NOT NULL THEN 'Y' ELSE 'N' END AS uses_third_party_login
    
FROM bi.payroll_admins pa
    INNER JOIN bi.companies comp
        ON pa.company_id = comp.id
    LEFT JOIN pay_periods pp 
        ON comp.id = pp.company_id
    LEFT JOIN wallet_users wu 
        ON pa.user_id = wu.user_id
    LEFT JOIN user_devices ud
        ON pa.user_id = ud.user_id
        AND comp.id = ud.company_id
    INNER JOIN zenpayroll_production.users zu
        ON pa.user_id = zu.id
    LEFT JOIN payroll_blockers pb 
        ON comp.id = pb.company_id
    LEFT JOIN gusto_company_data gcd    
        ON gcd.company_id = comp.id
    LEFT JOIN login_devices ld 
        ON pa.user_id = ld.user_id
        AND ld.company_id = comp.id 
    LEFT JOIN time_tracking tt
        ON comp.id = tt.company_id
    LEFT JOIN product_plans prp
        ON comp.id = prp.company_id
    LEFT JOIN payroll_history ph
        ON comp.id = ph.company_id
    LEFT JOIN third_party_logins tpl
        ON pa.user_id = tpl.user_id
WHERE
    pa.current_flag = TRUE
    AND pa.can_run_payroll = TRUE
    AND comp.current_flag = TRUE
    AND comp.is_active = TRUE
    AND comp.joined_at IS NOT NULL
    AND comp.id <> 7757616924789144
    AND pa.company_id NOT IN (
        SELECT DISTINCT company_id 
        FROM bi.gep_companies 
        WHERE is_active_er_today = TRUE
    );
