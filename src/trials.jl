#########
# Trial #
#########
abstract type AbstractTrial end
mutable struct Trial <: AbstractTrial
    params::Parameters
    times::Vector{Float64}
    gctimes::Vector{Float64}
    memory::Int
    allocs::Int
end

mutable struct MyTrial <: AbstractTrial
    params::Parameters
    times::Vector{Float64}
    gctimes::Vector{Float64}
    memory::Int
    allocs::Int
    mymetric::Vector{Any}
end

Trial(params::Parameters) = Trial(params, Float64[], Float64[], typemax(Int), typemax(Int))
MyTrial(params::Parameters) = MyTrial(params, Float64[], Float64[], typemax(Int), typemax(Int), [])

function Base.:(==)(a::Trial, b::Trial)
    return a.params == b.params &&
           a.times == b.times &&
           a.gctimes == b.gctimes &&
           a.memory == b.memory &&
           a.allocs == b.allocs
end

Base.copy(t::Trial) = Trial(copy(t.params), copy(t.times), copy(t.gctimes), t.memory, t.allocs)

function Base.push!(t::Trial, time, gctime, memory, allocs)
    push!(t.times, time)
    push!(t.gctimes, gctime)
    memory < t.memory && (t.memory = memory)
    allocs < t.allocs && (t.allocs = allocs)
    return t
end

function Base.push!(t::MyTrial, time, gctime, memory, allocs, mymetric)
    push!(t.times, time)
    push!(t.gctimes, gctime)
    memory < t.memory && (t.memory = memory)
    allocs < t.allocs && (t.allocs = allocs)
    push!(t.mymetric, mymetric)
    return t
end


function Base.deleteat!(t::Trial, i)
    deleteat!(t.times, i)
    deleteat!(t.gctimes, i)
    return t
end

Base.length(t::AbstractTrial) = length(t.times)

Base.getindex(t::Trial, i::Number) = push!(Trial(t.params), t.times[i], t.gctimes[i], t.memory, t.allocs)
Base.getindex(t::Trial, i) = Trial(t.params, t.times[i], t.gctimes[i], t.memory, t.allocs)
Base.lastindex(t::Trial) = length(t)

function Base.sort!(t::AbstractTrial)
    inds = sortperm(t.times)
    t.times = t.times[inds]
    t.gctimes = t.gctimes[inds]
    return t
end
function Base.sort!(t::MyTrial)
    inds = sortperm(t.mymetric)
    t.times = t.times[inds]
    t.gctimes = t.gctimes[inds]
    t.mymetric = t.mymetric[inds]
    return t
end

Base.sort(t::AbstractTrial) = sort!(copy(t))


Base.time(t::AbstractTrial) = time(minimum(t))
gctime(t::AbstractTrial) = gctime(minimum(t))
memory(t::AbstractTrial) = t.memory
allocs(t::AbstractTrial) = t.allocs
params(t::AbstractTrial) = t.params
mymetric(t::AbstractTrial) = Inf
mymetric(t::MyTrial) = minimum(t.mymetric)

# returns the index of the first outlier in `values`, if any outliers are detected.
# `values` is assumed to be sorted from least to greatest, and assumed to be right-skewed.
function skewcutoff(values)
    current_values = copy(values)
    while mean(current_values) > median(current_values)
        deleteat!(current_values, length(current_values))
    end
    return length(current_values) + 1
end

skewcutoff(t::AbstractTrial) = skewcutoff(t.times)

function rmskew!(t::AbstractTrial)
    sort!(t)
    i = skewcutoff(t)
    i <= length(t) && deleteat!(t, i:length(t))
    return t
end

function rmskew(t::AbstractTrial)
    st = sort(t)
    return st[1:(skewcutoff(st) - 1)]
end

trim(t::AbstractTrial, percentage = 0.1) = t[1:max(1, floor(Int, length(t) - (length(t) * percentage)))]

#################
# TrialEstimate #
#################

mutable struct TrialEstimate
    params::Parameters
    time::Float64
    gctime::Float64
    memory::Int
    allocs::Int
    mymetric::Float64
end

function TrialEstimate(trial::AbstractTrial, t, gct, mymetric)
    return TrialEstimate(params(trial), t, gct, memory(trial), allocs(trial), mymetric)
end

