using Test
using Awaits
using Awaits: SyncSeq

function tickingfor(ctx, sec)
    dt = 0.01
    @in ctx begin
        for i in 1:Int(cld(sec, dt))
            sleep(dt)
            @check
        end
    end
end
