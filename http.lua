-- send_webhook.lua
-- CC:Tweaked / ComputerCraft script to POST to a Discord webhook with retries and basic rate-limit handling.
-- Replace webhook variable below if you want to use a different webhook.

local webhook = "nop"
local function sleep_seconds(n)
  -- CC uses sleep() which accepts seconds
  sleep(n)
end
local function post_json(url, tbl, headers)
  local body = textutils.serializeJSON(tbl)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res, err = http.post(url, body, headers)
  if not res then
    return nil, err
  end
  local responseText = ""
  if res.readAll then
    responseText = res.readAll()
  end
  -- try to get a numeric response code if available
  local code
  if res.getResponseCode then
    code = res.getResponseCode()
  end
  if res.close then res.close() end
  return {
    code = code,
    body = responseText
  }
end
local function send_discord_webhook(payload, max_retries)
  max_retries = max_retries or 5
  local attempt = 0
  local backoff = 1 -- seconds
  while attempt < max_retries do
    attempt = attempt + 1
    local ok, result_or_err = pcall(post_json, webhook, payload)
    if not ok then
      print(("Attempt %d: http.post failed: %s"):format(attempt, tostring(result_or_err)))
      sleep_seconds(backoff)
      backoff = backoff * 2
    else
      local resp = result_or_err
      -- If Discord returned a code 429 or a JSON with retry_after, honor it
      local body = resp.body or ""
      local parsed = nil
      local success = false
      if resp.code and resp.code >= 200 and resp.code < 300 then
        print("Webhook sent successfully (HTTP " .. tostring(resp.code) .. ")")
        return true, resp
      end

      -- try to parse body for rate-limit info
      if body ~= "" then
        local ok2, parsed_json = pcall(textutils.unserializeJSON, body)
        if ok2 then parsed = parsed_json end
      end

      -- Handle rate limit - Discord often returns 429 with {"retry_after": <ms>, ...}
      if parsed and parsed.retry_after then
        local wait_seconds = tonumber(parsed.retry_after) and parsed.retry_after / 1000 or backoff
        print(("Rate limited. Server asked to retry after %.2f seconds."):format(wait_seconds))
        sleep_seconds(wait_seconds)
        backoff = backoff * 2
        -- continue loop to retry
      else
        -- If we have an HTTP code, show it; otherwise show body or generic error
        print(("Attempt %d: Unexpected response. HTTP code: %s, body: %s"):format(
          attempt, tostring(resp.code), tostring(body)
        ))
        -- small wait then retry with exponential backoff
        sleep_seconds(backoff)
        backoff = backoff * 2
      end
    end
  end
  return false, "exhausted retries"
end
-- Example payloads:
-- 1) Simple message
local payload_simple = {
  content = "From Tire's server:",
  username = "Testing"
}
-- 2) Rich embed example
local payload_embed = {
  username = "CC-Tweaked",
  embeds = {
    {
      title = "HTTP Test",
      description = "Goated shit is in the makings",
      fields = {
        { name = "Server", value = "Artgen SMP", inline = true },
        { name = "Test:", value = "its functioning", inline = true }
      },
      footer = { text = "CC:Tweaked webhook" },
      timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
  }
}
-- Choose payload to send:
local ok, info = send_discord_webhook(payload_embed)
if not ok then
  print("Failed to send webhook:", info)
else
  print("Webhook result:", textutils.serializeJSON(info))
end