function Base.:(==)(a::TrialEstimate, b::TrialEstimate)
    return a.params == b.params &&
           a.time == b.time &&
           a.gctime == b.gctime &&
           a.memory == b.memory &&
           a.allocs == b.allocs &&
           a.mymetric == b.mymetric
end

Base.copy(t::TrialEstimate) = TrialEstimate(copy(t.params), t.time, t.gctime, t.memory, t.allocs, t.mymetric)

function Base.minimum(trial::AbstractTrial)
    i = argmin(trial.times)
    return TrialEstimate(trial, trial.times[i], trial.gctimes[i])
end
function Base.minimum(trial::MyTrial)
    i = argmin(trial.mymetric)
    return TrialEstimate(trial, trial.times[i], trial.gctimes[i], trial.mymetric[i])
end


function Base.maximum(trial::AbstractTrial)
    i = argmax(trial.times)
    return TrialEstimate(trial, trial.times[i], trial.gctimes[i])
end

function Base.maximum(trial::MyTrial)
    i = argmax(trial.mymetric)
    return TrialEstimate(trial, trial.times[i], trial.gctimes[i], trial.mymetric[i])
end

Statistics.median(trial::Trial) = TrialEstimate(trial, median(trial.times), median(trial.gctimes), Inf)
Statistics.mean(trial::Trial) = TrialEstimate(trial, mean(trial.times), mean(trial.gctimes), Inf)
Statistics.median(trial::MyTrial) = TrialEstimate(trial, median(trial.times), median(trial.gctimes), median(trial.mymetric))
Statistics.mean(trial::MyTrial) = TrialEstimate(trial, mean(trial.times), mean(trial.gctimes), median(trial.mymetric))

Base.isless(a::TrialEstimate, b::TrialEstimate) = isless(time(a), time(b))

Base.time(t::TrialEstimate) = t.time
gctime(t::TrialEstimate) = t.gctime
memory(t::TrialEstimate) = t.memory
allocs(t::TrialEstimate) = t.allocs
params(t::TrialEstimate) = t.params
mymetric(t::TrialEstimate) = t.mymetric

##############
# TrialRatio #
##############

mutable struct TrialRatio
    params::Parameters
    time::Float64
    gctime::Float64
    memory::Float64
    allocs::Float64
    mymetric::Float64
end

function Base.:(==)(a::TrialRatio, b::TrialRatio)
    return a.params == b.params &&
           a.time == b.time &&
           a.gctime == b.gctime &&
           a.memory == b.memory &&
           a.allocs == b.allocs &&
           a.mymetric == b.mymetric
end

Base.copy(t::TrialRatio) = TrialRatio(copy(t.params), t.time, t.gctime, t.memory, t.allocs, t.mymetric)

Base.time(t::TrialRatio) = t.time
gctime(t::TrialRatio) = t.gctime
memory(t::TrialRatio) = t.memory
allocs(t::TrialRatio) = t.allocs
params(t::TrialRatio) = t.params
mymetric(t::TrialRatio) = t.mymetric

function ratio(a::Real, b::Real)
    if a == b # so that ratio(0.0, 0.0) returns 1.0
        return one(Float64)
    end
    return Float64(a / b)
end

function ratio(a::TrialEstimate, b::TrialEstimate)
    ttol = max(params(a).time_tolerance, params(b).time_tolerance)
    mtol = max(params(a).memory_tolerance, params(b).memory_tolerance)
    p = Parameters(params(a); time_tolerance = ttol, memory_tolerance = mtol)
    return TrialRatio(p, ratio(time(a), time(b)), ratio(gctime(a), gctime(b)),
                      ratio(memory(a), memory(b)), ratio(allocs(a), allocs(b)),
                      ratio(mymetric(a), mymetric(b)))
end

gcratio(t::TrialEstimate) =  ratio(gctime(t), time(t))

##################
# TrialJudgement #
##################

struct TrialJudgement
    ratio::TrialRatio
    time::Symbol
    memory::Symbol
    mymetric::Symbol
end

function TrialJudgement(r::TrialRatio)
    ttol = params(r).time_tolerance
    mtol = params(r).memory_tolerance
    return TrialJudgement(r, judge(time(r), ttol), judge(memory(r), mtol), judge(mymetric(r), 0.0))
end

function Base.:(==)(a::TrialJudgement, b::TrialJudgement)
    return a.ratio == b.ratio &&
           a.time == b.time &&
           a.memory == b.memory
