{{ config(materialized='view') }}

with outcome_contract as (

    select
        cast(null as string) as outcome_id,
        cast(null as string) as decision_id,

        cast(null as string) as symbol,

        cast(null as string) as outcome_status,

        cast(null as date) as observation_date,
        cast(null as timestamp) as observation_utc,

        cast(null as string) as temporal_granularity,
        cast(null as string) as availability_precision,

        cast(null as float64) as observed_low,
        cast(null as float64) as observed_high,
        cast(null as float64) as observed_last_price,

        cast(null as timestamp) as exit_utc,
        cast(null as float64) as exit_price,

        cast(null as float64) as realized_pnl,
        cast(null as float64) as realized_return,

        cast(null as string) as source_record_type,
        cast(null as string) as source_record_id

)

select *

from outcome_contract

where false
