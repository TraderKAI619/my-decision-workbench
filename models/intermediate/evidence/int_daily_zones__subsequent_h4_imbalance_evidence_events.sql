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

    interaction_start_utc,
    interaction_available_utc,

    touched_zone,
    entered_zone,
    fully_traversed_zone,
    penetration_depth,
    previous_close_location,
    close_location,

    subsequent_imbalance_start_utc as event_start_utc,
    subsequent_imbalance_available_utc as event_available_utc,

    'SUBSEQUENT_H4_IMBALANCE_FORMED' as evidence_type,

    subsequent_imbalance_direction as evidence_direction,
    subsequent_imbalance_low as imbalance_low,
    subsequent_imbalance_high as imbalance_high,
    subsequent_imbalance_size as imbalance_size,
    subsequent_imbalance_size_pips as imbalance_size_pips,

    subsequent_imbalance_number

from {{ ref('int_daily_zone_h4_interaction_sequences') }}