end

Base.copy(t::TrialJudgement) = TrialJudgement(copy(t.params), t.time, t.memory)

Base.time(t::TrialJudgement) = t.time
memory(t::TrialJudgement) = t.memory
ratio(t::TrialJudgement) = t.ratio
params(t::TrialJudgement) = params(ratio(t))

judge(a::TrialEstimate, b::TrialEstimate; kwargs...) = judge(ratio(a, b); kwargs...)

function judge(r::TrialRatio; kwargs...)
    newr = copy(r)
    newr.params = Parameters(params(r); kwargs...)
    return TrialJudgement(newr)
end

function judge(ratio::Real, tolerance::Float64)
    if isnan(ratio) || (ratio - tolerance) > 1.0
        return :regression
    elseif (ratio + tolerance) < 1.0
        return :improvement
    else
        return :invariant
    end
end

isimprovement(f, t::TrialJudgement) = f(t) == :improvement
isimprovement(t::TrialJudgement) = isimprovement(time, t) || isimprovement(memory, t)

isregression(f, t::TrialJudgement) = f(t) == :regression
isregression(t::TrialJudgement) = isregression(time, t) || isregression(memory, t)

isinvariant(f, t::TrialJudgement) = f(t) == :invariant
isinvariant(t::TrialJudgement) = isinvariant(time, t) && isinvariant(memory, t)

const colormap = (
    regression = :red,
    improvement = :green,
    invariant = :normal,
)

printtimejudge(io, t::TrialJudgement) =
    printstyled(io, time(t); color=colormap[time(t)])
printmemoryjudge(io, t::TrialJudgement) =
    printstyled(io, memory(t); color=colormap[memory(t)])

###################
# Pretty Printing #
###################

prettypercent(p) = string(@sprintf("%.2f", p * 100), "%")

function prettydiff(p)
    diff = p - 1.0
    return string(diff >= 0.0 ? "+" : "", @sprintf("%.2f", diff * 100), "%")
end

function prettytime(t)
    if t < 1e3
        value, units = t, "ns"
    elseif t < 1e6
        value, units = t / 1e3, "μs"
    elseif t < 1e9
        value, units = t / 1e6, "ms"
    else
        value, units = t / 1e9, "s"
    end
    return string(@sprintf("%.3f", value), " ", units)
end

function prettymemory(b)
    if b < 1024
        return string(b, " bytes")
    elseif b < 1024^2
        value, units = b / 1024, "KiB"
    elseif b < 1024^3
        value, units = b / 1024^2, "MiB"
    else
        value, units = b / 1024^3, "GiB"
    end
    return string(@sprintf("%.2f", value), " ", units)
end

function withtypename(f, io, t)
    needtype = get(io, :typeinfo, Nothing) !== typeof(t)
    if needtype
        print(io, nameof(typeof(t)), '(')
    end
    f()
    if needtype
        print(io, ')')
    end
end

_summary(io, t, args...) = withtypename(() -> print(io, args...), io, t)

Base.summary(io::IO, t::Trial) = _summary(io, t, prettytime(time(t)))
Base.summary(io::IO, t::TrialEstimate) = _summary(io, t, prettytime(time(t)))
Base.summary(io::IO, t::TrialRatio) = _summary(io, t, prettypercent(time(t)))
Base.summary(io::IO, t::TrialJudgement) = withtypename(io, t) do
    print(io, prettydiff(time(ratio(t))), " => ")
    printtimejudge(io, t)
end

_show(io, t) =
    if get(io, :compact, true)
        summary(io, t)
    else
        show(io, MIME"text/plain"(), t)
    end

Base.show(io::IO, t::Trial) = _show(io, t)
Base.show(io::IO, t::TrialEstimate) = _show(io, t)
Base.show(io::IO, t::TrialRatio) = _show(io, t)
Base.show(io::IO, t::TrialJudgement) = _show(io, t)

