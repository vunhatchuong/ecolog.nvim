local assert = require("luassert")
local mock = require("luassert.mock")
local stub = require("luassert.stub")

describe("ecolog", function()
  local ecolog
  local test_dir = vim.fn.tempname()

  before_each(function()
    -- Create temp test directory
    vim.fn.mkdir(test_dir, "p")

    -- Reset modules
    package.loaded["ecolog"] = nil
    package.loaded["ecolog.utils"] = nil
    package.loaded["ecolog.types"] = nil
    package.loaded["ecolog.shelter"] = nil
    package.loaded["ecolog.providers"] = nil

    -- Mock providers module
    package.loaded["ecolog.providers"] = {
      get_providers = function()
        return {}
      end,
      load_providers = function() end,
      register = function() end,
      register_many = function() end
    }

    -- Load module
    ecolog = require("ecolog")
  end)

  after_each(function()
    -- Clean up test directory
    vim.fn.delete(test_dir, "rf")
  end)

  describe("setup()", function()
    it("should initialize with default options", function()
      ecolog.setup({
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })
      local config = ecolog.get_config()
      assert.equals(vim.fn.getcwd(), config.path)
      assert.equals("", config.preferred_environment)
    end)
  end)

  describe("env file handling", function()
    before_each(function()
      -- Create test env files
      local env_content = [[
        DB_HOST=localhost
        DB_PORT=5432
        API_KEY="secret123" # API key for testing
      ]]
      vim.fn.writefile(vim.split(env_content, "\n"), test_dir .. "/.env")
    end)

    it("should find and parse env files", function()
      ecolog.setup({
        path = test_dir,
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })
      local env_vars = ecolog.get_env_vars()

      assert.is_not_nil(env_vars.DB_HOST)
      assert.equals("localhost", env_vars.DB_HOST.value)
      assert.equals("5432", env_vars.DB_PORT.value)
      assert.equals("secret123", env_vars.API_KEY.value)
    end)
  end)

  describe("file watcher", function()
    local test_dir = vim.fn.tempname()
    local original_notify
    local notify_messages = {}

    before_each(function()
      vim.fn.mkdir(test_dir, "p")
      original_notify = vim.notify
      notify_messages = {}
      vim.notify = function(msg, level)
        table.insert(notify_messages, { msg = msg, level = level })
      end
    end)

    after_each(function()
      vim.fn.delete(test_dir, "rf")
      vim.notify = original_notify
    end)

    it("should detect new env file creation", function()
      ecolog.setup({
        path = test_dir,
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      -- Create new env file
      local env_content = "NEW_VAR=test_value"
      vim.fn.writefile({ env_content }, test_dir .. "/.env")

      -- Trigger BufAdd event manually since we're in a test environment
      vim.api.nvim_exec_autocmds("BufAdd", {
        pattern = test_dir .. "/.env",
        data = { file = test_dir .. "/.env" },
      })

      -- Wait for file watcher to process
      vim.wait(100, function()
        local env_vars = ecolog.get_env_vars()
        return env_vars.NEW_VAR ~= nil
      end)

      local env_vars = ecolog.get_env_vars()
      assert.is_not_nil(env_vars.NEW_VAR)
      assert.equals("test_value", env_vars.NEW_VAR.value)
    end)

    it("should detect env file modifications", function()
      -- Create initial env file
      local initial_content = "INITIAL_VAR=old_value"
      vim.fn.writefile({ initial_content }, test_dir .. "/.env")

      ecolog.setup({
        path = test_dir,
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      -- Modify env file
      local new_content = "INITIAL_VAR=new_value\nADDED_VAR=added_value"
      vim.fn.writefile(vim.split(new_content, "\n"), test_dir .. "/.env")

      -- Wait for file watcher to process
      vim.wait(100)

      local env_vars = ecolog.get_env_vars()
      assert.equals("new_value", env_vars.INITIAL_VAR.value)
      assert.equals("added_value", env_vars.ADDED_VAR.value)
    end)

    it("should handle env file deletion", function()
      -- Create initial env file
      local initial_content = "TEST_VAR=value"
      vim.fn.writefile({ initial_content }, test_dir .. "/.env")

      ecolog.setup({
        path = test_dir,
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      -- Delete env file
      vim.fn.delete(test_dir .. "/.env")

      -- Wait for file watcher to process
      vim.wait(100)

      local env_vars = ecolog.get_env_vars()
      assert.is_nil(env_vars.TEST_VAR)
    end)
  end)

  describe("shell environment handling", function()
    local original_environ
    local test_env = {
      SHELL_VAR = "test_value",
      API_KEY = "secret123",
      DEBUG = "true",
      PORT = "3000",
    }

    before_each(function()
      -- Store original environ function
      original_environ = vim.fn.environ
      -- Mock environ function
      _G.vim = vim or {}
      _G.vim.fn = vim.fn or {}
      _G.vim.fn.environ = function()
        return test_env
      end

      -- Force refresh env vars before each test
      package.loaded["ecolog"] = nil
      ecolog = require("ecolog")
    end)

    after_each(function()
      -- Restore original environ function
      _G.vim.fn.environ = original_environ
    end)

    it("should load basic shell variables", function()
      ecolog.setup({
        load_shell = {
          enabled = true,
        },
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      -- Force refresh to load shell vars
      ecolog.refresh_env_vars({
        load_shell = {
          enabled = true,
        },
        types = true,
      })

      local env_vars = ecolog.get_env_vars()
      assert.is_not_nil(env_vars.SHELL_VAR)
      assert.equals("test_value", env_vars.SHELL_VAR.value)
      assert.equals("shell", env_vars.SHELL_VAR.source)
    end)

    it("should apply filter function", function()
      ecolog.setup({
        load_shell = {
          enabled = true,
          filter = function(key, _)
            return key:match("^API") ~= nil
          end,
        },
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      -- Force refresh with filter
      ecolog.refresh_env_vars({
        load_shell = {
          enabled = true,
          filter = function(key, _)
            return key:match("^API") ~= nil
          end,
        },
        types = true,
      })

      local env_vars = ecolog.get_env_vars()
      assert.is_not_nil(env_vars.API_KEY)
      assert.is_nil(env_vars.SHELL_VAR)
    end)

    it("should apply transform function", function()
      ecolog.setup({
        load_shell = {
          enabled = true,
          transform = function(_, value)
            return value:upper()
          end,
        },
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      -- Force refresh with transform
      ecolog.refresh_env_vars({
        load_shell = {
          enabled = true,
          transform = function(_, value)
            return value:upper()
          end,
        },
        types = true,
      })

      local env_vars = ecolog.get_env_vars()
      assert.equals("TEST_VALUE", env_vars.SHELL_VAR.value)
    end)

    it("should handle type detection for shell variables", function()
      ecolog.setup({
        load_shell = {
          enabled = true,
        },
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      -- Force refresh to load shell vars
      ecolog.refresh_env_vars({
        load_shell = {
          enabled = true,
        },
        types = true,
      })

      local env_vars = ecolog.get_env_vars()
      assert.equals("boolean", env_vars.DEBUG.type)
      assert.equals("number", env_vars.PORT.type)
    end)

    it("should respect override setting with .env files", function()
      -- Create env file with conflicting value
      local env_content = "SHELL_VAR=env_value"
      vim.fn.writefile({ env_content }, test_dir .. "/.env")

      ecolog.setup({
        path = test_dir,
        load_shell = {
          enabled = true,
          override = true,
        },
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      local env_vars = ecolog.get_env_vars()
      assert.equals("test_value", env_vars.SHELL_VAR.value)
      assert.equals("shell", env_vars.SHELL_VAR.source)
    end)
  end)

  describe("initial env file selection", function()
    it("should select initial env file with default patterns", function()
      -- Create test env files
      vim.fn.writefile({ "TEST=value" }, test_dir .. "/.env")
      vim.fn.writefile({ "TEST=dev" }, test_dir .. "/.env.development")

      ecolog.setup({
        path = test_dir,
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      local env_vars = ecolog.get_env_vars()
      assert.equals("value", env_vars.TEST.value)
    end)

    it("should select initial env file with custom patterns", function()
      -- Create test env files
      vim.fn.writefile({ "TEST=value" }, test_dir .. "/config.env")

      ecolog.setup({
        path = test_dir,
        env_file_pattern = "^.+/config%.env$",
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      local env_vars = ecolog.get_env_vars()
      assert.equals("value", env_vars.TEST.value)
    end)

    it("should respect preferred environment with custom patterns", function()
      -- Create test env files
      vim.fn.writefile({ "TEST=value" }, test_dir .. "/.env")
      vim.fn.writefile({ "TEST=dev" }, test_dir .. "/.env.development")

      ecolog.setup({
        path = test_dir,
        preferred_environment = "development",
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      local env_vars = ecolog.get_env_vars()
      assert.equals("dev", env_vars.TEST.value)
    end)

    it("should handle multiple custom patterns", function()
      -- Create test env files
      vim.fn.writefile({ "TEST=value" }, test_dir .. "/config.env")
      vim.fn.writefile({ "TEST=dev" }, test_dir .. "/.env.development")

      ecolog.setup({
        path = test_dir,
        env_file_pattern = { "^.+/config%.env$", "^.+/%.env%.development$" },
        shelter = {
          configuration = {},
          modules = {},
        },
        integrations = {
          nvim_cmp = false,
          blink_cmp = false,
          lsp = false,
          lspsaga = false,
          fzf = false,
        },
        types = true,
      })

      local env_vars = ecolog.get_env_vars()
      assert.equals("value", env_vars.TEST.value)
    end)
  end)
end)
