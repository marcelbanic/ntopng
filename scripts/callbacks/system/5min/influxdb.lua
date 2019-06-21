--
-- (C) 2013-19 - ntop.org
--

local ts_utils = require("ts_utils_core")

local MAX_INFLUX_EXPORT_QUEUE_LEN = 30

local probe = {
  name = "InfluxDB",
  description = "Monitors InfluxDB health and performance",
  page_script = "influxdb_stats.lua",
  page_order = 1600,
}

-- ##############################################

local function get_storage_size_query(influxdb, schema, tstart, tend, time_step)
  local q = 'SELECT SUM(disk_bytes) as disk_bytes from (SELECT MEAN(diskBytes) as disk_bytes' ..
      ' FROM "monitor"."shard" where "database"=\''.. influxdb.db ..'\' GROUP BY id, TIME('.. time_step ..'s)) WHERE ' ..
      " time >= " .. tstart .. "000000000 AND time <= " .. tend .. "000000000" ..
      " GROUP BY TIME(".. time_step .."s)"

  return(q)
end

local function get_memory_size_query(influxdb, schema, tstart, tend, time_step)
  local q = 'SELECT MEAN(Sys) as mem_bytes' ..
      ' FROM "_internal".."runtime"' ..
      " WHERE time >= " .. tstart .. "000000000 AND time <= " .. tend .. "000000000" ..
      " GROUP BY TIME(".. time_step .."s)"

  return(q)
end

local function get_write_success_query(influxdb, schema, tstart, tend, time_step)
  local q = 'SELECT SUM(writePointsOk) as points' ..
      ' FROM (SELECT '..
      ' (DERIVATIVE(MEAN(writePointsOk)) / '.. time_step ..') as writePointsOk' ..
      ' FROM "monitor"."shard" WHERE "database"=\''.. influxdb.db ..'\'' ..
      " AND time >= " .. tstart .. "000000000 AND time <= " .. tend .. "000000000" ..
      " GROUP BY id)" ..
      " GROUP BY TIME(".. time_step .."s)"

  return(q)
end

-- ##############################################

function probe.isEnabled()
  return(ts_utils.getDriverName() == "influxdb")
end

-- ##############################################

function probe.loadSchemas(ts_utils)
  local schema

  -- The following metrics are built-in into influxdb
  schema = ts_utils.newSchema("influxdb:storage_size", {
    influx_internal_query = get_storage_size_query,
    metrics_type = ts_utils.metrics.gauge, step = 10
  })
  schema:addMetric("disk_bytes")

  schema = ts_utils.newSchema("influxdb:memory_size", {
    influx_internal_query = get_memory_size_query,
    metrics_type = ts_utils.metrics.gauge, step = 10
  })
  schema:addMetric("mem_bytes")

  schema = ts_utils.newSchema("influxdb:write_successes", {
    influx_internal_query = get_write_success_query,
    metrics_type = ts_utils.metrics.counter, step = 10
  })
  schema:addMetric("points")

  schema = ts_utils.newSchema("influxdb:exported_points",
    {metrics_type = ts_utils.metrics.counter})
  schema:addMetric("points")

  schema = ts_utils.newSchema("influxdb:dropped_points", {metrics_type = ts_utils.metrics.counter})
  schema:addMetric("points")

  schema = ts_utils.newSchema("influxdb:rtt", {metrics_type = ts_utils.metrics.gauge})
  schema:addMetric("millis_rtt")
end

-- ##############################################

function probe.getTimeseriesMenu(ts_utils)
  local influxdb = ts_utils.getQueryDriver()

  return {
    {schema="influxdb:storage_size",                      label=i18n("system_stats.influxdb_storage", {dbname = influxdb.db})},
    {schema="influxdb:memory_size",                       label=i18n("memory")},
    {schema="influxdb:write_successes",                   label=i18n("system_stats.write_througput")},
    {schema="custom:infludb_exported_vs_dropped_points",  label=i18n("system_stats.exported_vs_dropped_points"),
      custom_schema = {
        bases = {"influxdb:exported_points", "influxdb:dropped_points"},
        types = {"area", "line"}, axis = {1,2},
      }
    },
    {schema="influxdb:rtt",                               label=i18n("graphs.num_ms_rtt")},
  }
end

-- ##############################################

function probe.getExportStats()
  local points_exported = 0
  local points_dropped = 0
  local ifnames = interface.getIfNames()

  for ifid, ifname in pairs(ifnames) do
     interface.select(ifname)
     local stats = interface.getInfluxExportStats()

     if(stats ~= nil) then
        points_exported = points_exported + stats.num_points_exported
        points_dropped = points_dropped + stats.num_points_dropped
     end
  end

  interface.select(getSystemInterfaceId())

  return {
    points_exported = points_exported,
    points_dropped = points_dropped
  }
end

-- ##############################################

function probe._measureRtt(when, ts_utils, influxdb)
  local start_ms = ntop.gettimemsec()
  local res = influxdb:getInfluxdbVersion()

  if res ~= nil then
    local end_ms = ntop.gettimemsec()

    ts_utils.append("influxdb:rtt", {millis_rtt = ((end_ms-start_ms)*1000)}, when)
  end
end

-- ##############################################

function probe._exportStats(when, ts_utils, influxdb)
  local stats = probe.getExportStats()

  ts_utils.append("influxdb:exported_points", {points = stats.points_exported}, when)
  ts_utils.append("influxdb:dropped_points", {points = stats.points_dropped}, when)
end

-- ##############################################

function probe._checkExportQueueLen(when, ts_utils, influxdb)
  local queue_len = influxdb.getExportQueueLength()

  if(queue_len > MAX_INFLUX_EXPORT_QUEUE_LEN) then
    local err_msg = i18n("alerts_dashboard.influxdb_queue_too_long_description",
      {length = queue_len})

    interface.storeAlert(alertEntity("influx_db"), influxdb.url,
      alertType("influxdb_queue_too_long"), alertSeverity("error"), err_msg)
  end

  traceError(TRACE_INFO, TRACE_CONSOLE, string.format("InfluxDB export queue length: %u", queue_len))
end

-- ##############################################

function probe.runTask(when, ts_utils)
  local influxdb = ts_utils.getQueryDriver()

  probe._exportStats(when, ts_utils, influxdb)
  probe._checkExportQueueLen(when, ts_utils, influxdb)
  probe._measureRtt(when, ts_utils, influxdb)
end

-- ##############################################

return probe
