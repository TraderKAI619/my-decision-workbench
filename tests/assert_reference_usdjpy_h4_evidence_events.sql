with interaction_events as (

    select *

    from {{ ref('int_daily_zones__h4_evidence_events') }}

    where zone_provider = 'OANDA'
      and symbol = 'USDJPY'
      and zone_formed_date = date('2026-08-11')

),

subsequent_imbalance_events as (

    select *

    from {{ ref('int_daily_zones__subsequent_h4_imbalance_evidence_events') }}

    where zone_provider = 'OANDA'
      and symbol = 'USDJPY'
      and zone_formed_date = date('2026-08-11')

),

interaction_error as (

    select
        count(*) as matching_rows

    from interaction_events

    where event_start_utc = timestamp('2026-08-20 13:00:00+00')
      and event_available_utc = timestamp('2026-08-20 17:00:00+00')
      and segment_id = 223
      and evidence_type = 'DAILY_ZONE_H4_INTERACTION'
      and touched_zone = true
      and entered_zone = true
      and fully_traversed_zone = true
      and abs(penetration_depth - 1.0) < 0.000001
      and previous_close_location = 'INSIDE'
      and close_location = 'ABOVE'

    having count(*) != 1

),

subsequent_imbalance_error as (

    select
        count(*) as matching_rows

    from subsequent_imbalance_events

    where interaction_start_utc = timestamp('2026-08-20 13:00:00+00')
      and interaction_available_utc = timestamp('2026-08-20 17:00:00+00')
      and event_start_utc = timestamp('2026-08-20 17:00:00+00')
      and event_available_utc = timestamp('2026-08-20 21:00:00+00')
      and segment_id = 223
      and evidence_type = 'SUBSEQUENT_H4_IMBALANCE_FORMED'
      and evidence_direction = 'UP'
      and subsequent_imbalance_number = 1
      and abs(imbalance_low - 158.799) < 0.000001
      and abs(imbalance_high - 158.969) < 0.000001
      and abs(imbalance_size_pips - 17.0) < 0.000001

    having count(*) != 1

)

select
    'DAILY_ZONE_H4_INTERACTION' as failed_contract,
    matching_rows
from interaction_error

union all

select
    'SUBSEQUENT_H4_IMBALANCE_FORMED' as failed_contract,
    matching_rows
from subsequent_imbalance_error
