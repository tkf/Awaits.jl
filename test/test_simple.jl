module TestSimple

include("preamble.jl")

# Test that task group are synchronized and the task context can be
# passed around across threads/tasks.
@testset "wait" begin
    results = SyncSeq()

    bg(context, id) = @in context @go @go push!(results, id)

    @taskgroup begin
        @go bg(_, 1)
        @go bg(_, 2)
        @go bg(_, 3)
    end

    @test sort(collect(results)) == 1:3
end

# Test cancellation on error.
@testset "cancel on error" begin
    results = SyncSeq()

    function bg(context, id)
        @in context begin
            @go begin
                push!(results, ("before sleep", id))
                @await tickingfor(_, 1)
                push!(results, ("after sleep", id))
            end
            if id == 1
                @await ErrorException("terminate")  # "throw" an error
            end
        end
    end

    @taskgroup begin
        @go bg(_, 1)
        @go bg(_, 2)
    end

    @test sort(collect(results)) == [("before sleep", 1), ("before sleep", 2)]
end

# Test manual cancellation
@testset "manual cancel" begin
    results = SyncSeq()

    function bg(context, id)
        @in context begin
            @go begin
                push!(results, ("before sleep", id))
                @await tickingfor(_, 1)
                push!(results, ("after sleep", id))
            end
            if id == 1
                cancel!(context)
            end
        end
    end

    @taskgroup begin
        @go bg(_, 1)
        @go bg(_, 2)
    end

    @test sort(collect(results)) == [("before sleep", 1), ("before sleep", 2)]
end

# Test that cancellation of `@cancelscope` does not leak out.
@testset "`@cancelscope`" begin
    results = SyncSeq()

    function bg(context, id)
        @in context begin
            subctx = @cancelscope begin
                @go begin
                    push!(results, ("before sleep", id))
                    @await tickingfor(_, 1)
                    push!(results, ("after sleep", id))
                end
            end
            if id == 1
                # Manually cancel only this scope:
                cancel!(subctx)
                # Note: `@await ErrorException("terminate")` inside
                # `@cancelscope` does not work because it cancels
                # everything; i.e., the error bubbles up until the
                # root `@taskgroup` which in turn cancels everything,
                # not just this `@cancelscope`.
            end
        end
    end

    @taskgroup begin
        @go bg(_, 1)
        @go bg(_, 2)
    end

    @test sort(collect(results)) ==
        [("after sleep", 2), ("before sleep", 1), ("before sleep", 2)]
end

end  # module
