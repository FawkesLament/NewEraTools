local OUTPUT = "tests/helpers/runner_fixtures/_output.txt"

local function ExitCode(status)
    if status == true or status == 0 then
        return 0
    end
    if type(status) ~= "number" then
        return 1
    end
    if status > 255 then
        return math.floor(status / 256)
    end
    return status
end

local function RunCli(arguments)
    os.remove(OUTPUT)
    local command = "luajit tests/run.lua " .. arguments .. " > " .. OUTPUT .. " 2>&1"
    local status = os.execute(command)
    local file = assert(io.open(OUTPUT, "rb"))
    local output = file:read("*a") or ""
    file:close()
    os.remove(OUTPUT)
    return ExitCode(status), output
end

describe("test runner", function()
    after_each(function()
        os.remove(OUTPUT)
    end)

    it("fails when no spec files are discovered", function()
        local code, output = RunCli("--no-discover")
        assert(code ~= 0, "expected a nonzero exit\n" .. output)
        assert(output:find("no spec files discovered", 1, true), output)
        assert(output:find("0 passed, 1 failed (0 spec files)", 1, true), output)
    end)

    it("fails a spec file that registers no examples", function()
        local emptyCode, emptyOutput = RunCli("tests/helpers/runner_fixtures/empty_file.lua")
        assert(emptyCode ~= 0, "expected a nonzero exit\n" .. emptyOutput)
        assert(emptyOutput:find("spec file registered no examples", 1, true), emptyOutput)

        local describeCode, describeOutput = RunCli("tests/helpers/runner_fixtures/describe_only.lua")
        assert(describeCode ~= 0, "expected a nonzero exit\n" .. describeOutput)
        assert(describeOutput:find("spec file registered no examples", 1, true), describeOutput)
    end)

    it("allows an empty it body", function()
        local code, output = RunCli("tests/helpers/runner_fixtures/empty_it.lua")
        assert(code == 0, "expected exit 0\n" .. output)
        assert(output:find("1 passed, 0 failed (1 spec files)", 1, true), output)
    end)

    it("runs every before_each and after_each, including nested scopes", function()
        local code, output = RunCli("tests/helpers/runner_fixtures/hooks.lua")
        assert(code == 0, "expected exit 0\n" .. output)
        assert(output:find("1 passed, 0 failed (1 spec files)", 1, true), output)
    end)

    it("still runs a single before_each and after_each", function()
        local code, output = RunCli("tests/helpers/runner_fixtures/single_hook.lua")
        assert(code == 0, "expected exit 0\n" .. output)
        assert(output:find("1 passed, 0 failed (1 spec files)", 1, true), output)
    end)

    it("reports the example error and the teardown error", function()
        local code, output = RunCli("tests/helpers/runner_fixtures/both_fail.lua")
        assert(code ~= 0, "expected a nonzero exit\n" .. output)
        assert(output:find("body-boom", 1, true), output)
        assert(output:find("teardown-boom", 1, true), output)
        assert(output:find("0 passed, 2 failed (1 spec files)", 1, true), output)
    end)
end)
