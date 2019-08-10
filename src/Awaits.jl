module Awaits

export @taskgroup, @in, @await, @go, @check

using MacroTools: postwalk, @capture

struct Cancelled <: Exception end

function locking(f, l)
    lock(l)
    try
        return f()
    finally
        unlock(l)
    end
end

struct TaskVector
    tasks::Vector{Any}
    lock::Threads.SpinLock
end

TaskVector(tasks::Vector{Any}) = TaskVector(tasks, Threads.SpinLock())

Base.push!(v::TaskVector, x) = locking(v.lock) do
    push!(v.tasks, x)
end

Base.iterate(v::TaskVector, i=1) = locking(v.lock) do
    iterate(v.tasks, i)
end

struct TaskContext
    tasks::TaskVector
    listening::Vector{Threads.Atomic{Bool}}
    cancelables::Vector{Threads.Atomic{Bool}}
end

TaskContext() = TaskContext(TaskVector([]), [], [])

function newcontext!(ctx::TaskContext)
    c = Threads.Atomic{Bool}(false)
    newctx = TaskContext(
        ctx.tasks,
        copy(ctx.listening),
        copy(ctx.cancelables),
    )
    push!(ctx.cancelables, c)
    push!(newctx.listening, c)
    return newctx
end

function shouldstop(ctx::TaskContext)
    for c in ctx.listening
        c[] && return true
    end
    return false
end

function cancel!(ctx::TaskContext)
    for c in ctx.cancelables
        c[] = true
    end
end

const ctx_varname = gensym("taskcontext")

macro taskgroup(body)
    var = esc(ctx_varname)
    quote
        let $var = TaskContext()
            v = $(esc(body))
            Base.sync_end($var.tasks)
            v
        end
    end
end

macro in(ctx, body)
    var = esc(ctx_varname)
    quote
        let $var = $(esc(ctx))
            $(esc(body))
        end
    end
end

substitute_context(ctx, body) =
    postwalk(body) do ex
        if @capture(ex, f_(xs__)) && :_ in xs
            :($f($((x == :_ ? ctx : x for x in xs)...)))
        else
            ex
        end
    end

macro await(body)
    quote
        ans = $(esc(substitute_context(ctx_varname, body)))
        if ans isa Exception
            cancel!($(esc(ctx_varname)))
            return ans
        end
        ans
    end
end

macro go(body)
    @gensym ctx
    quote
        $(esc(ctx)) = newcontext!($(esc(ctx_varname)))
        task = Threads.@spawn let $(esc(ctx_varname)) = $(esc(ctx))
            $(esc(substitute_context(ctx, body)))
        end
        push!($(esc(ctx)).tasks, task)
        task
    end
end

macro check()
    quote
        @check($(esc(ctx_varname)))
    end
end

macro check(ctx)
    var = esc(ctx)
    quote
        shouldstop($var) && return Cancelled()
    end
end

end # module
