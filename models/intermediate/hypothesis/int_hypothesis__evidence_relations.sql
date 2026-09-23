{{ config(materialized='view') }}

with relation_contract as (

    select
        cast(null as string) as hypothesis_id,

        cast(null as string) as evidence_scope,
        cast(null as string) as evidence_type,

        cast(null as string) as symbol,

        cast(null as date) as evidence_event_date,
        cast(null as timestamp) as evidence_event_start_utc,
        cast(null as timestamp) as evidence_available_utc,

        cast(null as string) as relation_type,

        cast(null as string) as relation_reason

)

select *
from relation_contract
where false
