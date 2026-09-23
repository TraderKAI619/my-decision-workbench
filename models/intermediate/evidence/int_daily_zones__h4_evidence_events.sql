{{ config(materialized='view') }}

select
    zone_source,
    zone_provider,
    symbol,
    zone_timeframe,

    zone_formed_date,
    zone_direction,
    zone_low,
    zone_high,
    zone_size,
    zone_size_pips,

    reaction_source,
    reaction_timeframe,
    segment_id,

    bar_start_utc as event_start_utc,
    bar_available_utc as event_available_utc,

    'DAILY_ZONE_H4_INTERACTION' as evidence_type,

    bar_open,
    bar_high,
    bar_low,
    bar_close,
    candle_direction,

    touched_zone,
    entered_zone,
    fully_traversed_zone,
    penetration_depth,

    previous_close_location,
    close_location,

    h4_has_imbalance,
    h4_imbalance_direction,
    h4_imbalance_low,
    h4_imbalance_high,
    h4_imbalance_size,
    h4_imbalance_size_pips

from {{ ref('int_daily_zones__h4_interactions') }}

where touched_zone = true
   or entered_zone = true
   or fully_traversed_zone = true
   or previous_close_location is distinct from close_location
