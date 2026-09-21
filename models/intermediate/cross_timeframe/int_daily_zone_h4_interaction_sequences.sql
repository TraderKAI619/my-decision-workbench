{{ config(materialized='view') }}

with interactions as (

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

        bar_start_utc as interaction_start_utc,
        bar_available_utc as interaction_available_utc,
        bar_open as interaction_open,
        bar_high as interaction_high,
        bar_low as interaction_low,
        bar_close as interaction_close,

        touched_zone,
        entered_zone,
        fully_traversed_zone,
        penetration_depth,
        previous_close_location,
        close_location

    from {{ ref('int_daily_zones__h4_interactions') }}

),

h4_imbalances as (

    select
        source,
        symbol,
        timeframe,
        segment_id,
        bar_start_utc,
        bar_available_utc,
        imbalance_direction,
        imbalance_low,
        imbalance_high,
        imbalance_size,
        imbalance_size_pips

    from {{ ref('int_dukascopy__h4_market_facts') }}

    where has_imbalance = true

),

sequence_candidates as (

    select
        i.*,

        h.bar_start_utc as subsequent_imbalance_start_utc,
        h.bar_available_utc as subsequent_imbalance_available_utc,
        h.imbalance_direction as subsequent_imbalance_direction,
        h.imbalance_low as subsequent_imbalance_low,
        h.imbalance_high as subsequent_imbalance_high,
        h.imbalance_size as subsequent_imbalance_size,
        h.imbalance_size_pips as subsequent_imbalance_size_pips

    from interactions i

    inner join h4_imbalances h
        on i.reaction_source = h.source
       and i.symbol = h.symbol
       and i.reaction_timeframe = h.timeframe
       and i.segment_id = h.segment_id
       and h.bar_start_utc >= i.interaction_available_utc

),

ranked_sequences as (

    select
        *,

        row_number() over (
            partition by
                zone_source,
                zone_provider,
                symbol,
                zone_timeframe,
                zone_formed_date,
                zone_direction,
                reaction_source,
                reaction_timeframe,
                segment_id,
                interaction_start_utc
            order by
                subsequent_imbalance_available_utc,
                subsequent_imbalance_start_utc
        ) as subsequent_imbalance_number

    from sequence_candidates

)

select *
from ranked_sequences
