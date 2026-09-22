{{ config(materialized='view') }}

with daily_zones as (

    select
        source as zone_source,
        provider as zone_provider,
        symbol,
        timeframe as zone_timeframe,
        zone_formed_date,
        zone_direction,
        zone_low,
        zone_high,
        zone_size,
        zone_size_pips

    from {{ ref('int_tradingview__daily_imbalance_zones') }}

),

h4_bars as (

    select
        source as reaction_source,
        symbol,
        timeframe as reaction_timeframe,
        bar_start_utc,
        bar_available_utc,
        segment_id,
        open,
        high,
        low,
        close,
        candle_direction,
        has_imbalance,
        imbalance_direction,
        imbalance_low,
        imbalance_high,
        imbalance_size,
        imbalance_size_pips

    from {{ ref('int_dukascopy__h4_market_facts') }}

),

zone_h4_pairs as (

    select
        z.zone_source,
        z.zone_provider,
        z.symbol,
        z.zone_timeframe,
        z.zone_formed_date,
        z.zone_direction,
        z.zone_low,
        z.zone_high,
        z.zone_size,
        z.zone_size_pips,

        h.reaction_source,
        h.reaction_timeframe,
        h.bar_start_utc,
        h.bar_available_utc,
        h.segment_id,
        h.open as bar_open,
        h.high as bar_high,
        h.low as bar_low,
        h.close as bar_close,
        h.candle_direction,

        h.has_imbalance as h4_has_imbalance,
        h.imbalance_direction as h4_imbalance_direction,
        h.imbalance_low as h4_imbalance_low,
        h.imbalance_high as h4_imbalance_high,
        h.imbalance_size as h4_imbalance_size,
        h.imbalance_size_pips as h4_imbalance_size_pips

    from daily_zones z

    inner join h4_bars h
        on z.symbol = h.symbol

    where date(h.bar_start_utc) > z.zone_formed_date

),

interaction_facts as (

    select
        *,

        bar_high >= zone_low
            and bar_low <= zone_high
            as touched_zone,

        bar_high > zone_low
            and bar_low < zone_high
            as entered_zone,

        bar_high >= zone_high
            and bar_low <= zone_low
            as fully_traversed_zone,

        case
            when zone_direction = 'UP' then
                case
                    when bar_low >= zone_high then 0.0
                    when bar_low <= zone_low then 1.0
                    else safe_divide(
                        zone_high - bar_low,
                        zone_high - zone_low
                    )
                end

            when zone_direction = 'DOWN' then
                case
                    when bar_high <= zone_low then 0.0
                    when bar_high >= zone_high then 1.0
                    else safe_divide(
                        bar_high - zone_low,
                        zone_high - zone_low
                    )
                end

            else null
        end as penetration_depth,

        case
            when bar_close > zone_high then 'ABOVE'
            when bar_close < zone_low then 'BELOW'
            else 'INSIDE'
        end as close_location

    from zone_h4_pairs

),

with_transitions as (

    select
        *,

        lag(close_location) over (
            partition by
                zone_source,
                zone_provider,
                symbol,
                zone_timeframe,
                zone_formed_date,
                reaction_source,
                reaction_timeframe,
                segment_id
            order by bar_start_utc
        ) as previous_close_location

    from interaction_facts

)

select *
from with_transitions
