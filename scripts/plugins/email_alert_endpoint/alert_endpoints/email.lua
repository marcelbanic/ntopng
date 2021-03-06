--
-- (C) 2017-20 - ntop.org
--

local plugins_utils = require "plugins_utils"

local email = {
   conf_params = {
      { param_name = "smtp_server" },
      { param_name = "email_sender"},
      { param_name = "smtp_username", optional = true },
      { param_name = "smtp_password", optional = true },
   },
   conf_template = {
      plugin_key = "email_alert_endpoint",
      template_name = "email_endpoint.template"
   },
   recipient_params = {
      { param_name = "email_recipient" },
      { param_name = "cc", optional = true },
   },
   recipient_template = {
      plugin_key = "email_alert_endpoint",
      template_name = "email_recipient.template"
   },
}

local json = require("dkjson")
local alert_utils = require "alert_utils"

email.EXPORT_FREQUENCY = 60
email.prio = 200

local MAX_ALERTS_PER_EMAIL = 100
local MAX_NUM_SEND_ATTEMPTS = 5
local NUM_ATTEMPTS_KEY = "ntopng.alerts.modules_notifications_queue.email.num_attemps"

-- ##############################################

local function recipient2sendMessageSettings(recipient)
  local settings = {
    smtp_server = recipient.endpoint_conf.endpoint_conf.smtp_server,
    from_addr = recipient.endpoint_conf.endpoint_conf.email_sender,
    to_addr = recipient.recipient_params.email_recipient,
    username = recipient.endpoint_conf.endpoint_conf.smtp_username,
    password = recipient.endpoint_conf.endpoint_conf.smtp_password,
  }

  return settings
end

-- ##############################################

local function buildMessageHeader(now_ts, from, to, subject, body)
  local now = os.date("%a, %d %b %Y %X", now_ts) -- E.g. "Tue, 3 Apr 2018 14:58:00"
  local msg_id = "<" .. now_ts .. "." .. os.clock() .. "@ntopng>"

  local lines = {
    "From: " .. from,
    "To: " .. to,
    "Subject: " .. subject,
    "Date: " ..  now,
    "Message-ID: " .. msg_id,
    "Content-Type: text/html; charset=UTF-8",
  }

  return table.concat(lines, "\r\n") .. "\r\n\r\n" .. body .. "\r\n"
end

-- ##############################################

function email.isAvailable()
  return(ntop.sendMail ~= nil)
end

-- ##############################################

function email.sendEmail(subject, message_body, settings)
  if isEmptyString(settings.from_addr) or 
     isEmptyString(settings.to_addr) or 
     isEmptyString(settings.smtp_server) then
    return false
  end

  local smtp_server = settings.smtp_server
  local from = settings.from_addr:gsub(".*<(.*)>", "%1")
  local to = settings.to_addr:gsub(".*<(.*)>", "%1")
  local product = ntop.getInfo(false).product
  local info = ntop.getHostInformation()

  subject = product .. " [" .. info.instance_name .. "@" .. info.ip .. "] " .. subject

  if not string.find(smtp_server, "://") then
    smtp_server = "smtp://" .. smtp_server
  end

  local parts = string.split(to, "@")

  if #parts == 2 then
    local sender_domain = parts[2]
    smtp_server = smtp_server .. "/" .. sender_domain
  end

  local message = buildMessageHeader(os.time(), settings.from_addr, settings.to_addr, subject, message_body)
  return ntop.sendMail(from, to, message, smtp_server, settings.username, settings.password)
end

-- ##############################################

-- Dequeue alerts from a recipient queue for sending notifications
function email.dequeueRecipientAlerts(recipient, budget)
  local sent = 0
  local more_available = true

  -- Dequeue alerts up to budget x MAX_ALERTS_PER_EMAIL
  -- Note: in this case budget is the number of email to send
  while sent < budget and more_available do
    
    -- Dequeue MAX_ALERTS_PER_EMAIL notifications
    local notifications = ntop.lrangeCache(recipient.export_queue, 0, MAX_ALERTS_PER_EMAIL-1)

    if not notifications or #notifications == 0 then
      more_available = false
      break
    end

    -- Prepare email
    local subject = ""
    local message_body = {}

    if #notifications > 1 then
      subject = "(" .. i18n("alert_messages.x_alerts", {num=#notifications}) .. ")"
    end

    for _, json_message in ipairs(notifications) do
      local notif = json.decode(json_message)
      message_body[#message_body + 1] = alert_utils.formatAlertNotification(notif, {nohtml=true})
    end

    message_body = table.concat(message_body, "<br>")

    local settings = recipient2sendMessageSettings(recipient)

    -- Send email
    local rv = email.sendEmail(subject, message_body, settings)

    -- Handle retries on failure
    if not rv then
      local num_attemps = (tonumber(ntop.getCache(NUM_ATTEMPTS_KEY)) or 0) + 1

      if num_attemps >= MAX_NUM_SEND_ATTEMPTS then
        ntop.delCache(NUM_ATTEMPTS_KEY)
        -- Prevent alerts starvation if the plugin is not working after max num attempts
        ntop.delCache(recipient.export_queue)
        return {success=false, error_message="Unable to send mails"}
      else
        ntop.setCache(NUM_ATTEMPTS_KEY, tostring(num_attemps))
        return {success=true}
      end
    else
      ntop.delCache(NUM_ATTEMPTS_KEY)
    end

    -- Remove the processed messages from the queue
    ntop.ltrimCache(recipient.export_queue, #notifications, -1)

    sent = sent + 1
  end

  return {success=true}
end

-- ##############################################

function email.runTest(recipient)
  local message_info

  local settings = recipient2sendMessageSettings(recipient)

  local success = email.sendEmail("TEST MAIL", "Email notification is working", settings)

  if success then
    message_info = i18n("prefs.email_sent_successfully")
  else
    message_info = i18n("prefs.email_send_error", {url="https://www.ntop.org/guides/ntopng/web_gui/alerts.html#email"})
  end

  return success, message_info

end

-- ##############################################

return email
