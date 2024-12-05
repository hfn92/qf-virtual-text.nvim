local log = require("qf-virtual-text.log")
local const = require("qf-virtual-text.const")

local M = {}

local config = const
local ns_id = vim.api.nvim_create_namespace("qf-virtual-text")
local ns_hl = vim.api.nvim_create_namespace("qf-virtual-text-hl")
-- GTest error formats
--
-- _TRUE, _FALSE
-- Value of: false
--   Actual: false
-- Expected: true
--

--
-- _EQ
-- Expected equality of these values:
--   1
--   2
--
-- Expected equality of these values:
--   1 - 1
--     Which is: 0
--   2 + 3
--     Which is: 5
--
-- _Gx, _Lx and _NE (why different from EQ?)
--  Expected: (2) <= (1), actual: 2 vs 1
--  Expected: (2 + 3) != (2 + 3), actual: 5 vs 5
--  Expected: (std::string("test")) != (std::string("test")), actual: "test" vs "test"
--
--  GMock
--Failure
-- Actual function call count doesn't match EXPECT_CALL(m, fn())...
--          Expected: to be called once
--            Actual: never called - unsatisfied and active
--
--SuiteA/main.cpp|50| Failure
--  Mock function called more times than expected - returning directly.
--      Function call: fn2()
--           Expected: to be called once
--             Actual: called twice - over-saturated and active
--
--
-- EXPECT_CALL(m, fni(1))...
--   Expected arg #0: is equal to 1
--            Actual: 2
--          Expected: to be called once
--            Actual: never called - unsatisfied and active-

local function clear()
  vim.diagnostic.reset(ns_id)
end

local function remove_prefix(text, prefix)
  if text:find(prefix, 1, true) == 1 then
    return true, text:sub(#prefix + 1)
  end
  return false, text
end

local function starts_with(text, prefix)
  return text:find(prefix, 1, true) == 1
end

local function get_text_gtest(qf_items, idx, item)
  local next = qf_items[idx + 1]
  -- if not next then
  --   return item.text, "error"
  -- end

  if next.text == "Expected equality of these values:" then
    local removed = false
    local left = qf_items[idx + 2].text
    local right = qf_items[idx + 3].text
    local check_right = 4
    removed, right = remove_prefix(right, "    Which is: ")
    if removed then
      left = right
      right = qf_items[idx + 4].text
      check_right = 5
    end

    local temp = ""
    removed, temp = remove_prefix(qf_items[idx + check_right].text, "    Which is: ")
    if removed then
      right = temp
    end

    return next.text .. " " .. left .. " vs " .. right
  end

  if starts_with(next.text, "Value of: ") then
    return qf_items[idx + 3].text .. qf_items[idx + 2].text
  end

  if starts_with(next.text, "Expected: ") then
    return next.text
  end

  if starts_with(next.text, "Mock function called more times than expected - returning directly.") then
    local ok, res = remove_prefix(qf_items[idx + 4].text, "           Actual: ")
    if ok then
      return res
    end
    return next.text
  end

  if starts_with(next.text, "Actual function call count doesn't match EXPECT_CALL") then
    local ok, res = remove_prefix(qf_items[idx + 3].text, "           Actual: ")
    if ok then
      return res
    end
    return next.text
  end

  if starts_with(item.text, " EXPECT_CALL(") or starts_with(item.text, " tried expectation ") then
    local ok1, first = remove_prefix(qf_items[idx + 1].text, "  Expected ")
    local ok2, second = remove_prefix(qf_items[idx + 2].text, "           Actual: ")
    if ok1 and ok2 then
      first = first:match("(.+):.+")
      return first .. " was " .. second
    end
    return next.text
  end

  return item.text
end

local function get_text(qf_items, idx, item)
  if
    item.text == " Failure"
    or starts_with(item.text, " EXPECT_CALL(")
    or starts_with(item.text, " tried expectation ")
  then
    local ok, text = pcall(function()
      return get_text_gtest(qf_items, idx, item)
    end)
    if ok then
      item.col = #"  EXPECT_XX"
      return text, vim.diagnostic.severity.ERROR
    end
  end

  for _, prefix in ipairs({
    "error: ",
    " error: ",
    "error:",
    " error:",
  }) do
    if starts_with(item.text, prefix) then
      item.text = string.sub(item.text, #prefix + 1)
      return item.text, vim.diagnostic.severity.ERROR
    end
  end

  for _, prefix in ipairs({
    "warning: ",
    " warning: ",
    "warning:",
    " warning:",
  }) do
    if starts_with(item.text, prefix) then
      item.text = string.sub(item.text, #prefix + 1)
      return item.text, vim.diagnostic.severity.WARN
    end
  end

  return item.text, vim.diagnostic.severity.INFO
end

local highlight = {
  [vim.diagnostic.severity.ERROR] = "QfError",
  [vim.diagnostic.severity.WARN] = "QfWarn",
}

local function get_quickfix_buffer()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_get_option_value("buftype", { buf = buf }) == "quickfix" then
      return buf
    end
  end
  return nil -- Return nil if no Quickfix window is found
end

local function show_virt_text()
  local qf_items = vim.fn.getqflist()

  local messages = {}

  local qfbuf = get_quickfix_buffer()

  if qfbuf then
    vim.api.nvim_buf_clear_namespace(qfbuf, ns_hl, 0, -1)
  end

  for idx, v in ipairs(qf_items) do
    if v.valid == 1 then
      local text, severity = get_text(qf_items, idx, v)

      if not messages[v.bufnr] then
        messages[v.bufnr] = {}
      end

      if qfbuf and highlight[severity] then
        pcall(function()
          vim.api.nvim_buf_add_highlight(qfbuf, ns_hl, highlight[severity], idx - 1, 0, -1)
        end)
      end

      messages[v.bufnr][#messages[v.bufnr] + 1] = {
        lnum = v.lnum - 1,
        col = v.col - 1,
        severity = severity,
        bufnr = v.bufnr,
        message = text,
        end_lnum = v.end_lnum > 0 and v.end_lnum or nil,
        end_col = v.end_col > 0 and v.end_col or nil,
      }
    end
  end

  pcall(function()
    for k, v in pairs(messages) do
      vim.diagnostic.set(ns_id, k, v, {})
    end
  end)

  -- vim.notify("DONE " .. vim.inspect(qf_items))
end

local function refresh_job()
  clear()
  show_virt_text()

  vim.defer_fn(function()
    refresh_job()
  end, config.refresh_rate_ms)
end

function M.setup(values)
  vim.tbl_deep_extend("force", config, values)

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("QfOnQfOpen", { clear = true }),
    pattern = "qf",
    callback = function()
      vim.api.nvim_set_hl(0, "QfError", { bg = "#542F2F" })
      vim.api.nvim_set_hl(0, "QfWarn", { bg = "#3b3c3c" })

      -- print("attack to qf")
      --
      -- vim.api.nvim_create_autocmd(
      --   { "QuickFixCmdPost", "BufReadPost", "TextChanged", "TextChangedI", "TextChangedP", "TextChangedI" },
      --   {
      --     buffer = ev.buf,
      --     group = vim.api.nvim_create_augroup("QfChanged", { clear = true }),
      --     callback = function(ev)
      --       vim.notify(vim.inspect(ev))
      --       vim.defer_fn(function()
      --         clear()
      --         show_virt_text()
      --       end, 250)
      --     end,
      --   }
      -- )
    end,
  })

  refresh_job()
end

return M
