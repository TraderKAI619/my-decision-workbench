with actual as (

    select *

    from {{ ref('int_tradingview__daily_evidence_events') }}

    where source = 'TRADINGVIEW'
      and provider = 'OANDA'
      and symbol = 'USDJPY'

),

daily_up_imbalance_error as (

    select
        count(*) as matching_rows

    from actual

    where event_date = date('2026-08-11')
      and evidence_type = 'DAILY_UP_IMBALANCE_FORMED'
      and evidence_direction = 'UP'
      and abs(zone_low - 158.575) < 0.000001
      and abs(zone_high - 158.921) < 0.000001
      and abs(zone_size_pips - 34.6) < 0.000001

    having count(*) != 1

),

recovery_50_error as (

    select
        count(*) as matching_rows

    from actual

    where event_date = date('2026-08-18')
      and evidence_type = 'RECOVERY_50_REACHED_BY_CLOSE'
      and move_direction = 'DOWN'
      and move_sequence = 6
      and impulse_start_date = date('2026-07-30')
      and abs(move_origin_price - 163.988) < 0.000001
      and abs(current_extreme_price - 155.226) < 0.000001
      and abs(current_move_size - 8.762) < 0.000001
      and abs(reference_price - 159.607) < 0.000001
      and abs(evidence_value - 0.5022825838849589) < 0.000001

    having count(*) != 1

)

select
    'DAILY_UP_IMBALANCE_FORMED' as failed_contract,
    matching_rows
from daily_up_imbalance_error

union all

select
    'RECOVERY_50_REACHED_BY_CLOSE' as failed_contract,
    matching_rows
from recovery_50_error
