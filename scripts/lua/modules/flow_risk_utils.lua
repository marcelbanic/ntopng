--
-- (C) 2017-20 - ntop.org
--

local flow_risk_utils = {}

-- ##############################################

-- Keep in sync with ndpi_typedefs.h, table keys are risk ids as found in nDPI
local id2name = {
   [0] = "ndpi_no_risk",
   [1] = "ndpi_url_possible_xss",
   [2] = "ndpi_url_possible_sql_injection",
   [3] = "ndpi_url_possible_rce_injection",
   [4] = "ndpi_binary_application_transfer",
   [5] = "ndpi_known_protocol_on_non_standard_port",
   [6] = "ndpi_tls_selfsigned_certificate",
   [7] = "ndpi_tls_obsolete_version",
   [8] = "ndpi_tls_weak_cipher",
}

-- ##############################################

-- Same as id2name, just with keys swapped
flow_risk_utils["risks"] = {}
for risk_id, risk_name in pairs(id2name) do
   flow_risk_utils["risks"][risk_name] = risk_id
end

-- ##############################################

-- @brief Returns an i18n-localized risk description given a risk_id as defined in nDPI
function flow_risk_utils.risk_id_2_i18n(risk_id)
   if risk_id and id2name[risk_id] then
      return i18n("flow_risk."..id2name[risk_id])
   end

   return ''
end

-- ##############################################

return flow_risk_utils
