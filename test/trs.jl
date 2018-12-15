include("../src/TRS.jl")
using Main.TRS
using Test, Random
using LinearAlgebra
using MATLAB
using Arpack

rng = MersenneTwister(123)
for n in [2, 5, 30, 100, 5000]
    P = randn(rng, n, n); P = (P + P')/2
    q = randn(rng, n)
    r = [1e-4 1e-2 1 1000]
    eye = Matrix{Float64}(I, n, n)
    for i = 1:length(r)
        x_g, x_l, info = trs(P, q, r[i], compute_local=true)
        x_matlab, λ_matlab = mxcall(:TRSgep, 2, P, q, eye, r[i])
        str = "Trs - r:"*string(r[i])
        @testset "$str" begin
            @test info.λ[1] - λ_matlab <= 1e-6*λ_matlab
            if size(x_matlab, 2) > 1
                diff = min(norm(x_g - x_matlab[:, 1]), norm(x_g - x_matlab[:, 2]))
            else
                diff = norm(x_g - x_matlab)
            end
            @test diff <= 1e-3*r[i]
        end
    end
    # hard case
    λ_min, v, _ = eigs(-P, nev=1, which=:LR)
    v = v/norm(v)
    q = (I - v*v')*q
    x_g, x_l, info = trs(P, q, r[end], compute_local=true)
    x_matlab, λ_matlab = mxcall(:TRSgep, 2, P, q, eye, r[end])
    @testset "Trs - hard case" begin
        @test info.λ[1] - λ_matlab <= 1e-6*λ_matlab
        if size(x_matlab, 2) > 1
            diff = min(norm(x_g - x_matlab[:, 1]), norm(x_g - x_matlab[:, 2]))
        else
            diff = norm(x_g - x_matlab)
        end
        @test diff <= 1e-3*r[end]
    end
end


nothing
