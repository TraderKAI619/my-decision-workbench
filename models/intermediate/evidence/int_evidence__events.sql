{{ config(materialized='view') }}

with daily as (

    select
        'DAILY' as evidence_scope,
        evidence_type,

        source,
        provider,
        symbol,
        timeframe,

        event_date,

        cast(null as timestamp) as event_start_utc,
        cast(null as timestamp) as event_available_utc,

        'DAILY' as temporal_granularity,
        'DATE_ONLY' as availability_precision,

        evidence_direction,
        evidence_value,
        reference_price,

        impulse_start_date as context_date,
        cast(null as timestamp) as context_start_utc,
        cast(null as timestamp) as context_available_utc,

        zone_low,
        zone_high,

        cast(null as int64) as segment_id

    from {{ ref('int_tradingview__daily_evidence_events') }}

),

h4_interactions as (

    select
        'H4_INTERACTION' as evidence_scope,
        evidence_type,

        reaction_source as source,
        zone_provider as provider,
        symbol,
        reaction_timeframe as timeframe,

        date(event_start_utc) as event_date,

        event_start_utc,
        event_available_utc,

        'H4' as temporal_granularity,
        'EXACT_TIMESTAMP' as availability_precision,

        zone_direction as evidence_direction,
        penetration_depth as evidence_value,
        cast(null as float64) as reference_price,

        zone_formed_date as context_date,
        cast(null as timestamp) as context_start_utc,
        cast(null as timestamp) as context_available_utc,

        zone_low,
        zone_high,

        segment_id

    from {{ ref('int_daily_zones__h4_evidence_events') }}

),

h4_imbalances as (

    select
        'H4_IMBALANCE' as evidence_scope,
        evidence_type,

        reaction_source as source,
        zone_provider as provider,
        symbol,
        reaction_timeframe as timeframe,

        date(event_start_utc) as event_date,

        event_start_utc,
        event_available_utc,

        'H4' as temporal_granularity,
        'EXACT_TIMESTAMP' as availability_precision,

        evidence_direction,
        cast(null as float64) as evidence_value,
        cast(null as float64) as reference_price,

        zone_formed_date as context_date,
        interaction_start_utc as context_start_utc,
        interaction_available_utc as context_available_utc,

        imbalance_low as zone_low,
        imbalance_high as zone_high,

        segment_id

    from {{ ref('int_daily_zones__subsequent_h4_imbalance_evidence_events') }}

)

select * from daily

union all

select * from h4_interactions

union all

select * from h4_imbalances
