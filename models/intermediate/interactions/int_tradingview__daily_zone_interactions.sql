{{ config(materialized='view') }}

with zones as (

    select *

    from {{ ref('int_tradingview__daily_imbalance_zones') }}

),

daily_bars as (

    select
        source,
        provider,
        symbol,
        timeframe,
        analytical_date,
        open,
        high,
        low,
        close

    from {{ ref('int_tradingview__daily_market_facts') }}

),

zone_bar_pairs as (

    select
        z.source,
        z.provider,
        z.symbol,
        z.timeframe,

        z.zone_formed_date,
        z.zone_direction,
        z.zone_low,
        z.zone_high,
        z.zone_size,
        z.zone_size_pips,

        b.analytical_date as interaction_date,

        b.open as bar_open,
        b.high as bar_high,
        b.low as bar_low,
        b.close as bar_close

    from zones z

    inner join daily_bars b
        on z.source = b.source
       and z.provider = b.provider
       and z.symbol = b.symbol
       and z.timeframe = b.timeframe
       and b.analytical_date > z.zone_formed_date

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

    from zone_bar_pairs

)

select *

from interaction_facts
