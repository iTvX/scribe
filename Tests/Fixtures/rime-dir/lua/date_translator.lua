-- 合成的测试样本：输入 rq 得到今天的日期。
local function translator(input, seg)
    if input == "rq" then
        yield(Candidate("date", seg.start, seg._end, os.date("%Y-%m-%d"), ""))
    end
end

return translator
