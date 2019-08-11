module Awaits

export @taskgroup, @cancelscope, @in, @go, @await, @check

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

"""
    SyncSeq([values])

A minimalistic wrapper of `Vector{Any}` that can be used from multiple
threads.
"""
struct SyncSeq
    values::Vector{Any}
    lock::Threads.SpinLock
end

SyncSeq() = SyncSeq([])
SyncSeq(values::Vector{Any}) = SyncSeq(values, Threads.SpinLock())

Base.push!(v::SyncSeq, x) = locking(v.lock) do
    push!(v.values, x)
end

Base.iterate(v::SyncSeq, i=1) = locking(v.lock) do
    iterate(v.values, i)
end

# For `collect` in test code:
Base.IteratorSize(::Type{<:SyncSeq}) = Base.SizeUnknown()

struct TaskContext
    tasks::SyncSeq
    listening::Vector{Threads.Atomic{Bool}}
    cancelables::Vector{Threads.Atomic{Bool}}
end

function TaskContext()
    c = Threads.Atomic{Bool}(false)
    return TaskContext(SyncSeq(), [c], [c])
end

function newcontext!(ctx::TaskContext)
    c = Threads.Atomic{Bool}(false)
    push!(ctx.cancelables, c)

    return TaskContext(ctx.tasks, push!(copy(ctx.listening), c), [c])
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
    ctx_var = esc(ctx_varname)
    sync_var = esc(Base.sync_varname)
    quote
        let $ctx_var = TaskContext(),
            $sync_var = $ctx_var.tasks

            v = $(esc(body))
            Base.sync_end($ctx_var.tasks)
            v
        end
    end
end

macro in(ctx, body)
    ctx_var = esc(ctx_varname)
    sync_var = esc(Base.sync_varname)
    quote
        let $ctx_var = $(esc(ctx)),
            $sync_var = $ctx_var.tasks

            $(esc(body))
        end
    end
end

#=
"""
    @cancelscope(body) :: TaskContext
"""
=#
macro cancelscope(body)
    ctx_var = esc(ctx_varname)
    quote
        let $ctx_var = newcontext!($ctx_var)
            $(esc(body))
            $ctx_var
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
    quote
        $Threads.@spawn $(substitute_context(ctx_varname, body))
    end |> esc
end

macro check()
    quote
        @check($ctx_varname)
    end |> esc
end

macro check(ctx)
    ctx_var = esc(ctx)
    quote
        shouldstop($ctx_var) && return Cancelled()
    end
end

end # module