function Base.show(io::IO, ::MIME"text/plain", t::Trial)
    if length(t) > 0
        min = minimum(t)
        max = maximum(t)
        med = median(t)
        avg = mean(t)
        memorystr = string(prettymemory(memory(min)))
        allocsstr = string(allocs(min))
        minstr = string(prettytime(time(min)), " (", prettypercent(gcratio(min)), " GC)")
        maxstr = string(prettytime(time(max)), " (", prettypercent(gcratio(max)), " GC)")
        medstr = string(prettytime(time(med)), " (", prettypercent(gcratio(med)), " GC)")
        meanstr = string(prettytime(time(avg)), " (", prettypercent(gcratio(avg)), " GC)")
    else
        memorystr = "N/A"
        allocsstr = "N/A"
        minstr = "N/A"
        maxstr = "N/A"
        medstr = "N/A"
        meanstr = "N/A"
    end
    println(io, "BenchmarkTools.Trial: ")
    pad = get(io, :pad, "")
    println(io, pad, "  memory estimate:  ", memorystr)
    println(io, pad, "  allocs estimate:  ", allocsstr)
    println(io, pad, "  --------------")
    println(io, pad, "  minimum time:     ", minstr)
    println(io, pad, "  median time:      ", medstr)
    println(io, pad, "  mean time:        ", meanstr)
    println(io, pad, "  maximum time:     ", maxstr)
    println(io, pad, "  --------------")
    println(io, pad, "  samples:          ", length(t))
    print(io,   pad, "  evals/sample:     ", t.params.evals)
end

function Base.show(io::IO, ::MIME"text/plain", t::MyTrial)
    if length(t) > 0
        min = minimum(t)
        max = maximum(t)
        med = median(t)
        avg = mean(t)
        memorystr = string(prettymemory(memory(min)))
        allocsstr = string(allocs(min))
        minstr = string(mymetric(min), " \t[", prettytime(time(min)), " (", prettypercent(gcratio(min)), " GC)]")
        maxstr = string(mymetric(max), " \t[", prettytime(time(max)), " (", prettypercent(gcratio(max)), " GC)]")
        medstr = string(mymetric(med), " \t[", prettytime(time(med)), " (", prettypercent(gcratio(med)), " GC)]")
        meanstr = string(mymetric(avg), " \t[", prettytime(time(avg)), " (", prettypercent(gcratio(avg)), " GC)]")
    else
        memorystr = "N/A"
        allocsstr = "N/A"
        minstr = "N/A"
        maxstr = "N/A"
        medstr = "N/A"
        meanstr = "N/A"
    end
    println(io, "BenchmarkTools.MyTrial: ")
    pad = get(io, :pad, "")
    println(io, pad, "  memory estimate:  ", memorystr)
    println(io, pad, "  allocs estimate:  ", allocsstr)
    println(io, pad, "  --------------")
    println(io, pad, "  minimum mymetric:     ", minstr)
    println(io, pad, "  median mymetric:      ", medstr)
    println(io, pad, "  mean mymetric:        ", meanstr)
    println(io, pad, "  maximum mymetric:     ", maxstr)
    println(io, pad, "  --------------")
    println(io, pad, "  samples:          ", length(t))
    print(io,   pad, "  evals/sample:     ", t.params.evals)
end

function Base.show(io::IO, ::MIME"text/plain", t::TrialEstimate)
    println(io, "BenchmarkTools.TrialEstimate: ")
    pad = get(io, :pad, "")
    println(io, pad, "  time:             ", prettytime(time(t)))
    println(io, pad, "  gctime:           ", prettytime(gctime(t)), " (", prettypercent(gctime(t) / time(t)),")")
    println(io, pad, "  memory:           ", prettymemory(memory(t)))
    print(io,   pad, "  allocs:           ", allocs(t))
end

function Base.show(io::IO, ::MIME"text/plain", t::TrialRatio)
    println(io, "BenchmarkTools.TrialRatio: ")
    pad = get(io, :pad, "")
    println(io, pad, "  time:             ", time(t))
    println(io, pad, "  gctime:           ", gctime(t))
    println(io, pad, "  memory:           ", memory(t))
    print(io,   pad, "  allocs:           ", allocs(t))
end

function Base.show(io::IO, ::MIME"text/plain", t::TrialJudgement)
    println(io, "BenchmarkTools.TrialJudgement: ")
    pad = get(io, :pad, "")
    print(io, pad, "  time:   ", prettydiff(time(ratio(t))), " => ")
    printtimejudge(io, t)
    println(io, " (", prettypercent(params(t).time_tolerance), " tolerance)")
    print(io,   pad, "  memory: ", prettydiff(memory(ratio(t))), " => ")
    printmemoryjudge(io, t)
    println(io, " (", prettypercent(params(t).memory_tolerance), " tolerance)")
end
