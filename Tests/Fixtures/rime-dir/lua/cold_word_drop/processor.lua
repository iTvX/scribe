-- 合成的测试样本：按前端选择删词快捷键。
local kNoop = 2

local P = {}

function P.init(env)
    env.delete_key = "Control+Delete"
    if rime_api.get_distribution_name() == '鼠鬚管' then
        env.delete_key = "Control+d"
    end
end

function P.func(key, env)
    return kNoop
end

return P
