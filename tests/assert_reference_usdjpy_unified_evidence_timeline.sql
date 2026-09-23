with actual as (

    select *

    from {{ ref('int_evidence__events') }}

    where symbol = 'USDJPY'
      and provider = 'OANDA'

),

daily_imbalance_error as (

    select count(*) as matching_rows

    from actual

    where evidence_scope = 'DAILY'
      and evidence_type = 'DAILY_UP_IMBALANCE_FORMED'
      and event_date = date('2026-08-11')
      and temporal_granularity = 'DAILY'
      and availability_precision = 'DATE_ONLY'
      and event_start_utc is null
      and event_available_utc is null
      and evidence_direction = 'UP'
      and abs(zone_low - 158.575) < 0.000001
      and abs(zone_high - 158.921) < 0.000001

    having count(*) != 1

),

recovery_error as (

    select count(*) as matching_rows

    from actual

    where evidence_scope = 'DAILY'
      and evidence_type = 'RECOVERY_50_REACHED_BY_CLOSE'
      and event_date = date('2026-08-18')
      and temporal_granularity = 'DAILY'
      and availability_precision = 'DATE_ONLY'
      and event_start_utc is null
      and event_available_utc is null
      and context_date = date('2026-07-30')
      and abs(evidence_value - 0.5022825838849589) < 0.000001
      and abs(reference_price - 159.607) < 0.000001

    having count(*) != 1

),

h4_interaction_error as (

    select count(*) as matching_rows

    from actual

    where evidence_scope = 'H4_INTERACTION'
      and evidence_type = 'DAILY_ZONE_H4_INTERACTION'
      and event_start_utc = timestamp('2026-08-20 13:00:00+00')
      and event_available_utc = timestamp('2026-08-20 17:00:00+00')
      and temporal_granularity = 'H4'
      and availability_precision = 'EXACT_TIMESTAMP'
      and context_date = date('2026-08-11')
      and segment_id = 223
      and abs(evidence_value - 1.0) < 0.000001
      and abs(zone_low - 158.575) < 0.000001
      and abs(zone_high - 158.921) < 0.000001

    having count(*) != 1

),

h4_imbalance_error as (

    select count(*) as matching_rows

    from actual

    where evidence_scope = 'H4_IMBALANCE'
      and evidence_type = 'SUBSEQUENT_H4_IMBALANCE_FORMED'
      and event_start_utc = timestamp('2026-08-20 17:00:00+00')
      and event_available_utc = timestamp('2026-08-20 21:00:00+00')
      and temporal_granularity = 'H4'
      and availability_precision = 'EXACT_TIMESTAMP'
      and evidence_direction = 'UP'
      and context_date = date('2026-08-11')
      and context_start_utc = timestamp('2026-08-20 13:00:00+00')
      and context_available_utc = timestamp('2026-08-20 17:00:00+00')
      and segment_id = 223
      and abs(zone_low - 158.799) < 0.000001
      and abs(zone_high - 158.969) < 0.000001

    having count(*) != 1

)

select 'DAILY_UP_IMBALANCE' as failed_contract, matching_rows
from daily_imbalance_error

union all

select 'RECOVERY_50', matching_rows
from recovery_error

union all

select 'H4_INTERACTION', matching_rows
from h4_interaction_error

union all

select 'H4_IMBALANCE', matching_rows
from h4_imbalance_error
