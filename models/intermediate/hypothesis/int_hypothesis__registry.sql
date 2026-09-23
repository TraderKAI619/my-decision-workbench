{{ config(materialized='view') }}

with hypothesis_contract as (

    select
        cast(null as string) as hypothesis_id,

        cast(null as string) as symbol,

        cast(null as string) as hypothesis_family,
        cast(null as string) as hypothesis_type,
        cast(null as string) as hypothesis_direction,

        cast(null as string) as trigger_type,

        cast(null as date) as trigger_date,
        cast(null as timestamp) as trigger_start_utc,
        cast(null as timestamp) as trigger_available_utc,

        cast(null as date) as hypothesis_created_date,
        cast(null as timestamp) as hypothesis_created_utc,

        cast(null as string) as temporal_granularity,
        cast(null as string) as availability_precision,

        cast(null as string) as hypothesis_status,

        cast(null as string) as source_context_type,
        cast(null as string) as source_context_id

)

select *
from hypothesis_contract
where false
