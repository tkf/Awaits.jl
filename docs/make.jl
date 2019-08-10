using Documenter, Awaits

makedocs(;
    modules=[Awaits],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/tkf/Awaits.jl/blob/{commit}{path}#L{line}",
    sitename="Awaits.jl",
    authors="Takafumi Arakaki <aka.tkf@gmail.com>",
    assets=String[],
)

deploydocs(;
    repo="github.com/tkf/Awaits.jl",
)
