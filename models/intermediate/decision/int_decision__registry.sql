{{ config(materialized='view') }}

with decision_contract as (

    select
        cast(null as string) as decision_id,

        cast(null as string) as symbol,

        cast(null as string) as decision_type,
        cast(null as string) as decision_direction,

        cast(null as date) as decision_date,
        cast(null as timestamp) as decision_utc,

        cast(null as string) as temporal_granularity,
        cast(null as string) as availability_precision,

        cast(null as string) as decision_status,

        cast(null as string) as primary_hypothesis_id,

        cast(null as float64) as entry_price,
        cast(null as timestamp) as entry_utc,

        cast(null as string) as source_record_type,
        cast(null as string) as source_record_id

)

select *

from decision_contract

where false
